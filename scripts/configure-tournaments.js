import { Account, Contract, RpcProvider, CallData } from 'starknet';
import * as dotenv from 'dotenv';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

dotenv.config();

// Network configuration
const networks = {
    sepolia: {
        nodeUrl: 'https://starknet-sepolia.public.blastapi.io',
    },
    mainnet: {
        nodeUrl: 'https://starknet-mainnet.public.blastapi.io',
    },
    devnet: {
        nodeUrl: 'http://127.0.0.1:5050',
    }
};

const NETWORK = process.env.NETWORK || 'sepolia';
const CLAIM_CONTRACT_ADDRESS = process.env.CLAIM_CONTRACT_ADDRESS;
const BUDOKAN_ADDRESS = process.env.BUDOKAN_ADDRESS;
const ACCOUNT_ADDRESS = process.env.ACCOUNT_ADDRESS;
const ACCOUNT_PRIVATE_KEY = process.env.ACCOUNT_PRIVATE_KEY;

// Tournament IDs from Budokan
const NUMS_TOURNAMENT_ID = process.env.NUMS_TOURNAMENT_ID;
const LS2_TOURNAMENT_ID = process.env.LS2_TOURNAMENT_ID;
const DW_TOURNAMENT_ID = process.env.DW_TOURNAMENT_ID;
const DARK_SHUFFLE_TOURNAMENT_ID = process.env.DARK_SHUFFLE_TOURNAMENT_ID;
const GLITCHBOMB_TOURNAMENT_ID = process.env.GLITCHBOMB_TOURNAMENT_ID || '0'; // Optional

// Load ABI
function loadABI() {
    const abiPath = join(__dirname, '../target/dev/booster_pack_devconnect_ClaimContract.contract_class.json');
    const contractClass = JSON.parse(readFileSync(abiPath, 'utf8'));
    return contractClass.abi;
}

async function main() {
    const command = process.argv[2];

    if (!CLAIM_CONTRACT_ADDRESS) {
        console.error('❌ CLAIM_CONTRACT_ADDRESS not set in .env');
        process.exit(1);
    }

    // Setup provider and account
    const provider = new RpcProvider({ nodeUrl: networks[NETWORK].nodeUrl });
    const account = new Account(provider, ACCOUNT_ADDRESS, ACCOUNT_PRIVATE_KEY);

    console.log(`🌐 Network: ${NETWORK}`);
    console.log(`📝 ClaimContract: ${CLAIM_CONTRACT_ADDRESS}`);
    console.log(`👤 Account: ${ACCOUNT_ADDRESS}\n`);

    // Load contract
    const abi = loadABI();
    const contract = new Contract(abi, CLAIM_CONTRACT_ADDRESS, provider);
    contract.connect(account);

    if (command === 'view') {
        await viewConfig(contract);
    } else if (command === 'set') {
        await setConfig(contract);
    } else {
        console.log('Usage:');
        console.log('  node configure-tournaments.js view  - View current configuration');
        console.log('  node configure-tournaments.js set   - Set tournament configuration');
    }
}

async function viewConfig(contract) {
    console.log('📖 Reading current tournament configuration...\n');

    try {
        const config = await contract.get_tournament_config();

        console.log('Current Configuration:');
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        console.log(`Budokan Address:          ${config.budokan_address}`);
        console.log(`Nums Tournament ID:       ${config.nums_tournament_id}`);
        console.log(`LS2 Tournament ID:        ${config.ls2_tournament_id}`);
        console.log(`DW Tournament ID:         ${config.dw_tournament_id}`);
        console.log(`Dark Shuffle Tournament:  ${config.dark_shuffle_tournament_id}`);
        console.log(`Glitchbomb Tournament:    ${config.glitchbomb_tournament_id} ${config.glitchbomb_tournament_id === 0n ? '(disabled)' : ''}`);
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    } catch (error) {
        console.error('❌ Error reading configuration:', error.message);
    }
}

async function setConfig(contract) {
    if (!BUDOKAN_ADDRESS) {
        console.error('❌ BUDOKAN_ADDRESS not set in .env');
        process.exit(1);
    }

    if (!NUMS_TOURNAMENT_ID || !LS2_TOURNAMENT_ID || !DW_TOURNAMENT_ID || !DARK_SHUFFLE_TOURNAMENT_ID) {
        console.error('❌ Tournament IDs not set in .env');
        console.error('   Required: NUMS_TOURNAMENT_ID, LS2_TOURNAMENT_ID, DW_TOURNAMENT_ID, DARK_SHUFFLE_TOURNAMENT_ID');
        process.exit(1);
    }

    console.log('⚙️  Setting tournament configuration...\n');

    const config = {
        budokan_address: BUDOKAN_ADDRESS,
        nums_tournament_id: NUMS_TOURNAMENT_ID,
        ls2_tournament_id: LS2_TOURNAMENT_ID,
        dw_tournament_id: DW_TOURNAMENT_ID,
        dark_shuffle_tournament_id: DARK_SHUFFLE_TOURNAMENT_ID,
        glitchbomb_tournament_id: GLITCHBOMB_TOURNAMENT_ID,
    };

    console.log('Configuration to set:');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`Budokan Address:          ${config.budokan_address}`);
    console.log(`Nums Tournament ID:       ${config.nums_tournament_id}`);
    console.log(`LS2 Tournament ID:        ${config.ls2_tournament_id}`);
    console.log(`DW Tournament ID:         ${config.dw_tournament_id}`);
    console.log(`Dark Shuffle Tournament:  ${config.dark_shuffle_tournament_id}`);
    console.log(`Glitchbomb Tournament:    ${config.glitchbomb_tournament_id} ${config.glitchbomb_tournament_id === '0' ? '(disabled)' : ''}`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    try {
        console.log('📤 Sending transaction...');
        const result = await contract.set_tournament_config(config);
        await provider.waitForTransaction(result.transaction_hash);

        console.log('✅ Configuration updated successfully!');
        console.log(`📋 Transaction: ${result.transaction_hash}\n`);
    } catch (error) {
        console.error('❌ Error setting configuration:', error.message);
    }
}

main().catch((error) => {
    console.error('Fatal error:', error);
    process.exit(1);
});
