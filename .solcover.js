// .solcover.js
// Configuración de cobertura para solidity-coverage

module.exports = {
  skipFiles: [
    // Excluir mocks y contratos de test
    "mocks/",
    "test/",
  ],

  // Umbral mínimo de cobertura (falla el CI si no se alcanza)
  istanbulReporter: ["html", "lcov", "text", "json"],

  providerOptions: {
    allowUnlimitedContractSize: false,
  },

  // Contratos a incluir explícitamente
  // (por defecto incluye todos los de /contracts)
  configureYulOptimizer: true,

  mocha: {
    timeout: 300_000, // 5 minutos para tests con coverage (más lento)
  },
};
