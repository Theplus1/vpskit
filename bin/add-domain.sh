#!/bin/bash

# Variables (Customize these)
DOMAIN_CONF_DIR="/etc/nginx/sites-available"
DOMAIN_CONF_ENABLED_DIR="/etc/nginx/sites-enabled"
SERVER_IP=$(hostname -I | awk '{print $1}') # Get the server's IP address

# Function to clean up configuration files if an error occurs
cleanup() {
    echo "Cleaning up..."
    if [ -n "$DOMAIN" ]; then
        sudo rm -f "$DOMAIN_CONF"
        sudo rm -f "$DOMAIN_CONF_ENABLED_DIR/$DOMAIN"
        sudo systemctl reload nginx
        echo "Reverted Nginx configuration for domain $DOMAIN."
    fi
    exit 1
}
# Function to validate domain format
validate_domain() {
    local domain=$1
    # Regular expression to validate domain name format
    local regex='^([a-zA-Z0-9]+[.-])*[a-zA-Z0-9]+(\.[a-zA-Z]{2,})+$'
    if [[ ! $domain =~ $regex ]]; then
        echo "Error: Invalid domain format $domain. Please provide a valid domain."
        exit 1
    fi
}
# Function to check if the domain resolves to the server IP
check_domain_ip() {
    local domain=$1
    local expected_ip=$2
    local resolved_ip=$(dig +short $domain | head -n 1)

    if [ "$resolved_ip" != "$expected_ip" ]; then
        echo "Error: Domain $domain does not resolve to the server IP $expected_ip. Please update your DNS settings."
        exit 1
    fi
}

# Get domain input from the command-line argument or interactively
if [ -n "$1" ]; then
    DOMAIN=$1
else
    read -p "Enter your domain name (e.g., example.com): " DOMAIN
fi

# Check if a domain was provided
if [ -z "$DOMAIN" ]; then
    echo "No domain provided. Exiting..."
    exit 1
fi

# Validate the domain format
echo "Validating domain format..."
validate_domain "$DOMAIN"

# Check if the domain resolves to the server's IP
echo "Checking if domain $DOMAIN resolves to the server IP $SERVER_IP..."
check_domain_ip "$DOMAIN" "$SERVER_IP"

# Define paths for the domain configuration file
DOMAIN_CONF="$DOMAIN_CONF_DIR/$DOMAIN.conf"

# Create domain-specific Nginx configuration
echo "Creating Nginx configuration for domain $DOMAIN..."
sudo tee "$DOMAIN_CONF" > /dev/null <<EOF
server {
    server_name $DOMAIN;

    # Include common settings
    include /etc/nginx/snippets/common.conf;
}
EOF

# Enable the new domain configuration
echo "Enabling Nginx configuration for domain $DOMAIN..."
sudo ln -s "$DOMAIN_CONF" "$DOMAIN_CONF_ENABLED_DIR"

# Allowing HTTPS Through the Firewall
sudo ufw allow 'Nginx Full'
sudo ufw delete allow 'Nginx HTTP'

# Request SSL certificate from Certbot
echo "Requesting SSL certificate for domain $DOMAIN..."
if ! sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email sidq@theplus1.net; then
    echo "Certbot SSL certificate request failed. Reverting changes..."
    cleanup
fi

# Test Nginx configuration
echo "Testing Nginx configuration..."
sudo nginx -t

# Reload Nginx to apply changes
echo "Reloading Nginx..."
sudo systemctl reload nginx

# Display status
echo "Nginx configuration for domain $DOMAIN has been successfully added and reloaded."