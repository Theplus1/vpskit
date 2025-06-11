#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Function to validate domain format
validate_domain() {
    local domain=$1
    # Regular expression to validate domain name format
    local regex='^([a-zA-Z0-9]+[.-_])*[a-zA-Z0-9]+(\.[a-zA-Z]{2,})+$'
    if [[ ! $domain =~ $regex ]]; then
        echo "Error: Invalid domain format $domain. Please provide a valid domain."
        exit 1
    fi
}

# Prompt for project name
read -p "Enter your domain name: " DOMAIN

# Check if a domain was provided
if [ -z "$DOMAIN" ]; then
    echo "No domain provided. Exiting..."
    exit 1
fi

# Validate the domain format
validate_domain "$DOMAIN"

# Function to convert domain to project name convert . to _ and set value to PROJECT_NAME
function domain_to_project_name() {
    echo $DOMAIN | tr . _
}
PROJECT_NAME=$(domain_to_project_name)
DB_NAME="${PROJECT_NAME}DB"
DB_USER="${PROJECT_NAME}User"
DB_PASS="${PROJECT_NAME}Pass"
WEB_ROOT="/www/wwwroot/$DOMAIN"
SQL_FILE="/www/wwwroot/$PROJECT_NAME/seaminstoreDB.sql"
MYSQL_ROOT_PASS="ThePlusOne2024@"
GIT_REPO="https://$GITHUB_USERNAME:$GITHUB_SECRET@github.com/Theplus1/kyc-website.git" 

# Prompt for certbot email
read -p "Enter CertBot email (tuandt@theplus1.net): " EMAIL
EMAIL=${EMAIL:-"tuandt@theplus1.net"}

# Step 1: Install Nginx
echo "Installing Nginx..."
sudo apt update
sudo apt install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx
sudo ufw allow 'Nginx Full'
sudo ufw enable

# Step 2: Install MySQL 8.0
echo "Installing MySQL 8.0..."
sudo apt install mysql-server expect -y
sudo systemctl enable mysql
sudo systemctl start mysql

# Secure MySQL installation
echo "Securing MySQL installation..."
expect <<EOF
spawn sudo mysql_secure_installation
expect "Press y|Y for Yes, any other key for No: "
send "n\r"
expect "New password: "
send "$MYSQL_ROOT_PASS\r"
expect "Re-enter new password: "
send "$MYSQL_ROOT_PASS\r"
expect "Remove anonymous users? (Press y|Y for Yes, any other key for No) : "
send "y\r"
expect "Disallow root login remotely? (Press y|Y for Yes, any other key for No) : "
send "y\r"
expect "Remove test database and access to it? (Press y|Y for Yes, any other key for No) : "
send "y\r"
expect "Reload privilege tables now? (Press y|Y for Yes, any other key for No) : "
send "y\r"
expect eof
EOF

# Create MySQL database and user for WordPress if they don't exist
echo "Checking and creating MySQL database and user if needed..."
mysql -uroot -p"$MYSQL_ROOT_PASS" -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$DB_NAME'" | grep -q "$DB_NAME"
if [ $? -ne 0 ]; then
    echo "Creating database $DB_NAME..."
    mysql -uroot -p"$MYSQL_ROOT_PASS" -e "CREATE DATABASE $DB_NAME;"
else
    echo "Database $DB_NAME already exists, skipping..."
fi

# Check if user exists, if not create it
mysql -uroot -p"$MYSQL_ROOT_PASS" -e "SELECT User FROM mysql.user WHERE User = '$DB_USER'" | grep -q "$DB_USER"
if [ $? -ne 0 ]; then
    echo "Creating user $DB_USER..."
    mysql -uroot -p"$MYSQL_ROOT_PASS" -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    mysql -uroot -p"$MYSQL_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    mysql -uroot -p"$MYSQL_ROOT_PASS" -e "FLUSH PRIVILEGES;"
else
    echo "User $DB_USER already exists, skipping..."
