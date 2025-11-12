import fs from 'fs';
import { hash, ec } from 'starknet';
import * as yaml from 'js-yaml';

/**
 * NEW ARCHITECTURE:
 * - Leaf data now only contains the amount (u256)
 * - Token addresses are stored in the claim contract storage, not in the merkle tree
 * - Each item type (LORDS, NUMS, CREDITS, etc.) has its own claim entrypoint
 * - This allows the same merkle tree to work on both mainnet and sepolia
 * - Token addresses can be updated without regenerating the merkle tree
 */

/**
 * Parse a front string to extract token name and amount
 * @param {string} front - e.g., "CREDITS_150000000000000000000" or "MYSTERY_ASSET"
 * @returns {Object} { tokenName, amount, itemType }
 */
function parseFront(front) {
  if (front === 'MYSTERY_ASSET') {
    return {
      tokenName: 'MYSTERY_ASSET',
      amount: '0',
      itemType: 'mystery'
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
    itemType: tokenName.toLowerCase()
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
 * @returns {Object} Leaf data structure with amount and item type
 */
function generateLeafData(card) {
  const { tokenName, amount, itemType } = parseFront(card.front);

  return {
    amount: amount,
    item_type: itemType  // 'lords', 'nums', 'credits', 'survivor', 'paper', or 'mystery'
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
      tokens: 0,
      byItem: {}
    };

    // Generate merkle drop data
    const merkleData = data.cards.map((card, index) => {
      const recipientAddress = ethAddressToStarknetFelt(card.address);
      const leafData = generateLeafData(card);

      // Update statistics
      const { tokenName, itemType } = parseFront(card.front);
      if (itemType === 'mystery') {
        stats.mystery++;
      } else {
        stats.tokens++;
      }
      stats.byItem[itemType] = (stats.byItem[itemType] || 0) + 1;

      return {
        recipient: recipientAddress,
        index: index,
        item_type: leafData.item_type,
        amount: leafData.amount
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
    console.log(`   MYSTERY claims: ${stats.mystery} (${((stats.mystery/stats.total)*100).toFixed(2)}%)`);
    console.log(`   Token claims: ${stats.tokens} (${((stats.tokens/stats.total)*100).toFixed(2)}%)`);
    console.log('\n   Item breakdown:');
    Object.entries(stats.byItem).forEach(([item, count]) => {
      console.log(`     ${item}: ${count} (${((count/stats.total)*100).toFixed(2)}%)`);
    });

    console.log('\n💡 Next steps:');
    console.log('   1. Deploy claim contract with token addresses');
    console.log('   2. Generate merkle tree from this data (use item_type to determine which entrypoint)');
    console.log('   3. Deploy forwarder contract with merkle root');
    console.log('   4. Configure tournament IDs in claim contract');
    console.log('   5. Token addresses can be updated later using setter functions');
    console.log('\n🎯 Benefits:');
    console.log('   ✓ Same merkle tree works on mainnet and sepolia');
    console.log('   ✓ Token addresses can be updated without regenerating merkle tree');
    console.log('   ✓ Users can claim multiple different items');
    console.log('   ✓ Simpler leaf data structure');

  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

main();
