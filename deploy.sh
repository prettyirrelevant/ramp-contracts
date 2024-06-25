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
        forge script script/Curve.s.sol:TestnetDeploymentScript --chain-id 2522 --rpc-url $FRAX_TESTNET_RPC_URL \
        --etherscan-api-key $FRAXSCAN_API_KEY --verifier-url https://api-holesky.fraxscan.com/api \
        --broadcast --verify -vvvv
        ;;
    mainnet)
        echo "Running contract deployment to $1..."
        forge script script/Curve.s.sol:TestnetDeploymentScript --chain-id 252 --rpc-url $FRAX_MAINNET_RPC_URL \
        --etherscan-api-key $FRAXSCAN_API_KEY --verifier-url https://api.fraxscan.com/api \
        --broadcast --verify -vvvv
        ;;
    *)
        echo "Unsupported network argument provided..."
        usage
        ;;
esac
