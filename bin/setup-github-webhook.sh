#!/bin/bash

# GitHub Webhook Setup Script for Ubuntu 24.04
# This script sets up a complete webhook service using adnanh/webhook

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration file paths
WEBHOOK_CONFIG_DIR="/etc/webhook"
WEBHOOK_CONFIG_FILE="$WEBHOOK_CONFIG_DIR/hooks.json"
WEBHOOK_SCRIPTS_DIR="$WEBHOOK_CONFIG_DIR/scripts"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/webhook.service"
LOG_FILE="/var/log/webhook-setup.log"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root for security reasons."
        print_error "Please run as a regular user with sudo privileges."
        exit 1
    fi
}

# Function to check if user has sudo privileges
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges. Please run with a user that has sudo access."
        exit 1
    fi
}

# Function to create progress file
create_progress_file() {
    local step=$1
    echo "$step" > /tmp/webhook_setup_progress
}

# Function to check progress file
check_progress() {
    if [[ -f /tmp/webhook_setup_progress ]]; then
        cat /tmp/webhook_setup_progress
    else
        echo "0"
    fi
}

# Function to collect user input
collect_input() {
    print_status "Collecting configuration information..."
    
    # Project path
    while [[ -z "$PROJECT_PATH" ]]; do
        read -p "Enter the full path to your project directory: " PROJECT_PATH
        if [[ ! -d "$PROJECT_PATH" ]]; then
            print_warning "Directory does not exist. Please enter a valid path."
            PROJECT_PATH=""
        fi
    done
    
    # Webhook secret
    while [[ -z "$WEBHOOK_SECRET" ]]; do
        read -s -p "Enter a secret key for webhook security (hidden input): " WEBHOOK_SECRET
        echo
        if [[ ${#WEBHOOK_SECRET} -lt 8 ]]; then
            print_warning "Secret should be at least 8 characters long."
            WEBHOOK_SECRET=""
        fi
    done
    
    # Webhook port
    while [[ -z "$WEBHOOK_PORT" ]]; do
        read -p "Enter port for webhook service (default: 9000): " WEBHOOK_PORT
        WEBHOOK_PORT=${WEBHOOK_PORT:-9000}
        if ! [[ "$WEBHOOK_PORT" =~ ^[0-9]+$ ]] || [[ "$WEBHOOK_PORT" -lt 1024 ]] || [[ "$WEBHOOK_PORT" -gt 65535 ]]; then
            print_warning "Please enter a valid port number between 1024-65535."
            WEBHOOK_PORT=""
        fi
    done
    
    # Repository name
    while [[ -z "$REPO_NAME" ]]; do
        read -p "Enter your GitHub repository name (e.g., username/repo): " REPO_NAME
    done
    
    # Branch name
    read -p "Enter branch to listen for (default: main): " BRANCH_NAME
    BRANCH_NAME=${BRANCH_NAME:-main}
    
    # Custom command
    read -p "Enter custom command to run after git pull (optional): " CUSTOM_COMMAND
    
    # User for service
    WEBHOOK_USER=$(whoami)
    
    print_success "Configuration collected successfully!"
}

# Function to install dependencies
install_dependencies() {
    local current_step=$(check_progress)
    if [[ "$current_step" -ge "1" ]]; then
        print_status "Skipping dependency installation (already completed)"
        return 0
    fi
    
    print_status "Installing dependencies..."
    
    sudo apt update
    sudo apt install -y curl git jq
    
    create_progress_file "1"
    print_success "Dependencies installed successfully!"
}

# Function to install webhook
install_webhook() {
    local current_step=$(check_progress)
    if [[ "$current_step" -ge "2" ]]; then
        print_status "Skipping webhook installation (already completed)"
        return 0
    fi
    
    print_status "Installing webhook..."
    
    # Get latest release
    LATEST_RELEASE=$(curl -s https://api.github.com/repos/adnanh/webhook/releases/latest | jq -r '.tag_name')
    DOWNLOAD_URL="https://github.com/adnanh/webhook/releases/download/$LATEST_RELEASE/webhook-linux-amd64.tar.gz"
    
    # Download and install
    cd /tmp
    curl -L -o webhook.tar.gz "$DOWNLOAD_URL"
    tar -xzf webhook.tar.gz
    sudo mv webhook-linux-amd64/webhook /usr/local/bin/
    sudo chmod +x /usr/local/bin/webhook
    rm -rf webhook* /tmp/webhook*
    
    create_progress_file "2"
    print_success "Webhook installed successfully!"
}

# Function to create webhook user and directories
setup_directories() {
    local current_step=$(check_progress)
    if [[ "$current_step" -ge "3" ]]; then
        print_status "Skipping directory setup (already completed)"
        return 0
    fi
    
    print_status "Setting up directories and permissions..."
    
    # Create directories
    sudo mkdir -p "$WEBHOOK_CONFIG_DIR"
    sudo mkdir -p "$WEBHOOK_SCRIPTS_DIR"
    sudo mkdir -p "/var/log/webhook"
    
    # Set ownership
    sudo chown -R "$WEBHOOK_USER:$WEBHOOK_USER" "$WEBHOOK_CONFIG_DIR"
    sudo chown -R "$WEBHOOK_USER:$WEBHOOK_USER" "/var/log/webhook"
    
    create_progress_file "3"
    print_success "Directories and permissions set up successfully!"
}

# Function to create webhook script
create_webhook_script() {
    local current_step=$(check_progress)
    if [[ "$current_step" -ge "4" ]]; then
        print_status "Skipping webhook script creation (already completed)"
        return 0
    fi
    
    print_status "Creating webhook execution script..."
    
    cat > "$WEBHOOK_SCRIPTS_DIR/deploy.sh" << EOF
#!/bin/bash

# Webhook deployment script
# Generated by webhook setup script

set -e

LOG_FILE="/var/log/webhook/deploy.log"
PROJECT_PATH="$PROJECT_PATH"
BRANCH_NAME="$BRANCH_NAME"
CUSTOM_COMMAND="$CUSTOM_COMMAND"

# Function to log with timestamp
log() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOG_FILE"
}

log "=== Webhook deployment started ==="
log "Repository: $REPO_NAME"
log "Branch: \$BRANCH_NAME"
log "Project path: \$PROJECT_PATH"

# Change to project directory
cd "\$PROJECT_PATH"

# Stash any local changes
log "Stashing local changes..."
git stash push -m "Auto-stash before webhook deployment \$(date)"

# Fetch latest changes
log "Fetching latest changes..."
git fetch origin

# Reset to latest commit on the specified branch
log "Resetting to origin/\$BRANCH_NAME..."
git reset --hard "origin/\$BRANCH_NAME"

# Run custom command if provided
if [[ -n "\$CUSTOM_COMMAND" ]]; then
    log "Running custom command: \$CUSTOM_COMMAND"
    eval "\$CUSTOM_COMMAND" >> "\$LOG_FILE" 2>&1
fi

log "=== Webhook deployment completed successfully ==="
EOF

    chmod +x "$WEBHOOK_SCRIPTS_DIR/deploy.sh"
    
    create_progress_file "4"
    print_success "Webhook script created successfully!"
}

# Function to create webhook configuration
create_webhook_config() {
    local current_step=$(check_progress)
    if [[ "$current_step" -ge "5" ]]; then
        print_status "Skipping webhook configuration (already completed)"
        return 0
    fi
    
    print_status "Creating webhook configuration..."
    
    cat > "$WEBHOOK_CONFIG_FILE" << EOF
[
  {
    "id": "github-webhook",
    "execute-command": "$WEBHOOK_SCRIPTS_DIR/deploy.sh",
    "command-working-directory": "$PROJECT_PATH",
    "response-message": "Deployment triggered successfully",
    "trigger-rule": {
      "and": [
        {
          "match": {
            "type": "payload-hmac-sha256",
            "secret": "$WEBHOOK_SECRET",
            "parameter": {
              "source": "header",
              "name": "X-Hub-Signature-256"
            }
          }
        },
        {
          "match": {
            "type": "value",
            "value": "refs/heads/$BRANCH_NAME",
            "parameter": {
              "source": "payload",
              "name": "ref"
            }
          }
        }
      ]
    }
  }
]
EOF

    create_progress_file "5"
    print_success "Webhook configuration created successfully!"
}

# Function to create systemd service
create_systemd_service() {
    local current_step=$(check_progress)
    if [[ "$current_step" -ge "6" ]]; then
        print_status "Skipping systemd service creation (already completed)"
        return 0
    fi
    
    print_status "Creating systemd service..."
    
    sudo tee "$SYSTEMD_SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=GitHub Webhook Service
After=network.target

[Service]
Type=simple
User=$WEBHOOK_USER
Group=$WEBHOOK_USER
ExecStart=/usr/local/bin/webhook -hooks $WEBHOOK_CONFIG_FILE -verbose -port $WEBHOOK_PORT
Restart=always
RestartSec=5
StandardOutput=append:/var/log/webhook/webhook.log
StandardError=append:/var/log/webhook/webhook-error.log

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable webhook
    
    create_progress_file "6"
    print_success "Systemd service created successfully!"
}

# Function to configure firewall
configure_firewall() {
    local current_step=$(check_progress)
    if [[ "$current_step" -ge "7" ]]; then
        print_status "Skipping firewall configuration (already completed)"
        return 0
    fi
    
    print_status "Configuring firewall..."
    
    if command -v ufw >/dev/null 2>&1; then
        sudo ufw allow "$WEBHOOK_PORT"/tcp
        print_success "UFW firewall rule added for port $WEBHOOK_PORT"
    else
        print_warning "UFW not found. Please manually configure your firewall to allow port $WEBHOOK_PORT"
    fi
    
    create_progress_file "7"
}

# Function to start services
start_services() {
    local current_step=$(check_progress)
    if [[ "$current_step" -ge "8" ]]; then
        print_status "Skipping service start (already completed)"
        return 0
    fi
    
    print_status "Starting webhook service..."
    
    sudo systemctl start webhook
    sleep 2
    
    if sudo systemctl is-active --quiet webhook; then
        print_success "Webhook service started successfully!"
    else
        print_error "Failed to start webhook service. Check logs with: sudo journalctl -u webhook"
        exit 1
    fi
    
    create_progress_file "8"
}

# Function to test webhook
test_webhook() {
    print_status "Testing webhook endpoint..."
    
    if curl -s "http://localhost:$WEBHOOK_PORT/hooks/github-webhook" >/dev/null; then
        print_success "Webhook endpoint is responding!"
    else
        print_warning "Webhook endpoint test failed. Service might still be starting up."
    fi
}

# Function to display final information
display_final_info() {
    print_success "GitHub Webhook setup completed successfully!"
    
    echo
    echo "==================== INTEGRATION INFORMATION ===================="
    echo
    echo "🔗 Webhook URL: http://$(curl -s ifconfig.me):$WEBHOOK_PORT/hooks/github-webhook"
    echo "🔐 Secret: $WEBHOOK_SECRET"
    echo "🌿 Branch: $BRANCH_NAME"
    echo "📁 Project Path: $PROJECT_PATH"
    echo "👤 Service User: $WEBHOOK_USER"
    echo
    echo "==================== GITHUB CONFIGURATION ===================="
    echo
    echo "1. Go to your GitHub repository: https://github.com/$REPO_NAME"
    echo "2. Navigate to Settings > Webhooks"
    echo "3. Click 'Add webhook'"
    echo "4. Set Payload URL: http://$(curl -s ifconfig.me):$WEBHOOK_PORT/hooks/github-webhook"
    echo "5. Set Content type: application/json"
    echo "6. Set Secret: $WEBHOOK_SECRET"
    echo "7. Select 'Just the push event'"
    echo "8. Check 'Active'"
    echo "9. Click 'Add webhook'"
    echo
    echo "==================== USEFUL COMMANDS ===================="
    echo
    echo "📊 Check service status: sudo systemctl status webhook"
    echo "📋 View service logs: sudo journalctl -u webhook -f"
    echo "📄 View deployment logs: tail -f /var/log/webhook/deploy.log"
    echo "🔄 Restart service: sudo systemctl restart webhook"
    echo "🛑 Stop service: sudo systemctl stop webhook"
    echo "📝 Edit config: sudo nano $WEBHOOK_CONFIG_FILE"
    echo "🔧 Edit script: nano $WEBHOOK_SCRIPTS_DIR/deploy.sh"
    echo
    echo "==================== SECURITY NOTES ===================="
    echo
    echo "⚠️  Make sure your server's port $WEBHOOK_PORT is accessible from the internet"
    echo "⚠️  Consider using a reverse proxy (nginx) with SSL for production"
    echo "⚠️  Keep your webhook secret secure and don't share it publicly"
    echo "⚠️  Regularly update the webhook binary for security patches"
    echo
    echo "=================================================================="
    
    # Clean up progress file
    rm -f /tmp/webhook_setup_progress
}

# Function to handle errors
handle_error() {
    print_error "Setup failed at step $(check_progress). You can re-run this script to continue from where it left off."
    exit 1
}

# Main function
main() {
    echo "🚀 GitHub Webhook Setup Script for Ubuntu 24.04"
    echo "================================================"
    echo
    
    # Set up error handling
    trap handle_error ERR
    
    # Initialize log file
    sudo touch "$LOG_FILE"
    sudo chown "$USER:$USER" "$LOG_FILE"
    
    # Perform checks
    # check_root
    # check_sudo
    
    # Collect input if not resuming
    local current_step=$(check_progress)
    if [[ "$current_step" == "0" ]]; then
        collect_input
    else
        print_status "Resuming setup from step $current_step..."
        # Re-collect input for resumed runs
        collect_input
    fi
    
    # Execute setup steps
    install_dependencies
    install_webhook
    setup_directories
    create_webhook_script
    create_webhook_config
    create_systemd_service
    configure_firewall
    start_services
    test_webhook
    display_final_info
}

# Run main function
main "$@"