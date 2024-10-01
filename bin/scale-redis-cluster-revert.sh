#!/bin/bash

# Define base directory and node configuration
BASE_DIR="$HOME/redis_cluster"
NODE_PORTS=(7000 7001 7002)  # Same ports as in the setup script
NODE_CONF_FILES=()

# Function to stop Redis instances
stop_redis_instances() {
    for PORT in "${NODE_PORTS[@]}"
    do
        echo "Stopping Redis server on port $PORT..."
        redis-cli -p "$PORT" shutdown
    done
}

# Function to remove Redis node directories
remove_directories() {
    echo "Removing Redis cluster directories..."
    rm -rf "$BASE_DIR"
}

# Function to remove Redis cluster configuration files
remove_configurations() {
    echo "Removing Redis cluster configuration files..."
    for PORT in "${NODE_PORTS[@]}"
    do
        NODE_DIR="$BASE_DIR/nodes/$PORT"
        NODE_CONF="$NODE_DIR/redis.conf"
        NODE_CONF_FILES+=("$NODE_CONF")

        if [ -f "$NODE_CONF" ]; then
            echo "Deleting configuration file: $NODE_CONF"
            rm -f "$NODE_CONF"
        fi
    done
}

# Start reverting process
echo "Starting the revert process for Redis cluster setup..."

# Stop Redis instances
stop_redis_instances

# Remove directories and configurations
remove_directories
remove_configurations

echo "Revert process complete. Redis cluster setup has been reverted."

# End of script