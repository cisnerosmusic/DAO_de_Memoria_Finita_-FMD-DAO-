# CoopetitionEngine
### Motor de coopetición: competencia que requiere colaboración para ganar
#### Módulo del HumanLayer · FMD-DAO · Ernesto Cisneros Cino

---

## ¿Qué es el CoopetitionEngine?

Es el contrato que hace operativo el principio central del HumanLayer: **la forma más eficiente de ganar individualmente requiere contribuir al bien colectivo**.

No lo pide como virtud. Lo hace inevitable como estructura.

El CoopetitionEngine gestiona tres mecanismos interdependientes:

1. **Voto cuadrático por intensidad** - expresar posiciones extremas es costoso, no prohibido.
2. **Incentivos acoplados C1/C2** - parte del beneficio individual depende del rendimiento conjunto de ambas cámaras.
3. **Créditos de gobernanza** - la moneda interna del sistema que fluye entre participación, contribución y voto.

---

## El problema que resuelve

En cualquier sistema de gobernanza con recursos finitos, la competencia sin fricción produce juegos de suma cero: bloqueos, capturas, traición estratégica. Los miembros maximizan su posición individual a costa del sistema.

El CoopetitionEngine introduce dos fricciones calculadas:

**Primera fricción - el coste cuadrático:** votar con intensidad 5 cuesta 25 créditos; votar con intensidad 1 cuesta 1. La posición extrema es posible pero cara. Esto no modera artificialmente las opiniones, hace que el votante elija cuándo vale la pena gastar su intensidad.

**Segunda fricción - el acoplamiento:** parte del incentivo de C1 depende de que C2 funcione bien, y viceversa. Sabotear a la cámara contraria se vuelve autodestructivo.

---

## Créditos de gobernanza

Los créditos no son tokens económicos, no se compran ni se venden. Se generan por participación y se gastan en votos de alta intensidad.

```txt
Generación de créditos:
  Completar Proof of Understanding:    +3 créditos
  Propuesta aprobada:                  +10 créditos
  Contribución a propuesta ajena:      +5 créditos
  Participación en ciclo completo:     +2 créditos

Gasto de créditos:
  Voto intensidad 1:   1 crédito
  Voto intensidad 2:   4 créditos
  Voto intensidad 3:   9 créditos
  Voto intensidad 4:  16 créditos
  Voto intensidad 5:  25 créditos

Los créditos no se acumulan indefinidamente:
  Decay de créditos = mismo λ que la reputación general
  (quien no participa, pierde capacidad de voto intenso)
```

---

## Incentivos acoplados

El incentivo total de un miembro de C1 se calcula como:

```txt
Incentivo_C1(i) = base_C1(i) + bonus * rendimiento_conjunto

donde:

  base_C1(i)          = proporcional a contribuciones verificadas
  rendimiento_conjunto = f(tasa_exito, participacion, R_actual)
  bonus               = parámetro fijo del ciclo (definido en GovernanceParams)
```

El `rendimiento_conjunto` es el mismo valor que calcula `HumanMath.jointPerformanceScore()`  ambas cámaras comparten la misma función de evaluación. Si C2 colapsa en participación, el bonus de C1 cae. Si C1 rechaza propuestas legítimas sistemáticamente, la tasa de éxito baja y el bonus de ambas cámaras se reduce.

---

## Fórmulas clave

```txt
Coste cuadrático de voto:
  cost(intensity) = intensity²

Rendimiento conjunto (normalizado 0–10000 BPS):
  score = (successRate × 4 + participationRate × 3 + rContribution × 3) / 10

  donde rContribution = 10000 si R ∈ [1,3], else 5000

Decay de créditos (misma forma que reputación):
  credits(t) = credits(t0) × e^(−λ × Δt)
```

---

## Estructura del contrato

```
CoopetitionEngine.sol
  ├── GovernanceCredits      struct — balance y timestamp de créditos
  ├── VoteRecord             struct — intensidad, coste, propuesta
  ├── CyclePerformance       struct — métricas del ciclo para bonus
  │
  ├── castVote()             — vota con intensidad, descuenta créditos
  ├── earnCredits()          — acredita participación verificada
  ├── applyCreditsDecay()    — decay periódico llamado por keeper
  ├── recordCycleMetrics()   — registra métricas al cierre de ciclo
  ├── calculateBonus()       — calcula bonus de C1 por ciclo
  └── getEffectiveCredits()  — lectura virtualizada con decay aplicado
```

---

## Notas de integración

```txt
Lee de:
  ResilienceIndex.sol      → R actual para jointPerformanceScore
  ImmunityCore.sol         → en crisis ROJA, intensidad máxima = 3 (no 5)
  IdeologicalOscillator.sol → peso de voto ajustado por rigidez
  ProofOfUnderstanding.sol  → multiplicador de peso por Proof

No escribe en ninguno de los contratos anteriores.

Desplegado en: Arbitrum One u Optimism (L2 Ethereum)
Solidity: ^0.8.20
OpenZeppelin: v5.x
```

---

## Licencia

MIT License · Ernesto Cisneros Cino

*Parte del proyecto [DAO de Memoria Finita (FMD-DAO)](https://github.com/cisnerosmusic/DAO_de_Memoria_Finita_-FMD-DAO-)*

*"El camino de máximo beneficio individual pasa por el éxito colectivo."*
