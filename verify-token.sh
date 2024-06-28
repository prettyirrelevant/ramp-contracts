NETWORK=$1
TOKEN_ADDRESS=$2
TOKEN_NAME=$3
TOKEN_SYMBOL=$4
CURVE_ADDRESS=$5
TOKEN_CREATOR=$6

source .env
case $NETWORK in
    testnet)
        echo "Verifying token $TOKEN_ADDRESS on $NETWORK.."
        forge verify-contract $TOKEN_ADDRESS src/Token.sol:RampToken --chain-id 2522 --etherscan-api-key $FRAXSCAN_API_KEY \
        --verifier-url https://api-holesky.fraxscan.com/api \
        --constructor-args $(cast abi-encode "constructor(string,string,address,address,uint256)" "$TOKEN_NAME" "$TOKEN_SYMBOL" "$CURVE_ADDRESS" "$TOKEN_CREATOR" "1000000000000000000000000000") \
        --watch
        ;;
    mainnet)
        echo "Verifying token $TOKEN_ADDRESS on $NETWORK.."
        forge verify-contract $TOKEN_ADDRESS src/Token.sol:RampToken --chain-id 252 --etherscan-api-key $FRAXSCAN_API_KEY \
        --verifier-url https://api.fraxscan.com/api \
        --constructor-args $(cast abi-encode "constructor(string,string,address,address,uint256)" "$TOKEN_NAME" "$TOKEN_SYMBOL" "$CURVE_ADDRESS" "$TOKEN_CREATOR" "1000000000000000000000000000") \
        --watch
        ;;
    *)
        echo "invalid network..."
        exit 1
        ;;
esac
