#!/bin/bash

# Define the installation directory where scripts are stored
INSTALL_DIR="/usr/local/vpskit"

# Function to display help information
function show_help() {
    echo "Usage: vpskit {command}"
    echo ""
    echo "Commands:"
    echo "  sellpage-hosting      Initialize hosting for a Sellpage"
    echo "  scale-redis           Scale a Redis cluster"
    echo "  scale-redis-revert    Revert a Redis cluster scaling"
    echo "  gh-webhook            Setup GitHub webhook for deployment"
    echo ""
    echo "Options:"
    echo "  -help      Show this help message"
    echo ""
}

# Check if -help is passed as an argument
if [[ "$1" == "-help" || "$1" == "--help" ]]; then
    show_help
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
  update)
    echo "Updating scripts..."
    git -C $INSTALL_DIR pull
    ;;
  *)
    echo "Error: Invalid command"
    show_help
    exit 1
    ;;
esac