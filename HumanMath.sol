// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title HumanMath
/// @author Ernesto Cisneros Cino — FMD-DAO HumanLayer
/// @notice Biblioteca de cálculos puros para el HumanLayer.
///         Sin estado. Solo matemáticas.
///
/// @dev Cubre:
///   - Decay exponencial con serie de Taylor (créditos y reputación dimensional)
///   - Rigidez ideológica y peso ajustado
///   - Coste cuadrático de voto
///   - Joint Performance Score para bonus de coopetición
///   - Multiplicadores de Proof of Understanding

library HumanMath {

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant BPS       = 10_000;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_SCORE = 10_000;

    // Lambda base: ln(2) / 60 días en segundos ≈ 1155 / 10^7
    uint256 public constant LAMBDA_BASE_NUM = 1155;
    uint256 public constant LAMBDA_BASE_DEN = 10_000_000;

    // Factores lambda por dimensión reputacional (en BPS sobre lambda base)
    uint256 public constant LAMBDA_PROPUESTA    = 8_000;
    uint256 public constant LAMBDA_VALIDACION   = 5_000;
    uint256 public constant LAMBDA_COMPRENSION  = 12_000;
    uint256 public constant LAMBDA_OSCILACION   = 9_000;
    uint256 public constant LAMBDA_COLABORACION = 6_000;

    // Peso del oscilador: alpha = 0.30 (30% de penalización máxima)
    uint256 public constant OSCILLATOR_ALPHA_BPS = 3_000;

    // Peso mínimo de voto: 50% del base
    uint256 public constant MIN_WEIGHT_BPS = 5_000;

    // Multiplicadores de Proof of Understanding
    uint256 public constant WEIGHT_OMITTED = 4_000;  // sin proof: 40%
    uint256 public constant WEIGHT_INVALID = 6_000;  // proof inválido: 60%
    uint256 public constant WEIGHT_VALID   = 10_000; // proof válido: 100%

    // Pesos del joint performance score para bonus de C1
    uint256 public constant WEIGHT_SUCCESS_RATE     = 4; // ×4
    uint256 public constant WEIGHT_PARTICIPATION    = 3; // ×3
    uint256 public constant WEIGHT_R_CONTRIBUTION   = 3; // ×3

    // ─── Decay Exponencial ────────────────────────────────────────────────────

    /// @notice Aplica decay exponencial con factor de lambda personalizado
    /// @param rawScore     Score antes de decay
    /// @param elapsed      Segundos transcurridos
    /// @param lambdaFactor Factor de escala del lambda base (en BPS)
    /// @param minFloorBps  Mínimo absoluto como porcentaje del rawScore (en BPS)
    ///                     (0 = sin mínimo, 500 = mínimo 5%)
    /// @return score Score con decay aplicado
    function applyDecay(
        uint256 rawScore,
        uint256 elapsed,
        uint256 lambdaFactor,
        uint256 minFloorBps
    ) internal pure returns (uint256 score) {
        if (rawScore == 0 || elapsed == 0) return rawScore;

        // lambda efectivo = LAMBDA_BASE × lambdaFactor / BPS
        uint256 effectiveNum = LAMBDA_BASE_NUM * lambdaFactor;
        uint256 effectiveDen = LAMBDA_BASE_DEN * BPS;

        // λt en unidades de PRECISION
        uint256 lambdaT = (effectiveNum * elapsed * PRECISION) / effectiveDen;

        uint256 decayFactor = _taylorDecay(lambdaT);

        score = (rawScore * decayFactor) / PRECISION;

        // Aplicar mínimo si está definido
        if (minFloorBps > 0) {
            uint256 floor = (rawScore * minFloorBps) / BPS;
            if (score < floor) score = floor;
        }
    }

    /// @notice Decay estándar para créditos de gobernanza (floor 0)
    function decayCredits(uint256 rawCredits, uint256 elapsed)
        internal pure returns (uint256)
    {
        return applyDecay(rawCredits, elapsed, BPS, 0); // lambda × 1.0, sin floor
    }

    /// @notice Decay para una dimensión reputacional específica
    /// @param dimension 0=PROPUESTA 1=VALIDACION 2=COMPRENSION 3=OSCILACION 4=COLABORACION
    function decayDimension(
        uint256 rawScore,
        uint256 elapsed,
        uint8   dimension
    ) internal pure returns (uint256) {
        uint256 factor = _lambdaForDimension(dimension);
        return applyDecay(rawScore, elapsed, factor, 100); // floor 1%
    }

    // ─── Oscilador Ideológico ─────────────────────────────────────────────────

    /// @notice Calcula la rigidez ideológica sobre una ventana de votos
    /// @param votes          Array de posiciones (0=contra, 1=favor)
    /// @param justifications Array de bool — si el cambio fue justificado
    /// @return rigidityBps   Rigidez en BPS (0 = flexible, 10000 = completamente rígido)
    function calculateRigidity(
        uint8[] memory votes,
        bool[]  memory justifications
    ) internal pure returns (uint256 rigidityBps) {
        uint256 n = votes.length;
        if (n < 2) return 0;

        uint256 changes    = 0;
        uint256 maxChanges = n - 1;

        for (uint256 i = 1; i < n; i++) {
            if (votes[i] != votes[i - 1]) {
                // Cambio detectado
                bool justified = (i - 1 < justifications.length) && justifications[i - 1];
                // Cambio justificado cuenta como 0.5 (media flexibilidad)
                // Representado como cambios × 2 para evitar fracciones
                changes += justified ? 1 : 2;
            }
        }

        // flexibility = changes / (maxChanges × 2)
        // rigidity = 1 - flexibility
        uint256 maxChangesScaled = maxChanges * 2;
        if (maxChangesScaled == 0) return BPS;

        uint256 flexibilityBps = (changes * BPS) / maxChangesScaled;
        rigidityBps = flexibilityBps >= BPS ? 0 : BPS - flexibilityBps;
    }

    /// @notice Calcula el peso de voto ajustado por rigidez
    /// @param baseWeightBps  Peso base en BPS (normalmente 10000)
    /// @param rigidityBps    Rigidez calculada (0–10000)
    /// @return adjustedBps   Peso ajustado (mínimo MIN_WEIGHT_BPS)
    function adjustedVoteWeight(
        uint256 baseWeightBps,
        uint256 rigidityBps
    ) internal pure returns (uint256 adjustedBps) {
        // W_ajustado = W_base × (1 - alpha × rigidez)
        uint256 penalty = (OSCILLATOR_ALPHA_BPS * rigidityBps) / BPS;
        uint256 factor  = penalty >= BPS ? 0 : BPS - penalty;
        adjustedBps     = (baseWeightBps * factor) / BPS;

        // Aplicar mínimo
        uint256 minWeight = (baseWeightBps * MIN_WEIGHT_BPS) / BPS;
        if (adjustedBps < minWeight) adjustedBps = minWeight;
    }

    // ─── Voto Cuadrático ──────────────────────────────────────────────────────

    /// @notice Coste cuadrático de un voto con intensidad dada
    /// @param intensity Intensidad del voto (1–5)
    /// @return cost     Créditos a descontar
    function quadraticCost(uint8 intensity)
        internal pure returns (uint256 cost)
    {
        return uint256(intensity) * uint256(intensity);
    }

    /// @notice Peso efectivo de un voto (intensidad × peso ajustado × multiplicador PoU)
    /// @param intensity    Intensidad del voto (1–5)
    /// @param weightBps    Peso ajustado del votante en BPS
    /// @param pouMultiplierBps Multiplicador PoU en BPS (4000|6000|10000)
    /// @return effectiveBps Peso efectivo total en BPS
    function effectiveVoteWeight(
        uint8   intensity,
        uint256 weightBps,
        uint256 pouMultiplierBps
    ) internal pure returns (uint256 effectiveBps) {
        // Peso efectivo = intensidad × peso × multiplicador / BPS
        effectiveBps = (uint256(intensity) * weightBps * pouMultiplierBps) / (BPS * BPS);
    }

    // ─── Coopetición: Joint Performance Score ─────────────────────────────────

    /// @notice Calcula el joint performance score para bonus de C1
    /// @param successRateBps      Tasa de éxito de propuestas (0–BPS)
    /// @param participationRateBps Tasa de participación C2 (0–BPS)
    /// @param resilienceR         Índice de resiliencia actual (×1000)
    ///                            1000–3000 = dentro del Valle
    /// @return scoreBps           Joint score (0–BPS)
    function jointPerformanceScore(
        uint256 successRateBps,
        uint256 participationRateBps,
        uint256 resilienceR
    ) internal pure returns (uint256 scoreBps) {
        // R dentro del Valle → contribución completa; fuera → 50%
        bool inValley = resilienceR >= 1_000 && resilienceR <= 3_000;
        uint256 rContribution = inValley ? BPS : BPS / 2;

        scoreBps = (
            successRateBps      * WEIGHT_SUCCESS_RATE  +
            participationRateBps * WEIGHT_PARTICIPATION +
            rContribution        * WEIGHT_R_CONTRIBUTION
        ) / (WEIGHT_SUCCESS_RATE + WEIGHT_PARTICIPATION + WEIGHT_R_CONTRIBUTION);
    }

    /// @notice Calcula el bonus de C1 a partir del joint score y la contribución base
    /// @param baseContribution   Contribución individual verificada
    /// @param bonusPercentBps    Porcentaje de bonus del sistema (en BPS)
    /// @param jointScoreBps      Joint performance score del ciclo (0–BPS)
    /// @return bonusAmount       Bonus resultante
    function c1BonusAmount(
        uint256 baseContribution,
        uint256 bonusPercentBps,
        uint256 jointScoreBps
    ) internal pure returns (uint256 bonusAmount) {
        bonusAmount = (baseContribution * bonusPercentBps * jointScoreBps) / (BPS * BPS);
    }

    // ─── Proof of Understanding ───────────────────────────────────────────────

    /// @notice Devuelve el multiplicador de peso según el resultado del PoU
    /// @param result 0=OMITTED · 1=INVALID · 2=VALID
    function pouWeightMultiplier(uint8 result)
        internal pure returns (uint256 multiplierBps)
    {
        if (result == 2) return WEIGHT_VALID;
        if (result == 1) return WEIGHT_INVALID;
        return WEIGHT_OMITTED;
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @notice Aproximación de e^(-x) via serie de Taylor truncada
    /// @param lambdaT λt en unidades de PRECISION
    /// @return decayFactor Factor de decay (0–PRECISION)
    function _taylorDecay(uint256 lambdaT) internal pure returns (uint256) {
        if (lambdaT == 0) return PRECISION;

        if (lambdaT <= PRECISION) {
            // e^(-x) ≈ 1 - x + x²/2 - x³/6 + x⁴/24
            uint256 x  = lambdaT;
            uint256 x2 = (x * x) / PRECISION;
            uint256 x3 = (x2 * x) / PRECISION;
            uint256 x4 = (x3 * x) / PRECISION;

            uint256 pos = PRECISION + x2 / 2 + x4 / 24;
            uint256 neg = x + x3 / 6;

            return pos > neg ? pos - neg : 0;
        }

        // Para lambdaT > PRECISION: floor del 1%
        return PRECISION / 100;
    }

    /// @notice Devuelve el factor lambda para una dimensión reputacional
    function _lambdaForDimension(uint8 dim) internal pure returns (uint256) {
        if (dim == 0) return LAMBDA_PROPUESTA;
        if (dim == 1) return LAMBDA_VALIDACION;
        if (dim == 2) return LAMBDA_COMPRENSION;
        if (dim == 3) return LAMBDA_OSCILACION;
        if (dim == 4) return LAMBDA_COLABORACION;
        return BPS; // default: lambda × 1.0
    }
}
