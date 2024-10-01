#!/bin/bash

# Variables (Customize these)
APP_NAME="buyer-web"                # Your app name
APP_DIR="/var/www/$APP_NAME"        # Your app directory
REPO_URL="https://$GITHUB_USERNAME:$GITHUB_SECRET@github.com/Theplus1/buyer-web.git"  # Your repo URL
BRANCH="hosting"                    # Branch to pull
NGINX_SNIP="/etc/nginx/snippets/common.conf" # Nginx snippet path
PORT=3000                           # The port the Next.js app will run on
NODE_VERSION="20"                   # Specify the Node.js version

# Create an array to track failed steps
failed_steps=()

# Function to log success or failure of steps
log_step() {
    if [ $1 -ne 0 ]; then
        echo "Step Failed: $2"
        failed_steps+=("$2")
    else
        echo "Step Succeeded: $2"
    fi
}

# Ask user if they want to configure Nginx for a domain
read -p "Do you want to configure Nginx for a domain? (y/n): " configure_nginx

if [[ "$configure_nginx" =~ ^[Yy]$ ]]; then
    # Get domain input from the user
    read -p "Enter your domain name (e.g., example.com): " DOMAIN
    NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
else
    echo "Skipping Nginx configuration."
fi

# Update & Install Dependencies
echo "Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
log_step $? "System update and package installation"

sudo apt install -y nodejs npm nginx redis-server certbot python3-certbot-nginx
log_step $? "Installing required packages"

# Install NVM (Node Version Manager)
echo "Checking for NVM..."
if ! command -v nvm &> /dev/null; then
    echo "NVM not found. Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    log_step $? "NVM installation"
else
    echo "NVM is already installed."
    log_step 0 "NVM installation check"
fi

# Install Node.js using NVM
echo "Installing Node.js version $NODE_VERSION using NVM..."
nvm install $NODE_VERSION
log_step $? "Node.js installation"

nvm use $NODE_VERSION
nvm alias default $NODE_VERSION
log_step $? "Setting Node.js version with NVM"

# Install Yarn & PM2
echo "Installing Yarn and PM2..."
sudo npm install -g pm2 yarn
log_step $? "PM2 and Yarn installation"

# Install Redis
echo "Config Redis..."
sudo systemctl enable redis-server
log_step $? "Enable Redis service"

# Restart Redis service
sudo systemctl start redis-server
log_step $? "Start Redis service"

# Modify 'supervised no' to 'supervised systemd'
sudo sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf
# Uncomment 'requirepass foobared' and change 'foobared' to 'Theplus1@123'
sudo sed -i 's/# requirepass foobared/requirepass Theplus1@123/' /etc/redis/redis.conf
# Restart Redis service
sudo systemctl restart redis-server
log_step $? "Config Redis service"

# Clone or pull the latest code
if [ -d "$APP_DIR" ]; then
    echo "Updating existing app..."
    cd "$APP_DIR" && git pull origin "$BRANCH"
    log_step $? "Pull latest code from repo"
else
    echo "Cloning the repository..."
    git clone -b "$BRANCH" "$REPO_URL" "$APP_DIR"
    log_step $? "Cloning the repository"
    cd "$APP_DIR"
fi

# Install project dependencies
echo "Installing project dependencies with Yarn..."
yarn install
log_step $? "Project dependencies installation"

# Build Next.js app
echo "Building Next.js app..."
rm .env.local
cp .env.hosting .env.production
yarn build
log_step $? "Next.js app build"

# Start app with PM2
echo "Starting app with PM2..."
pm2 delete "$APP_NAME" || true
log_step $? "Remove existing PM2 process"

pm2 start ecosystem.config.js
log_step $? "Starting app with PM2"

# Setup Nginx
echo "Configuring Nginx..."
sudo tee "$NGINX_SNIP" > /dev/null <<EOF
location / {
    proxy_pass http://127.0.0.1:$PORT;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_cache_bypass \$http_upgrade;

    # Enable and optimize buffering
    proxy_buffering on;
    proxy_buffers 16 16k;
    proxy_buffer_size 32k;
}

location /images/ {
    alias /var/www/$APP_NAME/public/images/;
    expires 30d;
    add_header Cache-Control "public, no-transform";
}
EOF
log_step $? "Nginx configuration snippet creation"

# Configure Nginx for domain if selected earlier
if [[ "$configure_nginx" =~ ^[Yy]$ ]]; then
    # Setup Nginx
    echo "Configuring Nginx for domain $DOMAIN..."
    sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
    server_name $DOMAIN;
    # Include common settings
    include /etc/nginx/snippets/common.conf;
}
EOF
    log_step $? "Nginx configuration for domain"

    # Enable Nginx config
    sudo ln -s "$NGINX_CONF" /etc/nginx/sites-enabled/
    sudo nginx -t
    log_step $? "Nginx config test"

    sudo systemctl restart nginx
    log_step $? "Restart Nginx"

    echo "Nginx has been configured for domain $DOMAIN"
fi

# Set PM2 to restart on reboot
echo "Configuring PM2 to auto-start on reboot..."
pm2 startup systemd
log_step $? "PM2 startup configuration"

pm2 save
log_step $? "Saving PM2 process list"

# Display status
echo ""
echo "Initialize complete!"
pm2 status
sudo systemctl status redis-server
if [[ "$configure_nginx" =~ ^[Yy]$ ]]; then
    sudo systemctl status nginx
fi

# Display a summary of any failed steps
echo ""
echo ""
echo "======================================================"
echo "================= Server Initialization Summary ================="
if [ ${#failed_steps[@]} -eq 0 ]; then
    echo "All steps completed successfully!"
else
    echo "The following steps failed:"
    for step in "${failed_steps[@]}"; do
        echo "- $step"
    done
    echo "Please check the logs for more details."
fi
echo "======================================================"
echo "======================================================"
