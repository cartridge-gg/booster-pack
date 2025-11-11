import fs from 'fs';
import { hash, ec } from 'starknet';
import * as yaml from 'js-yaml';

// Token type constants (matching Cairo constants)
const TOKEN_TYPES = {
  ERC_20: BigInt(hash.getSelectorFromName('ERC_20')),
  ERC_721: BigInt(hash.getSelectorFromName('ERC_721')),
  MYSTERY_ASSET: BigInt(hash.getSelectorFromName('MYSTERY_ASSET'))
};

// Token address mapping
// These should match your deployed token contract addresses
const TOKEN_ADDRESSES = {
  CREDITS: process.env.CREDITS_TOKEN_ADDRESS || '0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7', // ETH on Sepolia as placeholder
  LORDS: process.env.LORDS_TOKEN_ADDRESS || '0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7',
  SURVIVOR: process.env.SURVIVOR_TOKEN_ADDRESS || '0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7',
  NUMS: process.env.NUMS_TOKEN_ADDRESS || '0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7',
  PAPER: process.env.PAPER_TOKEN_ADDRESS || '0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7',
};

// Zero address for MYSTERY_ASSET (no specific token)
const ZERO_ADDRESS = '0x0';

/**
 * Parse a front string to extract token name and amount
 * @param {string} front - e.g., "CREDITS_150000000000000000000" or "MYSTERY_ASSET"
 * @returns {Object} { tokenName, amount, isMystery }
 */
function parseFront(front) {
  if (front === 'MYSTERY_ASSET') {
    return {
      tokenName: 'MYSTERY_ASSET',
      amount: '0',
      isMystery: true
    };
  }

  // Parse format: TOKEN_AMOUNT
  const parts = front.split('_');
  if (parts.length < 2) {
    throw new Error(`Invalid front format: ${front}`);
  }

  const tokenName = parts[0];
  const amount = parts[1];

  return {
    tokenName,
    amount,
    isMystery: false
  };
}

/**
 * Convert Ethereum address to Starknet felt252 format
 * @param {string} ethAddress - Ethereum address (0x...)
 * @returns {string} Starknet felt252
 */
function ethAddressToStarknetFelt(ethAddress) {
  // Remove 0x prefix and convert to BigInt
  const addressBigInt = BigInt(ethAddress);
  return '0x' + addressBigInt.toString(16);
}

/**
 * Generate leaf data for a card claim
 * @param {Object} card - Card object with address and front
 * @returns {Object} Leaf data structure
 */
function generateLeafData(card) {
  const { tokenName, amount, isMystery } = parseFront(card.front);

  if (isMystery) {
    return {
      amount: '0',
      token_address: ZERO_ADDRESS,
      token_type: TOKEN_TYPES.MYSTERY_ASSET.toString()
    };
  }

  // For ERC20 tokens
  const tokenAddress = TOKEN_ADDRESSES[tokenName];
  if (!tokenAddress) {
    throw new Error(`Unknown token: ${tokenName}`);
  }

  return {
    amount: amount,
    token_address: tokenAddress,
    token_type: TOKEN_TYPES.ERC_20.toString()
  };
}

/**
 * Main function to process filtered cards and generate merkle drop data
 */
async function main() {
  try {
    console.log('🔄 Reading filtered_cards.yaml...');

    // Read YAML file
    const yamlContent = fs.readFileSync('./scripts/filtered_cards.yaml', 'utf8');
    const data = yaml.load(yamlContent);

    if (!data.cards || !Array.isArray(data.cards)) {
      throw new Error('Invalid YAML format: expected cards array');
    }

    console.log(`📊 Processing ${data.cards.length} cards...`);

    // Statistics
    const stats = {
      total: data.cards.length,
      mystery: 0,
      erc20: 0,
      byToken: {}
    };

    // Generate merkle drop data
    const merkleData = data.cards.map((card, index) => {
      const recipientAddress = ethAddressToStarknetFelt(card.address);
      const leafData = generateLeafData(card);

      // Update statistics
      const { tokenName, isMystery } = parseFront(card.front);
      if (isMystery) {
        stats.mystery++;
      } else {
        stats.erc20++;
        stats.byToken[tokenName] = (stats.byToken[tokenName] || 0) + 1;
      }

      return {
        recipient: recipientAddress,
        index: index,
        leaf_data: leafData
      };
    });

    // Save to JSON
    const outputPath = './scripts/merkle-drop-data.json';
    fs.writeFileSync(
      outputPath,
      JSON.stringify(merkleData, null, 2)
    );

    console.log('\n✅ Merkle drop data generated successfully!');
    console.log(`📁 Output: ${outputPath}`);
    console.log('\n📊 Statistics:');
    console.log(`   Total cards: ${stats.total}`);
    console.log(`   MYSTERY_ASSET: ${stats.mystery} (${((stats.mystery/stats.total)*100).toFixed(2)}%)`);
    console.log(`   ERC20 tokens: ${stats.erc20} (${((stats.erc20/stats.total)*100).toFixed(2)}%)`);
    console.log('\n   Token breakdown:');
    Object.entries(stats.byToken).forEach(([token, count]) => {
      console.log(`     ${token}: ${count} (${((count/stats.total)*100).toFixed(2)}%)`);
    });

    console.log('\n💡 Next steps:');
    console.log('   1. Update token addresses in .env file');
    console.log('   2. Generate merkle tree from this data');
    console.log('   3. Deploy contracts with merkle root');
    console.log('   4. Configure tournament IDs');

  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

main();
