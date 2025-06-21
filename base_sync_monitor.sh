#!/bin/bash

# Base Node Sync Monitor
# This script tracks the sync progress and times when sync is complete
# Usage: Run as cron job every 1-5 minutes

# Configuration
LOG_DIR="$HOME/base-sync-logs"
LOG_FILE="$LOG_DIR/sync_progress.log"
STATUS_FILE="$LOG_DIR/sync_status.json"
FINAL_REPORT="$LOG_DIR/sync_complete_report.txt"

# RPC endpoints
OP_NODE_RPC="http://localhost:7545"
NETHERMIND_RPC="http://localhost:8545"
BASE_PUBLIC_RPC="https://mainnet.base.org"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to log with timestamp
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to get JSON value safely
get_json_value() {
    echo "$1" | jq -r "$2" 2>/dev/null || echo "null"
}

# Function to convert hex to decimal
hex_to_dec() {
    if [[ $1 =~ ^0x[0-9a-fA-F]+$ ]]; then
        printf "%d" "$1" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Initialize status file if it doesn't exist
if [ ! -f "$STATUS_FILE" ]; then
    cat > "$STATUS_FILE" << EOF
{
    "sync_started": "$(date -Iseconds)",
    "sync_completed": null,
    "initial_check": true,
    "was_syncing": false,
    "start_block": 0,
    "target_block": 0
}
EOF
    log_with_timestamp "🚀 Starting Base node sync monitoring"
fi

# Read current status
CURRENT_STATUS=$(cat "$STATUS_FILE")
SYNC_COMPLETED=$(get_json_value "$CURRENT_STATUS" ".sync_completed")
INITIAL_CHECK=$(get_json_value "$CURRENT_STATUS" ".initial_check")
WAS_SYNCING=$(get_json_value "$CURRENT_STATUS" ".was_syncing")

# If sync already completed, exit
if [ "$SYNC_COMPLETED" != "null" ]; then
    exit 0
fi

# Get current sync status from Nethermind
NETHERMIND_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
    "$NETHERMIND_RPC" 2>/dev/null)

NETHERMIND_SYNC_STATUS=$(get_json_value "$NETHERMIND_RESPONSE" ".result")

# Get current block numbers
LOCAL_BLOCK_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "$NETHERMIND_RPC" 2>/dev/null | jq -r '.result // "0x0"')

REMOTE_BLOCK_HEX=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "$BASE_PUBLIC_RPC" 2>/dev/null | jq -r '.result // "0x0"')

LOCAL_BLOCK=$(hex_to_dec "$LOCAL_BLOCK_HEX")
REMOTE_BLOCK=$(hex_to_dec "$REMOTE_BLOCK_HEX")

# Get op-node sync status
OP_NODE_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}' \
    "$OP_NODE_RPC" 2>/dev/null)

# Calculate sync percentage and blocks behind
BLOCKS_BEHIND=$((REMOTE_BLOCK - LOCAL_BLOCK))
if [ $REMOTE_BLOCK -gt 0 ]; then
    SYNC_PERCENTAGE=$(echo "scale=2; ($LOCAL_BLOCK * 100) / $REMOTE_BLOCK" | bc -l 2>/dev/null || echo "0")
else
    SYNC_PERCENTAGE="0"
fi

# Determine if currently syncing
IS_SYNCING=true
if [ "$NETHERMIND_SYNC_STATUS" = "false" ] && [ $BLOCKS_BEHIND -lt 10 ]; then
    IS_SYNCING=false
fi

# Handle initial check
if [ "$INITIAL_CHECK" = "true" ]; then
    START_BLOCK=$LOCAL_BLOCK
    # Update status file with initial data
    jq --arg start_block "$START_BLOCK" \
       --arg target_block "$REMOTE_BLOCK" \
       '.initial_check = false | .was_syncing = true | .start_block = ($start_block | tonumber) | .target_block = ($target_block | tonumber)' \
       "$STATUS_FILE" > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
    
    log_with_timestamp "📊 Initial sync status - Local: $LOCAL_BLOCK, Remote: $REMOTE_BLOCK, Behind: $BLOCKS_BEHIND blocks"
    WAS_SYNCING=true
else
    START_BLOCK=$(get_json_value "$CURRENT_STATUS" ".start_block")
fi

# Calculate progress from start
BLOCKS_SYNCED=$((LOCAL_BLOCK - START_BLOCK))
TOTAL_BLOCKS_TO_SYNC=$((REMOTE_BLOCK - START_BLOCK))

