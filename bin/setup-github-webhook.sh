#!/bin/bash

# Variables
WEBHOOK_DIR="/opt/webhook"
WEBHOOK_CONFIG="$WEBHOOK_DIR/hooks.json"
SCRIPT_PATH="/usr/local/bin/deploy.sh"
WEBHOOK_PORT=9000
WEBHOOK_ID="deploy-site"
REPO_PATH_FILE="$WEBHOOK_DIR/repo_paths.txt"

# Create the webhook directory if it doesn't exist
sudo mkdir -p $WEBHOOK_DIR

# Function to generate a random webhook secret
generate_webhook_secret() {
    echo "$(openssl rand -hex 16)"
}

# Get the server's public IP address
IP_ADDRESS=$(curl -s ifconfig.me)

# Prompt user for GitHub repository URL
read -p "Please enter the GitHub repository URL: " GITHUB_REPO_URL
if [[ -z "$GITHUB_REPO_URL" ]]; then
    echo "Error: GitHub repository URL is required."
    exit 1
fi

# Check if the repo paths file exists; if not, create it
if [[ ! -f $REPO_PATH_FILE ]]; then
    echo "Creating repository paths file at $REPO_PATH_FILE."
    sudo touch $REPO_PATH_FILE
fi

# Add new repository path
read -p "Enter a name for this repository: " REPO_NAME
read -p "Enter the path for repo '$REPO_NAME': " REPO_PATH

# Check if path already exists
if grep -q "^$REPO_NAME=" "$REPO_PATH_FILE"; then
    echo "Repository path already exists. Please use a different name."
    exit 1
fi

# Prompt user for branch selection (main or develop) for this repo path
read -p "Please enter the branch to pull (main/develop): " SELECTED_BRANCH
if [[ "$SELECTED_BRANCH" != "main" && "$SELECTED_BRANCH" != "develop" ]]; then
    echo "Error: Invalid branch selected."
    exit 1
fi

# Store the repository path and branch in the repo paths file
echo "$REPO_NAME=$REPO_PATH:$SELECTED_BRANCH" | sudo tee -a $REPO_PATH_FILE

# Generate a webhook secret
WEBHOOK_SECRET=$(generate_webhook_secret)

# Create or update the dynamic deployment script
echo "Creating/updating deployment script at $SCRIPT_PATH..."
cat <<EOL | sudo tee $SCRIPT_PATH
#!/bin/bash
REPO_NAME="\$1"
REPO_INFO="\$(grep -E "^\$REPO_NAME=" "$REPO_PATH_FILE")"
TARGET_PATH="\$(echo "\$REPO_INFO" | cut -d':' -f1)"
SELECTED_BRANCH="\$(echo "\$REPO_INFO" | cut -d':' -f2)"

if [[ -z "\$TARGET_PATH" || -z "\$SELECTED_BRANCH" ]]; then
    echo "Error: Repository path or branch not found for \$REPO_NAME."
    exit 1
fi

cd "\$TARGET_PATH" || exit 1
echo "Pulling latest changes from GitHub on branch '\$SELECTED_BRANCH'..."
git pull origin "\$SELECTED_BRANCH"
EOL

sudo chmod +x $SCRIPT_PATH

# Create Webhook configuration
echo "Creating Webhook configuration..."
sudo mkdir -p $WEBHOOK_DIR
cat <<EOL | sudo tee $WEBHOOK_CONFIG
[
    {
        "id": "$WEBHOOK_ID",
        "execute-command": "$SCRIPT_PATH",
        "command-working-directory": "$WEBHOOK_DIR",
        "response-message": "Deployed successfully!",
        "trigger-rule": {
            "and": [
                {
                    "match": {
                        "type": "value",
                        "value": "push",
                        "parameter": {
                            "source": "payload",
                            "name": "event"
                        }
                    }
                },
                {
                    "match": {
                        "type": "value",
                        "parameter": {
                            "source": "payload",
                            "name": "repository.name"
                        }
                    }
                }
            ]
        }
    }
]
EOL

# Create a systemd service for the webhook server
SERVICE_FILE="/etc/systemd/system/webhook.service"
cat <<EOF | sudo tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=Webhook Service

[Service]
ExecStart=/usr/local/bin/webhook -hooks $HOOKS_FILE -verbose
WorkingDirectory=$REPO_PATH
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Allow Port in Firewalld
sudo firewall-cmd --zone=public --add-port=$WEBHOOK_PORT/tcp --permanent
sudo firewall-cmd --reload

# Reload systemd and enable the webhook service
sudo systemctl daemon-reload
sudo systemctl enable webhook

# Start the webhook service
sudo systemctl start webhook

# Check the status of the webhook service
if sudo systemctl is-active --quiet webhook; then
    msg "Webhook server started successfully."
else
    msg "Failed to start the webhook server."
    exit 1
fi

# Print the webhook setup message with the server's IP address
echo "Webhook setup completed. Configure the GitHub webhook to point to your VPS at: http://$IP_ADDRESS:$WEBHOOK_PORT/hooks/$WEBHOOK_ID with the secret: $WEBHOOK_SECRET"