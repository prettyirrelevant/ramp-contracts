fork-test:
	forge test --match-path test/CurveTest.t.sol --match-contract MainnetForkTest --fork-url https://rpc.frax.com -vvv
	forge test --match-path test/CurveTest.t.sol --match-contract TestnetForkTest --fork-url https://rpc.testnet.frax.com -vvv