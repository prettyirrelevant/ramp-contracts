# Ramp Contracts

This repository contains the core smart contracts for [Ramp.fun](https://ramp-fun.vercel.app/), a decentralized application designed to facilitate fair and transparent token launches on the FraxTal L2 chain.

## Ramp Bonding Curve

This is the main [contract](/src/Curve.sol) that powers token launches, trading and liquidity migration.

### Deployment Addresses

|  Blockchain  |                                                            Address                                                            |
| :----------: | :---------------------------------------------------------------------------------------------------------------------------: |
| Fraxtal Mainnet | [0xD62BfbF2050e8fEAD90e32558329D43A6efce4C8](https://fraxscan.com/address/0xd62bfbf2050e8fead90e32558329d43a6efce4c8) |
| Fraxtal Testnet  | [0xD62BfbF2050e8fEAD90e32558329D43A6efce4C8](https://holesky.fraxscan.com/address/0xd62bfbf2050e8fead90e32558329d43a6efce4c8) |

## Ramp Token
This is the [token contract](/src/Token.sol) code for all tokens launched on [ramp.fun](https://ramp-fun.vercel.app/).

## Development

### Installation

- Clone the repository
- `cd ramp-contracts`
- Install foundry: `curl -L https://foundry.paradigm.xyz | bash`
- Set up .env according to [.env.example](/.env.example)

### Testing
The smart contract tests can be found in [CurveTest.t.sol](/test/CurveTest.t.sol)
Run Foundry Tests:
- Modify test [script](/runtests.sh) permissions
```bash
chmod 700 ./runtests.sh
```
- Run test on Fraxtal mainnet fork
```bash
./runtests.sh mainnet
```

Built with love ❤️ from 🇳🇬🚀.
