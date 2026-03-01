# GranularReputation
### Vector reputacional multidimensional con decay diferenciado por dimensión
#### Módulo del HumanLayer · FMD-DAO · Ernesto Cisneros Cino

---

## ¿Por qué reputación granular?

La mayoría de los sistemas de reputación colapsan un actor en un número único. Ese número oculta más de lo que revela: un experto técnico brillante puede ser un validador terrible; un gran proponente puede ser un colaborador pésimo. Un solo número los hace indistinguibles.

La reputación granular resuelve eso con un **vector de dimensiones independientes**, cada una con su propio decay y su propia lógica de actualización. Un miembro no tiene "reputación" — tiene un perfil con al menos cinco dimensiones que el sistema puede leer, ponderar y mostrar públicamente de forma específica.

Esto cumple dos funciones simultáneas: **el ego tiene un canal oficial** (las dimensiones son públicas y comparables) y **el sistema tiene señal de calidad desagregada** (puede ponderar contribuciones según el tipo de decisión que se está tomando).

---

## Las cinco dimensiones

| Dimensión | Qué mide | Quién la actualiza | Decay |
|---|---|---|---|
| `REP_PROPUESTA` | Calidad y tasa de éxito de propuestas presentadas | Oráculo al cierre de ciclo | Medio (λ × 0.8) |
| `REP_VALIDACION` | Precisión histórica en validaciones técnicas de C1 | Oráculo post-resultado | Lento (λ × 0.5) |
| `REP_COMPRENSION` | Historial de Proof of Understanding completados | ProofOfUnderstanding.sol | Rápido (λ × 1.2) |
| `REP_OSCILACION` | Índice de oscilación ideológica justificada | IdeologicalOscillator.sol | Medio (λ × 0.9) |
| `REP_COLABORACION` | Contribuciones a propuestas de otros miembros | Oráculo verificado | Lento (λ × 0.6) |

El decay diferenciado por dimensión refleja la vida útil del conocimiento que representa cada una. La validación técnica de hace dos años sigue siendo relevante más tiempo que un Proof of Understanding de hace seis meses.

---

## Visibilidad pública

Las dimensiones se expresan como hechos medibles, no como calificaciones abstractas:

```txt
REP_PROPUESTA:    "Propuesta #47 — redujo timelock promedio un 18%"
REP_VALIDACION:   "Validación #12 — predicción correcta en crisis NARANJA nov-2025"
REP_COMPRENSION:  "94% de tests completados con validación positiva (87/92)"
REP_OSCILACION:   "Cambio justificado en 4 de los últimos 6 ciclos"
REP_COLABORACION: "Contribuyó a 3 propuestas ajenas aprobadas en ciclo actual"
```

No existe un "nivel general" que oculte las dimensiones individuales. El sistema puede calcular un score agregado para decisiones que lo requieran, pero siempre como derivada del vector — nunca como sustituto.

---

## Score agregado ponderado

Para decisiones que necesitan un único número (por ejemplo, el peso de voto base o la elegibilidad para C1), el contrato expone una función de agregación configurable:

```txt
REP_TOTAL(i) = Σ ( REP_dim(i) × peso_dim ) / Σ pesos

Pesos por defecto:
  REP_PROPUESTA:    25%
  REP_VALIDACION:   30%
  REP_COMPRENSION:  15%
  REP_OSCILACION:   15%
  REP_COLABORACION: 15%

Los pesos son parámetros de gobernanza — pueden ajustarse por ciclo.
```

---

## Escritura virtualizada

Igual que los créditos y la reputación general, el decay no se escribe continuamente. Cada dimensión guarda su `rawScore` y su `lastUpdate`. La lectura aplica el decay acumulado sin escribir en cadena — solo se escribe cuando hay una actualización real (boost o penalización).

---

## Estructura del contrato

```
GranularReputation.sol
  ├── RepDimension        enum  — las cinco dimensiones
  ├── DimensionScore      struct — rawScore + lastUpdate + lambdaFactor
  ├── MemberProfile       struct — vector de cinco DimensionScore
  │
  ├── updateDimension()   — actualiza una dimensión (oráculo/contratos autorizados)
  ├── penalizeDimension() — penaliza una dimensión por comportamiento verificado
  ├── getEffectiveScore() — lectura virtualizada con decay aplicado
  ├── getAggregated()     — score total ponderado
  ├── getProfile()        — vector completo para un miembro
  └── setDimensionWeight() — ajuste de pesos por gobernanza
```

---

## Notas de integración

