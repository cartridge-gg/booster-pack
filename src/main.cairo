use starknet::ContractAddress;

const FORWARDER_ROLE: felt252 = selector!("FORWARDER_ROLE");

// Simplified leaf data structure - only contains amount
// Token addresses are now stored in the contract
#[derive(Drop, Copy, Serde, PartialEq)]
pub struct LeafData {
    pub amount: u256,
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

    // Separate claim entrypoints for each item type
    fn claim_lords_from_forwarder(ref self: T, recipient: ContractAddress, amount: u256);
    fn claim_nums_from_forwarder(ref self: T, recipient: ContractAddress, amount: u256);
    fn claim_survivor_from_forwarder(ref self: T, recipient: ContractAddress, amount: u256);
    fn claim_paper_from_forwarder(ref self: T, recipient: ContractAddress, amount: u256);
    fn claim_mystery_from_forwarder(ref self: T, recipient: ContractAddress, amount: u256);

    // Token address configuration
    fn set_lords_token(ref self: T, address: ContractAddress);
    fn set_nums_token(ref self: T, address: ContractAddress);
    fn set_survivor_token(ref self: T, address: ContractAddress);
    fn set_paper_token(ref self: T, address: ContractAddress);

    fn get_lords_token(self: @T) -> ContractAddress;
    fn get_nums_token(self: @T) -> ContractAddress;
    fn get_survivor_token(self: @T) -> ContractAddress;
    fn get_paper_token(self: @T) -> ContractAddress;

    // Treasury address configuration
    fn set_treasury(ref self: T, address: ContractAddress);
    fn get_treasury(self: @T) -> ContractAddress;

    // Tournament configuration
    fn set_tournament_config(ref self: T, config: TournamentConfig);
    fn get_tournament_config(self: @T) -> TournamentConfig;
}

#[starknet::contract]
pub mod ClaimContract {
    use booster_pack_devconnect::constants::interface::{
        IBudokanDispatcher, IBudokanDispatcherTrait, IERC20TokenDispatcher,
        IERC20TokenDispatcherTrait, QualificationProof,
    };
    use openzeppelin_access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_upgrades::UpgradeableComponent;
    use openzeppelin_upgrades::interface::IUpgradeable;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ClassHash, ContractAddress, get_contract_address};
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
        // Treasury address that holds the assets
        treasury: ContractAddress,
        // Tournament configuration for MYSTERY_ASSET claims
        budokan_address: ContractAddress,
        tournament_ids_len: u64,
        tournament_ids: Map<u64, u64>,
        // Token addresses for each claimable item
        lords_token: ContractAddress,
        nums_token: ContractAddress,
        survivor_token: ContractAddress,
        credits_token: ContractAddress,
        paper_token: ContractAddress,
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
        ref self: ContractState,
        owner: ContractAddress,
        forwarder_address: ContractAddress,
        treasury: ContractAddress,
        lords_token: ContractAddress,
        nums_token: ContractAddress,
        survivor_token: ContractAddress,
        credits_token: ContractAddress,
        paper_token: ContractAddress,
    ) {
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, owner);
        self.accesscontrol._grant_role(FORWARDER_ROLE, forwarder_address);

        // Initialize treasury address
        self.treasury.write(treasury);

        // Initialize token addresses
        self.lords_token.write(lords_token);
        self.nums_token.write(nums_token);
        self.survivor_token.write(survivor_token);
        self.paper_token.write(paper_token);
    }

    #[abi(embed_v0)]
    impl ClaimImpl of IClaim<ContractState> {
        fn initialize(ref self: ContractState, forwarder_address: ContractAddress) {
            // check if admin
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.accesscontrol._grant_role(FORWARDER_ROLE, forwarder_address);
        }

        fn set_tournament_config(ref self: ContractState, config: TournamentConfig) {
            // check if admin
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

        // ============ Claim Entrypoints ============

        fn claim_lords_from_forwarder(
            ref self: ContractState, recipient: ContractAddress, amount: u256,
        ) {
            self.accesscontrol.assert_only_role(FORWARDER_ROLE);
            let token_address = self.lords_token.read();
            self.transfer_erc20(token_address, recipient, amount);
            self.emit(TokenClaimed { recipient, token_address, amount });
        }

        fn claim_nums_from_forwarder(
            ref self: ContractState, recipient: ContractAddress, amount: u256,
        ) {
            self.accesscontrol.assert_only_role(FORWARDER_ROLE);
            let token_address = self.nums_token.read();
            self.transfer_erc20(token_address, recipient, amount);
            self.emit(TokenClaimed { recipient, token_address, amount });
        }

        fn claim_survivor_from_forwarder(
            ref self: ContractState, recipient: ContractAddress, amount: u256,
        ) {
            self.accesscontrol.assert_only_role(FORWARDER_ROLE);
            let token_address = self.survivor_token.read();
            self.transfer_erc20(token_address, recipient, amount);
            self.emit(TokenClaimed { recipient, token_address, amount });
        }

        fn claim_paper_from_forwarder(
            ref self: ContractState, recipient: ContractAddress, amount: u256,
        ) {
            self.accesscontrol.assert_only_role(FORWARDER_ROLE);
            let token_address = self.paper_token.read();
            self.transfer_erc20(token_address, recipient, amount);
            self.emit(TokenClaimed { recipient, token_address, amount });
        }

        fn claim_mystery_from_forwarder(
            ref self: ContractState, recipient: ContractAddress, amount: u256,
        ) {
            self.accesscontrol.assert_only_role(FORWARDER_ROLE);
            // amount parameter not used for MYSTERY_ASSET, included for consistency
            self.enter_all_tournaments(recipient);
        }

        // ============ Token Address Setters ============

        fn set_lords_token(ref self: ContractState, address: ContractAddress) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.lords_token.write(address);
        }

        fn set_nums_token(ref self: ContractState, address: ContractAddress) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.nums_token.write(address);
        }

        fn set_survivor_token(ref self: ContractState, address: ContractAddress) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.survivor_token.write(address);
        }

        fn set_paper_token(ref self: ContractState, address: ContractAddress) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.paper_token.write(address);
        }

        // ============ Token Address Getters ============

        fn get_lords_token(self: @ContractState) -> ContractAddress {
            self.lords_token.read()
        }

        fn get_nums_token(self: @ContractState) -> ContractAddress {
            self.nums_token.read()
        }

        fn get_survivor_token(self: @ContractState) -> ContractAddress {
            self.survivor_token.read()
        }

        fn get_paper_token(self: @ContractState) -> ContractAddress {
            self.paper_token.read()
        }

        // ============ Treasury Configuration ============

        fn set_treasury(ref self: ContractState, address: ContractAddress) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.treasury.write(address);
        }

        fn get_treasury(self: @ContractState) -> ContractAddress {
            self.treasury.read()
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
            let treasury = self.treasury.read();
            let erc20_token = IERC20TokenDispatcher { contract_address: token_address };
            erc20_token.transfer_from(treasury, recipient, amount);
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


    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
