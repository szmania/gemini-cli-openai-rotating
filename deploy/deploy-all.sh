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

# --- Deployment to Account One ---
echo "🚀 Deploying to Account One..."

# This command now uses the updated script from package.json,
# which leverages cfman to handle authentication.
npm run deploy:acc1

echo "✅ Successfully deployed to Account One."
echo "----------------------------------------"


# --- Deployment to Account Two ---
echo "🚀 Deploying to Account Two..."

npm run deploy:acc2

echo "✅ Successfully deployed to Account Two."
echo "----------------------------------------"

echo "🎉 All deployments completed successfully!"