fi

# Step 3: Install PHP 7.4 and configure for large file uploads
echo "Installing PHP 7.4 and configuring..."
sudo apt install software-properties-common -y
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update
sudo apt install php7.4 php7.4-fpm php7.4-mysql -y

# Modify php.ini for large uploads
echo "Configuring PHP settings for large uploads..."
sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 1024M/' /etc/php/7.4/fpm/php.ini
sudo sed -i 's/post_max_size = .*/post_max_size = 1024M/' /etc/php/7.4/fpm/php.ini
sudo sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php/7.4/fpm/php.ini

# Start and enable PHP-FPM
sudo systemctl start php7.4-fpm
sudo systemctl enable php7.4-fpm

# Step 4: Configure Nginx for WordPress
echo "Configuring Nginx for WordPress..."
sudo tee /etc/nginx/conf.d/$DOMAIN.conf > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root $WEB_ROOT;

    client_max_body_size 1G;  # Add this line

    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Test and reload Nginx
sudo nginx -t
sudo systemctl reload nginx

# Step 5: Set Up WordPress and Database from GitHub Repository
echo "Checking if WordPress is already installed..."
if [ ! -d "$WEB_ROOT" ] || [ -z "$(ls -A $WEB_ROOT)" ]; then
    echo "Setting up WordPress from GitHub repository..."
    sudo mkdir -p $WEB_ROOT
    cd /www/wwwroot/
    if [ ! -d "$PROJECT_NAME" ]; then
        sudo git clone $GIT_REPO $PROJECT_NAME
    fi
    sudo mv /www/wwwroot/$PROJECT_NAME/freshlife247/* $WEB_ROOT/
else
    echo "WordPress directory already exists and is not empty, skipping installation..."
fi

# Set ownership and permissions
sudo chown -R www-data:www-data $WEB_ROOT
sudo find $WEB_ROOT/ -type d -exec chmod 755 {} \;
sudo find $WEB_ROOT/ -type f -exec chmod 644 {} \;

# Update WordPress configuration file
sudo sed -i "s/your_db_name/$DB_NAME/" $WEB_ROOT/wp-config.php
sudo sed -i "s/your_db_user/$DB_USER/" $WEB_ROOT/wp-config.php
sudo sed -i "s/your_db_password/$DB_PASS/" $WEB_ROOT/wp-config.php

# Update domain in the SQL file
sudo sed -i "s/seaminstore.com/$DOMAIN/g" $SQL_FILE

# Import the database
echo "Importing the database..."
mysql -u$DB_USER -p$DB_PASS $DB_NAME < $SQL_FILE

# Step 6: Restart PHP-FPM and Nginx
echo "Restarting PHP-FPM and Nginx..."
sudo systemctl restart php7.4-fpm
sudo systemctl restart nginx

# Step 8: Install Certbot for Let's Encrypt
echo "Installing Certbot..."
sudo apt install certbot python3-certbot-nginx -y

# Step 9: Obtain an SSL Certificate
echo "Obtaining an SSL certificate..."
sudo certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --no-eff-email

# Step 10: Redirect HTTP to HTTPS
echo "Redirecting HTTP to HTTPS..."
sudo tee -a /etc/nginx/conf.d/$DOMAIN.conf > /dev/null <<EOF

server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
EOF

# Reload Nginx to apply changes
sudo systemctl reload nginx

# Step 11: Set Up Automatic Certificate Renewal
echo "Setting up automatic certificate renewal..."
sudo crontab -l | { cat; echo "30 2 1 * * /usr/bin/certbot renew --quiet --renew-hook 'systemctl reload nginx'"; } | sudo crontab -

# Final step: Set proper permissions
echo "Setting final permissions..."
sudo chown -R www-data:www-data $WEB_ROOT
sudo find $WEB_ROOT -type d -exec chmod 755 {} \;
sudo find $WEB_ROOT -type f -exec chmod 644 {} \;