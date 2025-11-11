graph TD
  subgraph Comunidad
    U[Usuarios / Proponentes (C2)]
  end

  subgraph Gobernanza Bicameral
    C2[Cámara de los Comunes\n(Propuestas, Señales, Legitimidad)]
    C1[Cámara de Expertos\n(Validación técnica, Auditoría)]
  end

  subgraph Capa On-chain
    SC[Smart Contracts\n(FMD-DAO Core)]
    REP[Reputación C1\n(Decay exponencial)]
    GOV[Parámetros de Gobierno\n(τ, Ω, umbrales)]
  end

  subgraph Oráculos / Servicios
    ORA[Oracle de Sincronización\n(keepers/cron)]
    ZK[Credenciales/Identidad\nSismo / GitPOAP / ZK]
    IDX[Indexers / Subgraph]
  end

  subgraph Observabilidad
    DUNE[Dune / Subgraph]
    GRAF[Grafana / Dashboards]
  end

  U -->|Propuestas / Votos| C2
  C2 -->|Propuestas escaladas| C1
  C1 -->|Aprobación técnica / Ajustes| SC

  SC --> REP
  SC --> GOV
  ORA -->|tick Δt| SC
  ZK --> SC
  SC --> IDX
  IDX --> DUNE
  DUNE --> GRAF

  sequenceDiagram
  participant User as Proponente (C2)
  participant C2 as Cámara de Comunes
  participant C1 as Cámara de Expertos
  participant SC as Smart Contracts
  participant ORA as Oracle/Keepers

  User->>C2: Crear propuesta (metadata + credenciales)
  C2->>C2: Deliberación / Señales / Quórum
  C2->>C1: Escalar propuesta (payload técnico)
  C1->>C1: Revisión técnica / Auditoría / Pareo ciego
  C1->>SC: Veredicto (aprobación/ajuste/rechazo)
  ORA->>SC: Commits periódicos (parámetros/decay)
  SC-->>User: Estado y resultados on-chain

  flowchart LR
  T0[Inicio de ciclo] --> U1[Actividad C1/C2]
  U1 --> METRIC[Medición continua:\nτ (memoria), Ω (frecuencia)]
  METRIC --> RVAL[Calcular R = τ × Ω]
  RVAL --> |R < 1| ALERTA1[Amnesia\n↑ actividad / ↑ expertos]
  RVAL --> |1 ≤ R ≤ 3| OK[En Valle de Resiliencia]
  RVAL --> |R > 3| ALERTA2[Rigidez\n↑ decay / ↑ rotación]

  subgraph Ritual Trimestral (≈ 90 días)
    DECAY[Aplicar Decay a C1\n e inactivar <5%]
    ROT[Rotación/Lotería ponderada\n(límites de mandato)]
    PARAMS[Ajuste de λ, umbrales, quórums]
  end

  OK --> Ritual Trimestral
  ALERTA1 --> Ritual Trimestral
  ALERTA2 --> Ritual Trimestral
  Ritual Trimestral --> T0


classDiagram
  class Expert {
    address id
    uint256 reputation  // 0..10000
    uint256 lastUpdate  // timestamp
    uint256 contributions
    bool active
  }

  class ReputationModule {
    +calculateDecay(rep, dt) uint256
    +updateDecay(addr) void
    +boostReputation(addr, amount, reason) void
    +removeExpert(addr) void
    +getCurrentReputation(addr) view uint256
  }

  class Governance {
    uint256 lambda            // λ * precision
    uint256 renewalThreshold  // e.g. 5%
    uint256 cycleLength       // e.g. 90 days
    +calculateResilienceIndex() view uint256
    +isInResilienceValley() view (bool, uint256)
  }

  Expert <.. ReputationModule
  ReputationModule <.. Governance


graph LR
  SC[Smart Contracts] -->|events/logs| IDX[Indexers/Subgraph]
  IDX --> DUNE[Dune Queries]
  IDX --> WARE[Data Warehouse opcional]
  DUNE --> GRAF[Grafana/Dashboards]

  subgraph KPIs Clave
    KPI1[Distribución de reputación C1]
    KPI2[Tasa de renovación / remoción]
    KPI3[R global, R_C1, R_C2]
    KPI4[Tiempo medio hasta remoción]
    KPI5[Gini reputacional]
    KPI6[Latencia C2→C1→SC]
  end

  DUNE --> KPI1
  DUNE --> KPI2
  DUNE --> KPI3
  DUNE --> KPI4
  DUNE --> KPI5
  DUNE --> KPI6


stateDiagram-v2
  [*] --> Virtualized
  Virtualized: Reputación se calcula "al leer"\n(no escritura continua)

  Virtualized --> WriteOnChange: Al modificar (boost/tx) aplica decay acumulado\n y actualiza estado
  WriteOnChange --> Virtualized

  Virtualized --> BatchKeeper: Keeper/Oracle en lotes\n(solo si drift > umbral)
  BatchKeeper --> Virtualized


mindmap
  root((Seguridad FMD-DAO))
    C1 (Expertos)
      Rotación/lotería ponderada
      Límites de mandato
      Decay exponencial
      Auditoría por pares
    C2 (Comunes)
      Verificación unicidad (ZK/POH)
      Quórums por cohorte temporal
      Anti-brigading
    Parámetros
      Timelock cambios críticos
      Pausa de emergencia (circuit breaker)
      Calibración dinámica de λ, umbrales
    Economía
      No-pay-to-speak
      Recompensas funcionales no monetarias
    Observabilidad
      Tableros públicos de R
      Logs del Ritual trimestral


/contracts
  ├─ FMDDAOCore.sol
  ├─ ReputationModule.sol
  └─ GovernanceParams.sol
/subgraph
  └─ schema.graphql
/docs
  └─ doc.md                # (este archivo)
/dashboards
  ├─ dune.sql
  └─ grafana.json
/test
  └─ *.test.ts
README.md                  # resumen + enlaces a /docs




