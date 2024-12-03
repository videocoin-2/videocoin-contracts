require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("dotenv").config(); // Import dotenv to load environment variables

// Load private keys from .env file
const privateKeys = process.env.PRIVATE_KEYS ? process.env.PRIVATE_KEYS.split(",") : [];

module.exports = {
  solidity: {
    compilers: [
        { version: "0.8.0" }, // For your contract files
        { version: "0.8.20" }, // For OpenZeppelin dependencies
      ],
  },
  networks: {
    hardhat: {},

    development: {
      url: "http://127.0.0.1:8545",
      chainId: 1337,
    },

    ci: {
      url: "http://127.0.0.1:8545",
      chainId: 1337,
    },

    coverage: {
      url: "http://localhost:8555",
      chainId: 1337,
      gas: 0xfffffffffff,
      gasPrice: 0x01,
    },

    arbitrum: {
      url: "https://arb1.arbitrum.io/rpc", // Mainnet RPC URL
      accounts: privateKeys,
      chainId: 42161, // Arbitrum One Mainnet Chain ID
      gas: 4000000, // Adjust as necessary
    },

    arbitrumTestnet: {
      url: "https://goerli-rollup.arbitrum.io/rpc", // Testnet RPC URL
      accounts: privateKeys,
      chainId: 421613, // Arbitrum Goerli Testnet Chain ID
      gas: 4000000, // Adjust as necessary
    },
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
  },
};
