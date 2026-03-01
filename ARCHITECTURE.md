# ARCHITECTURE.md
### Mapa completo de la arquitectura FMD-DAO
#### DAO de Memoria Finita · Ernesto Cisneros Cino

---

## Índice

- [Principio unificador](#principio-unificador)
- [Vista general del sistema](#vista-general-del-sistema)
- [Capas de la arquitectura](#capas-de-la-arquitectura)
- [Contratos: mapa completo](#contratos-mapa-completo)
- [Flujo de una propuesta](#flujo-de-una-propuesta)
- [Flujo del Ritual Trimestral](#flujo-del-ritual-trimestral)
- [Flujo de crisis](#flujo-de-crisis)
- [Flujo de oráculo](#flujo-de-oráculo)
- [Relaciones entre módulos](#relaciones-entre-módulos)
- [Reglas de diseño invariantes](#reglas-de-diseño-invariantes)
- [Stack técnico](#stack-técnico)
- [Despliegue](#despliegue)
- [Observabilidad](#observabilidad)

---

## Principio unificador

```
R = τ × Ω
1 < R < 3   →   Valle de Resiliencia
```

Todo el sistema existe para mantener R dentro del Valle. No como objetivo abstracto, sino como consecuencia de sus mecanismos concretos:

- `τ` (tau) es la memoria del sistema: cuánto tiempo recuerda sus decisiones antes de que decaigan.
- `Ω` (omega) es la frecuencia de sus ciclos: con qué regularidad se renueva.
- R demasiado bajo → amnesia. R demasiado alto → rigidez. Ambos colapsan.

Cada contrato, cada parámetro, cada mecanismo de decay o rotación sirve a esta ecuación.

---

## Vista general del sistema

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           FMD-DAO                                       │
│                                                                         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────────┐ │
│  │   C2        │    │   C1        │    │   OracleLayer               │ │
│  │  (Commons)  │───▶│  (Experts)  │    │  Registry · Router          │ │
│  │  propuestas │    │  validación │    │  Dispute · Scheduler        │ │
│  └──────┬──────┘    └──────┬──────┘    └──────────────┬──────────────┘ │
│         │                  │                           │                │
│         ▼                  ▼                           ▼                │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                      FMDDAOCore                                  │   │
│  │   GovernanceParams · ReputationModule · Ritual Trimestral        │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│         │                  │                           │                │
│         ▼                  ▼                           ▼                │
│  ┌──────────────┐  ┌───────────────────┐  ┌─────────────────────────┐  │
│  │ ImmunityCore │  │   HumanLayer      │  │  Observabilidad         │  │
│  │ ThreatOracle │  │ Oscillator · PoU  │  │  Subgraph · Dune        │  │
│  │ Inflammation │  │ Coopetition       │  │  Grafana · Alerts       │  │
│  └──────────────┘  │ GranularRep       │  └─────────────────────────┘  │
│                    │ SoulboundBadges   │                               │
│                    └───────────────────┘                               │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Capas de la arquitectura

El sistema tiene cinco capas. Cada capa solo se comunica con la inmediatamente adyacente. Ningún contrato de una capa accede directamente a contratos de dos capas de distancia.

```
CAPA 5 — OBSERVABILIDAD
  Subgraph (The Graph) · Dune Analytics · Grafana · Alertas
  Lee eventos on-chain. No escribe. No toma decisiones.

CAPA 4 — INTERFACES HUMANAS
  Frontend DAO · Dashboard de reputación · Simulador de propuestas
  Consume el subgraph y el OracleRouter para mostrar estado.

CAPA 3 — MÓDULOS ESPECIALIZADOS
  HumanLayer:    IdeologicalOscillator · ProofOfUnderstanding
                 CoopetitionEngine · GranularReputation · SoulboundBadges
  ImmunityCore:  ImmunityCore · ThreatOracle · InflammationController
  OracleLayer:   OracleRegistry · OracleRouter · OracleDispute · OracleScheduler

CAPA 2 — NÚCLEO
  FMDDAOCore · ReputationModule · GovernanceParams

CAPA 1 — MATEMÁTICAS Y PRIMITIVOS
  OracleMath · HumanMath · ThreatMath
  Bibliotecas puras (sin estado). Solo cálculo.
```

---

## Contratos: mapa completo

### Core

| Contrato | Responsabilidad | Lee de | Es leído por |
|---|---|---|---|
| `GovernanceParams` | Repositorio central de τ, Ω, λ, quórums, timelocks | — | Todos los módulos |
| `ReputationModule` | Decay exponencial de reputación C1, Gini, elegibilidad | `GovernanceParams` | `FMDDAOCore`, `ImmunityCore` |
| `FMDDAOCore` | Orquestador: propuestas, Ritual Trimestral, emergencias | `GovernanceParams`, `ReputationModule` | Interfaces externas |

### HumanLayer

| Contrato | Responsabilidad | Lee de | Es leído por |
|---|---|---|---|
| `IdeologicalOscillator` | Rigidez ideológica, peso de voto ajustado | — | `CoopetitionEngine`, `GranularReputation` |
| `ProofOfUnderstanding` | Verificación de comprensión de argumento opuesto | — | `CoopetitionEngine` |
| `GranularReputation` | Vector reputacional 5D con decay diferenciado | `IdeologicalOscillator`, `ProofOfUnderstanding` | `CoopetitionEngine`, `ImmunityCore`, `SoulboundBadges` |
| `CoopetitionEngine` | Voto cuadrático, créditos, bonus C1 acoplado | `ImmunityCore` (crisis), `GranularReputation` | `FMDDAOCore` |
| `SoulboundBadges` | NFT no transferibles por logros verificados | `GranularReputation` | Interfaces |

### ImmunityCore

| Contrato | Responsabilidad | Lee de | Es leído por |
|---|---|---|---|
| `ImmunityCore` | Threat Score, clasificación de severidad y velocidad | `OracleRouter`, `ReputationModule` | `FMDDAOCore`, `CoopetitionEngine`, `OracleScheduler` |
| `ThreatOracle` | Métricas de amenaza (participación, Gini, drenaje...) | `OracleRouter` | `ImmunityCore` |
| `InflammationController` | Respuesta graduada: parámetros ajustados por severidad | `ImmunityCore` | `GovernanceParams` (propone cambios) |

### OracleLayer

| Contrato | Responsabilidad | Lee de | Es leído por |
|---|---|---|---|
| `OracleRegistry` | Registro, score reputacional y estado de proveedores | `OracleMath` | `OracleRouter`, `OracleScheduler`, `OracleDispute` |
| `OracleRouter` | Punto único de consulta con TTL y flags STALE/DISPUTED | `OracleRegistry` | Todos los módulos que necesitan datos externos |
| `OracleDispute` | Apertura, votación C1 y resolución de disputas | `OracleRegistry`, `OracleRouter` | `OracleScheduler` |
| `OracleScheduler` | Rotación cíclica, confirmación automática, STALE takeover | `OracleRegistry`, `OracleDispute`, `OracleRouter` | `ImmunityCore` (alerta doble STALE) |

### Libraries

| Biblioteca | Funciones | Usada por |
|---|---|---|
| `OracleMath` | Decay de score, eligibilityScore, ajuste de score | `OracleRegistry` |
| `HumanMath` | Rigidez, jointPerformanceScore, decay de créditos | `CoopetitionEngine`, `GranularReputation` |
| `ThreatMath` | Threat Score, clasificación velocidad, Gini | `ImmunityCore`, `ThreatOracle` |

---

## Flujo de una propuesta

```
 MIEMBRO C2
     │
     ▼
 createProposal()                    FMDDAOCore
     │  título · descriptionHash(IPFS) · callData · target · tipo
     │
     ▼
 voteProposal()                      C2 delibera
     │  cualquier miembro C2 · máx 1 voto por propuesta
     │
     ▼
 escalateToC1()                      si aprobación C2 ≥ quórum
     │  quórum normal: 10% · constitutional: 75% · emergencia: 40%
     │
     ▼
 c1Vote()                            C1 valida técnicamente
     │  requiere reputación activa ≥ RENEWAL_THRESHOLD
     │  peso del voto ajustado por IdeologicalOscillator + PoU
     │
     ▼
 ProposalApproved                    si aprobación C1 ≥ quórum
     │  inicia timelock
     │  normal: 2 días · constitutional: 14 días
     │
     ▼
 executeProposal()                   tras timelock · cualquiera puede llamar
     │  llamada on-chain al contrato target con callData
     │  resultado registrado en evento ProposalExecuted
     │
     ▼
 ProposalExecuted ✓
```

---

## Flujo del Ritual Trimestral

```
 triggerRitual()                     cualquier miembro tras ~90 días
     │
     ▼
 ReputationModule.updateDecayBatch() aplica decay a todos los expertos C1
     │  solo escribe si drift > 1%
     │  remoción automática si rep < RENEWAL_THRESHOLD
     │
     ▼
 Verificar R = τ × Ω               ¿estamos en el Valle?
     │  1 < R < 3  →  OK
     │  R ≤ 1      →  amnesia → notificar ImmunityCore
     │  R ≥ 3      →  rigidez → notificar ImmunityCore
     │
     ▼
 Registrar RitualRecord             experts removidos · R · inValley · ciclo
     │
     ▼
 RepModule.advanceCycle()           avanza contador de ciclo
 currentCycle++
 lastRitualAt = now
     │
     ▼
 RitualExecuted (evento)
```

---

## Flujo de crisis

```
 ThreatOracle detecta métricas anómalas
     │  participación colapsa · Gini > 0.8 · drenaje > 30%...
     │
     ▼
 ImmunityCore.calculateThreatScore()
     │  0–3  → VERDE   (normal)
     │  4–6  → AMARILLO (alerta)
     │  7–9  → NARANJA  (crisis moderada)
     │  10–16 → ROJO    (crisis aguda)
     │
     ▼
 Clasificación de velocidad (dS/dt)
     │  < 2  → LOGARÍTMICA  (democracia plena)
     │  2–5  → LINEAL       (respuesta balanceada)
     │  ≥ 5  → EXPONENCIAL  (expertos al 60%, oracle 30%, C2 10%)
     │
     ▼
 InflammationController ajusta parámetros
     │  quórum sube hasta 40%
     │  timelock sube hasta 14 días
     │  tau_DAO baja a 15 días (memoria más corta = mayor reactividad)
     │
     ▼
 CoopetitionEngine.setCrisisState(true)
     │  intensidad máxima de voto: 3 (no 5)
     │  penalizaciones de reputación × 1.5
     │
     ▼
 OracleScheduler.setCrisisState(true)
     │  ventana de disputa: 24h (no 48h)
     │
     ▼
 MAX_INFLAMMATION_DAYS = 30
     │  si la crisis dura más de 30 días → revisión forzada por C1
     │
     ▼
 Recuperación: parámetros vuelven exponencialmente al estado normal
```

---

## Flujo de oráculo

```
 Proveedor ACTIVO publica dato
     │  OracleRouter.publishData(dataKey, value)
     │  dato recibe TTL (por defecto 6h para datos críticos)
     │
     ▼
 Ventana de disputa abierta (48h / 24h en crisis)
     │
     ├─ Sin disputa → OracleScheduler.confirmExpiredWindows()
     │                proveedor +100 BPS en OracleRegistry
     │
     └─ Con disputa → OracleDispute.openDispute(dataKey, altValue, source)
                          │  disputante deposita 5 créditos
                          │  dato congelado en Router
                          │
                          ▼
                      C1 delibera (48h adicionales)
                      castC1Vote() × mínimo 3 votos
                          │
                          ├─ CONFIRMED → dato original restaurado
                          │              proveedor +100 BPS
                          │              depósito perdido
                          │
                          ├─ REFUTED   → dato alternativo publicado
                          │              proveedor -300 BPS
                          │              depósito devuelto
                          │
                          └─ DRAW      → dato congelado indefinido
                                         ambos -50 BPS
                                         sistema usa último dato válido

 Si TTL vence sin actualización:
     dato marcado STALE
     proveedor -50 BPS/hora
     si STALE > 24h → STANDBY toma el control
     si ambos STALE → ImmunityCore recibe alerta +2 Threat Score

 Rotación al inicio de cada ciclo:
     ningún proveedor activo dos ciclos consecutivos
     eligibilityScore = score + bonus_por_espera
     el que tiene mayor eligibilityScore se convierte en ACTIVO
```

---

## Relaciones entre módulos

```
Regla fundamental:
  Los módulos leen de otros módulos.
  Los módulos NO escriben en otros módulos.
  Solo FMDDAOCore puede llamar funciones de escritura en módulos
  mediante coordinación explícita.

Diagrama de dependencias de lectura:

  GovernanceParams ◄──── todos los módulos
  ReputationModule ◄──── FMDDAOCore · ImmunityCore
  OracleRouter     ◄──── ImmunityCore · ThreatOracle · todos los que
                         necesitan datos externos
  ImmunityCore     ◄──── FMDDAOCore · CoopetitionEngine · OracleScheduler
  GranularReputation ◄── CoopetitionEngine · SoulboundBadges · ImmunityCore

Comunicación inter-módulo para acciones (escritura):
  FMDDAOCore → ReputationModule.updateDecayBatch()   (solo en Ritual)
  FMDDAOCore → ReputationModule.advanceCycle()       (solo en Ritual)
  ImmunityCore → GovernanceParams (propone cambios, no los ejecuta)
  OracleScheduler → OracleRegistry.rotateCycle()
  OracleScheduler → OracleRegistry.activateStandby()
  OracleDispute → OracleRegistry.adjustScore()
  OracleDispute → OracleRouter.freezeData() / resolveData()

Llamadas de bajo nivel (sin import directo, evitan dependencia circular):
  FMDDAOCore → ImmunityCore.receiveResilienceAlert(uint256 R)
  OracleScheduler → ImmunityCore.receiveDoubleStaleAlert(bytes32 dataKey)
```

---

## Reglas de diseño invariantes

Estas reglas no pueden ser modificadas por gobernanza ordinaria. Son los invariantes del sistema.

```
INVARIANTE 1 — Ninguna ejecución sin traza
  Todo cambio de estado relevante emite un evento.
  Todo evento incluye ciclo, timestamp y actor.
  El historial on-chain es inmutable.

INVARIANTE 2 — Ningún cambio de regla sin delay
  GovernanceParams: toda modificación tiene timelock propio.
  El timelock mínimo es 2 días. No hay excepciones.
  Las propuestas constitucionales tienen timelock de 14 días.

INVARIANTE 3 — Ninguna autoridad sin exposición
  C1: reputación pública, decayente, auditable.
  Oráculos: score público, rotación obligatoria, historial on-chain.
  FMDDAOCore: toda acción es un evento con actor explícito.

INVARIANTE 4 — Ningún oráculo permanente
  Ningún proveedor puede ser activo dos ciclos consecutivos.
  Todo proveedor inactivo recibe decay de relevancia.
  El standby toma el control automáticamente ante STALE > 24h.

INVARIANTE 5 — El tiempo es el único árbitro sin rol
  triggerRitual() puede ser llamado por cualquiera.
  triggerRotation() puede ser llamado por cualquiera.
  executeProposal() puede ser llamado por cualquiera.
  El tiempo es el único requisito — no el rol.

INVARIANTE 6 — La memoria tiene un límite máximo de 30 días de crisis
  MAX_INFLAMMATION_DAYS = 30
  Ninguna crisis puede extenderse más de 30 días sin revisión forzada de C1.
  El sistema no puede quedarse permanentemente en modo de emergencia.
```

---

## Stack técnico

```
Contratos:
  Solidity ^0.8.20
  OpenZeppelin v5.x (AccessControl, ReentrancyGuard, Pausable, ERC721)
  Red: Arbitrum One u Optimism (L2 Ethereum)

Indexación:
  The Graph Protocol — schema.graphql
  Subgraph deployado en The Graph Studio

Analytics:
  Dune Analytics — consultas SQL sobre eventos indexados
  Grafana — dashboard de KPIs en tiempo real
  Alertas: Tenderly o Defender (Threat Score > 6 → alerta inmediata)

Testing:
  Hardhat + Ethers v6
  @nomicfoundation/hardhat-network-helpers (time travel)
  Chai assertions
  Cobertura con hardhat-coverage

Automatización (keepers):
  Chainlink Automation o Gelato Network
  Funciones: confirmExpiredWindows · checkStaleData · applyCreditsDecay
  Fallback: cualquier miembro puede llamar estas funciones manualmente

Identidad:
  Sismo Connect o Worldcoin — verificación de unicidad
  GitPOAP — credenciales de contribución técnica
  ZK credentials — privacidad en Proof of Understanding

Estimación de coste anual (L2):
  OracleLayer + Core:  ~$800–1,200
  HumanLayer:          ~$600–900
  ImmunityCore:        ~$300–500
  Total estimado:      ~$1,700–2,600/año
```

---

## Despliegue

### Orden de despliegue (dependencias)

```
1. OracleMath.sol          (biblioteca — sin dependencias)
2. HumanMath.sol           (biblioteca — sin dependencias)
3. ThreatMath.sol          (biblioteca — sin dependencias)
4. GovernanceParams.sol    (solo admin)
5. ReputationModule.sol    (necesita GovernanceParams)
6. OracleRegistry.sol      (sin dependencias de otros contratos del sistema)
7. OracleRouter.sol        (necesita OracleRegistry)
8. OracleDispute.sol       (necesita OracleRegistry + OracleRouter)
9. OracleScheduler.sol     (necesita OracleRegistry + OracleDispute + OracleRouter)
10. ImmunityCore.sol       (necesita OracleRouter + ReputationModule)
11. IdeologicalOscillator.sol
12. ProofOfUnderstanding.sol
13. GranularReputation.sol
14. CoopetitionEngine.sol  (necesita GovernanceParams)
15. SoulboundBadges.sol    (necesita GranularReputation)
16. FMDDAOCore.sol         (necesita GovernanceParams + ReputationModule +
                            ImmunityCore + OracleRouter)

Post-despliegue:
  Conceder roles cruzados entre contratos
  Registrar dataKeys críticos en OracleScheduler
  Registrar primeros proveedores de oráculo en OracleRegistry
  Ejecutar primera rotación: OracleRegistry.rotateCycle()
  Añadir primeros expertos C1: ReputationModule.addExpert()
```

---

## Observabilidad

### KPIs del sistema

```
Resiliencia:
  R = τ × Ω  (objetivo: 1 < R < 3)
  Gini reputacional C1  (objetivo: < 0.5)
  Tasa de renovación de expertos por ciclo

Gobernanza:
  Tasa de propuestas aprobadas / rechazadas / canceladas
  Tiempo medio C2→C1→ejecución
  Participación C2 por ciclo

Inmunidad:
  Threat Score medio por ciclo
  Ciclos en ROJO / NARANJA / AMARILLO / VERDE
  Duración media de episodios de crisis

Oráculos:
  Score medio de proveedores activos
  Tasa de disputas / confirmaciones automáticas
  Eventos STALE por ciclo

HumanLayer:
  Rigidez media por cámara
  Distribución de badges
  Créditos en circulación vs. gastados
```

### Alertas críticas

```
CRÍTICO  (acción inmediata):
  Threat Score ≥ 10
  R < 0.5 o R > 5 (fuera del Valle por factor 2)
  Doble STALE en datos críticos
  Gini C1 > 0.8

ALERTA   (revisión en 24h):
  Threat Score 7–9
  R < 1 o R > 3
  Proveedor de oráculo suspendido
  Gini C1 > 0.6

INFO     (ciclo siguiente):
  Ritual Trimestral ejecutado
  Expertos removidos por decay
  Rotación de oráculo completada
  Propuesta constitucional aprobada
```

---

## Licencia

MIT License · Ernesto Cisneros Cino

*DAO de Memoria Finita (FMD-DAO)*
*https://github.com/cisnerosmusic/DAO_de_Memoria_Finita_-FMD-DAO-*

---

> *"No le pedimos a los ríos que fluyan cuesta arriba. Construimos canales."*
