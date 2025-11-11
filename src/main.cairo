use starknet::ContractAddress;

const FORWARDER_ROLE: felt252 = selector!("FORWARDER_ROLE");

// Leaf data structure with token information
#[derive(Drop, Copy, Serde, PartialEq)]
pub struct LeafDataWithExtraData {
    pub amount: u256,
    pub token_address: ContractAddress,
    pub token_type: felt252 // ERC_20, ERC_721, or MYSTERY_ASSET
}

// Tournament configuration for MYSTERY_ASSET claims
#[derive(Drop, Serde, PartialEq)]
pub struct TournamentConfig {
    pub budokan_address: ContractAddress,
    pub tournament_ids: Array<u64>,
}

#[starknet::interface]
pub trait IClaim<T> {
    fn initialize(ref self: T, forwarder_address: ContractAddress);
    fn claim_from_forwarder(ref self: T, recipient: ContractAddress, leaf_data: Span<felt252>);
    fn set_tournament_config(ref self: T, config: TournamentConfig);
    fn get_tournament_config(self: @T) -> TournamentConfig;
    fn has_claimed(self: @T, address: ContractAddress) -> bool;
}

#[starknet::contract]
pub mod ClaimContract {
    use booster_pack_devconnect::constants::identifier::{ERC_20, ERC_721, MYSTERY_ASSET};
    use booster_pack_devconnect::constants::interface::{
        IBudokanDispatcher, IBudokanDispatcherTrait, IERC20TokenDispatcher,
        IERC20TokenDispatcherTrait, IERC721TokenDispatcher, IERC721TokenDispatcherTrait,
        QualificationProof,
    };
    use openzeppelin_access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_upgrades::UpgradeableComponent;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_contract_address};
    use super::*;

    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);

    // External
    #[abi(embed_v0)]
    impl AccessControlMixinImpl =
        AccessControlComponent::AccessControlMixinImpl<ContractState>;

    // Internal
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        budokan_address: ContractAddress,
        tournament_ids_len: u64,
        tournament_ids: Map<u64, u64>,
        claimed: Map<ContractAddress, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        TokenClaimed: TokenClaimed,
        TournamentTicketsClaimed: TournamentTicketsClaimed,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokenClaimed {
        pub recipient: ContractAddress,
        pub token_address: ContractAddress,
        pub token_type: felt252,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TournamentTicketsClaimed {
        pub recipient: ContractAddress,
        pub token_ids: Array<u64>,
        pub entry_numbers: Array<u32>,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, forwarder_address: ContractAddress,
    ) {
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, owner);
        self.accesscontrol._grant_role(FORWARDER_ROLE, forwarder_address);
    }

    #[abi(embed_v0)]
    impl ClaimImpl of IClaim<ContractState> {
        fn initialize(ref self: ContractState, forwarder_address: ContractAddress) {
            self.accesscontrol._grant_role(FORWARDER_ROLE, forwarder_address);
        }

        fn set_tournament_config(ref self: ContractState, config: TournamentConfig) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);

            // Store budokan address
            self.budokan_address.write(config.budokan_address);

            // Store tournament IDs
            let len = config.tournament_ids.len();
            self.tournament_ids_len.write(len.into());

            let mut i: u64 = 0;
            while i < len.into() {
                self
                    .tournament_ids
                    .entry(i)
                    .write(*config.tournament_ids.at(i.try_into().unwrap()));
                i += 1;
            };
        }

        fn get_tournament_config(self: @ContractState) -> TournamentConfig {
            let budokan_address = self.budokan_address.read();
            let len = self.tournament_ids_len.read();

            let mut tournament_ids = ArrayTrait::new();
            let mut i: u64 = 0;
            while i < len {
                tournament_ids.append(self.tournament_ids.entry(i).read());
                i += 1;
            }

            TournamentConfig { budokan_address, tournament_ids }
        }

        fn has_claimed(self: @ContractState, address: ContractAddress) -> bool {
            self.claimed.entry(address).read()
        }

        fn claim_from_forwarder(
            ref self: ContractState, recipient: ContractAddress, leaf_data: Span<felt252>,
        ) {
            // MUST check caller is forwarder
            self.accesscontrol.assert_only_role(FORWARDER_ROLE);

            // Check if already claimed
            assert(!self.claimed.entry(recipient).read(), 'Already claimed');

            // Deserialize leaf_data
            let mut leaf_data_mut = leaf_data;
            let data = Serde::<LeafDataWithExtraData>::deserialize(ref leaf_data_mut).unwrap();

            // Handle different token types
            if data.token_type == ERC_20 {
                self.transfer_erc20(data.token_address, recipient, data.amount);
                self
                    .emit(
                        TokenClaimed {
                            recipient,
                            token_address: data.token_address,
                            token_type: data.token_type,
                            amount: data.amount,
                        },
                    );
            } else if data.token_type == ERC_721 {
                self.transfer_erc721(data.token_address, recipient, data.amount);
                self
                    .emit(
                        TokenClaimed {
                            recipient,
                            token_address: data.token_address,
                            token_type: data.token_type,
                            amount: data.amount,
                        },
                    );
            } else if data.token_type == MYSTERY_ASSET {
                self.enter_all_tournaments(recipient);
            }

            // Mark as claimed
            self.claimed.entry(recipient).write(true);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn transfer_erc20(
            self: @ContractState,
            token_address: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let erc20_token = IERC20TokenDispatcher { contract_address: token_address };
            erc20_token.transfer(recipient, amount);
        }

        fn transfer_erc721(
            self: @ContractState,
            token_address: ContractAddress,
            recipient: ContractAddress,
            token_id: u256,
        ) {
            let contract = get_contract_address();
            let erc721_token = IERC721TokenDispatcher { contract_address: token_address };
            erc721_token.safe_transfer_from(contract, recipient, token_id, array![].span());
        }

        fn enter_all_tournaments(ref self: ContractState, recipient: ContractAddress) {
            // Get budokan address and tournament IDs from storage
            let budokan_address = self.budokan_address.read();
            let tournament_ids_len = self.tournament_ids_len.read();

            // Generate player name from address
            let player_name = self.generate_player_name(recipient);

            // Get this contract's address for the allowlist qualification
            let claim_contract_address = get_contract_address();
            let qualification = Option::Some(QualificationProof::Allowlist(claim_contract_address));

            // Create Budokan dispatcher
            let budokan = IBudokanDispatcher { contract_address: budokan_address };

            // Arrays to collect results
            let mut token_ids = ArrayTrait::new();
            let mut entry_numbers = ArrayTrait::new();

            // Iterate over all tournament IDs and enter each tournament
            let mut i: u64 = 0;
            while i < tournament_ids_len {
                let tournament_id = self.tournament_ids.entry(i).read();
                let (token_id, entry_number) = budokan
                    .enter_tournament(tournament_id, player_name, recipient, qualification);

                token_ids.append(token_id);
                entry_numbers.append(entry_number);

                i += 1;
            }

            // Emit event with all token IDs and entry numbers
            self.emit(TournamentTicketsClaimed { recipient, token_ids, entry_numbers });
        }

        fn generate_player_name(self: @ContractState, address: ContractAddress) -> felt252 {
            // Generate a simple player name from the address
            let addr_felt: felt252 = address.into();
            addr_felt
        }
    }
}
