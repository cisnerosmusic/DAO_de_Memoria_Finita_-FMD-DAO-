// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ThreatMath
/// @author Ernesto Cisneros Cino — FMD-DAO ImmunityCore
/// @notice Biblioteca de cálculos puros para el sistema inmunológico.
///         Sin estado. Solo matemáticas.
///
/// @dev MÉTRICAS DE AMENAZA (6 indicadores, pesos 2–3):
///
///   participacion  peso 3 — colapso de participación > 70% en 48h
///   gini           peso 2 — concentración de reputación > 0.8
///   tesoreria      peso 3 — drenaje > 30% en 7 días
///   reputacion     peso 3 — spike de un actor > 40% en 72h
///   oracle         peso 2 — desviación oracle > 3σ
///   exploit        peso 3 — fallo técnico / halt
///
///   Threat Score máximo: 3+2+3+3+2+3 = 16
///
/// @dev CLASIFICACIÓN DE VELOCIDAD (dS/dt):
///
///   < 200 BPS/ciclo  → LOGARÍTMICA  (democracia plena)
///   200–499          → LINEAL        (respuesta balanceada)
///   ≥ 500            → EXPONENCIAL   (expertos al 60%)

library ThreatMath {

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant BPS       = 10_000;
    uint256 public constant PRECISION = 1e18;

    // Pesos de cada métrica (suman 16 máximo)
    uint256 public constant W_PARTICIPACION = 3;
    uint256 public constant W_GINI          = 2;
    uint256 public constant W_TESORERIA     = 3;
    uint256 public constant W_REPUTACION    = 3;
    uint256 public constant W_ORACLE        = 2;
    uint256 public constant W_EXPLOIT       = 3;

    uint256 public constant MAX_THREAT = 16;

    // Umbrales de severidad
    uint256 public constant THRESHOLD_VERDE    = 3;
    uint256 public constant THRESHOLD_AMARILLO = 6;
    uint256 public constant THRESHOLD_NARANJA  = 9;

    // Umbrales de velocidad (BPS por ciclo)
    uint256 public constant VELOCITY_LOG = 200;  // < 200 → LOGARÍTMICA
    uint256 public constant VELOCITY_LIN = 500;  // 200–499 → LINEAL, ≥500 → EXPONENCIAL

    // ─── Enums (representados como uint8) ────────────────────────────────────

    uint8 public constant SEVERITY_VERDE    = 0;
    uint8 public constant SEVERITY_AMARILLO = 1;
    uint8 public constant SEVERITY_NARANJA  = 2;
    uint8 public constant SEVERITY_ROJO     = 3;

    uint8 public constant VELOCITY_LOGARITMICA  = 0;
    uint8 public constant VELOCITY_LINEAL       = 1;
    uint8 public constant VELOCITY_EXPONENCIAL  = 2;

    // ─── Threat Score ─────────────────────────────────────────────────────────

    /// @notice Calcula el Threat Score (0–16) a partir de flags de amenaza
    /// @param participacionCaida  true si participación cayó > 70% en 48h
    /// @param giniAlto            true si Gini reputacional > 8000 BPS (0.8)
    /// @param tesoreriaDrenada    true si tesorería bajó > 30% en 7 días
    /// @param reputacionSpike     true si un actor superó 40% del total en 72h
    /// @param oracleDesviado      true si oracle desviación > 3σ
    /// @param exploitDetectado    true si se detectó fallo técnico o halt
    /// @return score Threat Score 0–16
    function calculateThreatScore(
        bool participacionCaida,
        bool giniAlto,
        bool tesoreriaDrenada,
        bool reputacionSpike,
        bool oracleDesviado,
        bool exploitDetectado
    ) internal pure returns (uint256 score) {
        if (participacionCaida) score += W_PARTICIPACION;
        if (giniAlto)           score += W_GINI;
        if (tesoreriaDrenada)   score += W_TESORERIA;
        if (reputacionSpike)    score += W_REPUTACION;
        if (oracleDesviado)     score += W_ORACLE;
        if (exploitDetectado)   score += W_EXPLOIT;
    }

    /// @notice Clasifica la severidad a partir del Threat Score
    /// @param score Threat Score (0–16)
    /// @return severity VERDE(0) | AMARILLO(1) | NARANJA(2) | ROJO(3)
    function classifySeverity(uint256 score)
        internal pure returns (uint8 severity)
    {
        if      (score <= THRESHOLD_VERDE)    return SEVERITY_VERDE;
        else if (score <= THRESHOLD_AMARILLO) return SEVERITY_AMARILLO;
        else if (score <= THRESHOLD_NARANJA)  return SEVERITY_NARANJA;
        else                                  return SEVERITY_ROJO;
    }

    /// @notice Clasifica la velocidad de escalada (dS/dt)
    /// @param prevScore Score del período anterior
    /// @param currScore Score actual
    /// @return velocity LOGARÍTMICA(0) | LINEAL(1) | EXPONENCIAL(2)
    function classifyVelocity(uint256 prevScore, uint256 currScore)
        internal pure returns (uint8 velocity)
    {
        uint256 delta = currScore > prevScore
            ? (currScore - prevScore) * BPS
            : 0;

        // Normalizar delta sobre MAX_THREAT para obtener BPS
        uint256 deltaBps = delta / MAX_THREAT;

        if      (deltaBps < VELOCITY_LOG) return VELOCITY_LOGARITMICA;
        else if (deltaBps < VELOCITY_LIN) return VELOCITY_LINEAL;
        else                              return VELOCITY_EXPONENCIAL;
    }

    /// @notice Calcula los pesos de cámara según severidad y velocidad
    /// @param severity Nivel de severidad (0–3)
    /// @param velocity Régimen de velocidad (0–2)
    /// @return c1WeightBps    Peso de C1 en BPS
    /// @return c2WeightBps    Peso de C2 en BPS
    /// @return oracleWeightBps Peso del oráculo en BPS
    function chamberWeights(uint8 severity, uint8 velocity)
        internal pure returns (
            uint256 c1WeightBps,
            uint256 c2WeightBps,
            uint256 oracleWeightBps
        )
    {
        if (severity <= SEVERITY_AMARILLO) {
            // Normal o alerta baja: democracia plena
            return (3_333, 3_333, 3_334);
        }

        if (severity == SEVERITY_NARANJA) {
            if (velocity == VELOCITY_LOGARITMICA) {
                return (4_000, 4_000, 2_000);
            } else {
                return (5_000, 3_000, 2_000);
            }
        }

        // ROJO
        if (velocity == VELOCITY_EXPONENCIAL) {
            // Crisis explosiva: expertos dominan
            return (6_000, 1_000, 3_000);
        } else if (velocity == VELOCITY_LINEAL) {
            return (5_000, 2_000, 3_000);
        } else {
            return (4_500, 3_500, 2_000);
        }
    }

    /// @notice Calcula el quórum requerido según severidad y velocidad
    /// @return quorumBps Quórum en BPS
    function requiredQuorum(uint8 severity, uint8 velocity)
        internal pure returns (uint256 quorumBps)
    {
        if (severity == SEVERITY_VERDE)    return 1_000;  // 10%
        if (severity == SEVERITY_AMARILLO) return 1_500;  // 15%
        if (severity == SEVERITY_NARANJA)  return 2_500;  // 25%

        // ROJO
        return velocity == VELOCITY_EXPONENCIAL ? 4_000 : 3_000; // 40% o 30%
    }

    /// @notice Calcula el timelock requerido en días según severidad
    function requiredTimelockDays(uint8 severity)
        internal pure returns (uint256 days_)
    {
        if (severity == SEVERITY_VERDE)    return 2;
        if (severity == SEVERITY_AMARILLO) return 3;
        if (severity == SEVERITY_NARANJA)  return 7;
        return 14; // ROJO
    }

    /// @notice Calcula el tau_DAO ajustado por crisis (en días)
    /// @dev En crisis: tau se reduce para aumentar reactividad
    function adjustedTau(uint256 baseTauDays, uint8 severity)
        internal pure returns (uint256)
    {
        if (severity <= SEVERITY_AMARILLO) return baseTauDays;
        if (severity == SEVERITY_NARANJA)  return (baseTauDays * 6_000) / BPS; // 60%
        return (baseTauDays * 2_500) / BPS; // ROJO: 25% → ~15 días si base=60
    }

    /// @notice Calcula el índice Gini de un array de valores
    /// @param values Array de valores (reputaciones, pesos...)
    /// @return giniBps Índice Gini en BPS (0 = igualdad, 10000 = concentración total)
    function calculateGini(uint256[] memory values)
        internal pure returns (uint256 giniBps)
    {
        uint256 n = values.length;
        if (n == 0) return 0;

        uint256 total = 0;
        for (uint256 i = 0; i < n; i++) total += values[i];
        if (total == 0) return 0;

        uint256 sumAbsDiff = 0;
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = i + 1; j < n; j++) {
                uint256 diff = values[i] > values[j]
                    ? values[i] - values[j]
                    : values[j] - values[i];
                sumAbsDiff += diff * 2;
            }
        }

        giniBps = (sumAbsDiff * BPS) / (2 * n * total);
    }

    /// @notice Verifica si una desviación supera el umbral de 3σ
    /// @param value     Valor actual del indicador
    /// @param mean      Media histórica (×PRECISION)
    /// @param stdDev    Desviación estándar (×PRECISION)
    /// @return true si |value - mean| > 3 × stdDev
    function exceeds3Sigma(
        uint256 value,
        uint256 mean,
        uint256 stdDev
    ) internal pure returns (bool) {
        if (stdDev == 0) return false;
        uint256 threshold = 3 * stdDev;
        uint256 deviation = value > mean
            ? value - mean
            : mean - value;
        return deviation > threshold;
    }
}
