import { RpcProvider, Contract, Account, shortString, cairo } from "starknet";
import fs from "fs";
import dotenv from "dotenv";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load .env from scripts directory
dotenv.config({ path: path.join(__dirname, ".env") });

// Configuration
const NETWORK = process.env.NETWORK || "sepolia"; // sepolia, mainnet, or devnet
const CLAIM_CONTRACT_ADDRESS = process.env.CLAIM_CONTRACT_ADDRESS;
const ACCOUNT_ADDRESS = process.env.ACCOUNT_ADDRESS;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

// RPC endpoints
const RPC_ENDPOINTS = {
  sepolia: "https://starknet-sepolia.public.blastapi.io/rpc/v0_7",
  mainnet: "https://starknet-mainnet.public.blastapi.io/rpc/v0_7",
  devnet: "http://localhost:5050/rpc",
};

// Mystery token configuration
// Token amounts with 18 decimals
const MYSTERY_TOKEN_CONFIG = [
  {
    name: "CREDITS",
    address: process.env.CREDITS_TOKEN_ADDRESS,
    amount: "150000000000000000000", // 150 tokens
  },
  {
    name: "NUMS",
    address: process.env.NUMS_TOKEN_ADDRESS,
    amount: "2000000000000000000000", // 2000 tokens
  },
  {
    name: "PAPER",
    address: process.env.PAPER_TOKEN_ADDRESS,
    amount: "3000000000000000000000", // 3000 tokens
  },
  {
    name: "LORDS",
    address: process.env.LORDS_TOKEN_ADDRESS,
    amount: "75000000000000000000", // 75 tokens
  },
];

// Load contract ABI
function loadContractABI() {
  try {
    const abiPath = "./target/dev/booster_pack_devconnect_ClaimContract.contract_class.json";
    const contractClass = JSON.parse(fs.readFileSync(abiPath, "utf8"));
    return contractClass.abi;
  } catch (error) {
    console.error("Error loading contract ABI:", error.message);
    console.log("Make sure to run 'scarb build' first to generate the ABI");
    process.exit(1);
  }
}

// Initialize provider and account
function initializeStarknet() {
  if (!CLAIM_CONTRACT_ADDRESS) {
    throw new Error("CLAIM_CONTRACT_ADDRESS not set in .env file");
  }
  if (!ACCOUNT_ADDRESS) {
    throw new Error("ACCOUNT_ADDRESS not set in .env file");
  }
  if (!PRIVATE_KEY) {
    throw new Error("PRIVATE_KEY not set in .env file");
  }

  const provider = new RpcProvider({ nodeUrl: RPC_ENDPOINTS[NETWORK] });
  const account = new Account(provider, ACCOUNT_ADDRESS, PRIVATE_KEY);

  return { provider, account };
}

// Set a single mystery token configuration
async function setMysteryTokenConfig(contract, account, tokenIndex, config) {
  console.log(`\n📝 Setting token config for index ${tokenIndex} (${config.name})...`);
  console.log(`   Token Address: ${config.address}`);
  console.log(`   Amount: ${config.amount}`);

  if (!config.address) {
    console.error(`❌ Token address not set for ${config.name}. Please update .env file.`);
    return false;
  }

  try {
    const mysteryTokenConfig = {
      token_address: config.address,
      amount: cairo.uint256(config.amount),
    };

    const call = contract.populate("set_mystery_token_config", [
      tokenIndex,
      mysteryTokenConfig,
    ]);

    const { transaction_hash } = await account.execute(call);
    console.log(`   Transaction hash: ${transaction_hash}`);

    // Wait for transaction
    console.log("   Waiting for transaction confirmation...");
    await account.waitForTransaction(transaction_hash);
    console.log(`✅ Successfully configured ${config.name}`);
    return true;
  } catch (error) {
    console.error(`❌ Error setting config for ${config.name}:`, error.message);
    return false;
  }
}

// Set all mystery tokens at once (batch operation)
async function setAllMysteryTokens(contract, account, configs) {
  console.log("\n📦 Setting all mystery tokens in a single transaction...");

  // Check if all addresses are set
  const missingTokens = configs.filter((c) => !c.address);
  if (missingTokens.length > 0) {
    console.error(
      `❌ Missing token addresses for: ${missingTokens.map((t) => t.name).join(", ")}`
    );
    console.error("Please update your .env file with all token addresses.");
    return false;
  }

  try {
    const mysteryTokenConfigs = configs.map((config) => ({
      token_address: config.address,
      amount: cairo.uint256(config.amount),
    }));

    const call = contract.populate("set_all_mystery_tokens", [mysteryTokenConfigs]);

    const { transaction_hash } = await account.execute(call);
    console.log(`   Transaction hash: ${transaction_hash}`);

    // Wait for transaction
    console.log("   Waiting for transaction confirmation...");
    await account.waitForTransaction(transaction_hash);
    console.log("✅ Successfully configured all mystery tokens");
    return true;
  } catch (error) {
    console.error("❌ Error setting all mystery tokens:", error.message);
    return false;
  }
}

