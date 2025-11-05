use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const};
use crate::{IClaimDispatcher, IClaimDispatcherTrait, MysteryTokenConfig};
use crate::constants::identifier::{ERC_20, ERC_721, MYSTERY_ASSET};
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

fn deploy_claim_contract() -> IClaimDispatcher {
    let contract = declare("ClaimContract").unwrap().contract_class();
    let (contract_address, _) = contract
        .deploy(@array![OWNER().into(), FORWARDER().into()])
        .unwrap();
    IClaimDispatcher { contract_address }
}

fn deploy_erc20(name: ByteArray, symbol: ByteArray, supply: u256, recipient: ContractAddress) -> ContractAddress {
    let contract = declare("ERC20Mock").unwrap().contract_class();
    let mut calldata = array![];
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    supply.serialize(ref calldata);
    recipient.serialize(ref calldata);

    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

// ========================================
// Mystery Asset Configuration Tests
// ========================================

#[test]
fn test_set_mystery_token_config() {
    println!("=== Testing Set Mystery Token Config ===\n");

    let claim_contract = deploy_claim_contract();

    // Deploy a test token
    let token_supply: u256 = 10000000000000000000000_u256;
    let token_address = deploy_erc20("Credits", "CREDITS", token_supply, claim_contract.contract_address);

    println!("Token deployed at: {:?}", token_address);

    // Set config for index 0
    let config = MysteryTokenConfig {
        token_address,
        amount: 150000000000000000000_u256,
    };

    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_mystery_token_config(0, config);
    stop_cheat_caller_address(claim_contract.contract_address);

    // Read back the config
    let read_config = claim_contract.get_mystery_token_config(0);

    println!("Config set successfully");
    println!("Token address: {:?}", read_config.token_address);
    println!("Amount: {}", read_config.amount);

    assert(read_config.token_address == token_address, 'Address mismatch');
    assert(read_config.amount == 150000000000000000000_u256, 'Amount mismatch');

    println!("\n[PASS] Mystery token config set successfully");
}

#[test]
fn test_set_all_mystery_tokens() {
    println!("=== Testing Set All Mystery Tokens ===\n");

    let claim_contract = deploy_claim_contract();

    // Deploy all 5 tokens
    let credits_address = deploy_erc20("Credits", "CREDITS", 10000000000000000000000_u256, claim_contract.contract_address);
    let nums_address = deploy_erc20("Nums", "NUMS", 20000000000000000000000_u256, claim_contract.contract_address);
    let paper_address = deploy_erc20("Paper", "PAPER", 30000000000000000000000_u256, claim_contract.contract_address);
    let lords_address = deploy_erc20("Lords", "LORDS", 5000000000000000000000_u256, claim_contract.contract_address);
    let survivor_address = deploy_erc20("Survivor", "SURVIVOR", 1000000000000000000000_u256, claim_contract.contract_address);

    println!("All tokens deployed");

    // Create configs array
    let configs = array![
        MysteryTokenConfig { token_address: credits_address, amount: 150000000000000000000_u256 },
        MysteryTokenConfig { token_address: nums_address, amount: 2000000000000000000000_u256 },
        MysteryTokenConfig { token_address: paper_address, amount: 3000000000000000000000_u256 },
        MysteryTokenConfig { token_address: lords_address, amount: 75000000000000000000_u256 },
        MysteryTokenConfig { token_address: survivor_address, amount: 10000000000000000000_u256 },
    ];

    // Set all configs
    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_all_mystery_tokens(configs.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    println!("\nVerifying all configs:");

    // Verify each config
    let config0 = claim_contract.get_mystery_token_config(0);
    assert(config0.token_address == credits_address, 'Config 0 address wrong');
    assert(config0.amount == 150000000000000000000_u256, 'Config 0 amount wrong');
    println!("  [0] CREDITS: {} tokens", config0.amount);

    let config1 = claim_contract.get_mystery_token_config(1);
    assert(config1.token_address == nums_address, 'Config 1 address wrong');
    assert(config1.amount == 2000000000000000000000_u256, 'Config 1 amount wrong');
    println!("  [1] NUMS: {} tokens", config1.amount);

    let config2 = claim_contract.get_mystery_token_config(2);
    assert(config2.token_address == paper_address, 'Config 2 address wrong');
    assert(config2.amount == 3000000000000000000000_u256, 'Config 2 amount wrong');
    println!("  [2] PAPER: {} tokens", config2.amount);

    let config3 = claim_contract.get_mystery_token_config(3);
    assert(config3.token_address == lords_address, 'Config 3 address wrong');
    assert(config3.amount == 75000000000000000000_u256, 'Config 3 amount wrong');
    println!("  [3] LORDS: {} tokens", config3.amount);

    let config4 = claim_contract.get_mystery_token_config(4);
    assert(config4.token_address == survivor_address, 'Config 4 address wrong');
    assert(config4.amount == 10000000000000000000_u256, 'Config 4 amount wrong');
    println!("  [4] SURVIVOR: {} tokens", config4.amount);

    println!("\n[PASS] All mystery tokens configured successfully");
}

// ========================================
// Mystery Asset Claim Tests
// ========================================

#[test]
fn test_mystery_asset_random_selection() {
    println!("=== Testing Mystery Asset Random Selection ===\n");

    let claim_contract = deploy_claim_contract();
    let recipient = RECIPIENT();

    // Deploy and configure all 5 tokens
    let credits_address = deploy_erc20("Credits", "CREDITS", 10000000000000000000000_u256, claim_contract.contract_address);
    let nums_address = deploy_erc20("Nums", "NUMS", 20000000000000000000000_u256, claim_contract.contract_address);
    let paper_address = deploy_erc20("Paper", "PAPER", 30000000000000000000000_u256, claim_contract.contract_address);
    let lords_address = deploy_erc20("Lords", "LORDS", 5000000000000000000000_u256, claim_contract.contract_address);
    let survivor_address = deploy_erc20("Survivor", "SURVIVOR", 1000000000000000000000_u256, claim_contract.contract_address);

    let configs = array![
        MysteryTokenConfig { token_address: credits_address, amount: 150000000000000000000_u256 },
        MysteryTokenConfig { token_address: nums_address, amount: 2000000000000000000000_u256 },
        MysteryTokenConfig { token_address: paper_address, amount: 3000000000000000000000_u256 },
        MysteryTokenConfig { token_address: lords_address, amount: 75000000000000000000_u256 },
        MysteryTokenConfig { token_address: survivor_address, amount: 10000000000000000000_u256 },
    ];

    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_all_mystery_tokens(configs.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    println!("Mystery tokens configured\n");

    // Create mystery asset leaf data
    let mut mystery_data = array![];
    Serde::serialize(@0_u256, ref mystery_data);
    Serde::serialize(@contract_address_const::<0x0>(), ref mystery_data);
    Serde::serialize(@MYSTERY_ASSET, ref mystery_data);

    println!("Claiming mystery asset for recipient: {:?}", recipient);

    // Claim mystery asset
    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient, mystery_data.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    // Check which token was received
    let credits_token = IERC20MockDispatcher { contract_address: credits_address };
    let nums_token = IERC20MockDispatcher { contract_address: nums_address };
    let paper_token = IERC20MockDispatcher { contract_address: paper_address };
    let lords_token = IERC20MockDispatcher { contract_address: lords_address };
    let survivor_token = IERC20MockDispatcher { contract_address: survivor_address };

    let credits_balance = credits_token.balance_of(recipient);
    let nums_balance = nums_token.balance_of(recipient);
    let paper_balance = paper_token.balance_of(recipient);
    let lords_balance = lords_token.balance_of(recipient);
    let survivor_balance = survivor_token.balance_of(recipient);

    println!("\n=== Recipient Balances ===");
    println!("CREDITS: {}", credits_balance);
    println!("NUMS: {}", nums_balance);
    println!("PAPER: {}", paper_balance);
    println!("LORDS: {}", lords_balance);
    println!("SURVIVOR: {}", survivor_balance);

    // Verify exactly one token was received
    let mut non_zero_count = 0;
    if credits_balance > 0 { non_zero_count += 1; }
    if nums_balance > 0 { non_zero_count += 1; }
    if paper_balance > 0 { non_zero_count += 1; }
    if lords_balance > 0 { non_zero_count += 1; }
    if survivor_balance > 0 { non_zero_count += 1; }

    assert(non_zero_count == 1, 'Should receive exactly 1 token');

    println!("\n[PASS] Mystery asset claim successful - received 1 random token");
}

#[test]
fn test_mystery_asset_distribution() {
    println!("=== Testing Mystery Asset Distribution ===\n");

    let claim_contract = deploy_claim_contract();

    // Deploy and configure all 5 tokens with large supply
    let credits_address = deploy_erc20("Credits", "CREDITS", 100000000000000000000000_u256, claim_contract.contract_address);
    let nums_address = deploy_erc20("Nums", "NUMS", 200000000000000000000000_u256, claim_contract.contract_address);
    let paper_address = deploy_erc20("Paper", "PAPER", 300000000000000000000000_u256, claim_contract.contract_address);
    let lords_address = deploy_erc20("Lords", "LORDS", 50000000000000000000000_u256, claim_contract.contract_address);
    let survivor_address = deploy_erc20("Survivor", "SURVIVOR", 10000000000000000000000_u256, claim_contract.contract_address);

    let configs = array![
        MysteryTokenConfig { token_address: credits_address, amount: 150000000000000000000_u256 },
        MysteryTokenConfig { token_address: nums_address, amount: 2000000000000000000000_u256 },
        MysteryTokenConfig { token_address: paper_address, amount: 3000000000000000000000_u256 },
        MysteryTokenConfig { token_address: lords_address, amount: 75000000000000000000_u256 },
        MysteryTokenConfig { token_address: survivor_address, amount: 10000000000000000000_u256 },
    ];

    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_all_mystery_tokens(configs.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    println!("Claiming 25 mystery assets to test distribution...\n");

    // Claim 25 mystery assets with different recipients to get variety
    let mut i: u32 = 0;
    loop {
        if i >= 25 {
            break;
        }

        // Create different recipient addresses for variety
        let recipient_felt: felt252 = (i + 1000).into();
        let recipient: ContractAddress = recipient_felt.try_into().unwrap();

        let mut mystery_data = array![];
        Serde::serialize(@0_u256, ref mystery_data);
        Serde::serialize(@contract_address_const::<0x0>(), ref mystery_data);
        Serde::serialize(@MYSTERY_ASSET, ref mystery_data);

        start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
        claim_contract.claim_from_forwarder(recipient, mystery_data.span());
        stop_cheat_caller_address(claim_contract.contract_address);

        i += 1;
    };

    // Check contract balances to see distribution
    let credits_token = IERC20MockDispatcher { contract_address: credits_address };
    let nums_token = IERC20MockDispatcher { contract_address: nums_address };
    let paper_token = IERC20MockDispatcher { contract_address: paper_address };
    let lords_token = IERC20MockDispatcher { contract_address: lords_address };
    let survivor_token = IERC20MockDispatcher { contract_address: survivor_address };

    let initial_credits = 100000000000000000000000_u256;
    let initial_nums = 200000000000000000000000_u256;
    let initial_paper = 300000000000000000000000_u256;
    let initial_lords = 50000000000000000000000_u256;
    let initial_survivor = 10000000000000000000000_u256;

    let remaining_credits = credits_token.balance_of(claim_contract.contract_address);
    let remaining_nums = nums_token.balance_of(claim_contract.contract_address);
    let remaining_paper = paper_token.balance_of(claim_contract.contract_address);
    let remaining_lords = lords_token.balance_of(claim_contract.contract_address);
    let remaining_survivor = survivor_token.balance_of(claim_contract.contract_address);

    let credits_claimed = initial_credits - remaining_credits;
    let nums_claimed = initial_nums - remaining_nums;
    let paper_claimed = initial_paper - remaining_paper;
    let lords_claimed = initial_lords - remaining_lords;
    let survivor_claimed = initial_survivor - remaining_survivor;

    println!("=== Distribution Results (25 claims) ===");
    println!("CREDITS claimed: {} (count: {})", credits_claimed, credits_claimed / 150000000000000000000_u256);
    println!("NUMS claimed: {} (count: {})", nums_claimed, nums_claimed / 2000000000000000000000_u256);
    println!("PAPER claimed: {} (count: {})", paper_claimed, paper_claimed / 3000000000000000000000_u256);
    println!("LORDS claimed: {} (count: {})", lords_claimed, lords_claimed / 75000000000000000000_u256);
    println!("SURVIVOR claimed: {} (count: {})", survivor_claimed, survivor_claimed / 10000000000000000000_u256);

    // Verify at least 3 different token types were distributed (with 25 claims, very likely)
    let mut token_types_distributed: u32 = 0;
    if credits_claimed > 0 { token_types_distributed += 1; }
    if nums_claimed > 0 { token_types_distributed += 1; }
    if paper_claimed > 0 { token_types_distributed += 1; }
    if lords_claimed > 0 { token_types_distributed += 1; }
    if survivor_claimed > 0 { token_types_distributed += 1; }

    println!("\nToken types distributed: {}/5", token_types_distributed);

    assert(token_types_distributed > 2_u32, 'Should distribute 3+ types');

    println!("\n[PASS] Mystery asset distribution working correctly");
}

#[test]
fn test_mystery_asset_with_different_recipients() {
    println!("=== Testing Mystery Asset with Different Recipients ===\n");

    let claim_contract = deploy_claim_contract();
    let recipient1 = RECIPIENT();
    let recipient2 = RECIPIENT_2();

    // Deploy and configure tokens
    let credits_address = deploy_erc20("Credits", "CREDITS", 10000000000000000000000_u256, claim_contract.contract_address);
    let nums_address = deploy_erc20("Nums", "NUMS", 20000000000000000000000_u256, claim_contract.contract_address);
    let paper_address = deploy_erc20("Paper", "PAPER", 30000000000000000000000_u256, claim_contract.contract_address);
    let lords_address = deploy_erc20("Lords", "LORDS", 5000000000000000000000_u256, claim_contract.contract_address);
    let survivor_address = deploy_erc20("Survivor", "SURVIVOR", 1000000000000000000000_u256, claim_contract.contract_address);

    let configs = array![
        MysteryTokenConfig { token_address: credits_address, amount: 150000000000000000000_u256 },
        MysteryTokenConfig { token_address: nums_address, amount: 2000000000000000000000_u256 },
        MysteryTokenConfig { token_address: paper_address, amount: 3000000000000000000000_u256 },
        MysteryTokenConfig { token_address: lords_address, amount: 75000000000000000000_u256 },
        MysteryTokenConfig { token_address: survivor_address, amount: 10000000000000000000_u256 },
    ];

    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_all_mystery_tokens(configs.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    // Claim for recipient 1
    println!("Claiming mystery asset for recipient 1: {:?}", recipient1);
    let mut mystery_data1 = array![];
    Serde::serialize(@0_u256, ref mystery_data1);
    Serde::serialize(@contract_address_const::<0x0>(), ref mystery_data1);
    Serde::serialize(@MYSTERY_ASSET, ref mystery_data1);

    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient1, mystery_data1.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    // Claim for recipient 2
    println!("Claiming mystery asset for recipient 2: {:?}", recipient2);
    let mut mystery_data2 = array![];
    Serde::serialize(@0_u256, ref mystery_data2);
    Serde::serialize(@contract_address_const::<0x0>(), ref mystery_data2);
    Serde::serialize(@MYSTERY_ASSET, ref mystery_data2);

    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient2, mystery_data2.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    // Check balances for both recipients
    let credits_token = IERC20MockDispatcher { contract_address: credits_address };
    let nums_token = IERC20MockDispatcher { contract_address: nums_address };
    let paper_token = IERC20MockDispatcher { contract_address: paper_address };
    let lords_token = IERC20MockDispatcher { contract_address: lords_address };
    let survivor_token = IERC20MockDispatcher { contract_address: survivor_address };

    println!("\n=== Recipient 1 Balances ===");
    let r1_credits = credits_token.balance_of(recipient1);
    let r1_nums = nums_token.balance_of(recipient1);
    let r1_paper = paper_token.balance_of(recipient1);
    let r1_lords = lords_token.balance_of(recipient1);
    let r1_survivor = survivor_token.balance_of(recipient1);
    println!("CREDITS: {}", r1_credits);
    println!("NUMS: {}", r1_nums);
    println!("PAPER: {}", r1_paper);
    println!("LORDS: {}", r1_lords);
    println!("SURVIVOR: {}", r1_survivor);

    println!("\n=== Recipient 2 Balances ===");
    let r2_credits = credits_token.balance_of(recipient2);
    let r2_nums = nums_token.balance_of(recipient2);
    let r2_paper = paper_token.balance_of(recipient2);
    let r2_lords = lords_token.balance_of(recipient2);
    let r2_survivor = survivor_token.balance_of(recipient2);
    println!("CREDITS: {}", r2_credits);
    println!("NUMS: {}", r2_nums);
    println!("PAPER: {}", r2_paper);
    println!("LORDS: {}", r2_lords);
    println!("SURVIVOR: {}", r2_survivor);

    // Verify each recipient received exactly one token
    let mut r1_count = 0;
    if r1_credits > 0 { r1_count += 1; }
    if r1_nums > 0 { r1_count += 1; }
    if r1_paper > 0 { r1_count += 1; }
    if r1_lords > 0 { r1_count += 1; }
    if r1_survivor > 0 { r1_count += 1; }

    let mut r2_count = 0;
    if r2_credits > 0 { r2_count += 1; }
    if r2_nums > 0 { r2_count += 1; }
    if r2_paper > 0 { r2_count += 1; }
    if r2_lords > 0 { r2_count += 1; }
    if r2_survivor > 0 { r2_count += 1; }

    assert(r1_count == 1, 'Recipient 1 should get 1 token');
    assert(r2_count == 1, 'Recipient 2 should get 1 token');

    println!("\n[PASS] Different recipients received mystery assets successfully");
}

// ========================================
// Complete Integration Test
// ========================================

#[test]
fn test_complete_integration_with_mystery_assets() {
    println!("=== Testing Complete Integration with Mystery Assets ===\n");

    let claim_contract = deploy_claim_contract();
    let recipient = RECIPIENT();

    // Deploy all tokens and configure mystery assets
    let credits_address = deploy_erc20("Credits", "CREDITS", 10000000000000000000000_u256, claim_contract.contract_address);
    let nums_address = deploy_erc20("Nums", "NUMS", 20000000000000000000000_u256, claim_contract.contract_address);
    let paper_address = deploy_erc20("Paper", "PAPER", 30000000000000000000000_u256, claim_contract.contract_address);
    let lords_address = deploy_erc20("Lords", "LORDS", 5000000000000000000000_u256, claim_contract.contract_address);
    let survivor_address = deploy_erc20("Survivor", "SURVIVOR", 1000000000000000000000_u256, claim_contract.contract_address);

    println!("All tokens deployed\n");

    // Configure mystery assets
    let configs = array![
        MysteryTokenConfig { token_address: credits_address, amount: 150000000000000000000_u256 },
        MysteryTokenConfig { token_address: nums_address, amount: 2000000000000000000000_u256 },
        MysteryTokenConfig { token_address: paper_address, amount: 3000000000000000000000_u256 },
        MysteryTokenConfig { token_address: lords_address, amount: 75000000000000000000_u256 },
        MysteryTokenConfig { token_address: survivor_address, amount: 10000000000000000000_u256 },
    ];

    start_cheat_caller_address(claim_contract.contract_address, OWNER());
    claim_contract.set_all_mystery_tokens(configs.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    println!("Mystery assets configured\n");

    // Test sequence: Direct ERC20 claim -> Mystery Asset -> Another Direct ERC20 claim

    // Claim 1: Direct CREDITS claim
    println!("--- Claim 1: Direct CREDITS (150 tokens) ---");
    let mut credits_data = array![];
    Serde::serialize(@150000000000000000000_u256, ref credits_data);
    Serde::serialize(@credits_address, ref credits_data);
    Serde::serialize(@ERC_20, ref credits_data);

    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient, credits_data.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    let credits_token = IERC20MockDispatcher { contract_address: credits_address };
    let balance_after_claim1 = credits_token.balance_of(recipient);
    println!("CREDITS balance: {}\n", balance_after_claim1);
    assert(balance_after_claim1 == 150000000000000000000_u256, 'Direct claim 1 failed');

    // Claim 2: Mystery Asset
    println!("--- Claim 2: Mystery Asset ---");
    let mut mystery_data = array![];
    Serde::serialize(@0_u256, ref mystery_data);
    Serde::serialize(@contract_address_const::<0x0>(), ref mystery_data);
    Serde::serialize(@MYSTERY_ASSET, ref mystery_data);

    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient, mystery_data.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    println!("Mystery asset claimed\n");

    // Claim 3: Direct LORDS claim
    println!("--- Claim 3: Direct LORDS (75 tokens) ---");
    let mut lords_data = array![];
    Serde::serialize(@75000000000000000000_u256, ref lords_data);
    Serde::serialize(@lords_address, ref lords_data);
    Serde::serialize(@ERC_20, ref lords_data);

    start_cheat_caller_address(claim_contract.contract_address, FORWARDER());
    claim_contract.claim_from_forwarder(recipient, lords_data.span());
    stop_cheat_caller_address(claim_contract.contract_address);

    let lords_token = IERC20MockDispatcher { contract_address: lords_address };
    let lords_balance = lords_token.balance_of(recipient);
    println!("LORDS balance: {}\n", lords_balance);
    assert(lords_balance == 75000000000000000000_u256, 'Direct claim 3 failed');

    // Verify final state
    println!("=== Final Recipient Balances ===");
    let final_credits = credits_token.balance_of(recipient);
    let nums_token = IERC20MockDispatcher { contract_address: nums_address };
    let paper_token = IERC20MockDispatcher { contract_address: paper_address };
    let survivor_token = IERC20MockDispatcher { contract_address: survivor_address };

    let final_nums = nums_token.balance_of(recipient);
    let final_paper = paper_token.balance_of(recipient);
    let final_lords = lords_token.balance_of(recipient);
    let final_survivor = survivor_token.balance_of(recipient);

    println!("CREDITS: {}", final_credits);
    println!("NUMS: {}", final_nums);
    println!("PAPER: {}", final_paper);
    println!("LORDS: {}", final_lords);
    println!("SURVIVOR: {}", final_survivor);

    // Verify direct claims worked
    assert(final_credits >= 150000000000000000000_u256, 'CREDITS claim failed');
    assert(final_lords == 75000000000000000000_u256, 'LORDS claim failed');

    // Verify mystery asset gave something
    let total_balance = final_credits + final_nums + final_paper + final_lords + final_survivor;
    let expected_minimum = 150000000000000000000_u256 + 75000000000000000000_u256;
    assert(total_balance > expected_minimum, 'Mystery asset not claimed');

    println!("\n[PASS] Complete integration test with mystery assets successful!");
}
