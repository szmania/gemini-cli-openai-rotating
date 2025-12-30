#!/bin/bash

# This script deploys the Cloudflare worker to two separate accounts using cfman.
# It exits immediately if any command fails.
set -e

# --- Pre-flight Check ---
# Ensure cfman is installed and available in the system's PATH.
if ! command -v cfman &> /dev/null; then
    echo "❌ Error: cfman is not installed or not in your PATH."
    echo "Please install it globally with: npm install -g cfman"
    echo "Then, configure your accounts using: cfman setup"
    exit 1
fi

# Load environment variables from .dev.vars file in the project root
ENV_FILE="../.dev.vars"
if [ -f "$ENV_FILE" ]; then
    export $(cat "$ENV_FILE" | xargs)
else
    echo "Error: $ENV_FILE file not found."
    exit 1
fi

# Check for required environment variables
if [ -z "$CF_ACCOUNT_ONE_ALIAS" ] || [ -z "$CF_ACCOUNT_TWO_ALIAS" ]; then
    echo "Error: CF_ACCOUNT_ONE_ALIAS and/or CF_ACCOUNT_TWO_ALIAS not set in $ENV_FILE"
    echo "Please add the following lines to $ENV_FILE:"
    echo "CF_ACCOUNT_ONE_ALIAS=your_account_one_alias"
    echo "CF_ACCOUNT_TWO_ALIAS=your_account_two_alias"
    exit 1
fi

# --- Deployment to Account One ---
echo "🚀 Deploying to Account One ($CF_ACCOUNT_ONE_ALIAS)..."

# Direct cfman deployment using environment variable
cfman wrangler --account "$CF_ACCOUNT_ONE_ALIAS" deploy

echo "✅ Successfully deployed to Account One."
echo "----------------------------------------"


# --- Deployment to Account Two ---
echo "🚀 Deploying to Account Two ($CF_ACCOUNT_TWO_ALIAS)..."

# Direct cfman deployment using environment variable
cfman wrangler --account "$CF_ACCOUNT_TWO_ALIAS" secret put GCP_SERVICE_ACCOUNT_12

cfman wrangler --account "$CF_ACCOUNT_TWO_ALIAS" secret put GEMINI_PROJECT_ID_14

echo "✅ Successfully deployed to Account Two."
echo "----------------------------------------"

echo "🎉 All deployments completed successfully!"
