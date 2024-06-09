import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-chai-matchers';
import '@nomicfoundation/hardhat-toolbox';
import '@nomicfoundation/hardhat-foundry';
import 'hardhat-abi-exporter';
import 'hardhat-gas-reporter';
import 'solidity-coverage';
import 'dotenv/config';

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.24',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  gasReporter: {
    enabled: true,
  },
  abiExporter: {
    runOnCompile: true,
    path: './abis',
    pretty: true,
    clear: true,
    only: [],
  },
  networks: process.env.DEPLOYER_PRIVATE_KEY
    ? {
        fraxtalTestnet: {
          url: 'https://rpc.testnet.frax.com',
          chainId: 2522,
          accounts: [process.env.DEPLOYER_PRIVATE_KEY!],
        },
        fraxtal: {
          url: 'https://rpc.frax.com',
          chainId: 252,
          accounts: [process.env.DEPLOYER_PRIVATE_KEY!],
        },
      }
    : undefined,
  etherscan: process.env.FRAXSCAN_API_KEY
    ? {
        customChains: [
          {
            network: 'fraxtal',
            chainId: 252,
            urls: {
              apiURL: 'https://api.fraxscan.com/api',
              browserURL: 'https://fraxscan.com',
            },
          },
          {
            network: 'fraxtalTestnet',
            chainId: 2522,
            urls: {
              apiURL: 'https://api-holesky.fraxscan.com/api',
              browserURL: 'https://holesky.fraxscan.com',
            },
          },
        ],
        apiKey: {
          fraxtal: process.env.FRAXSCAN_API_KEY!,
          fraxtalTestnet: process.env.FRAXSCAN_API_KEY!,
        },
      }
    : undefined,
  sourcify: {
    enabled: true,
  },
};

export default config;
