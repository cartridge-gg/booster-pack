#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
const { CallData } = require('starknet');

/**
 * Format filtered_cards.yaml data for merkle drop
 * Output format: [address, index, [...CallData.compile({ amount, token_type, token_address })]]
 */

const YAML_FILE = path.join(__dirname, 'filtered_cards.yaml');
const OUTPUT_JSON = path.join(__dirname, 'merkle-drop-data.json');

// Token address mapping
const TOKEN_ADDRESSES = {
  LORDS: '0x0124aeb495b947201f5faC96fD1138E326AD86195B98df6DEc9009158A533B49',
  SURVIVOR: '0x042DD777885AD2C116be96d4D634abC90A26A790ffB5871E037Dd5Ae7d2Ec86B',
  NUMS: '0x042DD777885AD2C116be96d4D634abC90A26A790ffB5871E037Dd5Ae7d2Ec86B',
  PAPER: '0x042DD777885AD2C116be96d4D634abC90A26A790ffB5871E037Dd5Ae7d2Ec86B',
  CREDITS: '0x0',
  MYSTERY_ASSET: '0x0'
};

function loadYamlData() {
  try {
    const fileContents = fs.readFileSync(YAML_FILE, 'utf8');
    const data = yaml.load(fileContents);
    return data.cards || [];
  } catch (error) {
    console.error('Error reading YAML file:', error.message);
    process.exit(1);
  }
}

function parseFrontValue(front) {
  // Extract token type and amount from front string
  // e.g., "CREDITS_150000000000000000000" -> { type: "CREDITS", amount: "150000000000000000000" }
  // e.g., "MYSTERY_ASSET" -> { type: "MYSTERY_ASSET", amount: null }

  if (front === 'MYSTERY_ASSET') {
    return {
      type: 'MYSTERY_ASSET',
      amount: null,
      tokenType: 'MYSTERY',
      address: TOKEN_ADDRESSES.MYSTERY_ASSET
    };
  }

  const parts = front.split('_');
  if (parts.length < 2) {
    console.warn(`Unexpected front format: ${front}`);
    return null;
  }

  const tokenName = parts[0];
  const amount = parts[1];

  // Determine token type based on token name
  let tokenType;
  if (tokenName === 'CREDITS') {
    tokenType = 'ERC_20';
  } else {
    // LORDS, SURVIVOR, NUMS, PAPER are all ERC_20
    tokenType = 'ERC_20';
  }

  return {
    type: tokenName,
    amount,
    tokenType,
    address: TOKEN_ADDRESSES[tokenName] || '0x0'
  };
}

function compileCallData(frontData) {
  // Use CallData.compile from starknet.js
  // For mystery: compile { token_type, token_address } (no amount)
  // For others: compile { amount, token_type, token_address }

  if (frontData.type === 'MYSTERY_ASSET') {
    const data = {
      token_type: frontData.tokenType,
      token_address: frontData.address
    };
    return [...CallData.compile(data)];
  }

  const data = {
    amount: frontData.amount,
    token_type: frontData.tokenType,
    token_address: frontData.address
  };

  return [...CallData.compile(data)];
}

function formatMerkleDropData(cards) {
  const formattedData = [];

  cards.forEach((card, index) => {
    const frontData = parseFrontValue(card.front);

    if (!frontData) {
      console.warn(`Skipping card at index ${index} due to parsing error`);
      return;
    }

    const callData = compileCallData(frontData);

    formattedData.push([
      card.address,  // Ethereum address
      index,         // Sequential index
      callData       // Compiled call data
    ]);
  });

  return formattedData;
}

function saveOutput(data) {
  fs.writeFileSync(OUTPUT_JSON, JSON.stringify(data, null, 2));
  console.log(`✓ Merkle drop data saved to: ${OUTPUT_JSON}`);
  console.log(`✓ Total entries: ${data.length}`);
}

function displaySample(data) {
  console.log('\n' + '='.repeat(80));
  console.log('SAMPLE ENTRIES (first 5)');
  console.log('='.repeat(80) + '\n');

  data.slice(0, 5).forEach(entry => {
    console.log(JSON.stringify(entry, null, 2));
  });

  console.log('\n' + '='.repeat(80));
  console.log('DISTRIBUTION BY TOKEN TYPE');
  console.log('='.repeat(80) + '\n');

  const distribution = {};
  data.forEach(([_, __, callData]) => {
    const tokenType = callData[1]; // First data element after length
    distribution[tokenType] = (distribution[tokenType] || 0) + 1;
  });

  Object.entries(distribution).forEach(([type, count]) => {
    console.log(`${type}: ${count} entries`);
  });
  console.log('');
}

function main() {
  console.log('Loading cards from filtered_cards.yaml...');

  const cards = loadYamlData();
  console.log(`Loaded ${cards.length} cards\n`);

  console.log('Formatting data for merkle drop...');
  const merkleData = formatMerkleDropData(cards);

  displaySample(merkleData);
  saveOutput(merkleData);

  console.log('Done!\n');
}

main();
