# CHANGELOG
### DAO de Memoria Finita · FMD-DAO
#### Formato: [Keep a Changelog](https://keepachangelog.com/) · Versionado: [SemVer](https://semver.org/)

---

Todos los cambios relevantes de este proyecto están documentados aquí.
Los cambios on-chain (propuestas ejecutadas) se marcan con el prefijo `[ON-CHAIN]`.

---

## [Unreleased]

### Added
- `InflammationController.sol`: recuperación gradual en `RECOVERY_CYCLES = 3` pasos
  con interpolación lineal hacia valores base
- `ThreatOracle.sol`: evaluación periódica de métricas con historial de evaluaciones
- `SoulboundBadges.sol`: 11 tipos de badge en 4 categorías — `_update()` bloquea
  transferencias entre cuentas, solo mint y burn permitidos
- `ImmunityCore.sol`: circuit breaker automático a los 30 días de inflamación
  continua, requiere `forceResolveInflammation()` por C1 para continuar
- `ThreatMath.sol`: biblioteca pura con cálculo de Gini, umbrales de 3σ,
  pesos de cámara y ajuste de tau por severidad
- `HumanMath.sol`: biblioteca pura con decay por dimensión, rigidez ideológica
  con cambios justificados a peso 0.5, joint performance score y PoU multipliers
- `fmddao.test.ts`: 30 tests en 9 suites — cobertura de Core, HumanLayer,
  OracleLayer y ciclo completo de integración
- `schema.graphql`: 28 entidades para The Graph — `SystemSummary` singleton,
  `@derivedFrom` en todos los arrays inversos
- `ARCHITECTURE.md`: flujos completos de propuesta, ritual, crisis y oráculo;
  orden de despliegue de 16 contratos; invariantes absolutos; KPIs y alertas
- `CONTRIBUTING.md`: 4 niveles de contribución, plantilla RFC, estándares de
  código y documentación, proceso de disputa, código de conducta
- `hardhat.config.ts`: `viaIR: true`, `evmVersion: "paris"`, gas reporter,
  redes Arbitrum y Optimism (testnet y mainnet), verificación de contratos
- `package.json`: scripts granularizados por módulo, dependencias fijadas,
  script `ci` con ciclo compile → lint → typecheck → test → coverage
- `fmd_dao_sim.py`: simulación integrada en Python con Plotly — 4 sistemas
  (oráculos, reputación, sistema inmune, oscilador ideológico), 24 ciclos × 30 días

---

## [0.2.0] — 2026-02-28

### Added
- `OracleScheduler.sol`: rotación cíclica con `triggerRotation()` callable por
  cualquiera sin rol; `registerCriticalKey()` para datos con STALE activo;
  notificación a ImmunityCore por doble STALE mediante call de bajo nivel
- `OracleDispute.sol`: ciclo completo de disputa optimista — depósito de 5 créditos,
  ventana 48h (24h en crisis), votos C1 con quórum mínimo 3, resolución
  CONFIRMED / REFUTED / DRAW con ajuste de score del proveedor
- `OracleRouter.sol`: punto único de consulta con TTL configurable por dataKey,
  flags FRESH / STALE / DISPUTED / FROZEN, `freezeData()` y `resolveData()`
  solo accesibles por OracleDispute
- `OracleRegistry.sol`: registro de proveedores con `eligibilityScore = score +
  waitBonus` (máx +3000 BPS), rotación por `rotateCycle()`, suspensión automática
  bajo 3000 BPS, eliminación bajo 1000 BPS
- `OracleMath.sol`: decay de score de oráculo con λ_oracle = λ_base × 0.7;
  cálculo de eligibilityScore; ajuste de score por evento
- `OracleLayer.md`: documentación completa de la arquitectura de 4 niveles
  (on-chain, consenso C1, proveedor externo, VRF), análisis de modos de falla,
  mecanismo de disputa optimista, rotación cíclica anti-dictadura
- `CoopetitionEngine.sol`: créditos de gobernanza con decay, voto cuadrático
  intensidad 1–5, bonus C1 acoplado al joint performance score, intensidad
  máxima reducida a 3 en crisis ROJA
- `GranularReputation.sol`: vector 5D con decay diferenciado por dimensión,
  historial de eventos públicos, cálculo de Gini on-chain, escritura virtualizada

