#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 {testnet|mainnet}"
    exit 1
}

# Check if an argument is provided
if [ -z "$1" ]; then
    echo "Network argument not provided..."
    usage
fi

# Check if .env file exists
if [ -f ".env" ]; then
    source .env
else
    echo ".env file not found in directory"
    exit 1
fi

# Get the argument
NETWORK=$1

# Run commands based on the argument
case $NETWORK in
    testnet)
        echo "Running contract deployment to $1..."
        forge script script/Curve.s.sol:TestnetDeploymentScript --chain-id 84532 --rpc-url $BASE_SEPOLIA_RPC_URL \
        --etherscan-api-key $BASESCAN_API_KEY --verifier-url $BASESCAN_SEPOLIA_API \
        --broadcast --verify -vvvv
        ;;
    mainnet)
        echo "Running contract deployment to $1..."
        forge script script/Curve.s.sol:MainnetDeploymentScript --chain-id 8453 --rpc-url $BASE_RPC_URL \
        --etherscan-api-key $BASESCAN_API_KEY --verifier-url $BASESCAN_API \
        --broadcast --verify -vvvv
        ;;
    *)
        echo "Unsupported network argument provided..."
        usage
        ;;
esac
