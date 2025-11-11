use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const};
use crate::{IClaimDispatcher, IClaimDispatcherTrait, TournamentConfig, LeafDataWithExtraData};
use crate::mocks::budokan_mock::{IBudokanMockDispatcher, IBudokanMockDispatcherTrait};
use crate::mocks::erc20_mock::{IERC20MockDispatcher, IERC20MockDispatcherTrait};
use crate::constants::identifier::{ERC_20, MYSTERY_ASSET};

fn OWNER() -> ContractAddress {
    contract_address_const::<'OWNER'>()
}

fn FORWARDER() -> ContractAddress {
    contract_address_const::<'FORWARDER'>()
}

fn RECIPIENT() -> ContractAddress {
    contract_address_const::<'RECIPIENT'>()
}

fn RECIPIENT_2() -> ContractAddress {
    contract_address_const::<'RECIPIENT_2'>()
}

fn deploy_claim_contract() -> IClaimDispatcher {
    let contract = declare("ClaimContract").unwrap().contract_class();
    let (contract_address, _) = contract
        .deploy(@array![OWNER().into(), FORWARDER().into()])
        .unwrap();
    IClaimDispatcher { contract_address }
}

fn deploy_budokan_mock() -> IBudokanMockDispatcher {
    let contract = declare("BudokanMock").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    IBudokanMockDispatcher { contract_address }
}

fn deploy_erc20(
    name: ByteArray, symbol: ByteArray, supply: u256, recipient: ContractAddress
) -> ContractAddress {
    let contract = declare("ERC20Mock").unwrap().contract_class();
    let mut calldata = array![];
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    supply.serialize(ref calldata);
    recipient.serialize(ref calldata);

    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

fn setup_tournament_config(claim_contract: IClaimDispatcher, budokan: IBudokanMockDispatcher) {
    let mut tournament_ids = ArrayTrait::new();
    tournament_ids.append(1);
    tournament_ids.append(2);
    tournament_ids.append(3);
    tournament_ids.append(4);

    let config = TournamentConfig {
        budokan_address: budokan.contract_address, tournament_ids,
    };

    // Set ClaimContract on allowlist for each tournament
    budokan.set_tournament_allowlist(1, claim_contract.contract_address);
    budokan.set_tournament_allowlist(2, claim_contract.contract_address);
    budokan.set_tournament_allowlist(3, claim_contract.contract_address);
    budokan.set_tournament_allowlist(4, claim_contract.contract_address);

    // Configure tournaments in ClaimContract
    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_tournament_config(config);
    stop_cheat_caller_address(claim_contract.contract_address);
}

// ========================================
// ERC20 Token Claim Tests
// ========================================

#[test]
fn test_claim_erc20_tokens() {
    let claim_contract = deploy_claim_contract();
    let recipient = RECIPIENT();

    // Deploy ERC20 token and fund ClaimContract
    let token_supply: u256 = 10000000000000000000000_u256; // 10,000 tokens
    let token_address = deploy_erc20("Credits", "CREDITS", token_supply, claim_contract.contract_address);

    // Create leaf data for ERC_20 claim
    let leaf_data = LeafDataWithExtraData {
        amount: 150000000000000000000_u256, // 150 tokens
        token_address: token_address,
        token_type: ERC_20,
    };

    let mut serialized = array![];
    Serde::serialize(@leaf_data, ref serialized);

    // Claim tokens
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient, serialized.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    // Verify recipient received tokens
    let token = IERC20MockDispatcher { contract_address: token_address };
    let balance = token.balance_of(recipient);
    assert(balance == 150000000000000000000_u256, 'Wrong token balance');

    // Verify claimed status
    assert(claim_contract.has_claimed(recipient), 'Should be marked as claimed');
}

#[test]
#[should_panic(expected: ('Already claimed',))]
fn test_erc20_prevent_double_claim() {
    let claim_contract = deploy_claim_contract();
    let recipient = RECIPIENT();

    let token_supply: u256 = 10000000000000000000000_u256;
    let token_address = deploy_erc20("Credits", "CREDITS", token_supply, claim_contract.contract_address);

    let leaf_data = LeafDataWithExtraData {
        amount: 150000000000000000000_u256,
        token_address: token_address,
        token_type: ERC_20,
    };

    let mut serialized = array![];
    Serde::serialize(@leaf_data, ref serialized);

    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());

    // First claim - should succeed
    claim_contract.claim_from_forwarder(recipient, serialized.span());

    // Second claim - should panic
    claim_contract.claim_from_forwarder(recipient, serialized.span());

    stop_cheat_caller_address(claim_contract.contract_address);
}