### Changed
- `ReputationModule.sol`: añadida función `calculateGini()` para uso por
  ImmunityCore; `updateDecayBatch()` solo escribe si drift > 1%
- `FMDDAOCore.sol`: `triggerRitual()` y `executeProposal()` ahora callable por
  cualquier cuenta sin rol especial — el tiempo es el único árbitro

---

## [0.1.0] — 2026-01-15

### Added
- `GovernanceParams.sol`: repositorio central de parámetros con timelock por
  parámetro individual (mínimo 2 días, máximo 30 días); 12 parámetros iniciales
  incluyendo TAU_DAO=60, OMEGA=1667, LAMBDA_BPS=1155, CYCLE_DAYS=90
- `ReputationModule.sol`: decay exponencial con serie de Taylor truncada (4 términos);
  remoción automática bajo RENEWAL_THRESHOLD=500 BPS; `isInResilienceValley()`
  para verificación de R = τ × Ω; `advanceCycle()` sincronizado con FMDDAOCore
- `FMDDAOCore.sol`: orquestador bicameral con tres tipos de propuesta
  (STANDARD, CONSTITUTIONAL, EMERGENCY); quórums diferenciados 10% / 75% / 40%;
  Ritual Trimestral con aplicación de decay en lote y verificación del Valle;
  pausa de emergencia via GUARDIAN_ROLE
- `IdeologicalOscillator.sol`: rigidez calculada sobre ventana de 6 votos;
  cambios justificados cuentan como 0.5 (representado ×2 para evitar fracciones);
  peso ajustado = W_base × (1 - 0.30 × rigidez), mínimo 50%
- `ProofOfUnderstanding.sol`: submit de hash IPFS, validación por oracle C1,
  multiplicadores OMITTED=40% / INVALID=60% / VALID=100%; un solo proof por
  propuesta por miembro
- `HumanLayer.md`: documentación completa con fórmulas de rigidez, decay de
  créditos, joint performance score y lógica de badges
- `SoulboundBadges.sol` (borrador): estructura de 11 tipos en 4 categorías;
  soulbound enforcement via override de `_update()`
- `ruido_estabilizador.md`: especificación del módulo de variabilidad controlada
  con VRF y amplitud configurable
- `sistema_inmunologico.md`: especificación del sistema inmunológico con
  Threat Score 0–16, clasificación VERDE/AMARILLO/NARANJA/ROJO,
  velocidades LOGARÍTMICA/LINEAL/EXPONENCIAL y respuesta graduada
- `HumanLayer.md`: blueprint completo del capa humana
- `gobernanza_bicameral.md`: especificación de C1/C2 con diagramas de flujo

### Architecture
- Decisión de arquitectura: módulos especializados con comunicación via
  call de bajo nivel para evitar dependencias circulares
- Decisión de arquitectura: escritura virtualizada (lazy decay) — el decay
  se calcula al leer, solo se escribe cuando hay actualización real
- Decisión de arquitectura: `triggerRitual()` sin rol especial — cualquier
  cuenta puede pagar el gas para mantener el sistema funcionando
- Decisión de arquitectura: OracleLayer con cuatro niveles de datos según
  sensibilidad y frecuencia de actualización

---

## [0.0.1] — 2025-12-01

### Added
- Concepto inicial: DAO de Memoria Finita basada en el Valle de Resiliencia
- Fórmula fundamental: R = τ × Ω, con Valle definido en 1 < R < 3
- Blueprint filosófico: memoria finita como principio estructural,
  no como metáfora — el olvido como mecanismo de renovación
- Arquitectura bicameral inicial: C1 (expertos con reputación decayente)
  y C2 (commons con votación cuadrática)
- Primera especificación del Ritual Trimestral como mecanismo de renovación
  cíclica obligatoria
- Repositorio inicial en GitHub:
  `cisnerosmusic/DAO_de_Memoria_Finita_-FMD-DAO-`

---

## Convenciones de versión

```
MAJOR.MINOR.PATCH

MAJOR: cambio en los invariantes del sistema o en la arquitectura bicameral
MINOR: nuevos contratos o módulos completos
PATCH: correcciones, optimizaciones, mejoras de documentación
```

Los cambios on-chain ejecutados mediante propuestas constitucionales
se registran aquí con el prefijo `[ON-CHAIN]` y el ID de la propuesta.

---

*"No le pedimos a los ríos que fluyan cuesta arriba. Construimos canales."*
