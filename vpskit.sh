#!/bin/bash

# Check if GITHUB_USERNAME and GITHUB_TOKEN are not defined
if [[ -z "$GITHUB_USERNAME" || -z "$GITHUB_SECRET" ]]; then
  echo "GitHub credentials are not found. Please enter your GitHub credentials."
  read -p "GitHub Username: " GITHUB_USERNAME
  read -sp "GitHub Personal Access Token (PAT): " GITHUB_SECRET
  echo
  # Optionally save the credentials to ~/.bashrc for future sessions
  if ! grep -q "GITHUB_USERNAME" ~/.bashrc; then
    echo "export GITHUB_USERNAME=$GITHUB_USERNAME" >> ~/.bashrc
  fi
  if ! grep -q "GITHUB_SECRET" ~/.bashrc; then
    echo "export GITHUB_SECRET=$GITHUB_SECRET" >> ~/.bashrc
  fi

  # Source ~/.bashrc to apply immediately for the current session
  source ~/.bashrc
fi

# Define the installation directory where scripts are stored
INSTALL_DIR="/usr/local/vpskit"

chmod +x $INSTALL_DIR/bin/*.sh

# Function to display help information
function show_help() {
    echo "Usage: vpskit {command}"
    echo ""
    echo "Commands:"
    echo "  kyc-hosting           Initialize hosting for a KYC website"
    echo "  sellpage-hosting      Initialize hosting for a Sellpage"
    echo "  scale-redis           Scale a Redis cluster"
    echo "  scale-redis-revert    Revert a Redis cluster scaling"
    echo "  gh-webhook            Setup GitHub webhook for deployment"
    echo "  add-domain            Add a new sellpage domain"
    echo "  add-domain {domain}   Quick add a new sellpage domain"
    echo ""
    echo "Options:"
    echo "  -help | -h            Show this help message"
    echo "  -update | -u          Update the vpskit scripts"
    echo ""
}

# Check if -help is passed as an argument
if [[ "$1" == "-help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

if [[ "$1" == "-update" || "$1" == "-u" ]]; then
    echo "Updating scripts..."
    git -C $INSTALL_DIR pull
    chmod +x $INSTALL_DIR/vpskit.sh
    exit 0
fi

# Main script logic based on the command passed
case $1 in
  kyc-hosting)
    $INSTALL_DIR/bin/deploy-kyc-website.sh
    ;;
  sellpage-hosting)
    $INSTALL_DIR/bin/initialize-sellpage-hosting.sh
    ;;
  scale-redis)
    $INSTALL_DIR/bin/scale-redis-cluster.sh
    ;;
  scale-redis-revert)
    $INSTALL_DIR/bin/scale-redis-cluster-revert.sh
    ;;
  gh-webhook)
    $INSTALL_DIR/bin/setup-github-webhook.sh
    ;;
  add-domain)
    $INSTALL_DIR/bin/add-domain.sh
    ;;
  *)
    echo "Error: Invalid command"
    show_help
    exit 1
    ;;
esac