// ========================================
// MYSTERY_ASSET Tournament Claim Tests
// ========================================

#[test]
fn test_claim_mystery_asset_tournaments() {
    let claim_contract = deploy_claim_contract();
    let budokan = deploy_budokan_mock();
    let recipient = RECIPIENT();

    setup_tournament_config(claim_contract, budokan);

    // Create leaf data for MYSTERY_ASSET claim
    let leaf_data = LeafDataWithExtraData {
        amount: 0, // Not used for MYSTERY_ASSET
        token_address: contract_address_const::<0x0>(),
        token_type: MYSTERY_ASSET,
    };

    let mut serialized = array![];
    Serde::serialize(@leaf_data, ref serialized);

    // Claim tournament entries
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient, serialized.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    // Verify entries were created for all tournaments
    let nums_entries = budokan.get_tournament_entry_count(1);
    let ls2_entries = budokan.get_tournament_entry_count(2);
    let dw_entries = budokan.get_tournament_entry_count(3);
    let dark_shuffle_entries = budokan.get_tournament_entry_count(4);

    assert(nums_entries == 1, 'Should have 1 Nums entry');
    assert(ls2_entries == 1, 'Should have 1 LS2 entry');
    assert(dw_entries == 1, 'Should have 1 DW entry');
    assert(dark_shuffle_entries == 1, 'Should have 1 DS entry');

    // Verify total entries
    let total_entries = budokan.get_total_entries();
    assert(total_entries == 4, 'Should have 4 total entries');

    // Verify claimed status
    assert(claim_contract.has_claimed(recipient), 'Should be marked as claimed');
}

// ========================================
// Mixed Claim Type Tests
// ========================================

#[test]
fn test_mixed_claim_types() {
    let claim_contract = deploy_claim_contract();
    let budokan = deploy_budokan_mock();

    setup_tournament_config(claim_contract, budokan);

    // Deploy tokens
    let token_supply: u256 = 100000000000000000000000_u256;
    let credits_address = deploy_erc20("Credits", "CREDITS", token_supply, claim_contract.contract_address);
    let lords_address = deploy_erc20("Lords", "LORDS", token_supply, claim_contract.contract_address);

    // Recipient 1: Claims ERC_20 (CREDITS)
    let recipient1 = contract_address_const::<'RECIPIENT_1'>();
    let leaf_data1 = LeafDataWithExtraData {
        amount: 150000000000000000000_u256,
        token_address: credits_address,
        token_type: ERC_20,
    };
    let mut serialized1 = array![];
    Serde::serialize(@leaf_data1, ref serialized1);

    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient1, serialized1.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    // Recipient 2: Claims MYSTERY_ASSET (tournaments)
    let recipient2 = contract_address_const::<'RECIPIENT_2'>();
    let leaf_data2 = LeafDataWithExtraData {
        amount: 0,
        token_address: contract_address_const::<0x0>(),
        token_type: MYSTERY_ASSET,
    };
    let mut serialized2 = array![];
    Serde::serialize(@leaf_data2, ref serialized2);

    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient2, serialized2.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    // Recipient 3: Claims ERC_20 (LORDS)
    let recipient3 = contract_address_const::<'RECIPIENT_3'>();
    let leaf_data3 = LeafDataWithExtraData {
        amount: 75000000000000000000_u256,
        token_address: lords_address,
        token_type: ERC_20,
    };
    let mut serialized3 = array![];
    Serde::serialize(@leaf_data3, ref serialized3);

    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient3, serialized3.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    // Verify Recipient 1 got CREDITS
    let credits_token = IERC20MockDispatcher { contract_address: credits_address };
    let r1_balance = credits_token.balance_of(recipient1);
    assert(r1_balance == 150000000000000000000_u256, 'R1: Wrong CREDITS balance');

    // Verify Recipient 2 got tournament entries
    let total_entries = budokan.get_total_entries();
    assert(total_entries == 4, 'R2: Wrong tournament entries');

    // Verify Recipient 3 got LORDS
    let lords_token = IERC20MockDispatcher { contract_address: lords_address };
    let r3_balance = lords_token.balance_of(recipient3);
    assert(r3_balance == 75000000000000000000_u256, 'R3: Wrong LORDS balance');

    // Verify all claimed
    assert(claim_contract.has_claimed(recipient1), 'R1 not claimed');
    assert(claim_contract.has_claimed(recipient2), 'R2 not claimed');
    assert(claim_contract.has_claimed(recipient3), 'R3 not claimed');
}

