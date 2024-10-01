#!/bin/bash

# Prompt for GitHub credentials
echo "Please enter your GitHub credentials."
read -p "GitHub Username: " GITHUB_USERNAME
read -sp "GitHub Personal Access Token (PAT): " GITHUB_TOKEN
echo

# Export the credentials as environment variables
export GITHUB_USERNAME
export GITHUB_TOKEN

# Install directory
INSTALL_DIR="/usr/local/vpskit"

# Clone the repository
echo "Cloning setup scripts from GitHub..."
git clone https://github.com/Theplus1/vpskit.git $INSTALL_DIR

# Make scripts executable
chmod +x $INSTALL_DIR/bin/*.sh
chmod +x $INSTALL_DIR/vpskit.sh

# Create a symlink for easy command access
ln -sf $INSTALL_DIR/vpskit.sh /usr/local/bin/vpskit
chmod +x /usr/local/vpskit/vpskit.sh

# Ignore file mode changes in Git 
git config core.filemode false

echo "Installation complete. You can now use 'vpskit -help' to view commands."