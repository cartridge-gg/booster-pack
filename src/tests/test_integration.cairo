use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const};
use crate::{IClaimDispatcher, IClaimDispatcherTrait, TournamentConfig};
use crate::mocks::budokan_mock::{IBudokanMockDispatcher, IBudokanMockDispatcherTrait};

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

fn setup_tournament_config(
    claim_contract: IClaimDispatcher, budokan: IBudokanMockDispatcher
) -> TournamentConfig {
    let config = TournamentConfig {
        budokan_address: budokan.contract_address,
        nums_tournament_id: 1,
        ls2_tournament_id: 2,
        dw_tournament_id: 3,
        dark_shuffle_tournament_id: 4,
        glitchbomb_tournament_id: 5,
    };

    // Set ClaimContract on allowlist for each tournament
    budokan.set_tournament_allowlist(1, claim_contract.contract_address);
    budokan.set_tournament_allowlist(2, claim_contract.contract_address);
    budokan.set_tournament_allowlist(3, claim_contract.contract_address);
    budokan.set_tournament_allowlist(4, claim_contract.contract_address);
    budokan.set_tournament_allowlist(5, claim_contract.contract_address);

    // Configure tournaments in ClaimContract
    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_tournament_config(config);
    stop_cheat_caller_address(claim_contract.contract_address);

    config
}

// ========================================
// Tournament Configuration Tests
// ========================================

#[test]
fn test_set_tournament_config() {
    let claim_contract = deploy_claim_contract();
    let budokan = deploy_budokan_mock();

    let config = TournamentConfig {
        budokan_address: budokan.contract_address,
        nums_tournament_id: 1,
        ls2_tournament_id: 2,
        dw_tournament_id: 3,
        dark_shuffle_tournament_id: 4,
        glitchbomb_tournament_id: 5,
    };

    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_tournament_config(config);
    stop_cheat_caller_address(claim_contract.contract_address);

    let read_config = claim_contract.get_tournament_config();

    assert(read_config.budokan_address == budokan.contract_address, 'Budokan address mismatch');
    assert(read_config.nums_tournament_id == 1, 'Nums ID mismatch');
    assert(read_config.ls2_tournament_id == 2, 'LS2 ID mismatch');
    assert(read_config.dw_tournament_id == 3, 'DW ID mismatch');
    assert(read_config.dark_shuffle_tournament_id == 4, 'DS ID mismatch');
    assert(read_config.glitchbomb_tournament_id == 5, 'GB ID mismatch');
}

// ========================================
// Tournament Entry Claim Tests
// ========================================

#[test]
fn test_claim_tournament_entries() {
    let claim_contract = deploy_claim_contract();
    let budokan = deploy_budokan_mock();
    let recipient = RECIPIENT();

    setup_tournament_config(claim_contract, budokan);

    // Claim tournament entries
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Verify entries were created for all tournaments
    let nums_entries = budokan.get_tournament_entry_count(1);
    let ls2_entries = budokan.get_tournament_entry_count(2);
    let dw_entries = budokan.get_tournament_entry_count(3);
    let dark_shuffle_entries = budokan.get_tournament_entry_count(4);
    let glitchbomb_entries = budokan.get_tournament_entry_count(5);

    assert(nums_entries == 1, 'Should have 1 Nums entry');
    assert(ls2_entries == 1, 'Should have 1 LS2 entry');
    assert(dw_entries == 1, 'Should have 1 DW entry');
    assert(dark_shuffle_entries == 1, 'Should have 1 DS entry');
    assert(glitchbomb_entries == 1, 'Should have 1 GB entry');

    // Verify total entries
    let total_entries = budokan.get_total_entries();
    assert(total_entries == 5, 'Should have 5 total entries');

    // Verify claimed status
    assert(claim_contract.has_claimed(recipient), 'Should be marked as claimed');
}

#[test]
#[should_panic(expected: ('Already claimed',))]
fn test_prevent_double_claim() {
    let claim_contract = deploy_claim_contract();
    let budokan = deploy_budokan_mock();
    let recipient = RECIPIENT();

    setup_tournament_config(claim_contract, budokan);

    // First claim - should succeed
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient);

    // Second claim - should panic
    claim_contract.claim_from_forwarder(recipient);
    stop_cheat_caller_address(claim_contract.contract_address);
}

#[test]
fn test_multiple_recipients() {
    let claim_contract = deploy_claim_contract();
    let budokan = deploy_budokan_mock();
    let recipient1 = RECIPIENT();
    let recipient2 = RECIPIENT_2();

    setup_tournament_config(claim_contract, budokan);

    // Claim for recipient 1
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient1);

    // Claim for recipient 2
    claim_contract.claim_from_forwarder(recipient2);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Verify both recipients claimed
    assert(claim_contract.has_claimed(recipient1), 'R1 should be claimed');
    assert(claim_contract.has_claimed(recipient2), 'R2 should be claimed');

    // Verify tournament entry counts
    let nums_entries = budokan.get_tournament_entry_count(1);
    let ls2_entries = budokan.get_tournament_entry_count(2);
    let dw_entries = budokan.get_tournament_entry_count(3);
    let dark_shuffle_entries = budokan.get_tournament_entry_count(4);
    let glitchbomb_entries = budokan.get_tournament_entry_count(5);

    assert(nums_entries == 2, 'Should have 2 Nums entries');
    assert(ls2_entries == 2, 'Should have 2 LS2 entries');
    assert(dw_entries == 2, 'Should have 2 DW entries');
    assert(dark_shuffle_entries == 2, 'Should have 2 DS entries');
    assert(glitchbomb_entries == 2, 'Should have 2 GB entries');

    // Verify total entries (2 users * 5 games = 10 entries)
    let total_entries = budokan.get_total_entries();
    assert(total_entries == 10, 'Should have 10 total entries');
}

