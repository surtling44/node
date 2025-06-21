#!/bin/bash

echo "Testing Base node (corrected ports)..."

# Check if op-node is responding
echo "Checking op-node (port 7545)..."
OP_NODE_STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}' \
  http://localhost:7545)

if [[ $OP_NODE_STATUS == *"result"* ]]; then
    echo "✅ Op-node is responding"
    echo "Sync status: $OP_NODE_STATUS"
else
    echo "❌ Op-node not responding on port 7545"
fi

# Check if Nethermind is responding
echo "Checking Nethermind (port 8545)..."
SYNC_STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://localhost:8545 | jq -r '.result // "error"')

if [ "$SYNC_STATUS" = "false" ]; then
    echo "✅ Nethermind is synced"
elif [ "$SYNC_STATUS" = "error" ]; then
    echo "❌ Nethermind not responding on port 8545"
else
    echo "⏳ Nethermind is still syncing: $SYNC_STATUS"
fi

# Check chain ID
CHAIN_ID=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://localhost:8545 | jq -r '.result')

if [ "$CHAIN_ID" = "0x2105" ]; then
    echo "✅ Correct chain ID for Base mainnet: $CHAIN_ID"
else
    echo "❌ Unexpected chain ID: $CHAIN_ID (expected 0x2105)"
fi

echo "🎉 Base node test complete!"
