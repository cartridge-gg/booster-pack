#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

/**
 * Extract unique fronts from filtered_cards.yaml
 * Outputs statistics and distribution data
 */

const YAML_FILE = path.join(__dirname, 'filtered_cards.yaml');
const OUTPUT_JSON = path.join(__dirname, 'unique-fronts.json');
const OUTPUT_CSV = path.join(__dirname, 'unique-fronts.csv');

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

function extractUniqueFronts(cards) {
  const frontCounts = {};

  cards.forEach(card => {
    const front = card.front;
    if (front) {
      frontCounts[front] = (frontCounts[front] || 0) + 1;
    }
  });

  return frontCounts;
}

function generateStatistics(frontCounts, totalCards) {
  return Object.entries(frontCounts).map(([front, count]) => ({
    front,
    count,
    percentage: ((count / totalCards) * 100).toFixed(2)
  })).sort((a, b) => b.count - a.count);
}

function displayConsoleTable(stats, totalCards) {
  console.log('\n' + '='.repeat(80));
  console.log('UNIQUE FRONTS ANALYSIS');
  console.log('='.repeat(80));
  console.log(`\nTotal Cards: ${totalCards}`);
  console.log(`Unique Fronts: ${stats.length}\n`);

  console.log('┌─────────────────────────────────────────────┬─────────┬────────────┐');
  console.log('│ Front                                       │ Count   │ Percentage │');
  console.log('├─────────────────────────────────────────────┼─────────┼────────────┤');

  stats.forEach(({ front, count, percentage }) => {
    const frontPadded = front.padEnd(43);
    const countPadded = count.toString().padStart(7);
    const percentPadded = (percentage + '%').padStart(10);
    console.log(`│ ${frontPadded} │ ${countPadded} │ ${percentPadded} │`);
  });

  console.log('└─────────────────────────────────────────────┴─────────┴────────────┘\n');
}

function saveJsonOutput(stats, totalCards) {
  const output = {
    totalCards,
    uniqueFrontCount: stats.length,
    fronts: stats
  };

  fs.writeFileSync(OUTPUT_JSON, JSON.stringify(output, null, 2));
  console.log(`✓ JSON output saved to: ${OUTPUT_JSON}`);
}

function saveCsvOutput(stats) {
  const csvHeader = 'Front,Count,Percentage\n';
  const csvRows = stats.map(({ front, count, percentage }) =>
    `${front},${count},${percentage}`
  ).join('\n');

  fs.writeFileSync(OUTPUT_CSV, csvHeader + csvRows);
  console.log(`✓ CSV output saved to: ${OUTPUT_CSV}`);
}

function main() {
  console.log('Loading data from filtered_cards.yaml...');

  const cards = loadYamlData();
  const totalCards = cards.length;

  if (totalCards === 0) {
    console.error('No cards found in YAML file');
    process.exit(1);
  }

  console.log(`Loaded ${totalCards} cards`);

  const frontCounts = extractUniqueFronts(cards);
  const stats = generateStatistics(frontCounts, totalCards);

  displayConsoleTable(stats, totalCards);
  saveJsonOutput(stats, totalCards);
  saveCsvOutput(stats);

  console.log('\nDone!\n');
}

main();
