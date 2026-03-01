import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import "hardhat-gas-reporter";
import "solidity-coverage";
import * as dotenv from "dotenv";

dotenv.config();

// ─── HELPERS ─────────────────────────────────────────────────────────────────

function required(key: string): string {
  const val = process.env[key];
  if (!val) {
    // En tests locales no se requieren todas las variables
    // Solo fallar si se intenta usar la red que las necesita
    return "";
  }
  return val;
}

function privateKeys(): string[] {
  const key = process.env.DEPLOYER_PRIVATE_KEY;
  if (!key) return [];
  return [key.startsWith("0x") ? key : `0x${key}`];
}

// ─── CONFIG ───────────────────────────────────────────────────────────────────

const config: HardhatUserConfig = {

  // ── Compilador ─────────────────────────────────────────────────────────────

  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,          // balance entre deploy cost y call cost
          },
          viaIR: true,          // habilitar IR pipeline para mejor optimización
          evmVersion: "paris",  // compatible con Arbitrum One y Optimism
          outputSelection: {
            "*": {
              "*": [
                "abi",
                "evm.bytecode",
                "evm.deployedBytecode",
                "evm.methodIdentifiers",
                "metadata",
                "storageLayout",  // necesario para upgrades y auditorías
              ],
            },
          },
        },
      },
    ],
  },

  // ── Redes ──────────────────────────────────────────────────────────────────

  networks: {

    // Local — Hardhat Network (default para tests)
    hardhat: {
      chainId: 31337,
      allowUnlimitedContractSize: false,  // respetar límites reales de EVM
      blockGasLimit: 30_000_000,
      gas: "auto",
      mining: {
        auto: true,
        interval: 0,  // minar inmediatamente en tests
      },
      accounts: {
        count: 20,          // suficientes para todas las fixtures de tests
        accountsBalance: "10000000000000000000000", // 10,000 ETH por cuenta
      },
    },

    // Localhost — nodo Hardhat externo (`npx hardhat node`)
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337,
    },

    // ── Testnets ──────────────────────────────────────────────────────────────

    // Arbitrum Sepolia — testnet principal
    arbitrumSepolia: {
      url: process.env.ARBITRUM_SEPOLIA_RPC_URL || "https://sepolia-rollup.arbitrum.io/rpc",
      chainId: 421614,
      accounts: privateKeys(),
      gasPrice: "auto",
      gas: "auto",
    },

    // Optimism Sepolia — testnet secundaria
    optimismSepolia: {
      url: process.env.OPTIMISM_SEPOLIA_RPC_URL || "https://sepolia.optimism.io",
      chainId: 11155420,
      accounts: privateKeys(),
      gasPrice: "auto",
      gas: "auto",
    },

    // Sepolia — Ethereum testnet (para pruebas de bridges)
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "https://rpc.sepolia.org",
      chainId: 11155111,
      accounts: privateKeys(),
    },

    // ── Mainnets ──────────────────────────────────────────────────────────────

    // Arbitrum One — red de producción principal
    arbitrum: {
      url: process.env.ARBITRUM_RPC_URL || "https://arb1.arbitrum.io/rpc",
      chainId: 42161,
      accounts: privateKeys(),
      gasPrice: "auto",
      gas: "auto",
      // Límite de confirmaciones para considerar una tx como definitiva
      confirmations: 2,
    },

    // Optimism — red de producción secundaria
    optimism: {
      url: process.env.OPTIMISM_RPC_URL || "https://mainnet.optimism.io",
      chainId: 10,
      accounts: privateKeys(),
      gasPrice: "auto",
      gas: "auto",
      confirmations: 2,
    },
  },

  // ── Verificación de contratos ──────────────────────────────────────────────

  etherscan: {
    apiKey: {
      arbitrumOne:     process.env.ARBISCAN_API_KEY    || "",
      arbitrumSepolia: process.env.ARBISCAN_API_KEY    || "",
      optimisticEthereum: process.env.OPTIMISM_API_KEY || "",
      optimismSepolia: process.env.OPTIMISM_API_KEY    || "",
      sepolia:         process.env.ETHERSCAN_API_KEY   || "",
    },
    customChains: [
      {
        network: "arbitrumSepolia",
        chainId: 421614,
        urls: {
          apiURL:      "https://api-sepolia.arbiscan.io/api",
          browserURL:  "https://sepolia.arbiscan.io",
        },
      },
      {
        network: "optimismSepolia",
        chainId: 11155420,
        urls: {
          apiURL:      "https://api-sepolia-optimistic.etherscan.io/api",
          browserURL:  "https://sepolia-optimism.etherscan.io",
        },
      },
    ],
  },

  // ── Gas Reporter ──────────────────────────────────────────────────────────

  gasReporter: {
    enabled:       process.env.REPORT_GAS === "true",
    currency:      "USD",
    coinmarketcap: process.env.COINMARKETCAP_API_KEY || "",
    token:         "ETH",
    gasPriceApi:   "https://api.arbiscan.io/api?module=proxy&action=eth_gasPrice",
    outputFile:    process.env.GAS_REPORT_FILE || undefined,
    noColors:      !!process.env.GAS_REPORT_FILE,
    // Mostrar métodos ordenados por coste
    reportPureAndViewMethods: false,
    // Excluir contratos de test y mocks
    excludeContracts: ["Mock", "Test", "Stub"],
  },

  // ── Coverage ──────────────────────────────────────────────────────────────

  // Configurado via .solcover.js — ver abajo

  // ── Paths ─────────────────────────────────────────────────────────────────

  paths: {
    sources:   "./contracts",
    tests:     "./test",
    cache:     "./cache",
    artifacts: "./artifacts",
  },

  // ── Mocha (test runner) ───────────────────────────────────────────────────

  mocha: {
    timeout:   120_000,    // 2 minutos — suficiente para tests con time travel
    reporter:  "spec",
    bail:      false,      // continuar aunque falle un test
    parallel:  false,      // tests en serie — evitar conflictos de estado
  },
};

export default config;

// ─── TIPOS PARA SCRIPTS DE DEPLOY ─────────────────────────────────────────────
//
// Importar en scripts de deploy:
//   import { ethers, network, run } from "hardhat";
//
// Verificar contratos:
//   await run("verify:verify", {
//     address: contractAddress,
//     constructorArguments: [admin, param2, ...],
//   });
//
// Network helpers en tests:
//   import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
//   await time.increase(90 * 24 * 3600); // avanzar 90 días
//   await time.increaseTo(targetTimestamp);
