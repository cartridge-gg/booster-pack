use starknet::ContractAddress;

const FORWARDER_ROLE: felt252 = selector!("FORWARDER_ROLE");

#[starknet::interface]
pub trait IClaim<T> {
    fn initialize(ref self: T, forwarder_address: ContractAddress);
    fn claim_from_forwarder(ref self: T, recipient: ContractAddress, leaf_data: Span<felt252>);
}

#[derive(Drop, Copy, Clone, Serde, PartialEq)]
pub struct LeafDataWithExtraData {
    pub amount: u256,
    pub token_address: ContractAddress,
    pub token_id: u256,
    pub token_type: felt252,
}

#[starknet::contract]
mod ClaimContract {
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
    use starknet::{ContractAddress, get_contract_address};
    use crate::constants::identifier::{ERC_20, ERC_721};
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

        fn claim_from_forwarder(
            ref self: ContractState, recipient: ContractAddress, leaf_data: Span<felt252>,
        ) {
            // MUST check caller is forwarder
            // self.assert_caller_is_forwarder();

            // deserialize leaf_data
            let mut leaf_data = leaf_data;
            let data = Serde::<LeafDataWithExtraData>::deserialize(ref leaf_data).unwrap();

            // mint token id and respective amount
            let amount = data.amount;
            let token_address = data.token_address;
            let token_id = data.token_id;
            let token_type = data.token_type;

            // check if erc20 OR erc 721
            if token_type == ERC_20 {
                // transfer erc20
                self.mint_erc20(token_address, recipient, amount);
            } else if token_type == ERC_721 {
                // transfer erc721
                self.mint_erc721(token_address, recipient, token_id);
            } else {
                core::panic_with_felt252('Invalid token type');
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
            let contract = get_contract_address();
            let erc20_token = IERC20TokenDispatcher { contract_address: contract_address };
            erc20_token.transfer_from(contract, recipient, amount);
        }

        fn mint_erc721(
            self: @ContractState,
            contract_address: ContractAddress,
            recipient: ContractAddress,
            token_id: u256,
        ) {
            let contract = get_contract_address();
            let erc721_token = IERC721TokenDispatcher { contract_address: contract_address };
            erc721_token.transfer_from(contract, recipient, token_id);
        }
    }
}
