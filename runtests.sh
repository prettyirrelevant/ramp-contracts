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

# Get the argument
NETWORK=$1

# Run commands based on the argument
source .env
case $NETWORK in
    testnet)
        echo "Running tests on forked $1..."
        forge test --match-path test/CurveTest.t.sol --match-contract TestnetForkTest --gas-report --fork-url https://rpc.testnet.frax.com -vvv
        ;;
    mainnet)
        echo "Running tests on forked $1..."
        forge test --match-path test/CurveTest.t.sol --match-contract MainnetForkTest --gas-report --fork-url https://rpc.frax.com -vvv
        ;;
    *)
        echo "Unsupported network argument provided..."
        usage
        ;;
esac