// ========================================
// Access Control Tests
// ========================================

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_only_forwarder_can_claim() {
    let claim_contract = deploy_claim_contract();
    let unauthorized = contract_address_const::<'UNAUTHORIZED'>();
    let recipient = RECIPIENT();

    let token_supply: u256 = 10000000000000000000000_u256;
    let token_address = deploy_erc20("Credits", "CREDITS", token_supply, claim_contract.contract_address);

    let leaf_data = LeafDataWithExtraData {
        amount: 150000000000000000000_u256,
        token_address: token_address,
        token_type: ERC_20,
    };

    let mut serialized = array![];
    Serde::serialize(@leaf_data, ref serialized);

    // Try to claim from unauthorized address - should panic
    start_cheat_caller_address(claim_contract.contract_address, unauthorized);
    claim_contract.claim_from_forwarder(recipient, serialized.span());
    stop_cheat_caller_address(claim_contract.contract_address);
}

#[test]
fn test_tournament_config() {
    let claim_contract = deploy_claim_contract();
    let budokan = deploy_budokan_mock();

    let mut tournament_ids = ArrayTrait::new();
    tournament_ids.append(1);
    tournament_ids.append(2);
    tournament_ids.append(3);
    tournament_ids.append(4);

    let config = TournamentConfig {
        budokan_address: budokan.contract_address, tournament_ids,
    };

    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_tournament_config(config);
    stop_cheat_caller_address(claim_contract.contract_address);

    let read_config = claim_contract.get_tournament_config();

    assert(read_config.budokan_address == budokan.contract_address, 'Budokan address mismatch');
    assert(read_config.tournament_ids.len() == 4, 'Tournament IDs length wrong');
    assert(*read_config.tournament_ids.at(0) == 1, 'Tournament ID 0 mismatch');
    assert(*read_config.tournament_ids.at(1) == 2, 'Tournament ID 1 mismatch');
    assert(*read_config.tournament_ids.at(2) == 3, 'Tournament ID 2 mismatch');
    assert(*read_config.tournament_ids.at(3) == 4, 'Tournament ID 3 mismatch');
}

#[test]
fn test_tournament_config_single_tournament() {
    let claim_contract = deploy_claim_contract();
    let budokan = deploy_budokan_mock();
    let recipient = RECIPIENT();

    // Test with single tournament for easier testing
    let mut tournament_ids = ArrayTrait::new();
    tournament_ids.append(1);

    let config = TournamentConfig {
        budokan_address: budokan.contract_address, tournament_ids,
    };

    // Set ClaimContract on allowlist
    budokan.set_tournament_allowlist(1, claim_contract.contract_address);

    // Configure tournament in ClaimContract
    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_tournament_config(config);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Create leaf data for MYSTERY_ASSET claim
    let leaf_data = LeafDataWithExtraData {
        amount: 0,
        token_address: contract_address_const::<0x0>(),
        token_type: MYSTERY_ASSET,
    };

    let mut serialized = array![];
    Serde::serialize(@leaf_data, ref serialized);

    // Claim tournament entry
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient, serialized.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    // Verify only one entry was created
    let tournament_entries = budokan.get_tournament_entry_count(1);
    assert(tournament_entries == 1, 'Should have 1 entry');

    let total_entries = budokan.get_total_entries();
    assert(total_entries == 1, 'Should have 1 total entry');
}

#[test]
fn test_unclaimed_address() {
    let claim_contract = deploy_claim_contract();
    let unclaimed_address = contract_address_const::<'UNCLAIMED'>();

    assert(!claim_contract.has_claimed(unclaimed_address), 'Should not be claimed');
}
