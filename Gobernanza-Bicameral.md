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
