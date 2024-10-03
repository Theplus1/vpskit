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
sudo dnf install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx
sudo firewall-cmd --permanent --zone=public --add-service=http
sudo firewall-cmd --permanent --zone=public --add-service=https
sudo firewall-cmd --reload

# Step 2: Install MySQL 8.0
echo "Installing MySQL 8.0..."
sudo dnf install mysql mysql-server expect -y
sudo systemctl enable --now mysqld
sudo systemctl start mysqld

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

# Create MySQL database and user for WordPress
echo "Creating MySQL database and user..."
mysql -uroot -p"$MYSQL_ROOT_PASS" -e "
CREATE DATABASE $DB_NAME;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
"

# Step 3: Install PHP 7.4 and configure for large file uploads
echo "Installing PHP 7.4 and configuring..."
sudo dnf install epel-release -y
sudo dnf install https://rpms.remirepo.net/enterprise/remi-release-9.rpm -y
sudo dnf module reset php
sudo dnf module enable php:remi-7.4 -y
sudo dnf install php php-fpm php-mysqlnd -y

# Modify php.ini for large uploads
echo "Configuring PHP settings for large uploads..."
sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 1024M/' /etc/php.ini
sudo sed -i 's/post_max_size = .*/post_max_size = 1024M/' /etc/php.ini
sudo sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php.ini

# Start and enable PHP-FPM
sudo systemctl start php-fpm
sudo systemctl enable php-fpm

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
        fastcgi_pass unix:/var/run/php-fpm/www.sock;
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
echo "Setting up WordPress from GitHub repository..."
sudo mkdir -p $WEB_ROOT
cd /www/wwwroot/
sudo git clone $GIT_REPO
sudo mv /www/wwwroot/$PROJECT_NAME/freshlife247/* $WEB_ROOT/

# Set ownership and permissions
sudo chown -R nginx:nginx $WEB_ROOT
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

# Step 6: Temporarily Set SELinux to Permissive Mode
echo "Setting SELinux to permissive mode..."
sudo setenforce 0

# Step 7: Restart PHP-FPM and Nginx
echo "Restarting PHP-FPM and Nginx..."
sudo systemctl restart php-fpm
sudo systemctl restart nginx

# Step 8: Install Certbot for Let's Encrypt
echo "Installing Certbot..."
sudo dnf install certbot python3-certbot-nginx -y

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

# Step 12: Updating SELinux to allow php-fpm
echo "Updating SELinux to allow php-fpm"
sudo yum install policycoreutils-python-utils
sudo audit2allow -a -M my_php_fpm_policy
sudo semodule -i my_php_fpm_policy.pp