// Get and display current mystery token configuration
async function getMysteryTokenConfig(contract, tokenIndex) {
  try {
    const config = await contract.get_mystery_token_config(tokenIndex);
    return {
      token_address: config.token_address,
      amount: config.amount.toString(),
    };
  } catch (error) {
    console.error(`Error getting config for index ${tokenIndex}:`, error.message);
    return null;
  }
}

// Display current configuration
async function displayCurrentConfig(contract) {
  console.log("\n📊 Current Mystery Token Configuration:");
  console.log("═".repeat(70));

  for (let i = 0; i < MYSTERY_TOKEN_CONFIG.length; i++) {
    const config = await getMysteryTokenConfig(contract, i);
    if (config) {
      const tokenName = MYSTERY_TOKEN_CONFIG[i].name;
      console.log(`\n[${i}] ${tokenName}:`);
      console.log(`    Token Address: ${config.token_address}`);
      console.log(`    Amount: ${config.amount}`);
    }
  }
  console.log("\n" + "═".repeat(70));
}

// Main execution
async function main() {
  console.log("\n🎰 Mystery Token Configuration Script");
  console.log("═".repeat(70));
  console.log(`Network: ${NETWORK}`);
  console.log(`Claim Contract: ${CLAIM_CONTRACT_ADDRESS}`);
  console.log("═".repeat(70));

  const { provider, account } = initializeStarknet();
  const abi = loadContractABI();
  const contract = new Contract(abi, CLAIM_CONTRACT_ADDRESS, provider);
  contract.connect(account);

  // Get command line arguments
  const args = process.argv.slice(2);
  const command = args[0] || "view";

  if (command === "view" || command === "status") {
    // View current configuration
    await displayCurrentConfig(contract);
  } else if (command === "set-single") {
    // Set a single token config
    const tokenIndex = parseInt(args[1]);
    if (isNaN(tokenIndex) || tokenIndex < 0 || tokenIndex >= MYSTERY_TOKEN_CONFIG.length) {
      console.error(
        `❌ Invalid token index. Must be between 0 and ${MYSTERY_TOKEN_CONFIG.length - 1}`
      );
      process.exit(1);
    }

    const success = await setMysteryTokenConfig(
      contract,
      account,
      tokenIndex,
      MYSTERY_TOKEN_CONFIG[tokenIndex]
    );

    if (success) {
      await displayCurrentConfig(contract);
    }
  } else if (command === "set-all") {
    // Set all tokens in batch
    const success = await setAllMysteryTokens(contract, account, MYSTERY_TOKEN_CONFIG);

    if (success) {
      await displayCurrentConfig(contract);
    }
  } else {
    console.log("\n📖 Usage:");
    console.log("  node scripts/configure-mystery-tokens.js [command]");
    console.log("\nCommands:");
    console.log("  view         - Display current mystery token configuration (default)");
    console.log("  status       - Alias for 'view'");
    console.log("  set-single <index> - Set configuration for a single token (0-3)");
    console.log("  set-all      - Set all mystery token configurations in one transaction");
    console.log("\nExamples:");
    console.log("  node scripts/configure-mystery-tokens.js view");
    console.log("  node scripts/configure-mystery-tokens.js set-single 0");
    console.log("  node scripts/configure-mystery-tokens.js set-all");
    console.log("\nRequired Environment Variables (.env):");
    console.log("  CLAIM_CONTRACT_ADDRESS - Address of deployed claim contract");
    console.log("  ACCOUNT_ADDRESS        - Your Starknet account address");
    console.log("  PRIVATE_KEY           - Your account private key");
    console.log("  CREDITS_TOKEN_ADDRESS - CREDITS ERC20 token address");
    console.log("  NUMS_TOKEN_ADDRESS    - NUMS ERC20 token address");
    console.log("  PAPER_TOKEN_ADDRESS   - PAPER ERC20 token address");
    console.log("  LORDS_TOKEN_ADDRESS   - LORDS ERC20 token address");
    console.log("  NETWORK               - Network to use (sepolia/mainnet/devnet)");
  }
}

main()
  .then(() => {
    console.log("\n✨ Done!");
    process.exit(0);
  })
  .catch((error) => {
    console.error("\n❌ Error:", error);
    process.exit(1);
  });