```txt
Lee de:
  IdeologicalOscillator.sol  → actualiza REP_OSCILACION
  ProofOfUnderstanding.sol   → actualiza REP_COMPRENSION
  ImmunityCore.sol           → en crisis ROJA, penalizaciones se amplifican ×1.5

Es leído por:
  CoopetitionEngine.sol      → para calcular peso base de voto
  ImmunityCore.sol           → Gini reputacional del vector REP_VALIDACION
  SoulboundBadges.sol        → umbrales para otorgar badges

No modifica ningún contrato externo.

Red: Arbitrum One u Optimism (L2 Ethereum)
Solidity: ^0.8.20 · OpenZeppelin v5.x
```

---

## Licencia

MIT License · Ernesto Cisneros Cino

*Parte del proyecto [DAO de Memoria Finita (FMD-DAO)](https://github.com/cisnerosmusic/DAO_de_Memoria_Finita_-FMD-DAO-)*

*"Un miembro no tiene reputación. Tiene un perfil."*


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title GranularReputation
/// @author Ernesto Cisneros Cino — FMD-DAO HumanLayer
/// @notice Vector reputacional multidimensional con decay diferenciado por dimensión.
///         Cada miembro tiene cinco dimensiones independientes de reputación,
///         cada una con su propio factor de decay y lógica de actualización.
/// @dev    Escritura virtualizada: el decay se calcula al leer, no se escribe
///         continuamente. Solo se escribe al actualizar o penalizar una dimensión.
contract GranularReputation is AccessControl {

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant ORACLE_ROLE     = keccak256("ORACLE_ROLE");
    bytes32 public constant UPDATER_ROLE    = keccak256("UPDATER_ROLE"); // contratos autorizados
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant BPS        = 10_000;
    uint256 public constant PRECISION  = 1e18;
    uint256 public constant MAX_SCORE  = 10_000; // 10000 = reputación máxima en una dimensión

    // Lambda base: ln(2) / 60 días en segundos
    // LAMBDA_BASE_NUM / LAMBDA_BASE_DEN por segundo
    uint256 public constant LAMBDA_BASE_NUM = 1155;
    uint256 public constant LAMBDA_BASE_DEN = 10_000_000;

    // Factores de decay por dimensión (en BPS, aplicados sobre lambda base)
    // dim 0 REP_PROPUESTA:    λ × 0.80
    // dim 1 REP_VALIDACION:   λ × 0.50
    // dim 2 REP_COMPRENSION:  λ × 1.20
    // dim 3 REP_OSCILACION:   λ × 0.90
    // dim 4 REP_COLABORACION: λ × 0.60
    uint256[5] public lambdaFactorsBps = [8_000, 5_000, 12_000, 9_000, 6_000];

    // Pesos por defecto para score agregado (deben sumar BPS)
    uint256[5] public dimensionWeightsBps = [2_500, 3_000, 1_500, 1_500, 1_500];

    // Amplificador de penalización en crisis ROJA
    uint256 public constant CRISIS_PENALTY_AMPLIFIER_BPS = 15_000; // 1.5×

    // ─── Enums ───────────────────────────────────────────────────────────────

    enum RepDimension {
        PROPUESTA,      // 0 — calidad y tasa de éxito de propuestas
        VALIDACION,     // 1 — precisión en validaciones técnicas C1
        COMPRENSION,    // 2 — historial de Proof of Understanding
        OSCILACION,     // 3 — oscilación ideológica justificada
        COLABORACION    // 4 — contribuciones a propuestas ajenas
    }

    // ─── Structs ─────────────────────────────────────────────────────────────

    /// @notice Score de una dimensión individual con metadatos de decay
    struct DimensionScore {
        uint256 rawScore;       // score antes de aplicar decay
        uint256 lastUpdate;     // timestamp de la última escritura
        uint256 totalBoosts;    // acumulado histórico de boosts recibidos
        uint256 totalPenalties; // acumulado histórico de penalizaciones
    }

    /// @notice Perfil reputacional completo de un miembro
    struct MemberProfile {
        DimensionScore[5] dimensions;
        bool exists;
    }

    /// @notice Evento de actualización con descripción legible del logro
    struct ReputationEvent {
        RepDimension dimension;
        int256       delta;         // positivo = boost, negativo = penalización
        string       description;   // "Propuesta #47 redujo timelock un 18%"
        uint256      timestamp;
        uint256      cycle;
    }

    // ─── State ───────────────────────────────────────────────────────────────

    mapping(address => MemberProfile)       public profiles;
    mapping(address => ReputationEvent[])   public eventHistory;

    bool public systemInCrisis;
    uint256 public currentCycle;

    // ─── Events ──────────────────────────────────────────────────────────────

    event DimensionUpdated(
        address indexed member,
        RepDimension    dimension,
        uint256         before,
        uint256         after_,
        string          description,
        uint256         cycle
    );

    event DimensionPenalized(
        address indexed member,
        RepDimension    dimension,
        uint256         before,
        uint256         after_,
        string          reason,
        uint256         cycle
    );

    event WeightsUpdated(uint256[5] newWeights);
    event CrisisStateUpdated(bool inCrisis);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        currentCycle = 1;
    }

    // ─── Update ──────────────────────────────────────────────────────────────

    /// @notice Actualiza (boost) una dimensión de reputación con descripción de logro
    /// @param member Dirección del miembro
    /// @param dimension Dimensión a actualizar
    /// @param amount Cantidad a añadir (en unidades de MAX_SCORE)
    /// @param description Descripción legible y específica del logro
    function updateDimension(
        address        member,
        RepDimension   dimension,
        uint256        amount,
        string calldata description
    ) external onlyRole(UPDATER_ROLE) {
        _ensureProfile(member);

        uint8 dim = uint8(dimension);
        uint256 current = getEffectiveScore(member, dimension);
        uint256 newScore = current + amount;
        if (newScore > MAX_SCORE) newScore = MAX_SCORE;

        uint256 before = current;

        profiles[member].dimensions[dim] = DimensionScore({
            rawScore:       newScore,
            lastUpdate:     block.timestamp,
            totalBoosts:    profiles[member].dimensions[dim].totalBoosts + amount,
            totalPenalties: profiles[member].dimensions[dim].totalPenalties
        });

        eventHistory[member].push(ReputationEvent({
            dimension:   dimension,
            delta:       int256(amount),
            description: description,
            timestamp:   block.timestamp,
            cycle:       currentCycle
        }));

        emit DimensionUpdated(member, dimension, before, newScore, description, currentCycle);
    }

    /// @notice Penaliza una dimensión de reputación por comportamiento verificado
    /// @param member Dirección del miembro
    /// @param dimension Dimensión a penalizar
    /// @param amount Cantidad a restar (amplificada ×1.5 en crisis ROJA)
    /// @param reason Descripción verificable de la causa
    function penalizeDimension(
        address        member,
        RepDimension   dimension,
        uint256        amount,
        string calldata reason
    ) external onlyRole(ORACLE_ROLE) {
        _ensureProfile(member);

        uint8 dim = uint8(dimension);
        uint256 current = getEffectiveScore(member, dimension);

        // Amplificar penalización en crisis
        uint256 effectiveAmount = systemInCrisis
            ? (amount * CRISIS_PENALTY_AMPLIFIER_BPS) / BPS
            : amount;

        uint256 newScore = current > effectiveAmount
            ? current - effectiveAmount
            : 0;

        uint256 before = current;

        profiles[member].dimensions[dim] = DimensionScore({
            rawScore:       newScore,
            lastUpdate:     block.timestamp,
            totalBoosts:    profiles[member].dimensions[dim].totalBoosts,
            totalPenalties: profiles[member].dimensions[dim].totalPenalties + effectiveAmount
        });

        eventHistory[member].push(ReputationEvent({
            dimension:   dimension,
            delta:       -int256(effectiveAmount),
            description: reason,
            timestamp:   block.timestamp,
            cycle:       currentCycle
        }));

        emit DimensionPenalized(member, dimension, before, newScore, reason, currentCycle);
    }

    // ─── Read (virtualized decay) ─────────────────────────────────────────────

    /// @notice Devuelve el score efectivo de una dimensión con decay aplicado
    /// @param member Dirección del miembro
    /// @param dimension Dimensión a consultar
    /// @return Score efectivo actual
    function getEffectiveScore(address member, RepDimension dimension)
        public view returns (uint256)
    {
        if (!profiles[member].exists) return 0;

        uint8 dim = uint8(dimension);
        DimensionScore memory ds = profiles[member].dimensions[dim];

        if (ds.rawScore == 0) return 0;

        uint256 elapsed = block.timestamp - ds.lastUpdate;
        if (elapsed == 0) return ds.rawScore;

        return _applyDecay(ds.rawScore, elapsed, lambdaFactorsBps[dim]);
    }

    /// @notice Devuelve el score agregado ponderado de un miembro
    /// @param member Dirección del miembro
    /// @return aggregated Score total (0–MAX_SCORE)
    function getAggregated(address member)
        external view returns (uint256 aggregated)
    {
        uint256 weightedSum = 0;
        uint256 totalWeight = 0;

        for (uint8 dim = 0; dim < 5; dim++) {
            uint256 score = getEffectiveScore(member, RepDimension(dim));
            weightedSum += score * dimensionWeightsBps[dim];
            totalWeight += dimensionWeightsBps[dim];
        }

        aggregated = totalWeight > 0 ? weightedSum / totalWeight : 0;
    }

    /// @notice Devuelve el vector completo de scores efectivos de un miembro
    /// @param member Dirección del miembro
    /// @return scores Array de 5 scores efectivos [PROPUESTA, VALIDACION, COMPRENSION, OSCILACION, COLABORACION]
    function getProfile(address member)
        external view returns (uint256[5] memory scores)
    {
        for (uint8 dim = 0; dim < 5; dim++) {
            scores[dim] = getEffectiveScore(member, RepDimension(dim));
        }
    }

    /// @notice Devuelve el historial de eventos reputacionales de un miembro
    function getEventHistory(address member)
        external view returns (ReputationEvent[] memory)
    {
        return eventHistory[member];
    }

    /// @notice Calcula el índice Gini de una dimensión entre un conjunto de miembros
    /// @dev Usado por ImmunityCore para detectar concentración de reputación
    /// @param members Array de direcciones a evaluar
    /// @param dimension Dimensión sobre la que calcular el Gini
    /// @return giniBps Índice Gini en BPS (0 = igualdad perfecta, BPS = concentración total)
    function calculateGini(address[] calldata members, RepDimension dimension)
        external view returns (uint256 giniBps)
    {
        uint256 n = members.length;
        if (n == 0) return 0;

        uint256[] memory scores = new uint256[](n);
        uint256 totalScore = 0;

        for (uint256 i = 0; i < n; i++) {
            scores[i] = getEffectiveScore(members[i], dimension);
            totalScore += scores[i];
        }

        if (totalScore == 0) return 0;

        // Gini = (Σ Σ |xi - xj|) / (2 × n × Σxi)
        uint256 sumAbsDiff = 0;
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = i + 1; j < n; j++) {
                uint256 diff = scores[i] > scores[j]
                    ? scores[i] - scores[j]
                    : scores[j] - scores[i];
                sumAbsDiff += diff * 2; // contar ambos lados
            }
        }

        giniBps = (sumAbsDiff * BPS) / (2 * n * totalScore);
    }

    // ─── Governance ──────────────────────────────────────────────────────────

    /// @notice Actualiza los pesos de agregación (deben sumar BPS)
    function setDimensionWeights(uint256[5] calldata newWeights)
        external onlyRole(GOVERNANCE_ROLE)
    {
        uint256 total = 0;
        for (uint256 i = 0; i < 5; i++) total += newWeights[i];
        require(total == BPS, "GranularReputation: weights must sum to BPS");

        dimensionWeightsBps = newWeights;
        emit WeightsUpdated(newWeights);
    }

    /// @notice Actualiza el estado de crisis (llamado por oráculo desde ImmunityCore)
    function setCrisisState(bool inCrisis) external onlyRole(ORACLE_ROLE) {
        systemInCrisis = inCrisis;
        emit CrisisStateUpdated(inCrisis);
    }

    /// @notice Avanza el ciclo actual
    function advanceCycle() external onlyRole(ORACLE_ROLE) {
        currentCycle++;
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @notice Inicializa el perfil de un miembro si no existe
    function _ensureProfile(address member) internal {
        if (!profiles[member].exists) {
            profiles[member].exists = true;
            for (uint8 dim = 0; dim < 5; dim++) {
                profiles[member].dimensions[dim] = DimensionScore({
                    rawScore:       0,
                    lastUpdate:     block.timestamp,
                    totalBoosts:    0,
                    totalPenalties: 0
                });
            }
        }
    }

    /// @notice Aplica decay exponencial virtualizado a un score
    /// @param rawScore Score sin decay
    /// @param elapsed Segundos transcurridos desde la última actualización
    /// @param lambdaFactorBps Factor de escala del lambda base (en BPS)
    /// @return Score con decay aplicado
    function _applyDecay(
        uint256 rawScore,
        uint256 elapsed,
        uint256 lambdaFactorBps
    ) internal pure returns (uint256) {
        // lambda efectivo = LAMBDA_BASE × lambdaFactor
        uint256 effectiveLambdaNum = LAMBDA_BASE_NUM * lambdaFactorBps;
        uint256 effectiveLambdaDen = LAMBDA_BASE_DEN * BPS;

        // λt en unidades de PRECISION
        uint256 lambdaT = (effectiveLambdaNum * elapsed * PRECISION) / effectiveLambdaDen;

        uint256 decayFactor;

        if (lambdaT <= PRECISION) {
            // Serie de Taylor: e^(-x) ≈ 1 - x + x²/2 - x³/6
            uint256 x  = lambdaT;
            uint256 x2 = (x * x) / PRECISION;
            uint256 x3 = (x2 * x) / PRECISION;

            uint256 pos = PRECISION + x2 / 2;
            uint256 neg = x + x3 / 6;

            decayFactor = pos > neg ? pos - neg : 0;
        } else {
            // Para períodos muy largos: mínimo del 5%
            decayFactor = PRECISION / 20;
        }

        return (rawScore * decayFactor) / PRECISION;
    }
}


