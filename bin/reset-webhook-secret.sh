#!/bin/bash

WEBHOOK_DIR="/opt/webhook"
WEBHOOK_CONFIG="$WEBHOOK_DIR/hooks.json"
WEBHOOK_ID="deploy-site"

# Function to generate a random webhook secret
generate_webhook_secret() {
    echo "$(openssl rand -hex 16)"
}

# Generate a new webhook secret
NEW_WEBHOOK_SECRET=$(generate_webhook_secret)

# Update the webhook configuration with the new secret
if [[ -f "$WEBHOOK_CONFIG" ]]; then
    sudo jq --arg secret "$NEW_WEBHOOK_SECRET" \
        '.[0].webhook-secret = $secret' "$WEBHOOK_CONFIG" | sudo tee "$WEBHOOK_CONFIG" > /dev/null
    echo "Webhook secret updated to: $NEW_WEBHOOK_SECRET"
else
    echo "Error: Webhook configuration file not found."
    exit 1
fi