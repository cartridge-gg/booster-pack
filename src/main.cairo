use starknet::ContractAddress;

const FORWARDER_ROLE: felt252 = selector!("FORWARDER_ROLE");

// Leaf data structure with token information
#[derive(Drop, Copy, Serde, PartialEq)]
pub struct LeafDataWithExtraData {
    pub amount: u256,
    pub token_address: ContractAddress,
    pub token_type: felt252, // ERC_20, ERC_721, or MYSTERY_ASSET
}

// Tournament configuration for MYSTERY_ASSET claims
#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub struct TournamentConfig {
    pub budokan_address: ContractAddress,
    pub nums_tournament_id: u64,
    pub ls2_tournament_id: u64,
    pub dw_tournament_id: u64,
    pub dark_shuffle_tournament_id: u64,
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
        IERC20TokenDispatcher, IERC20TokenDispatcherTrait, IERC721TokenDispatcher,
        IERC721TokenDispatcherTrait, IBudokanDispatcher, IBudokanDispatcherTrait,
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
        tournament_config: TournamentConfig,
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
        pub nums_token_id: u64,
        pub nums_entry_number: u32,
        pub ls2_token_id: u64,
        pub ls2_entry_number: u32,
        pub dw_token_id: u64,
        pub dw_entry_number: u32,
        pub dark_shuffle_token_id: u64,
        pub dark_shuffle_entry_number: u32,
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
            self.tournament_config.write(config);
        }

        fn get_tournament_config(self: @ContractState) -> TournamentConfig {
            self.tournament_config.read()
        }

        fn has_claimed(self: @ContractState, address: ContractAddress) -> bool {
            self.claimed.entry(address).read()
        }

        fn claim_from_forwarder(
            ref self: ContractState, recipient: ContractAddress, leaf_data: Span<felt252>
        ) {
            // MUST check caller is forwarder
            self.accesscontrol.assert_only_role(FORWARDER_ROLE);

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
                        }
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
                        }
                    );
            } else if data.token_type == MYSTERY_ASSET {
                self.enter_all_tournaments(recipient);
            }
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
            // Get tournament configuration
            let config = self.tournament_config.read();

            // Generate player name from address
            let player_name = self.generate_player_name(recipient);

            // Get this contract's address for the allowlist qualification
            let claim_contract_address = get_contract_address();
            let qualification = Option::Some(
                QualificationProof::Allowlist(claim_contract_address)
            );

            // Create Budokan dispatcher
            let budokan = IBudokanDispatcher { contract_address: config.budokan_address };

            // Enter each tournament and get the minted token IDs
            let (nums_token_id, nums_entry_number) = budokan
                .enter_tournament(
                    config.nums_tournament_id, player_name, recipient, qualification
                );

            let (ls2_token_id, ls2_entry_number) = budokan
                .enter_tournament(config.ls2_tournament_id, player_name, recipient, qualification);

            let (dw_token_id, dw_entry_number) = budokan
                .enter_tournament(config.dw_tournament_id, player_name, recipient, qualification);

            let (dark_shuffle_token_id, dark_shuffle_entry_number) = budokan
                .enter_tournament(
                    config.dark_shuffle_tournament_id, player_name, recipient, qualification,
                );

            // Emit event with all token IDs and entry numbers
            self
                .emit(
                    TournamentTicketsClaimed {
                        recipient,
                        nums_token_id,
                        nums_entry_number,
                        ls2_token_id,
                        ls2_entry_number,
                        dw_token_id,
                        dw_entry_number,
                        dark_shuffle_token_id,
                        dark_shuffle_entry_number,
                    }
                );
        }

        fn generate_player_name(self: @ContractState, address: ContractAddress) -> felt252 {
            // Generate a simple player name from the address
            let addr_felt: felt252 = address.into();
            addr_felt
        }
    }
}
