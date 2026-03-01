# OracleLayer
### Arquitectura híbrida, cíclica y resistente a dictadura de oráculos
#### Módulo de la DAO de Memoria Finita (FMD-DAO) · Ernesto Cisneros Cino

---

## Índice

- [El problema que nadie nombra](#el-problema-que-nadie-nombra)
- [Principios de diseño](#principios-de-diseño)
- [Estratificación por tipo de dato](#estratificación-por-tipo-de-dato)
- [Rotación cíclica de proveedores](#rotación-cíclica-de-proveedores)
- [Mecanismo de disputa y ventana optimista](#mecanismo-de-disputa-y-ventana-optimista)
- [Decay de oráculos inactivos o desactualizados](#decay-de-oráculos-inactivos-o-desactualizados)
- [Arquitectura de contratos](#arquitectura-de-contratos)
- [Implementación en Solidity](#implementación-en-solidity)
- [Relación con otros módulos](#relación-con-otros-módulos)
- [Licencia](#licencia)

---

## El problema que nadie nombra

Un sistema de gobernanza descentralizada puede tener contratos perfectamente auditados, decay exponencial, bicameralidad, ruido estabilizador y sistema inmunológico — y aun así ser completamente capturado si su oráculo es un punto de falla único.

**Quien controla el oráculo, controla el sistema.** No hace falta hackear los contratos. Basta con controlar qué datos entran.

Los modos de falla son varios y todos silenciosos:

```txt
Modo 1 — Dictadura directa:
  Un solo proveedor de oráculo alimenta todos los datos.
  Si ese proveedor miente, el sistema ejecuta sobre mentiras.

Modo 2 — Captura por inactividad:
  El oráculo deja de actualizarse. Los datos envejecen.
  El sistema sigue ejecutando sobre datos obsoletos sin saberlo.

Modo 3 — Sincronización de proveedores:
  Múltiples oráculos, pero controlados por los mismos actores.
  El consenso entre ellos no es garantía de verdad.

Modo 4 — Dictadura de infraestructura:
  Dependencia permanente de un proveedor externo (Chainlink, UMA).
  Si ese proveedor cambia condiciones, el sistema queda rehén.

Modo 5 — Oráculo fijo sin renovación:
  El proveedor aprobado en el ciclo 1 sigue siéndolo en el ciclo 50.
  La memoria finita aplica a todo — incluso a los oráculos.
```

La solución no es encontrar el oráculo perfecto. Es diseñar un sistema donde **ningún oráculo sea permanente, ninguno sea único, y todos estén sujetos al mismo principio de memoria finita que el resto del sistema**.

---

## Principios de diseño

### 1. Ningún oráculo es permanente

Los proveedores de oráculo rotan. Su autorización tiene vida útil definida — exactamente igual que la reputación de un experto en C1. Un oráculo que no se renueva, caduca.

### 2. Ningún oráculo es único

Para cualquier dato crítico, el sistema requiere al menos dos fuentes independientes. Si coinciden, el dato es válido. Si divergen, se activa disputa automática.

### 3. La fuente cambia, el contrato no

El `OracleRouter` es el único contrato que los módulos consultan. Internamente rota entre proveedores según el ciclo activo. Los contratos externos nunca saben qué proveedor está activo — eso rompe la posibilidad de colusión dirigida.

### 4. Lo que puede ser on-chain, lo es

Cualquier dato que pueda calcularse directamente desde eventos y estado de los contratos no pasa por oráculo externo. El oráculo solo toca lo que genuinamente no puede estar on-chain.

### 5. Los datos tienen fecha de vencimiento

Todo dato ingresado por un oráculo lleva timestamp y TTL (time-to-live). Si el TTL vence sin actualización, el dato se marca como `STALE` y el sistema entra en modo de precaución hasta recibir dato fresco.

### 6. Memoria finita también para oráculos

Un proveedor de oráculo acumula historial de precisión. Su peso en el consenso decae si sus datos históricos han sido disputados y refutados con frecuencia. El oráculo que miente repetidamente pierde autoridad gradualmente, igual que un experto que valida mal.

---

## Estratificación por tipo de dato

No todos los datos necesitan el mismo nivel de descentralización. La estratificación reduce coste y complejidad sin sacrificar seguridad donde importa.

```txt
NIVEL 0 — Completamente on-chain (sin oráculo externo)
  ┌─────────────────────────────────────────────────────┐
  │ Gini reputacional          calculado en contrato    │
  │ Decay acumulado            calculado en contrato    │
  │ Tasa de participación      calculado en contrato    │
  │ Índice de Resiliencia R    calculado en contrato    │
  │ Rigidez ideológica         calculado en contrato    │
  └─────────────────────────────────────────────────────┘

NIVEL 1 — Consenso interno (oráculos operados por C1)
  ┌─────────────────────────────────────────────────────┐
  │ Resultados de Proof of Understanding                │
  │ Validación de justificaciones de voto               │
  │ Métricas de rendimiento de propuestas               │
  │ Detección de comportamiento anómalo                 │
  └─────────────────────────────────────────────────────┘
  Mínimo 3 nodos · Quórum 2/3 · Ventana de disputa 48h

NIVEL 2 — Proveedor externo rotante + fallback interno
  ┌─────────────────────────────────────────────────────┐
  │ Drenaje de tesorería (cross-chain)                  │
  │ Desviaciones de precio / activos externos           │
  │ Datos de identidad ZK (Sismo, WorldID)              │
  │ Timestamps verificados (beacon de tiempo)           │
  └─────────────────────────────────────────────────────┘
  Proveedor A activo + Proveedor B en standby
  Rotación cada N ciclos · Fallback automático

NIVEL 3 — Aleatoriedad verificable (VRF)
  ┌─────────────────────────────────────────────────────┐
  │ Ruido estabilizador (τ, Ω, quórums)                 │
  │ Selección de auditores por sorteo                   │
  │ Lotería ponderada de rotación C1                    │
  └─────────────────────────────────────────────────────┘
  VRF rotante entre proveedores aprobados
  Chainlink VRF · Drand · API3 QRNG en rotación
```

---

## Rotación cíclica de proveedores

### El mecanismo

El sistema mantiene un **registro de proveedores aprobados** con sus metadatos de elegibilidad. En cada ciclo de gobernanza, el `OracleRouter` selecciona el proveedor activo y el de standby según un algoritmo determinista que combina:

- historial de precisión del proveedor (score reputacional del oráculo),
- antigüedad desde la última vez que fue proveedor activo,
- disponibilidad verificada en el último ciclo.

La selección es pública, predecible en sus reglas pero no en su resultado concreto (porque depende del estado del sistema en ese momento), y no puede ser influenciada por ningún actor individual.

### Diagrama de rotación

```txt
Ciclo N:
  Proveedor ACTIVO   →  A  (score: 8400 BPS)
  Proveedor STANDBY  →  C  (score: 7900 BPS)
  En espera          →  B, D, E

Ciclo N+1:
  A lleva 1 ciclo activo → elegible para standby, no para activo
  Selección de nuevo activo entre {B, C, D, E} por score + antigüedad
  Proveedor ACTIVO   →  C  (mayor score entre elegibles)
  Proveedor STANDBY  →  B  (segundo mayor)
  A pasa a espera

Ciclo N+2:
  Proveedor ACTIVO   →  B
  Proveedor STANDBY  →  D
  C y A en espera

...y así sucesivamente.
```

Ningún proveedor puede ser activo en dos ciclos consecutivos. El standby del ciclo anterior tiene prioridad para ser activo en el siguiente, pero solo si su score lo permite.

### Score reputacional del oráculo

```txt
OracleScore(p) = score base ajustado por historial

Ajustes:
  +100 BPS por cada dato confirmado sin disputa
  -300 BPS por cada dato refutado en disputa
  -50  BPS por cada dato marcado STALE (no actualizado a tiempo)
  -200 BPS por ausencia completa en un ciclo donde era STANDBY

Decay del OracleScore:
  Mismo mecanismo que la reputación de expertos
  λ_oracle = λ_base × 0.7  (decay más lento — la infraestructura cambia despacio)

Umbral de exclusión:
  OracleScore < 3000 BPS → proveedor suspendido hasta recuperación
  OracleScore < 1000 BPS → proveedor eliminado del registro
```

---

## Mecanismo de disputa y ventana optimista

### Principio optimista

Los datos ingresados por el oráculo activo se asumen válidos durante una **ventana de 48 horas**. Durante ese período, cualquier miembro puede disputar el dato aportando evidencia alternativa.

Si no hay disputa, el dato se confirma y el proveedor recibe crédito de precisión.
Si hay disputa, el dato queda congelado y se activa el proceso de resolución.

### Proceso de resolución de disputa

```txt
Hora 0:    Oráculo activo publica dato D con firma
Hora 0–48: Ventana de disputa abierta
           Cualquier miembro puede disputar aportando:
             - dato alternativo D' con fuente verificable
             - firma del proveedor STANDBY como respaldo opcional

Si disputa activada:
  Hora 48:  C1 recibe la disputa (quórum mínimo 3 expertos)
  Hora 48–96: C1 evalúa D vs D'
  Hora 96:  Veredicto:
              D confirmado  → D' disputante penalizado en créditos
                            → proveedor activo +100 BPS
              D' confirmado → proveedor activo -300 BPS
                            → proveedor activo puede ser suspendido
                            → dato D' reemplaza D on-chain
              Empate        → dato congelado, se usa último dato válido
                            → ambos proveedores -50 BPS
```

### Datos STALE

Si el oráculo activo no actualiza un dato antes de su TTL:

```txt
TTL vencido → dato marcado STALE
Sistema entra en modo PRECAUCIÓN para ese dato:
  - el módulo que depende del dato usa el último valor válido
  - se registra evento STALE en cadena
  - proveedor activo recibe -50 BPS por cada hora de retraso
  - si STALE dura más de 24h → proveedor STANDBY toma el control automáticamente
  - si ambos STALE → Sistema Inmunológico recibe señal de alerta (métricas de amenaza +2)
```

---

## Decay de oráculos inactivos o desactualizados

Un oráculo que estuvo activo hace diez ciclos y regresa con datos no actualizados es tan peligroso como uno nuevo sin historial. El sistema aplica **decay de relevancia** a los proveedores que han estado inactivos:

```txt
RelevanciaDecay(p, t_inactivo) = OracleScore(p) × e^(-λ_oracle × t_inactivo)

Efecto:
  Un proveedor inactivo durante 3 ciclos vuelve con score reducido
  No pierde su historial, pero su peso en consenso disminuye
  Debe "reactivarse" gradualmente — igual que un experto que regresa a C1

Reactivación:
  Ciclo de reactivación: el proveedor opera como STANDBY obligatorio
  Si no comete errores: score se recupera al ritmo normal de acumulación
  Si comete errores en reactivación: puede ser excluido definitivamente
```

Esto evita que proveedores hibernantes sean activados por sorpresa con score histórico alto pero conocimiento desactualizado de las condiciones del sistema.

---

## Arquitectura de contratos

```
OracleLayer/
├── OracleRouter.sol         # Punto único de consulta para módulos internos
├── OracleRegistry.sol       # Registro de proveedores aprobados y sus scores
├── OracleDispute.sol        # Gestión de disputas y resolución por C1
├── OracleScheduler.sol      # Lógica de rotación cíclica de proveedores
└── libraries/
    └── OracleMath.sol       # Decay de score, TTL, cálculo de elegibilidad
```

### Flujo de consulta (desde módulo interno)

```txt
ImmunityCore.sol
  └── llama OracleRouter.getLatestData(METRIC_TREASURY_DRAIN)
        └── OracleRouter verifica:
              - proveedor activo para ese tipo de dato
              - dato dentro de TTL (no STALE)
              - dato confirmado (ventana de disputa pasada) o en ventana
            Si OK → devuelve dato
            Si STALE → devuelve último dato válido + flag STALE
            Si en disputa → devuelve dato congelado + flag DISPUTED
```

Los módulos internos nunca saben qué proveedor está activo. Solo consultan al Router. El Router es el único que conoce el estado de rotación.

---

## Implementación en Solidity

### OracleMath.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title OracleMath
/// @notice Cálculos de decay, TTL y elegibilidad de proveedores de oráculo
library OracleMath {

    uint256 public constant PRECISION       = 1e18;
    uint256 public constant BPS             = 10_000;

    // λ_oracle = λ_base × 0.7
    // λ_base = ln(2) / 60 días ≈ 1155 / 10_000_000 por segundo
    uint256 public constant LAMBDA_NUM      = 1155 * 7; // × 0.7
    uint256 public constant LAMBDA_DEN      = 10_000_000 * 10;

    uint256 public constant MIN_SCORE       = 1_000;  // por debajo → eliminado
    uint256 public constant SUSPEND_SCORE   = 3_000;  // por debajo → suspendido
    uint256 public constant MAX_SCORE       = 10_000;

    // Ajustes de score
    int256 public constant SCORE_CONFIRMED  =  100;
    int256 public constant SCORE_REFUTED    = -300;
    int256 public constant SCORE_STALE      =  -50;  // por hora de retraso
    int256 public constant SCORE_ABSENT     = -200;

    /// @notice Aplica decay al score de un proveedor inactivo
    function applyInactivityDecay(
        uint256 currentScore,
        uint256 inactiveSeconds
    ) internal pure returns (uint256) {
        if (inactiveSeconds == 0) return currentScore;

        uint256 lambdaT = (LAMBDA_NUM * inactiveSeconds * PRECISION) / LAMBDA_DEN;

        uint256 decayFactor;
        if (lambdaT <= PRECISION) {
            uint256 x  = lambdaT;
            uint256 x2 = (x * x) / PRECISION;
            uint256 x3 = (x2 * x) / PRECISION;
            uint256 pos = PRECISION + x2 / 2;
            uint256 neg = x + x3 / 6;
            decayFactor = pos > neg ? pos - neg : 0;
        } else {
            decayFactor = PRECISION / 20; // mínimo 5%
        }

        uint256 decayed = (currentScore * decayFactor) / PRECISION;
        return decayed < MIN_SCORE ? MIN_SCORE : decayed;
    }

    /// @notice Calcula el score de elegibilidad para rotación
    /// @dev Combina score actual con bonus por antigüedad de espera
    function eligibilityScore(
        uint256 oracleScore,
        uint256 cyclesWaiting  // ciclos desde la última vez activo
    ) internal pure returns (uint256) {
        // Bonus por espera: +500 BPS por ciclo de espera, máximo +3000
        uint256 waitBonus = cyclesWaiting * 500;
        if (waitBonus > 3_000) waitBonus = 3_000;
        uint256 total = oracleScore + waitBonus;
        return total > MAX_SCORE ? MAX_SCORE : total;
    }

    /// @notice Ajusta el score tras un evento
    function adjustScore(
        uint256 currentScore,
        int256  delta
    ) internal pure returns (uint256) {
        if (delta >= 0) {
            uint256 increased = currentScore + uint256(delta);
            return increased > MAX_SCORE ? MAX_SCORE : increased;
        } else {
            uint256 decrease = uint256(-delta);
            return currentScore > decrease ? currentScore - decrease : 0;
        }
    }
}
```

---

### OracleRegistry.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../libraries/OracleMath.sol";

/// @title OracleRegistry
/// @notice Registro de proveedores de oráculo aprobados con score reputacional
///         y gestión del ciclo de rotación.
contract OracleRegistry is AccessControl {

    using OracleMath for uint256;

    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant SCHEDULER_ROLE  = keccak256("SCHEDULER_ROLE");
    bytes32 public constant DISPUTE_ROLE    = keccak256("DISPUTE_ROLE");

    // ─── Structs ─────────────────────────────────────────────────────────────

    enum ProviderStatus { INACTIVE, ACTIVE, STANDBY, SUSPENDED, ELIMINATED }

    struct OracleProvider {
        address  endpoint;          // dirección o identificador del proveedor
        string   name;              // nombre legible (Chainlink, Drand, interno-C1...)
        uint256  score;             // score reputacional actual (0–10000 BPS)
        uint256  lastActiveAt;      // timestamp del último ciclo como ACTIVO
        uint256  lastUpdateAt;      // timestamp de la última actualización de datos
        uint256  cyclesWaiting;     // ciclos consecutivos en espera
        uint256  totalConfirmed;    // datos confirmados histórico
        uint256  totalRefuted;      // datos refutados histórico
        uint256  totalStale;        // datos STALE histórico
        ProviderStatus status;
        bool     exists;
    }

    // ─── State ───────────────────────────────────────────────────────────────

    mapping(bytes32 => OracleProvider) public providers; // id → provider
    bytes32[]                          public providerIds;

    bytes32 public activeProviderId;
    bytes32 public standbyProviderId;

    uint256 public currentCycle;

    // ─── Events ──────────────────────────────────────────────────────────────

    event ProviderRegistered(bytes32 indexed id, string name, address endpoint);
    event ProviderRotated(bytes32 indexed newActive, bytes32 indexed newStandby, uint256 cycle);
    event ScoreAdjusted(bytes32 indexed id, uint256 before, uint256 after_, string reason);
    event ProviderSuspended(bytes32 indexed id, uint256 score);
    event ProviderEliminated(bytes32 indexed id);
    event StandbyTookControl(bytes32 indexed standbyId, uint256 timestamp);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        currentCycle = 1;
    }

    // ─── Registration ─────────────────────────────────────────────────────────

    /// @notice Registra un nuevo proveedor de oráculo
    function registerProvider(
        bytes32        id,
        string calldata name,
        address        endpoint,
        uint256        initialScore
    ) external onlyRole(GOVERNANCE_ROLE) {
        require(!providers[id].exists, "OracleRegistry: already exists");
        require(initialScore <= OracleMath.MAX_SCORE, "OracleRegistry: invalid score");

        providers[id] = OracleProvider({
            endpoint:       endpoint,
            name:           name,
            score:          initialScore,
            lastActiveAt:   0,
            lastUpdateAt:   block.timestamp,
            cyclesWaiting:  0,
            totalConfirmed: 0,
            totalRefuted:   0,
            totalStale:     0,
            status:         ProviderStatus.INACTIVE,
            exists:         true
        });

        providerIds.push(id);
        emit ProviderRegistered(id, name, endpoint);
    }

    // ─── Rotation ─────────────────────────────────────────────────────────────

    /// @notice Ejecuta la rotación cíclica de proveedores
    /// @dev Llamado por OracleScheduler al inicio de cada ciclo
    function rotateCycle() external onlyRole(SCHEDULER_ROLE) {
        // El activo anterior pasa a espera y acumula ciclo de enfriamiento
        if (activeProviderId != bytes32(0)) {
            providers[activeProviderId].status = ProviderStatus.INACTIVE;
            providers[activeProviderId].cyclesWaiting = 0; // reset — acaba de estar activo
        }

        // El standby anterior incrementa su ciclo de espera
        if (standbyProviderId != bytes32(0)) {
            providers[standbyProviderId].status = ProviderStatus.INACTIVE;
            providers[standbyProviderId].cyclesWaiting++;
        }

        // Incrementar ciclos de espera para todos los inactivos
        for (uint256 i = 0; i < providerIds.length; i++) {
            bytes32 pid = providerIds[i];
            if (providers[pid].status == ProviderStatus.INACTIVE &&
                pid != activeProviderId &&
                pid != standbyProviderId) {
                providers[pid].cyclesWaiting++;

                // Aplicar decay de inactividad
                uint256 inactiveTime = block.timestamp - providers[pid].lastActiveAt;
                providers[pid].score = OracleMath.applyInactivityDecay(
                    providers[pid].score,
                    inactiveTime
                );
            }
        }

        // Seleccionar nuevo activo y standby por eligibilityScore
        (bytes32 newActive, bytes32 newStandby) = _selectNextProviders();

        providers[newActive].status       = ProviderStatus.ACTIVE;
        providers[newActive].lastActiveAt = block.timestamp;
        providers[newActive].cyclesWaiting = 0;

        providers[newStandby].status = ProviderStatus.STANDBY;

        activeProviderId  = newActive;
        standbyProviderId = newStandby;
        currentCycle++;

        emit ProviderRotated(newActive, newStandby, currentCycle);
    }

    /// @notice Transfiere el control al standby si el activo produce datos STALE > 24h
    function activateStandby() external onlyRole(SCHEDULER_ROLE) {
        require(standbyProviderId != bytes32(0), "OracleRegistry: no standby");

        bytes32 oldActive = activeProviderId;
        providers[oldActive].status = ProviderStatus.SUSPENDED;
        // Penalización por forzar activación de standby
        _adjustScore(oldActive, OracleMath.SCORE_REFUTED, "Forced standby activation");

        providers[standbyProviderId].status       = ProviderStatus.ACTIVE;
        providers[standbyProviderId].lastActiveAt = block.timestamp;
        activeProviderId = standbyProviderId;
        standbyProviderId = bytes32(0);

        emit StandbyTookControl(activeProviderId, block.timestamp);
    }

    // ─── Score Management ─────────────────────────────────────────────────────

    /// @notice Ajusta el score de un proveedor tras un evento verificado
    function adjustScore(
        bytes32        id,
        int256         delta,
        string calldata reason
    ) external onlyRole(DISPUTE_ROLE) {
        require(providers[id].exists, "OracleRegistry: unknown provider");
        _adjustScore(id, delta, reason);
    }

    function _adjustScore(
        bytes32        id,
        int256         delta,
        string memory  reason
    ) internal {
        uint256 before = providers[id].score;
        providers[id].score = OracleMath.adjustScore(before, delta);

        emit ScoreAdjusted(id, before, providers[id].score, reason);

        // Verificar umbrales de suspensión y eliminación
        if (providers[id].score < OracleMath.MIN_SCORE) {
            providers[id].status = ProviderStatus.ELIMINATED;
            emit ProviderEliminated(id);
        } else if (providers[id].score < OracleMath.SUSPEND_SCORE) {
            providers[id].status = ProviderStatus.SUSPENDED;
            emit ProviderSuspended(id, providers[id].score);
        }
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @notice Selecciona el proveedor con mayor eligibilityScore entre los elegibles
    /// @dev Elegible = existe + no suspendido + no eliminado + no fue activo el ciclo anterior
    function _selectNextProviders()
        internal view
        returns (bytes32 bestActive, bytes32 bestStandby)
    {
        uint256 bestActiveScore  = 0;
        uint256 bestStandbyScore = 0;

        for (uint256 i = 0; i < providerIds.length; i++) {
            bytes32 pid = providerIds[i];
            OracleProvider memory p = providers[pid];

            // No elegible si fue activo el ciclo anterior, suspendido o eliminado
            if (pid == activeProviderId) continue;
            if (p.status == ProviderStatus.SUSPENDED) continue;
            if (p.status == ProviderStatus.ELIMINATED) continue;
            if (!p.exists) continue;

            uint256 eligibility = OracleMath.eligibilityScore(p.score, p.cyclesWaiting);

            if (eligibility > bestActiveScore) {
                bestStandby      = bestActive;
                bestStandbyScore = bestActiveScore;
                bestActive       = pid;
                bestActiveScore  = eligibility;
            } else if (eligibility > bestStandbyScore) {
                bestStandby      = pid;
                bestStandbyScore = eligibility;
            }
        }

        require(bestActive != bytes32(0), "OracleRegistry: no eligible providers");
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    function getActiveProvider() external view returns (OracleProvider memory) {
        return providers[activeProviderId];
    }

    function getStandbyProvider() external view returns (OracleProvider memory) {
        return providers[standbyProviderId];
    }

    function getProvider(bytes32 id) external view returns (OracleProvider memory) {
        return providers[id];
    }

    function getAllProviderIds() external view returns (bytes32[] memory) {
        return providerIds;
    }
}
```

---

### OracleRouter.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./OracleRegistry.sol";

/// @title OracleRouter
/// @notice Punto único de consulta de datos de oráculo para todos los módulos internos.
///         Los módulos nunca saben qué proveedor está activo — solo consultan al Router.
///         Gestiona TTL, flags STALE y DISPUTED por tipo de dato.
contract OracleRouter is AccessControl {

    bytes32 public constant WRITER_ROLE     = keccak256("WRITER_ROLE");   // proveedores autorizados
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    OracleRegistry public registry;

    // ─── Structs ─────────────────────────────────────────────────────────────

    enum DataStatus { FRESH, STALE, DISPUTED, FROZEN }

    struct OracleData {
        bytes    value;         // dato serializado (ABI encoded)
        uint256  timestamp;
        uint256  ttl;           // segundos antes de marcarse STALE
        bytes32  providerId;    // quién lo publicó
        DataStatus status;
    }

    // ─── State ───────────────────────────────────────────────────────────────

    // dataKey → OracleData
    mapping(bytes32 => OracleData) public latestData;

    // TTL por defecto por tipo de dato (en segundos)
    mapping(bytes32 => uint256) public defaultTTL;

    // ─── Events ──────────────────────────────────────────────────────────────

    event DataPublished(bytes32 indexed dataKey, bytes32 indexed providerId, uint256 timestamp);
    event DataMarkedStale(bytes32 indexed dataKey, uint256 age);
    event DataFrozen(bytes32 indexed dataKey);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address admin, address _registry) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        registry = OracleRegistry(_registry);
    }

    // ─── Write ────────────────────────────────────────────────────────────────

    /// @notice El proveedor activo publica un dato
    /// @param dataKey Identificador del tipo de dato (e.g. keccak256("TREASURY_DRAIN"))
    /// @param value Dato codificado en ABI
    function publishData(bytes32 dataKey, bytes calldata value)
        external onlyRole(WRITER_ROLE)
    {
        OracleRegistry.OracleProvider memory active = registry.getActiveProvider();
        require(active.endpoint == msg.sender, "OracleRouter: not active provider");

        uint256 ttl = defaultTTL[dataKey] > 0 ? defaultTTL[dataKey] : 6 hours;

        latestData[dataKey] = OracleData({
            value:      value,
            timestamp:  block.timestamp,
            ttl:        ttl,
            providerId: registry.activeProviderId(),
            status:     DataStatus.FRESH
        });

        emit DataPublished(dataKey, registry.activeProviderId(), block.timestamp);
    }

    // ─── Read ─────────────────────────────────────────────────────────────────

    /// @notice Consulta un dato con verificación de freshness
    /// @param dataKey Identificador del tipo de dato
    /// @return value Dato serializado
    /// @return status Estado del dato (FRESH, STALE, DISPUTED, FROZEN)
    function getLatestData(bytes32 dataKey)
        external view
        returns (bytes memory value, DataStatus status)
    {
        OracleData memory d = latestData[dataKey];

        if (d.timestamp == 0) {
            return (bytes(""), DataStatus.STALE);
        }

        // Calcular status actual
        DataStatus currentStatus = d.status;
        if (currentStatus == DataStatus.FRESH) {
            if (block.timestamp > d.timestamp + d.ttl) {
                currentStatus = DataStatus.STALE;
            }
        }

        return (d.value, currentStatus);
    }

    /// @notice Consulta un uint256 directamente (helper para datos numéricos)
    function getUint256(bytes32 dataKey)
        external view
        returns (uint256 value, DataStatus status)
    {
        (bytes memory raw, DataStatus s) = this.getLatestData(dataKey);
        if (raw.length == 0) return (0, s);
        value = abi.decode(raw, (uint256));
        status = s;
    }

    // ─── Status Management ────────────────────────────────────────────────────

    /// @notice Marca un dato como DISPUTED (llamado por OracleDispute)
    function freezeData(bytes32 dataKey)
        external onlyRole(GOVERNANCE_ROLE)
    {
        latestData[dataKey].status = DataStatus.FROZEN;
        emit DataFrozen(dataKey);
    }

    /// @notice Actualiza un dato tras resolución de disputa
    function resolveData(bytes32 dataKey, bytes calldata newValue)
        external onlyRole(GOVERNANCE_ROLE)
    {
        latestData[dataKey].value     = newValue;
        latestData[dataKey].status    = DataStatus.FRESH;
        latestData[dataKey].timestamp = block.timestamp;
    }

    // ─── Config ───────────────────────────────────────────────────────────────

    /// @notice Configura el TTL por defecto para un tipo de dato
    function setDefaultTTL(bytes32 dataKey, uint256 ttlSeconds)
        external onlyRole(GOVERNANCE_ROLE)
    {
        defaultTTL[dataKey] = ttlSeconds;
    }
}
```

---

## Relación con otros módulos

```txt
FMD-DAO
├── OracleLayer  ◄── este módulo
│     ├── OracleRegistry   — quién puede ser oráculo y con qué score
│     ├── OracleRouter     — punto único de consulta para módulos internos
│     ├── OracleScheduler  — cuándo y cómo rotan los proveedores
│     └── OracleDispute    — qué pasa cuando un dato es disputado
│
├── Sistema Inmunológico
│     └── consume datos del Router (drenaje de tesorería, desviación de oráculos)
│         si Router devuelve STALE → +2 al Threat Score automáticamente
│
├── Ruido Estabilizador
│     └── consume VRF del Router
│         el proveedor VRF rota igual que el resto
│
├── GranularReputation
│     └── OracleRegistry tiene su propio score reputacional
│         con el mismo mecanismo de decay que GranularReputation
│
├── Gobernanza Bicameral
│     └── C1 resuelve disputas de oráculo
│         El Ritual Trimestral incluye revisión del registro de proveedores
│
└── HumanLayer
      └── Los datos de Proof of Understanding pasan por oráculos de Nivel 1
          (consenso interno C1, no proveedor externo)
```

---

## El invariante del OracleLayer

```txt
Ningún proveedor activo dos ciclos consecutivos.
Ningún dato válido sin TTL.
Ningún oráculo sin score decayente.
Ningún módulo con acceso directo al proveedor — solo al Router.
```

> La dictadura del oráculo se evita igual que cualquier otra dictadura:
> rotación obligatoria, memoria finita, y que el poder
> nunca fluya sin dejar rastro.

---

## Licencia

MIT License · Ernesto Cisneros Cino

---

*Parte del proyecto [DAO de Memoria Finita (FMD-DAO)](https://github.com/cisnerosmusic/DAO_de_Memoria_Finita_-FMD-DAO-)*

*"Quien controla el oráculo, controla el sistema. Por eso nadie lo controla dos veces seguidas."*


