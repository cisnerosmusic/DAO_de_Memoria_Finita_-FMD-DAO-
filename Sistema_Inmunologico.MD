# Sistema Inmunológico de la FMD-DAO
### Respuesta Inflamatoria, Detección de Amenazas y Gobernanza de Crisis
#### Módulo de la DAO de Memoria Finita (FMD-DAO) · Ernesto Cisneros Cino

---

## Índice

- [Capa 1 - Para no especialistas](#capa-1--para-no-especialistas)
- [Capa 2 - Para especialistas](#capa-2--para-especialistas-gobernanza-y-sistemas-complejos)
- [Capa 3 - Implementación en Solidity](#capa-3--implementación-en-solidity-ethereum)
- [Relación con otros módulos de la FMD-DAO](#relación-con-otros-módulos)
- [Licencia](#licencia)

---

# Capa 1 — Para no especialistas

## ¿Qué es el Sistema Inmunológico de una DAO?

Una DAO (organización autónoma descentralizada) es una comunidad que se gobierna mediante reglas escritas en código. Como cualquier organización humana, puede ser atacada, manipulada o sufrir crisis internas.

El **Sistema Inmunológico** es el mecanismo que detecta esas crisis y responde de forma proporcional, igual que el sistema inmune de tu cuerpo: no reacciona igual ante un resfriado que ante una infección grave.

## La analogía biológica

Cuando tu cuerpo detecta una infección, activa una **respuesta inflamatoria**:

- sube la temperatura (inhóspita para bacterias),
- concentra recursos en el área afectada,
- suspende funciones no esenciales,
- y cuando pasa la amenaza, **vuelve al estado normal**.

No es un estado permanente. Es una respuesta temporal con un propósito claro.

La FMD-DAO hace exactamente lo mismo con su gobernanza:

| Cuerpo humano | FMD-DAO |
|---|---|
| Termómetro sube | Métricas de amenaza suben |
| Fiebre alta = infección grave | Threat Score alto = crisis grave |
| Respuesta proporcional al patógeno | Respuesta proporcional a la velocidad de la crisis |
| La fiebre baja cuando el peligro pasa | Los parámetros vuelven a la normalidad |
| Sistema inmune aprende del ataque | El sistema se auto-calibra tras cada crisis |

## ¿Qué puede amenazar a una DAO?

- Que de repente casi nadie vote (colapso de participación).
- Que una sola persona acumule demasiado poder o reputación muy rápido.
- Que alguien drene los fondos comunes de forma acelerada.
- Que el consenso se fragmente y la comunidad quede paralizada.
- Que un error técnico (exploit) comprometa los contratos.

## ¿Cómo responde el sistema?

Cuando detecta una amenaza, el sistema **ajusta temporalmente** ciertos parámetros:

- Eleva el umbral de quórum (se necesitan más votos para tomar decisiones).
- Alarga los tiempos de espera antes de ejecutar cambios importantes.
- Da más peso temporal a los expertos técnicos en decisiones urgentes.
- Registra todo con auditoría obligatoria.

Y lo más importante: **tiene fecha de vencimiento**. La respuesta inflamatoria no puede durar para siempre. El sistema vuelve solo a la normalidad.

> No es dictadura.
> Es un reflejo espinal con accountability brutal.

---

# Capa 2 - Para especialistas (gobernanza y sistemas complejos)

## Arquitectura del sistema

El Sistema Inmunológico opera sobre tres ejes:

1. **Detección** - monitoreo continuo de métricas de salud del sistema.
2. **Clasificación** - cálculo de un Threat Score y su velocidad de cambio.
3. **Respuesta graduada** - ajuste paramétrico proporcional a la severidad y velocidad.

---

## Métricas monitoreadas (señales de amenaza)

| Métrica | Condición de alerta | Peso |
|---|---|---|
| Colapso de participación | >70% caída en 48h | 3 |
| Fragmentación de consenso | Índice Gini >0.8 | 2 |
| Drenaje de tesorería | >30% salida en 7 días | 3 |
| Spike de reputación | 1 actor >40% del total en 72h | 3 |
| Desviación de oráculos | >3σ de la media histórica | 2 |
| Falla técnica | Exploit confirmado / halt de contrato | 3 |

**Threat Score S** = suma ponderada de métricas activas, rango 0–16.

---

## Niveles de severidad

```txt
S ∈ [0, 3]   →   VERDE    — Operación normal
S ∈ [4, 6]   →   AMARILLO — Observación aumentada
S ∈ [7, 9]   →   NARANJA  — Restricciones leves
S ∈ [10, 16] →   ROJO     — Inflamación total
```

---

## El factor crítico: velocidad de la amenaza

La magnitud del Threat Score importa, pero **la velocidad importa más**.

```txt
Velocidad = dS/dt   (puntos de threat por hora)

dS/dt < 2           →   LOGARÍTMICA  (crecimiento lento, hay tiempo)
2 ≤ dS/dt < 5       →   LINEAL       (moderado, vigilancia activa)
dS/dt ≥ 5           →   EXPONENCIAL  (crisis explosiva, respuesta inmediata)
```

> La velocidad de amenaza determina el nivel de democracia permisible en la respuesta.

Este principio es la columna vertebral del sistema: una crisis lenta permite deliberación colectiva; una crisis explosiva requiere que la experticia técnica prevalezca temporalmente.

---

## Respuesta graduada: ajuste de parámetros

### Crisis EXPONENCIAL (dS/dt ≥ 5)

```txt
Quórum:              40%     (vs 10% en operación normal)
Timelock:            14 días (vs 48h en operación normal)
tau_DAO:             15 días (vs 60 días)
tau_IA:              18 meses (vs 33 meses)
Ratio tau_IA/tau_DAO: 432    (vs 200 en normal)

Pesos de decisión para cancelar inflamación:
  C1 (Expertos):      60%
  Oráculo verificado: 30%
  C2 (Comunes):       10%   (testimonial, no tiebreaker)
```

**Razón:** En crisis rápida, la experticia técnica debe prevalecer sobre la legitimidad democrática. El tiempo no permite deliberación amplia.

---

### Crisis LOGARÍTMICA (dS/dt < 2)

```txt
Parámetros: casi normales, con ligero aumento de vigilancia.

Pesos de decisión:
  C1 (Expertos):      33%
  Oráculo verificado: 33%
  C2 (Comunes):       34%   (democracia plena)
```

**Razón:** Hay tiempo. La comunidad puede deliberar. El sistema no necesita centralizar.

---

## Sistema auto-calibrable (v2.2)

El sistema aprende de cada crisis para reducir falsos positivos y falsos negativos.

### Aprendizaje por historial

```txt
Sea H = { (S_i, dS/dt_i, resultado_i) } el historial de crisis.

Después de cada crisis resuelta:

  - Si fue falso positivo (inflamación sin amenaza real):
      → ajustar pesos a la baja para esa métrica
      → reducir sensibilidad del detector

  - Si fue falso negativo (amenaza real sin detección):
      → ajustar pesos al alza
      → reducir umbrales de activación
```

### Circuit Breakers

Para evitar que el sistema se quede "atascado" en inflamación:

```txt
MAX_INFLAMMATION_DAYS = 30

Si la inflamación dura más de 30 días sin resolverse:
  → activar revisión forzosa por C1 + C2 + Oráculo
  → publicar reporte obligatorio de estado
  → reducir parámetros inflamatorios a la mitad
```

### Decaimiento forzoso post-crisis

Una vez resuelta la amenaza, los parámetros no vuelven instantáneamente:

```txt
P(t) = P_normal + (P_inflamed - P_normal) * e^(-lambda * t)

donde lambda define la velocidad de recuperación.
```

Esto evita oscilaciones bruscas y da estabilidad a la transición.

---

## Relación con el Índice de Resiliencia R

Durante la inflamación, R se monitorea con mayor frecuencia:

```txt
R = tau * Omega

En crisis ROJA:
  tau se reduce (respuesta rápida)
  Omega aumenta (ciclos más frecuentes)
  R se mantiene dentro del Valle [1, 3] por diseño

Si R cae fuera del Valle durante la inflamación:
  → señal de que la respuesta misma está siendo demasiado agresiva
  → activar revisión automática de los parámetros de crisis
```

> El Valle de Resiliencia es el árbitro final.
> Ni siquiera la respuesta de emergencia puede sacar al sistema del Valle.

---

# Capa 3 — Implementación en Solidity (Ethereum)

> Compatible con Solidity ^0.8.20 y OpenZeppelin v5.
> Diseñado para desplegarse en L2 (Arbitrum u Optimism) para reducir costos de gas.

---

## Estructura de contratos

```
FMD_DAO/
├── core/
│   ├── ImmunityCore.sol          # Lógica central del sistema inmune
│   ├── ThreatOracle.sol          # Alimenta métricas de amenaza
│   └── InflammationController.sol # Gestiona parámetros durante crisis
├── governance/
│   ├── BicameralVoting.sol       # Votación C1/C2 con pesos variables
│   └── ResilienceIndex.sol       # Cálculo y monitoreo de R
├── interfaces/
│   ├── IImmunity.sol
│   └── IThreatOracle.sol
└── libraries/
    └── ThreatMath.sol            # Cálculos de Threat Score y velocidad
```

---

## ThreatMath.sol — Cálculo del Threat Score y velocidad

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ThreatMath
/// @notice Librería para cálculo del Threat Score y su velocidad de cambio
library ThreatMath {

    uint256 public constant MAX_SCORE = 16;

    struct ThreatMetric {
        uint256 value;      // Valor actual de la métrica (escalado x100)
        uint256 threshold;  // Umbral de activación (escalado x100)
        uint256 weight;     // Peso en el Threat Score total
        bool    active;     // Si la métrica está por encima del umbral
    }

    /// @notice Calcula el Threat Score total como suma ponderada
    /// @param metrics Array de métricas activas
    /// @return score Threat Score total (0-16)
    function calculateThreatScore(
        ThreatMetric[] memory metrics
    ) internal pure returns (uint256 score) {
        for (uint256 i = 0; i < metrics.length; i++) {
            if (metrics[i].value >= metrics[i].threshold) {
                score += metrics[i].weight;
            }
        }
        require(score <= MAX_SCORE, "ThreatMath: score overflow");
    }

    /// @notice Clasifica la velocidad de la amenaza
    /// @param prevScore Threat Score anterior
    /// @param currScore Threat Score actual
    /// @param hoursElapsed Horas transcurridas entre mediciones
    /// @return velocity Velocidad en puntos/hora (escalada x100)
    /// @return regime 0=logaritmico, 1=lineal, 2=exponencial
    function classifyVelocity(
        uint256 prevScore,
        uint256 currScore,
        uint256 hoursElapsed
    ) internal pure returns (uint256 velocity, uint8 regime) {
        require(hoursElapsed > 0, "ThreatMath: invalid time");

        if (currScore <= prevScore) {
            return (0, 0); // Amenaza decreciente
        }

        // velocity * 100 para evitar decimales
        velocity = ((currScore - prevScore) * 100) / hoursElapsed;

        if (velocity < 200) {
            regime = 0; // Logarítmica: dS/dt < 2
        } else if (velocity < 500) {
            regime = 1; // Lineal: 2 <= dS/dt < 5
        } else {
            regime = 2; // Exponencial: dS/dt >= 5
        }
    }
}
```

---

## ImmunityCore.sol — Núcleo del sistema inmune

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ThreatMath.sol";
import "../interfaces/IThreatOracle.sol";

/// @title ImmunityCore
/// @notice Gestiona el ciclo completo del Sistema Inmunológico de la FMD-DAO
/// @dev El sistema inmune NO puede modificar invariantes constitucionales
contract ImmunityCore {

    using ThreatMath for ThreatMath.ThreatMetric[];

    // ─── Enums ──────────────────────────────────────────────────────────────

    enum SeverityLevel { GREEN, YELLOW, ORANGE, RED }
    enum VelocityRegime { LOGARITHMIC, LINEAR, EXPONENTIAL }

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct SystemParams {
        uint256 quorumBps;        // Quórum en basis points (10000 = 100%)
        uint256 timelockDays;     // Timelock en días
        uint256 tauDAO;           // Tau DAO en días
        uint256 tauIA;            // Tau IA en meses
    }

    struct InflammationState {
        bool    active;
        uint256 startTimestamp;
        uint256 threatScore;
        SeverityLevel severity;
        VelocityRegime velocityRegime;
        uint256 c1WeightBps;      // Peso C1 en basis points
        uint256 oracleWeightBps;  // Peso Oráculo en basis points
        uint256 c2WeightBps;      // Peso C2 en basis points
    }

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant MAX_INFLAMMATION_DAYS = 30;
    uint256 public constant BPS_DENOMINATOR       = 10_000;

    // Parámetros normales
    SystemParams public normalParams = SystemParams({
        quorumBps:    1_000,  // 10%
        timelockDays: 2,      // 48 horas
        tauDAO:       60,
        tauIA:        33
    });

    // Parámetros en crisis exponencial
    SystemParams public crisisParams = SystemParams({
        quorumBps:    4_000,  // 40%
        timelockDays: 14,
        tauDAO:       15,
        tauIA:        18
    });

    // ─── State ───────────────────────────────────────────────────────────────

    InflammationState public inflammation;
    SystemParams      public activeParams;
    IThreatOracle     public oracle;

    uint256 public prevThreatScore;
    uint256 public prevScoreTimestamp;

    // Historial de crisis para auto-calibración
    uint256[] public crisisHistory;   // threat scores registrados
    bool[]    public falsePositives;  // false = real, true = falso positivo

    // ─── Events ──────────────────────────────────────────────────────────────

    event InflammationActivated(
        uint256 threatScore,
        SeverityLevel severity,
        VelocityRegime velocityRegime,
        uint256 timestamp
    );
    event InflammationResolved(uint256 duration, uint256 timestamp);
    event ParamsAdjusted(SystemParams newParams);
    event CircuitBreakerTriggered(uint256 daysSinceStart);

    // ─── Modifiers ───────────────────────────────────────────────────────────

    modifier onlyOracle() {
        require(msg.sender == address(oracle), "ImmunityCore: not oracle");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address _oracle) {
        oracle = IThreatOracle(_oracle);
        activeParams = normalParams;
        prevScoreTimestamp = block.timestamp;
    }

    // ─── Core Logic ──────────────────────────────────────────────────────────

    /// @notice Punto de entrada principal: recibe nuevo Threat Score del oráculo
    /// @param newScore Nuevo Threat Score calculado off-chain o por el oráculo
    function updateThreatScore(uint256 newScore) external onlyOracle {
        require(newScore <= ThreatMath.MAX_SCORE, "ImmunityCore: invalid score");

        uint256 hoursElapsed = (block.timestamp - prevScoreTimestamp) / 1 hours;
        if (hoursElapsed == 0) hoursElapsed = 1;

        (, uint8 regime) = ThreatMath.classifyVelocity(
            prevThreatScore,
            newScore,
            hoursElapsed
        );

        SeverityLevel severity = _classifySeverity(newScore);

        _applyResponse(severity, VelocityRegime(regime), newScore);

        prevThreatScore = newScore;
        prevScoreTimestamp = block.timestamp;

        // Circuit breaker
        if (inflammation.active) {
            _checkCircuitBreaker();
        }
    }

    /// @notice Resuelve la inflamación si el Threat Score vuelve a zona verde
    function resolveInflammation() external onlyOracle {
        require(inflammation.active, "ImmunityCore: no active inflammation");
        require(
            _classifySeverity(prevThreatScore) == SeverityLevel.GREEN,
            "ImmunityCore: threat not resolved"
        );

        uint256 duration = block.timestamp - inflammation.startTimestamp;
        inflammation.active = false;

        // Recuperación gradual (no instantánea)
        _beginGradualRecovery();

        emit InflammationResolved(duration, block.timestamp);
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    function _classifySeverity(uint256 score)
        internal pure returns (SeverityLevel)
    {
        if (score <= 3)  return SeverityLevel.GREEN;
        if (score <= 6)  return SeverityLevel.YELLOW;
        if (score <= 9)  return SeverityLevel.ORANGE;
        return SeverityLevel.RED;
    }

    function _applyResponse(
        SeverityLevel severity,
        VelocityRegime regime,
        uint256 score
    ) internal {
        if (severity == SeverityLevel.GREEN) return;

        if (!inflammation.active) {
            inflammation.active = true;
            inflammation.startTimestamp = block.timestamp;
            crisisHistory.push(score);
        }

        inflammation.severity      = severity;
        inflammation.threatScore   = score;
        inflammation.velocityRegime = regime;

        // Determinar pesos según velocidad
        if (regime == VelocityRegime.EXPONENTIAL) {
            // Crisis explosiva: expertos al frente
            inflammation.c1WeightBps     = 6_000; // 60%
            inflammation.oracleWeightBps = 3_000; // 30%
            inflammation.c2WeightBps     = 1_000; // 10%
            activeParams = crisisParams;
        } else if (regime == VelocityRegime.LINEAR) {
            // Crisis moderada: equilibrio con inclinación técnica
            inflammation.c1WeightBps     = 4_500; // 45%
            inflammation.oracleWeightBps = 3_500; // 35%
            inflammation.c2WeightBps     = 2_000; // 20%
            // Parámetros intermedios
            activeParams.quorumBps    = 2_500;
            activeParams.timelockDays = 7;
        } else {
            // Crisis lenta: democracia plena
            inflammation.c1WeightBps     = 3_300; // 33%
            inflammation.oracleWeightBps = 3_300; // 33%
            inflammation.c2WeightBps     = 3_400; // 34%
            activeParams.quorumBps    = 1_500;
            activeParams.timelockDays = 3;
        }

        emit InflammationActivated(
            score, severity, regime, block.timestamp
        );
        emit ParamsAdjusted(activeParams);
    }

    function _checkCircuitBreaker() internal {
        uint256 daysSinceStart =
            (block.timestamp - inflammation.startTimestamp) / 1 days;

        if (daysSinceStart >= MAX_INFLAMMATION_DAYS) {
            // Forzar revisión: reducir parámetros inflamatorios a la mitad
            activeParams.quorumBps    = (activeParams.quorumBps + normalParams.quorumBps) / 2;
            activeParams.timelockDays = (activeParams.timelockDays + normalParams.timelockDays) / 2;

            emit CircuitBreakerTriggered(daysSinceStart);
        }
    }

    /// @notice Recuperación exponencial hacia parámetros normales
    /// @dev En producción, llamar periódicamente con un keeper/oracle
    function _beginGradualRecovery() internal {
        // Cada llamada reduce la distancia a normalParams a la mitad
        // Simula P(t) = P_normal + (P_inflamed - P_normal) * e^(-lambda*t)
        activeParams.quorumBps =
            (activeParams.quorumBps + normalParams.quorumBps) / 2;
        activeParams.timelockDays =
            (activeParams.timelockDays + normalParams.timelockDays) / 2;
        activeParams.tauDAO =
            (activeParams.tauDAO + normalParams.tauDAO) / 2;
    }

    // ─── View functions ───────────────────────────────────────────────────────

    /// @notice Devuelve el estado completo del sistema inmune
    function getImmunityStatus() external view returns (
        bool active,
        SeverityLevel severity,
        VelocityRegime regime,
        uint256 c1Weight,
        uint256 c2Weight,
        uint256 oracleWeight,
        SystemParams memory params
    ) {
        return (
            inflammation.active,
            inflammation.severity,
            inflammation.velocityRegime,
            inflammation.c1WeightBps,
            inflammation.c2WeightBps,
            inflammation.oracleWeightBps,
            activeParams
        );
    }

    /// @notice Devuelve si el sistema está en zona segura del Valle de Resiliencia
    /// @param tau Valor actual de tau en días
    /// @param omega Valor actual de omega (ciclos/día, escalado x1000)
    function isInResilienceValley(uint256 tau, uint256 omega)
        external pure returns (bool)
    {
        // R = tau * omega, el Valle es 1 < R < 3 (escalado x1000)
        uint256 R = (tau * omega) / 1000;
        return R > 1 && R < 3;
    }
}
```

---

## ThreatOracle.sol — Alimentador de métricas

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/ThreatMath.sol";
import "./ImmunityCore.sol";

/// @title ThreatOracle
/// @notice Calcula el Threat Score a partir de métricas on-chain y lo reporta
/// @dev Las métricas pueden venir de Chainlink, Dune, o consenso interno
contract ThreatOracle {

    ImmunityCore public immunityCore;
    address      public admin;

    // Métricas individuales con sus umbrales y pesos
    // Índices: 0=participacion, 1=gini, 2=tesoreria, 3=reputacion, 4=oracle, 5=exploit
    uint256[6] public thresholds = [70, 80, 30, 40, 300, 1];
    uint256[6] public weights    = [3, 2, 3, 3, 2, 3];

    event MetricsUpdated(uint256[6] values, uint256 score);

    modifier onlyAdmin() {
        require(msg.sender == admin, "ThreatOracle: not admin");
        _;
    }

    constructor(address _immunityCore) {
        immunityCore = ImmunityCore(_immunityCore);
        admin = msg.sender;
    }

    /// @notice Envía nuevas métricas y dispara actualización del sistema inmune
    /// @param values Array de 6 valores de métricas (escalados x100 donde aplica)
    function submitMetrics(uint256[6] calldata values) external onlyAdmin {
        uint256 score = 0;
        for (uint256 i = 0; i < 6; i++) {
            if (values[i] >= thresholds[i]) {
                score += weights[i];
            }
        }

        emit MetricsUpdated(values, score);
        immunityCore.updateThreatScore(score);
    }
}
```

---

## Notas de despliegue

```txt
Red recomendada:    Arbitrum One o Optimism (L2 sobre Ethereum)
Solidity:           ^0.8.20
OpenZeppelin:       v5.x
Verificación:       Etherscan + Sourcify

Costos estimados anuales en L2:
  Actualizaciones de métricas (~365 txs): ~$800
  Activaciones de inflamación (~5/año):   ~$150
  Resoluciones de crisis (~5/año):         ~$150
  Total estimado:                          ~$1,100

Invariante de seguridad:
  El sistema inmune NUNCA puede modificar:
    - invariantes constitucionales
    - umbrales de seguridad duros
    - mecanismos de emergencia base

  Solo puede ajustar parámetros periféricos dentro de rangos predefinidos.
```

---

# Relación con otros módulos

```txt
FMD-DAO
├── Memoria Finita (decay reputacional)
│     └── Durante crisis: tau_DAO y tau_IA se ajustan temporalmente
│
├── Ruido Estabilizador
│     └── Permanece activo durante crisis (no se suspende)
│         El ruido sigue amortiguando aunque los parámetros sean más estrictos
│
├── Índice de Resiliencia R
│     └── Es el árbitro final: ni la respuesta de emergencia
│         puede sacar al sistema del Valle [1, 3]
│
└── Sistema Inmunológico  ◄── este módulo
      ├── Detecta amenazas
      ├── Clasifica por magnitud y velocidad
      ├── Ajusta parámetros periféricos
      ├── Se auto-calibra con historial
      └── Vuelve solo al estado normal
```

---

## El invariante fundamental

```
No execution without trace.
No rule change without delay.
No authority without exposure.
```

Este invariante es **no negociable**. El sistema inmune no es una excepción, es la prueba de que el sistema puede responder a una crisis sin abandonar sus principios.

---

## Licencia

MIT License · Ernesto Cisneros Cino

---

*Parte del proyecto [DAO de Memoria Finita (FMD-DAO)](https://github.com/cisnerosmusic/DAO_de_Memoria_Finita_-FMD-DAO-)*

*"Un organismo que no puede enfermar, tampoco puede sanar."*
