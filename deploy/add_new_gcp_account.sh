#!/bin/bash

set -e

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq to continue."
    echo "On macOS: brew install jq"
    echo "On Ubuntu/Debian: sudo apt-get install jq"
    exit 1
fi

# Define path to .dev.vars file
DEV_VARS_FILE="../.dev.vars"

# Check if .dev.vars file exists
if [ ! -f "$DEV_VARS_FILE" ]; then
    echo "Error: $DEV_VARS_FILE not found. Please run this script from the deploy directory."
    exit 1
fi

# Find the next available service account index
echo "Finding next available GCP service account index..."
if grep -q "^GCP_SERVICE_ACCOUNT_" "$DEV_VARS_FILE"; then
    # Extract the highest index number and increment by 1
    NEXT_INDEX=$(grep "^GCP_SERVICE_ACCOUNT_" "$DEV_VARS_FILE" | \
                 sed -E 's/^GCP_SERVICE_ACCOUNT_([0-9]+)=.*/\1/' | \
                 sort -n | \
                 tail -1 | \
                 awk '{print $1+1}')
else
    # If no accounts exist, start at index 0
    NEXT_INDEX=0
fi

echo "Next available index: $NEXT_INDEX"

# Prompt user for the service account JSON
echo ""
echo "Please paste your complete GCP service account JSON below."
echo "Press Ctrl+D when finished:"
echo ""

# Read the JSON input from stdin
SERVICE_ACCOUNT_JSON=$(cat)

# Validate and minify the JSON using jq
echo "Validating and processing JSON..."
if [ -z "$SERVICE_ACCOUNT_JSON" ]; then
    echo "Error: Empty input received. No credentials were added."
    exit 1
fi

# Try to parse and minify the JSON
MINIFIED_JSON=$(echo "$SERVICE_ACCOUNT_JSON" | jq -c . 2>/dev/null)

# Check if jq succeeded
if [ $? -ne 0 ] || [ -z "$MINIFIED_JSON" ]; then
    echo "Error: Invalid JSON provided. No credentials were added."
    exit 1
fi

# Create the new entry
NEW_ENTRY="GCP_SERVICE_ACCOUNT_${NEXT_INDEX}=${MINIFIED_JSON}"

# Ensure .dev.vars ends with a newline before appending
if [ -n "$(tail -c1 "$DEV_VARS_FILE")" ]; then
    echo "" >> "$DEV_VARS_FILE"
fi

# Append the new entry to .dev.vars
echo "$NEW_ENTRY" >> "$DEV_VARS_FILE"

echo ""
echo "Successfully added new GCP service account credential:"
echo "  Key: GCP_SERVICE_ACCOUNT_${NEXT_INDEX}"
echo ""
echo "Remember to run './put_kv_secrets.sh' to sync the updated credentials to Cloudflare."
