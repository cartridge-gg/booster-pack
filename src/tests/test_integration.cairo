use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const};
use crate::{IClaimDispatcher, IClaimDispatcherTrait, TournamentConfig};
use crate::mocks::budokan_mock::{IBudokanMockDispatcher, IBudokanMockDispatcherTrait};
use crate::mocks::erc20_mock::{IERC20MockDispatcher, IERC20MockDispatcherTrait};

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

fn TREASURY() -> ContractAddress {
    contract_address_const::<'TREASURY'>()
}

fn deploy_claim_contract(
    lords_token: ContractAddress,
    nums_token: ContractAddress,
    survivor_token: ContractAddress,
    credits_token: ContractAddress,
    paper_token: ContractAddress,
) -> IClaimDispatcher {
    let contract = declare("ClaimContract").unwrap().contract_class();
    let (contract_address, _) = contract
        .deploy(
            @array![
                OWNER().into(),
                FORWARDER().into(),
                TREASURY().into(),
                lords_token.into(),
                nums_token.into(),
                survivor_token.into(),
                credits_token.into(),
                paper_token.into(),
            ]
        )
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
fn test_claim_paper_tokens() {
    let recipient = RECIPIENT();
    let treasury = TREASURY();

    // Deploy ERC20 token and fund Treasury
    let token_supply: u256 = 10000000000000000000000_u256; // 10,000 tokens
    let zero_address = contract_address_const::<0x0>();

    // Deploy claim contract
    let claim_contract = deploy_claim_contract(
        zero_address, // lords (not needed for this test)
        zero_address, // nums
        zero_address, // survivor
        zero_address, // credits
        zero_address, // paper (will be set after deployment)
    );

    // Deploy token to treasury
    let token_address = deploy_erc20("Paper", "PAPER", token_supply, treasury);

    // Set the paper token address
    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_paper_token(token_address);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Approve claim contract to spend from treasury
    let token = IERC20MockDispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, treasury);
    token.approve(claim_contract.contract_address, token_supply);
    stop_cheat_caller_address(token_address);

    let amount: u256 = 150000000000000000000_u256; // 150 tokens

    // Claim tokens using new entrypoint
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_paper_from_forwarder(recipient, amount);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Verify recipient received tokens
    let balance = token.balance_of(recipient);
    assert(balance == 150000000000000000000_u256, 'Wrong token balance');
}

#[test]
fn test_multi_claim_same_user() {
    // Test that the same user can claim multiple different items
    let recipient = RECIPIENT();
    let treasury = TREASURY();
    let zero_address = contract_address_const::<0x0>();

    let claim_contract = deploy_claim_contract(
        zero_address, zero_address, zero_address, zero_address, zero_address,
    );

    // Deploy two different ERC20 tokens to treasury
    let token_supply: u256 = 10000000000000000000000_u256;
    let paper_address = deploy_erc20("Paper", "PAPER", token_supply, treasury);
    let lords_address = deploy_erc20("Lords", "LORDS", token_supply, treasury);

    // Set token addresses
    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_paper_token(paper_address);
    claim_contract.set_lords_token(lords_address);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Approve claim contract to spend from treasury
    let paper_token = IERC20MockDispatcher { contract_address: paper_address };
    start_cheat_caller_address(paper_address, treasury);
    paper_token.approve(claim_contract.contract_address, token_supply);
    stop_cheat_caller_address(paper_address);

    let lords_token = IERC20MockDispatcher { contract_address: lords_address };
    start_cheat_caller_address(lords_address, treasury);
    lords_token.approve(claim_contract.contract_address, token_supply);
    stop_cheat_caller_address(lords_address);

    let paper_amount: u256 = 150000000000000000000_u256;
    let lords_amount: u256 = 75000000000000000000_u256;

    // Same user claims PAPER
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_paper_from_forwarder(recipient, paper_amount);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Same user claims LORDS (should succeed - no duplicate claim check)
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_lords_from_forwarder(recipient, lords_amount);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Verify both claims succeeded
    let paper_balance = paper_token.balance_of(recipient);
    assert(paper_balance == 150000000000000000000_u256, 'Wrong PAPER balance');

    let lords_balance = lords_token.balance_of(recipient);
    assert(lords_balance == 75000000000000000000_u256, 'Wrong LORDS balance');
}

// ========================================
// MYSTERY_ASSET Tournament Claim Tests
// ========================================

