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