#[test]
fn test_claim_without_glitchbomb() {
    let claim_contract = deploy_claim_contract();
    let budokan = deploy_budokan_mock();
    let recipient = RECIPIENT();

    // Setup config without Glitchbomb (ID = 0)
    let config = TournamentConfig {
        budokan_address: budokan.contract_address,
        nums_tournament_id: 1,
        ls2_tournament_id: 2,
        dw_tournament_id: 3,
        dark_shuffle_tournament_id: 4,
        glitchbomb_tournament_id: 0, // Disabled
    };

    // Set ClaimContract on allowlist for tournaments 1-4
    budokan.set_tournament_allowlist(1, claim_contract.contract_address);
    budokan.set_tournament_allowlist(2, claim_contract.contract_address);
    budokan.set_tournament_allowlist(3, claim_contract.contract_address);
    budokan.set_tournament_allowlist(4, claim_contract.contract_address);

    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_tournament_config(config);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Claim tournament entries
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Verify entries for first 4 games only
    let nums_entries = budokan.get_tournament_entry_count(1);
    let ls2_entries = budokan.get_tournament_entry_count(2);
    let dw_entries = budokan.get_tournament_entry_count(3);
    let dark_shuffle_entries = budokan.get_tournament_entry_count(4);
    let glitchbomb_entries = budokan.get_tournament_entry_count(5);

    assert(nums_entries == 1, 'Should have 1 Nums entry');
    assert(ls2_entries == 1, 'Should have 1 LS2 entry');
    assert(dw_entries == 1, 'Should have 1 DW entry');
    assert(dark_shuffle_entries == 1, 'Should have 1 DS entry');
    assert(glitchbomb_entries == 0, 'Should have 0 GB entries');

    // Verify total entries (4 games only)
    let total_entries = budokan.get_total_entries();
    assert(total_entries == 4, 'Should have 4 total entries');
}

#[test]
#[should_panic(expected: ('Not on allowlist',))]
fn test_unauthorized_caller_cannot_enter_tournament() {
    let claim_contract = deploy_claim_contract();
    let budokan = deploy_budokan_mock();
    let recipient = RECIPIENT();

    // Setup tournament config but DON'T add ClaimContract to allowlist
    let config = TournamentConfig {
        budokan_address: budokan.contract_address,
        nums_tournament_id: 1,
        ls2_tournament_id: 2,
        dw_tournament_id: 3,
        dark_shuffle_tournament_id: 4,
        glitchbomb_tournament_id: 5,
    };

    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_tournament_config(config);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Try to claim - should panic because ClaimContract is not on allowlist
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient);
    stop_cheat_caller_address(claim_contract.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_only_forwarder_can_claim() {
    let claim_contract = deploy_claim_contract();
    let budokan = deploy_budokan_mock();
    let recipient = RECIPIENT();
    let unauthorized = contract_address_const::<'UNAUTHORIZED'>();

    setup_tournament_config(claim_contract, budokan);

    // Try to claim from unauthorized address - should panic
    start_cheat_caller_address(claim_contract.contract_address, unauthorized);
    claim_contract.claim_from_forwarder(recipient);
    stop_cheat_caller_address(claim_contract.contract_address);
}

#[test]
fn test_mass_claiming() {
    let claim_contract = deploy_claim_contract();
    let budokan = deploy_budokan_mock();

    setup_tournament_config(claim_contract, budokan);

    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());

    // Claim for 10 recipients
    let mut i: u32 = 1;
    loop {
        if i > 10 {
            break;
        }

        let recipient_felt: felt252 = (1000 + i).into();
        let recipient: ContractAddress = recipient_felt.try_into().unwrap();
        claim_contract.claim_from_forwarder(recipient);

        i += 1;
    };

    stop_cheat_caller_address(claim_contract.contract_address);

    // Verify all tournaments have 10 entries each
    let nums_entries = budokan.get_tournament_entry_count(1);
    let ls2_entries = budokan.get_tournament_entry_count(2);
    let dw_entries = budokan.get_tournament_entry_count(3);
    let dark_shuffle_entries = budokan.get_tournament_entry_count(4);
    let glitchbomb_entries = budokan.get_tournament_entry_count(5);

    assert(nums_entries == 10, 'Should have 10 Nums entries');
    assert(ls2_entries == 10, 'Should have 10 LS2 entries');
    assert(dw_entries == 10, 'Should have 10 DW entries');
    assert(dark_shuffle_entries == 10, 'Should have 10 DS entries');
    assert(glitchbomb_entries == 10, 'Should have 10 GB entries');

    // Verify total entries (10 users * 5 games = 50 entries)
    let total_entries = budokan.get_total_entries();
    assert(total_entries == 50, 'Should have 50 total entries');
}

#[test]
fn test_check_unclaimed_address() {
    let claim_contract = deploy_claim_contract();
    let unclaimed_address = contract_address_const::<'UNCLAIMED'>();

    // Verify address has not claimed
    assert(!claim_contract.has_claimed(unclaimed_address), 'Should not be claimed');
}
