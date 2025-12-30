#!/bin/bash

# This script reads secrets from a .dev.vars file and intelligently uploads them
# to two separate Cloudflare accounts using cfman. It checks a hash of the secret
# in KV storage to avoid unnecessary 'put' operations.
# It exits immediately if any command fails.
set -e

# --- Pre-flight Checks ---

# 1. Check for cfman
if ! command -v cfman &> /dev/null; then
    echo "❌ Error: cfman is not installed or not in your PATH."
    echo "Please install it globally with: npm install -g cfman"
    echo "Then, configure your accounts using: cfman setup"
    exit 1
fi

# 2. Load environment variables from .dev.vars file in the project root
ENV_FILE="../.dev.vars"
if [ -f "$ENV_FILE" ]; then
    # Load variables, ignoring comments and empty lines
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo "❌ Error: $ENV_FILE file not found in the parent directory."
    exit 1
fi

# 3. Check for required account aliases
if [ -z "$CF_ACCOUNT_ONE_ALIAS" ] || [ -z "$CF_ACCOUNT_TWO_ALIAS" ]; then
    echo "❌ Error: CF_ACCOUNT_ONE_ALIAS and/or CF_ACCOUNT_TWO_ALIAS not set in $ENV_FILE"
    echo "Please add the following lines to $ENV_FILE:"
    echo "CF_ACCOUNT_ONE_ALIAS=your_account_one_alias"
    echo "CF_ACCOUNT_TWO_ALIAS=your_account_two_alias"
    exit 1
fi

# 4. Check for .dev.vars file in the parent directory
DEV_VARS_FILE="../.dev.vars"
if [ ! -f "$DEV_VARS_FILE" ]; then
    echo "❌ Error: $DEV_VARS_FILE file not found in the parent directory."
    exit 1
fi

# --- Main Logic ---

# Array of account aliases to upload secrets to
ACCOUNTS=("$CF_ACCOUNT_ONE_ALIAS" "$CF_ACCOUNT_TWO_ALIAS")

# Loop through each account
for account in "${ACCOUNTS[@]}"; do
    echo "🚀 Syncing secrets for Account: $account..."

    # Read .dev.vars, filter out comments and empty lines, and process each secret
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        # Skip empty lines and comments
        if [[ -z "$key" ]] || [[ "$key" =~ ^\s*# ]]; then
            continue
        fi

        # Trim leading/trailing whitespace from the key
        key=$(echo "$key" | xargs)

        # Trim leading/trailing whitespace and remove quotes from the value
        value=$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e "s/^'//" -e "s/'$//" -e 's/^"//' -e 's/"$//')

        if [ -n "$key" ]; then
            # Calculate the hash of the new value
            new_hash=$(echo -n "$value" | sha256sum | awk '{print $1}')
            kv_key="secret_hash_${key}"

            # Get the old hash from KV storage, suppressing "key not found" errors
            old_hash=$(cfman wrangler --account "$account" kv:key get "$kv_key" 2>/dev/null || echo "")

            # Compare hashes
            if [ "$new_hash" == "$old_hash" ]; then
                echo "  - ✅ Secret '$key' is already up-to-date. Skipping."
            else
                echo "  - 🔄 Secret '$key' has changed. Uploading new value..."
                # Use wrangler secret put, passing the value via stdin for safety
                echo "$value" | cfman wrangler --account "$account" secret put "$key"

                # Update the hash in KV storage for the new value
                echo "  - 💾 Updating hash for '$key' in KV storage."
                cfman wrangler --account "$account" kv:key put "$kv_key" "$new_hash"
            fi
        fi
    done < "$DEV_VARS_FILE"

    echo "✅ Secret sync completed for Account: $account."
    echo "----------------------------------------"
done

echo "🎉 All secrets synced successfully!"
