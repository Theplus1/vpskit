#!/bin/bash

# Define base directory and node configuration
BASE_DIR="$HOME/redis_cluster"
NODE_PORTS=(7000 7001 7002)  # Add a third node on port 7002
REDIS_CONF="/etc/redis/redis.conf"
NODE_CONF_FILES=()
REDIS_PASSWORD="Theplus1@123"

# Ensure Redis is installed
if ! command -v redis-server &> /dev/null
then
    echo "Redis is not installed. Installing..."
    sudo apt update && sudo apt install -y redis-server
else
    echo "Redis is already installed."
fi

# Create directories and configuration for each node
for PORT in "${NODE_PORTS[@]}"
do
    NODE_DIR="$BASE_DIR/nodes/$PORT"
    NODE_CONF="$NODE_DIR/redis.conf"
    NODE_CONF_FILES+=("$NODE_CONF")

    echo "Setting up node directory: $NODE_DIR"
    mkdir -p "$NODE_DIR"

    echo "Copying and modifying configuration for node on port $PORT"
    cp "$REDIS_CONF" "$NODE_CONF"

    # Modify the configuration file for the node
    sed -i "s/^port .*/port $PORT/" "$NODE_CONF"
    sed -i "s/^# cluster-enabled yes/cluster-enabled yes/" "$NODE_CONF"
    sed -i "s|^# cluster-config-file nodes-.*|cluster-config-file nodes-$PORT.conf|" "$NODE_CONF"
    sed -i "s/^# cluster-node-timeout 15000/cluster-node-timeout 5000/" "$NODE_CONF"
    sed -i "s/^appendonly .*/appendonly yes/" "$NODE_CONF"
    
    # Add password authentication
    echo "requirepass $REDIS_PASSWORD" >> "$NODE_CONF"
    echo "masterauth $REDIS_PASSWORD" >> "$NODE_CONF"
done

# Start each Redis instance
for NODE_CONF in "${NODE_CONF_FILES[@]}"
do
    echo "Starting Redis server with configuration $NODE_CONF"
    redis-server "$NODE_CONF"
done

# Wait for Redis instances to start
sleep 2

# Create the Redis Cluster with authentication
echo "Creating Redis Cluster with the following nodes:"
for PORT in "${NODE_PORTS[@]}"
do
    echo "127.0.0.1:$PORT"
done

echo "Running redis-cli --cluster create command with authentication..."
yes yes | redis-cli --cluster create 127.0.0.1:${NODE_PORTS[0]} 127.0.0.1:${NODE_PORTS[1]} 127.0.0.1:${NODE_PORTS[2]} --cluster-replicas 0 -a $REDIS_PASSWORD

echo "Redis cluster setup complete."