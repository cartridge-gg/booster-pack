use starknet::ContractAddress;

const FORWARDER_ROLE: felt252 = selector!("FORWARDER_ROLE");

#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub struct TournamentConfig {
    pub budokan_address: ContractAddress,
    pub nums_tournament_id: u64,
    pub ls2_tournament_id: u64,
    pub dw_tournament_id: u64,
    pub dark_shuffle_tournament_id: u64,
    pub glitchbomb_tournament_id: u64, // Use 0 to disable
}

#[starknet::interface]
pub trait IClaim<T> {
    fn initialize(ref self: T, forwarder_address: ContractAddress);
    fn claim_from_forwarder(ref self: T, recipient: ContractAddress);
    fn set_tournament_config(ref self: T, config: TournamentConfig);
    fn get_tournament_config(self: @T) -> TournamentConfig;
    fn has_claimed(self: @T, address: ContractAddress) -> bool;
}

#[starknet::contract]
pub mod ClaimContract {
    use booster_pack_devconnect::constants::interface::{
        IBudokanDispatcher, IBudokanDispatcherTrait, QualificationProof,
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
        TournamentTicketsClaimed: TournamentTicketsClaimed,
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
        pub glitchbomb_token_id: u64,
        pub glitchbomb_entry_number: u32,
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

        fn claim_from_forwarder(ref self: ContractState, recipient: ContractAddress) {
            // MUST check caller is forwarder
            self.accesscontrol.assert_only_role(FORWARDER_ROLE);

            // Prevent double claiming
            assert(!self.claimed.entry(recipient).read(), 'Already claimed');
            self.claimed.entry(recipient).write(true);

            // Get tournament configuration
            let config = self.tournament_config.read();

            // Generate player name from address
            let player_name = self.generate_player_name(recipient);

            // Get this contract's address for the allowlist qualification
            let claim_contract_address = get_contract_address();
            let qualification = Option::Some(QualificationProof::Allowlist(claim_contract_address));

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
                    config.dark_shuffle_tournament_id, player_name, recipient, qualification
                );

            // Optional: Glitchbomb - only enter if tournament ID is not zero
            let (glitchbomb_token_id, glitchbomb_entry_number) =
                if config.glitchbomb_tournament_id != 0 {
                budokan
                    .enter_tournament(
                        config.glitchbomb_tournament_id, player_name, recipient, qualification
                    )
            } else {
                (0, 0)
            };

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
                        glitchbomb_token_id,
                        glitchbomb_entry_number,
                    }
                );
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn generate_player_name(self: @ContractState, address: ContractAddress) -> felt252 {
            // Generate a simple player name from the address
            // Takes last 8 characters and prefixes with 'DC_' (DevConnect)
            // Example: DC_a1b2c3d4
            let addr_felt: felt252 = address.into();
            addr_felt // For now, just use the address as the name
        // In production, you might want to truncate/format this better
        }
    }
}
