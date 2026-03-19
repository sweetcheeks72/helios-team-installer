#!/usr/bin/env node
// lib/json-merge.js — Additive JSON merge for helios installer
// Replaces duplicate Python+Node merge logic in install.sh
// Usage: node lib/json-merge.js <target> <source> [--set key=value ...]

const fs = require('fs');
const path = require('path');

function deepMergeAdditive(target, source) {
  const result = { ...target };
  for (const key of Object.keys(source)) {
    if (Array.isArray(source[key]) && Array.isArray(result[key])) {
      // Additive: union arrays by package name or string value
      const existing = new Set(result[key].map(item => 
        typeof item === 'object' ? (item.name || JSON.stringify(item)) : item
      ));
      for (const item of source[key]) {
        const id = typeof item === 'object' ? (item.name || JSON.stringify(item)) : item;
        if (!existing.has(id)) {
          result[key].push(item);
        }
      }
    } else if (source[key] !== null && source[key] !== undefined) {
      // Scalars: source wins (provider, model, etc.)
      result[key] = source[key];
    }
  }
  return result;
}

function main() {
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.error('Usage: node json-merge.js <target.json> <source.json> [--set key=value ...]');
    process.exit(1);
  }
  
  const targetPath = args[0];
  const sourcePath = args[1];
  
  let target = {};
  try {
    target = JSON.parse(fs.readFileSync(targetPath, 'utf8'));
  } catch (e) {
    // Target doesn't exist or is corrupt — start fresh
  }
  
  let source = {};
  try {
    source = JSON.parse(fs.readFileSync(sourcePath, 'utf8'));
  } catch (e) {
    console.error(`Error reading source: ${e.message}`);
    process.exit(1);
  }
  
  let result = deepMergeAdditive(target, source);
  
  // Process --set key=value overrides
  for (let i = 2; i < args.length; i++) {
    if (args[i] === '--set' && args[i + 1]) {
      const [key, ...valueParts] = args[i + 1].split('=');
      const value = valueParts.join('='); // Handle values with = in them
      result[key] = value;
      i++;
    }
  }
  
  fs.writeFileSync(targetPath, JSON.stringify(result, null, 2) + '\n');
}

main();