if [ $TOTAL_BLOCKS_TO_SYNC -gt 0 ]; then
    PROGRESS_PERCENTAGE=$(echo "scale=2; ($BLOCKS_SYNCED * 100) / $TOTAL_BLOCKS_TO_SYNC" | bc -l 2>/dev/null || echo "0")
else
    PROGRESS_PERCENTAGE="100"
fi

# Log current status
log_with_timestamp "📈 Block: $LOCAL_BLOCK/$REMOTE_BLOCK (${SYNC_PERCENTAGE}%) | Behind: $BLOCKS_BEHIND | Progress: ${PROGRESS_PERCENTAGE}% | Syncing: $IS_SYNCING"

# Check if sync just completed
if [ "$WAS_SYNCING" = "true" ] && [ "$IS_SYNCING" = "false" ]; then
    # Sync completed!
    COMPLETION_TIME=$(date -Iseconds)
    SYNC_START_TIME=$(get_json_value "$CURRENT_STATUS" ".sync_started")
    
    # Calculate sync duration
    START_TIMESTAMP=$(date -d "$SYNC_START_TIME" +%s 2>/dev/null || date +%s)
    END_TIMESTAMP=$(date +%s)
    DURATION_SECONDS=$((END_TIMESTAMP - START_TIMESTAMP))
    
    HOURS=$((DURATION_SECONDS / 3600))
    MINUTES=$(((DURATION_SECONDS % 3600) / 60))
    SECONDS=$((DURATION_SECONDS % 60))
    
    # Update status file
    jq --arg completion_time "$COMPLETION_TIME" \
       '.sync_completed = $completion_time | .was_syncing = false' \
       "$STATUS_FILE" > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
    
    # Create final report
    cat > "$FINAL_REPORT" << EOF
🎉 BASE NODE SYNC COMPLETED! 🎉

Sync Started:    $SYNC_START_TIME
Sync Completed:  $COMPLETION_TIME
Total Duration:  ${HOURS}h ${MINUTES}m ${SECONDS}s

Blocks Synced:   $BLOCKS_SYNCED blocks
Start Block:     $START_BLOCK
Final Block:     $LOCAL_BLOCK
Target Block:    $REMOTE_BLOCK

Final Status:
- Local Block:   $LOCAL_BLOCK
- Remote Block:  $REMOTE_BLOCK  
- Blocks Behind: $BLOCKS_BEHIND
- Sync Status:   COMPLETE ✅

Generated: $(date)
EOF

    log_with_timestamp "🎉 SYNC COMPLETED! Duration: ${HOURS}h ${MINUTES}m ${SECONDS}s"
    log_with_timestamp "📄 Final report saved to: $FINAL_REPORT"
    
    # Optional: Send notification (uncomment if you want email notifications)
    # echo "Base node sync completed in ${HOURS}h ${MINUTES}m ${SECONDS}s" | mail -s "Base Node Sync Complete" your-email@example.com
    
else
    # Update was_syncing status
    jq --argjson is_syncing "$IS_SYNCING" \
       '.was_syncing = $is_syncing' \
       "$STATUS_FILE" > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
fi

# Estimate time remaining (only if syncing and has progress)
if [ "$IS_SYNCING" = "true" ] && [ $BLOCKS_SYNCED -gt 100 ]; then
    # Calculate sync rate (blocks per minute)
    CURRENT_TIME=$(date +%s)
    SYNC_START_TIME_UNIX=$(get_json_value "$CURRENT_STATUS" ".sync_started" | xargs -I {} date -d {} +%s 2>/dev/null || echo $CURRENT_TIME)
    ELAPSED_MINUTES=$(((CURRENT_TIME - SYNC_START_TIME_UNIX) / 60))
    
    if [ $ELAPSED_MINUTES -gt 0 ]; then
        BLOCKS_PER_MINUTE=$((BLOCKS_SYNCED / ELAPSED_MINUTES))
        if [ $BLOCKS_PER_MINUTE -gt 0 ]; then
            REMAINING_BLOCKS=$((TOTAL_BLOCKS_TO_SYNC - BLOCKS_SYNCED))
            ETA_MINUTES=$((REMAINING_BLOCKS / BLOCKS_PER_MINUTE))
            ETA_HOURS=$((ETA_MINUTES / 60))
            ETA_MINS=$((ETA_MINUTES % 60))
            
            log_with_timestamp "⏱️  ETA: ~${ETA_HOURS}h ${ETA_MINS}m (${BLOCKS_PER_MINUTE} blocks/min)"
        fi
    fi
fi
