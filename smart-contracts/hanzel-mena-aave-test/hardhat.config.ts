import { HardhatUserConfig } from "hardhat/config";

import "@nomicfoundation/hardhat-toolbox";

import "@nomiclabs/hardhat-etherscan";

import "hardhat-dependency-compiler";

import "@nomiclabs/hardhat-ethers";

import * as dotenv from "dotenv";

import "hardhat-gas-reporter";

import "solidity-coverage";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
    ],
  },

  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      chainId: 1,
      forking: {
        url: `${process.env.ETHEREUM_MAINNET_RPC}`,
        blockNumber: Number(process.env.MAINNET_FORK_BLOCK_NUMBER || 0),
      },
    },
  },

  mocha: {
    timeout: 100_000_000,
  },

  gasReporter: {
    enabled: true,
    currency: "USD",
    gasPrice: 21,
    coinmarketcap: process.env.COIN_MARKET_CAP_API_KEY,
  },
};

export default config;
