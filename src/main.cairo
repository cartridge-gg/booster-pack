use starknet::ContractAddress;

const FORWARDER_ROLE: felt252 = selector!("FORWARDER_ROLE");

#[derive(Drop, Copy, Serde, PartialEq)]
pub struct MysteryTokenConfig {
    pub token_address: ContractAddress,
    pub amount: u256,
}

#[starknet::interface]
pub trait IClaim<T> {
    fn initialize(ref self: T, forwarder_address: ContractAddress);
    fn claim_from_forwarder(ref self: T, recipient: ContractAddress, leaf_data: Span<felt252>);
    fn set_mystery_token_config(ref self: T, token_index: u8, config: MysteryTokenConfig);
    fn set_all_mystery_tokens(ref self: T, configs: Span<MysteryTokenConfig>);
    fn get_mystery_token_config(self: @T, token_index: u8) -> MysteryTokenConfig;
}

#[derive(Drop, Copy, Serde, PartialEq)]
pub struct LeafDataWithExtraData {
    pub amount: u256,
    pub token_address: ContractAddress,
    pub token_type: felt252,
}

#[starknet::contract]
pub mod ClaimContract {
    use booster_pack_devconnect::constants::interface::{
        IERC20TokenDispatcher, IERC20TokenDispatcherTrait, IERC721TokenDispatcher,
        IERC721TokenDispatcherTrait,
    };
    use openzeppelin_access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_upgrades::UpgradeableComponent;
    use openzeppelin_upgrades::interface::IUpgradeable;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_contract_address, get_tx_info};
    use core::poseidon::poseidon_hash_span;
    use crate::constants::identifier::{ERC_20, ERC_721, MYSTERY_ASSET};
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
        mystery_token_count: u8,
        mystery_tokens: Map<u8, ContractAddress>,
        mystery_amounts: Map<u8, u256>,
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
        MysteryTokenSelected: MysteryTokenSelected,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MysteryTokenSelected {
        pub recipient: ContractAddress,
        pub selected_token: ContractAddress,
        pub selected_token_index: u8,
        pub amount: u256,
    }


    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, forwarder_address: ContractAddress,
    ) {
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, owner);
        self.accesscontrol._grant_role(FORWARDER_ROLE, forwarder_address);
        self.mystery_token_count.write(4_u8);
    }

    #[abi(embed_v0)]
    impl ClaimImpl of IClaim<ContractState> {
        fn initialize(ref self: ContractState, forwarder_address: ContractAddress) {
            self.accesscontrol._grant_role(FORWARDER_ROLE, forwarder_address);
        }

        fn set_mystery_token_config(
            ref self: ContractState, token_index: u8, config: MysteryTokenConfig
        ) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            assert(token_index < 4, 'Token index out of bounds');
            self.mystery_tokens.entry(token_index).write(config.token_address);
            self.mystery_amounts.entry(token_index).write(config.amount);
        }

        fn set_all_mystery_tokens(ref self: ContractState, configs: Span<MysteryTokenConfig>) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            assert(configs.len() == 4, 'Must provide exactly 5 tokens');

            let mut i: u8 = 0;
            while i < 4 {
                let config = *configs.at(i.into());
                self.mystery_tokens.entry(i).write(config.token_address);
                self.mystery_amounts.entry(i).write(config.amount);
                i += 1;
            }
        }

        fn get_mystery_token_config(self: @ContractState, token_index: u8) -> MysteryTokenConfig {
            assert(token_index < 4, 'Token index out of bounds');
            MysteryTokenConfig {
                token_address: self.mystery_tokens.entry(token_index).read(),
                amount: self.mystery_amounts.entry(token_index).read(),
            }
        }

        fn claim_from_forwarder(
            ref self: ContractState, recipient: ContractAddress, leaf_data: Span<felt252>,
        ) {
            // MUST check caller is forwarder
            self.accesscontrol.assert_only_role(FORWARDER_ROLE);

            // Deserialize leaf_data
            let mut leaf_data = leaf_data;
            let data = Serde::<LeafDataWithExtraData>::deserialize(ref leaf_data).unwrap();

            // Handle different token types
            if data.token_type == ERC_20 {
                self.mint_erc20(data.token_address, recipient, data.amount);
            } else if data.token_type == ERC_721 {
                self.mint_erc721(data.token_address, recipient, 1);
            } else if data.token_type == MYSTERY_ASSET {
                // Generate random token index
                let random_index = self.generate_random_token_index(recipient);

                // Get token config
                let token_address = self.mystery_tokens.entry(random_index).read();
                let amount = self.mystery_amounts.entry(random_index).read();

                // Transfer the selected token
                self.mint_erc20(token_address, recipient, amount);

                // Emit event
                self.emit(MysteryTokenSelected {
                    recipient,
                    selected_token: token_address,
                    selected_token_index: random_index,
                    amount,
                });
            }
        }
    }
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn mint_erc20(
            self: @ContractState,
            contract_address: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let erc20_token = IERC20TokenDispatcher { contract_address: contract_address };
            erc20_token.transfer(recipient, amount);
        }

        fn mint_erc721(
            self: @ContractState,
            contract_address: ContractAddress,
            recipient: ContractAddress,
            token_id: u256,
        ) {
            let contract = get_contract_address();
            let erc721_token = IERC721TokenDispatcher { contract_address: contract_address };
            erc721_token.safe_transfer_from(contract, recipient, token_id, array![].span());
        }

        fn generate_random_token_index(self: @ContractState, recipient: ContractAddress) -> u8 {
            let tx_info = get_tx_info().unbox();
            let hash: felt252 = poseidon_hash_span(
                array![tx_info.transaction_hash, recipient.into()].span()
            );
            let hash_u256: u256 = hash.into();
            let token_count: u256 = self.mystery_token_count.read().into();
            let random_index: u8 = (hash_u256 % token_count).try_into().unwrap();
            random_index
        }
    }
}
