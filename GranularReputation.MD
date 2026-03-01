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