#[test]
fn test_claim_mystery_tournaments() {
    let zero_address = contract_address_const::<0x0>();
    let claim_contract = deploy_claim_contract(
        zero_address, zero_address, zero_address, zero_address, zero_address,
    );
    let budokan = deploy_budokan_mock();
    let recipient = RECIPIENT();

    setup_tournament_config(claim_contract, budokan);

    // Claim tournament entries using new entrypoint
    // Amount parameter is not used for mystery claims, but included for consistency
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_mystery_from_forwarder(recipient, 0);
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
}

// ========================================
// Mixed Claim Type Tests
// ========================================

#[test]
fn test_mixed_claim_types() {
    let zero_address = contract_address_const::<0x0>();
    let treasury = TREASURY();
    let claim_contract = deploy_claim_contract(
        zero_address, zero_address, zero_address, zero_address, zero_address,
    );
    let budokan = deploy_budokan_mock();

    setup_tournament_config(claim_contract, budokan);

    // Deploy tokens to treasury
    let token_supply: u256 = 100000000000000000000000_u256;
    let paper_address = deploy_erc20("Paper", "PAPER", token_supply, treasury);
    let lords_address = deploy_erc20("Lords", "LORDS", token_supply, treasury);

    // Set token addresses
    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_paper_token(paper_address);
    claim_contract.set_lords_token(lords_address);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Approve claim contract to spend from treasury
    let paper_token = IERC20MockDispatcher { contract_address: paper_address };
    start_cheat_caller_address(paper_address, treasury);
    paper_token.approve(claim_contract.contract_address, token_supply);
    stop_cheat_caller_address(paper_address);

    let lords_token = IERC20MockDispatcher { contract_address: lords_address };
    start_cheat_caller_address(lords_address, treasury);
    lords_token.approve(claim_contract.contract_address, token_supply);
    stop_cheat_caller_address(lords_address);

    // Recipient 1: Claims PAPER
    let recipient1 = contract_address_const::<'RECIPIENT_1'>();
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_paper_from_forwarder(recipient1, 150000000000000000000_u256);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Recipient 2: Claims MYSTERY (tournaments)
    let recipient2 = contract_address_const::<'RECIPIENT_2'>();
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_mystery_from_forwarder(recipient2, 0);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Recipient 3: Claims LORDS
    let recipient3 = contract_address_const::<'RECIPIENT_3'>();
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_lords_from_forwarder(recipient3, 75000000000000000000_u256);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Verify Recipient 1 got PAPER
    let r1_balance = paper_token.balance_of(recipient1);
    assert(r1_balance == 150000000000000000000_u256, 'R1: Wrong PAPER balance');

    // Verify Recipient 2 got tournament entries
    let total_entries = budokan.get_total_entries();
    assert(total_entries == 4, 'R2: Wrong tournament entries');

    // Verify Recipient 3 got LORDS
    let r3_balance = lords_token.balance_of(recipient3);
    assert(r3_balance == 75000000000000000000_u256, 'R3: Wrong LORDS balance');
}

// ========================================
// Access Control Tests
// ========================================

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_only_forwarder_can_claim() {
    let zero_address = contract_address_const::<0x0>();
    let treasury = TREASURY();
    let claim_contract = deploy_claim_contract(
        zero_address, zero_address, zero_address, zero_address, zero_address,
    );
    let unauthorized = contract_address_const::<'UNAUTHORIZED'>();
    let recipient = RECIPIENT();

    let token_supply: u256 = 10000000000000000000000_u256;
    let token_address = deploy_erc20("Paper", "PAPER", token_supply, treasury);

    // Set token address
    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_paper_token(token_address);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Approve claim contract
    let token = IERC20MockDispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, treasury);
    token.approve(claim_contract.contract_address, token_supply);
    stop_cheat_caller_address(token_address);

    // Try to claim from unauthorized address - should panic
    start_cheat_caller_address(claim_contract.contract_address, unauthorized);
    claim_contract.claim_paper_from_forwarder(recipient, 150000000000000000000_u256);
    stop_cheat_caller_address(claim_contract.contract_address);
}

#[test]
fn test_tournament_config() {
    let zero_address = contract_address_const::<0x0>();
    let claim_contract = deploy_claim_contract(
        zero_address, zero_address, zero_address, zero_address, zero_address,
    );
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
    let zero_address = contract_address_const::<0x0>();
    let claim_contract = deploy_claim_contract(
        zero_address, zero_address, zero_address, zero_address, zero_address,
    );
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

    // Claim tournament entry
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_mystery_from_forwarder(recipient, 0);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Verify only one entry was created
    let tournament_entries = budokan.get_tournament_entry_count(1);
    assert(tournament_entries == 1, 'Should have 1 entry');

    let total_entries = budokan.get_total_entries();
    assert(total_entries == 1, 'Should have 1 total entry');
}
