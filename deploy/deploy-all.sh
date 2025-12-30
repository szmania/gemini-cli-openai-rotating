#!/bin/bash

# This script deploys the Cloudflare worker to two separate accounts.
# It exits immediately if any command fails.
set -e

# --- Pre-flight Check ---
if [ -z "$API_TOKEN_ACCOUNT_ONE" ]; then
    echo "❌ Error: API_TOKEN_ACCOUNT_ONE environment variable is not set."
    exit 1
fi

if [ -z "$API_TOKEN_ACCOUNT_TWO" ]; then
    echo "❌ Error: API_TOKEN_ACCOUNT_TWO environment variable is not set."
    exit 1
fi

# --- Deployment to Account One ---
echo "🚀 Deploying to Account One..."

# Set the environment variable for the first account's API token.
# This tells Wrangler which account to authenticate with.
export CLOUDFLARE_API_TOKEN=$API_TOKEN_ACCOUNT_ONE

# Run the deployment script defined in package.json for the first account.
npm run deploy:acc1

echo "✅ Successfully deployed to Account One."
echo "----------------------------------------"


# --- Deployment to Account Two ---
echo "🚀 Deploying to Account Two..."

# Set the environment variable for the second account's API token.
export CLOUDFLARE_API_TOKEN=$API_TOKEN_ACCOUNT_TWO

# Run the deployment script for the second account.
npm run deploy:acc2

echo "✅ Successfully deployed to Account Two."
echo "----------------------------------------"


# Unset the environment variable as a security best practice.
unset CLOUDFLARE_API_TOKEN

echo "🎉 All deployments completed successfully!"
