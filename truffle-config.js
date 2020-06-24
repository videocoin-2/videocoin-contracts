const HDWalletProvider = require("@truffle/hdwallet-provider");
const Wallet = require("ethereumjs-wallet");
const fs = require("fs");

function readV3Key(cipherFile, passphraseFile) {
  try {
    const priv = JSON.parse(fs.readFileSync(cipherFile));
    const passphrase = fs.readFileSync(passphraseFile, "utf8");
    const wallet = Wallet.fromV3(priv, passphrase.trim());

    return wallet.getPrivateKey().toString("hex");
  } catch (err) {
    if (err.code === "ENOENT") {
      console.log("File not found!", err.toString());
    }

    throw err;
  }
}


module.exports = {

  networks: {
    development: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*",
    },

    ci: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*",
    },

    coverage: {
      host: "localhost",
      network_id: "*",
      port: 8555,
      gas: 0xfffffffffff,
      gasPrice: 0x01
    },

    everest: {
      provider: function () {
        // IMPORTANT: do not change key order!
        const privateKeys = [
          readV3Key("/vault/secrets/stream-manager.priv", "/vault/secrets/stream-manager.pass"),
          readV3Key("/vault/secrets/staking-manager.priv", "/vault/secrets/staking-manager.pass"),
          readV3Key("/vault/secrets/payment-manager.priv", "/vault/secrets/payment-manager.pass"),
          readV3Key("/vault/secrets/bridge-native.priv", "/vault/secrets/bridge-native.pass"),
          readV3Key("/vault/secrets/bridge-remote.priv", "/vault/secrets/bridge-remote.pass"),
          readV3Key("/vault/secrets/cas-manager.priv", "/vault/secrets/cas-manager.pass"),
        ];

        return new HDWalletProvider(
          privateKeys,
          "http://symphony-geth-archiver.symphony.svc.cluster.local:8545"
        );
      },
      gas: 4000000,
      network_id: "*",
    },

    ethereum: {
      provider: function () {
        const keyPath = process.env.ETHEREUM_KEY_PATH;
        const pwPath = process.env.ETHEREUM_PW_PATH;
        const chainURL = process.env.ETHEREUM_CHAIN_URL;
        const v3key = readV3Key(keyPath, pwPath);
        return new HDWalletProvider(
          [v3key],
          chainURL,
        );
      },
      gas: 8000000,
      gasPrice: 40000000000,
      network_id: "*",
    },

    goerli: {
      provider: function () {
        const keyPath = process.env.ETHEREUM_KEY_PATH;
        const pwPath = process.env.ETHEREUM_PW_PATH;
        const chainURL = process.env.ETHEREUM_CHAIN_URL;
        const v3key = readV3Key(keyPath, pwPath);
        return new HDWalletProvider(
          [v3key],
          chainURL,
        );
      },
      gas: 8000000,
      gasPrice: 40000000000,
      network_id: 5,
    },
  },

  // Set default mocha options here, use special reporters etc.
  mocha: {
    // timeout: 100000
  },

  plugins: ["solidity-coverage"],

  compilers: {
    solc: {
      // NOTE: we are using this compiler version, because of sealer EVM version
      version: "0.5.13",
      settings: {
        // See the solidity docs for advice about optimization and evmVersion
        optimizer: {
          enabled: true,
          runs: 1,
        },
      },
    },
  },
};
