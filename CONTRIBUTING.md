# CONTRIBUTING.md
### Cómo contribuir a FMD-DAO
#### DAO de Memoria Finita · Ernesto Cisneros Cino

---

## Índice

- [Antes de empezar](#antes-de-empezar)
- [Tipos de contribución](#tipos-de-contribución)
- [El proceso bicameral de contribución](#el-proceso-bicameral-de-contribución)
- [Flujo técnico: Pull Requests](#flujo-técnico-pull-requests)
- [Estándares de código](#estándares-de-código)
- [Estándares de documentación](#estándares-de-documentación)
- [Tests obligatorios](#tests-obligatorios)
- [Revisión por C1](#revisión-por-c1)
- [Código de conducta](#código-de-conducta)
- [Configuración del entorno](#configuración-del-entorno)

---

## Antes de empezar

FMD-DAO no es un proyecto de software convencional. Es un sistema de gobernanza
que aplica sus propios principios a su propio desarrollo:

- **Memoria finita**: las decisiones de diseño tienen vida útil. Lo que se
  decidió en el ciclo 1 puede ser revisado en el ciclo 4 — con argumentos,
  no con autoridad.

- **Bicameralidad**: las contribuciones técnicas pasan por validación de C1
  (expertos) y las contribuciones filosóficas o de diseño pasan por deliberación
  de C2 (commons). Una propuesta que toca ambas requiere ambas cámaras.

- **Ruido estabilizador**: no buscamos consenso perfecto. Buscamos propuestas
  suficientemente robustas para sobrevivir a la crítica honesta.

Si algo en este proceso te parece rígido o innecesario, esa observación es
bienvenida — abre un issue en C2.

---

## Tipos de contribución

### Nivel 0 — Sin proceso formal (bienvenido directamente)
- Corrección de errores tipográficos en documentación
- Mejoras de legibilidad en comentarios NatSpec
- Adición de ejemplos en README o ARCHITECTURE

### Nivel 1 — Issue + PR con revisión de un experto C1
- Corrección de bugs en contratos existentes
- Mejoras de gas en funciones existentes (sin cambio de comportamiento)
- Nuevos tests que aumentan cobertura
- Mejoras al schema del subgraph

### Nivel 2 — Issue + RFC + PR con revisión de dos expertos C1
- Nuevas funciones en contratos existentes
- Cambios de parámetros de gobernanza
- Nuevas entidades en el schema
- Modificaciones al modelo de decay o rotación

### Nivel 3 — Issue + RFC + deliberación C2 + aprobación C1
- Nuevos contratos
- Cambios en los invariantes del sistema
- Modificaciones al flujo de propuestas o al Ritual Trimestral
- Cambios en el modelo matemático (R, λ, Valle de Resiliencia)

### Nivel 4 — Propuesta constitucional (on-chain)
- Cambios en los invariantes absolutamente no modificables por gobernanza ordinaria
- Modificaciones al MAX_INFLAMMATION_DAYS
- Cambios en el superquórum constitucional (75%)
- Cualquier cambio que afecte la estructura bicameral

---

## El proceso bicameral de contribución

### Para contribuciones Nivel 1

```
1. Abre un Issue describiendo el problema o la mejora
2. Espera 48h para feedback de la comunidad
3. Abre un Pull Request referenciando el Issue
4. Un experto C1 revisa y aprueba
5. Merge tras aprobación
```

### Para contribuciones Nivel 2

```
1. Abre un Issue con etiqueta [RFC]
2. Escribe un RFC siguiendo la plantilla (ver abajo)
3. Período de deliberación: 7 días mínimo
4. Si hay consenso informal → abre PR
5. Dos expertos C1 revisan independientemente
6. Merge si ambos aprueban (sin objeciones mayores sin resolver)
```

### Para contribuciones Nivel 3

```
1. Abre un Issue con etiqueta [C2-PROPOSAL]
2. Escribe el RFC con sección de impacto en R = τ × Ω
3. Período de deliberación C2: 14 días
4. Votación informal en el Issue (thumbs up / thumbs down)
5. Si mayoría C2 → escalado a C1 para validación técnica
6. C1 revisa en 7 días
7. Si C1 aprueba → PR abierto y mergeado
```

### Para contribuciones Nivel 4

El proceso ocurre on-chain siguiendo el flujo de `ProposalType.CONSTITUTIONAL`
en `FMDDAOCore`. Ver `ARCHITECTURE.md` → Flujo de una propuesta.

---

## Plantilla RFC

Usa esta plantilla para Issues de Nivel 2 y superiores:

```markdown
## RFC: [Título descriptivo]

### Resumen
Un párrafo que explique qué cambia y por qué.

### Motivación
¿Qué problema resuelve? ¿Qué falla en el diseño actual?

### Impacto en R = τ × Ω
¿Este cambio afecta τ, Ω, o la relación entre ambos?
¿Empuja el sistema hacia o fuera del Valle de Resiliencia?

### Descripción técnica
Cambios concretos propuestos. Pseudocódigo o diff si aplica.

### Alternativas consideradas
¿Qué otras opciones se evaluaron y por qué se descartan?

### Riesgos y mitigaciones
¿Qué puede salir mal? ¿Cómo se detecta? ¿Cómo se revierte?

### Tests propuestos
¿Qué escenarios de test verifican el comportamiento esperado?

### Compatibilidad hacia atrás
¿Rompe algo existente? ¿Requiere migración de datos?
```

---

## Flujo técnico: Pull Requests

### Ramas

```
main          — producción, siempre desplegable
develop       — integración, tests pasan siempre
feature/xxx   — nuevas funcionalidades
fix/xxx       — correcciones de bugs
docs/xxx      — documentación
test/xxx      — tests nuevos o mejorados
```

### Convención de commits

Usamos [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(oracle): add inactivity decay to OracleRegistry
fix(immunity): correct velocity classification threshold
docs(architecture): update module dependency diagram
test(core): add full proposal cycle integration test
refactor(reputation): virtualize decay in updateDecayBatch
chore(deps): upgrade OpenZeppelin to v5.1
```

Tipos válidos: `feat` · `fix` · `docs` · `test` · `refactor` · `chore` · `perf`

Scopes válidos: `core` · `oracle` · `immunity` · `humanlayer` · `reputation`
                `params` · `simulation` · `subgraph` · `deploy`

### Checklist antes de abrir un PR

```
[ ] Los tests pasan: npx hardhat test
[ ] Cobertura no decrece: npx hardhat coverage
[ ] El código compila sin warnings: npx hardhat compile
[ ] NatSpec completo en todas las funciones públicas
[ ] El ARCHITECTURE.md está actualizado si cambió algo estructural
[ ] El schema.graphql está actualizado si se añadieron eventos
[ ] El CHANGELOG.md tiene entrada para este cambio
[ ] No hay console.log ni comentarios de debug en producción
```

---

## Estándares de código

### Solidity

```solidity
// ✅ Correcto — NatSpec completo
/// @notice Aplica decay en lote para todos los expertos activos
/// @dev Solo escribe si el drift es > 1% para optimizar gas
/// @return count Número de expertos cuyo score fue actualizado
function updateDecayBatch() external onlyRole(ORACLE_ROLE) returns (uint256 count) {

// ❌ Incorrecto — sin documentación, nombre ambiguo
function update() external {
```

**Orden de elementos en un contrato:**

```
1. SPDX + pragma
2. imports
3. interfaces implementadas
4. errores custom
5. events
6. enums
7. structs
8. constantes (ALL_CAPS)
9. variables de estado (grouped by purpose)
10. constructor
11. funciones externas
12. funciones públicas
13. funciones internas
14. funciones privadas
15. funciones view/pure
```

**Reglas obligatorias:**

- `ReentrancyGuard` en toda función que transfiera valor o llame contratos externos
- `nonReentrant` antes de cualquier efecto externo (checks-effects-interactions)
- Errores custom en lugar de `require` con strings cuando el contexto es claro
- `SafeMath` no necesario en ^0.8.20 — overflow es nativo
- Evitar loops sobre arrays dinámicos sin límite de gas explícito en funciones de escritura
- Todas las funciones de escritura emiten al menos un evento

**Nombres:**

```
contratos:  PascalCase        (OracleRegistry)
funciones:  camelCase         (updateDecayBatch)
variables:  camelCase         (rawRep, lastUpdate)
constantes: UPPER_SNAKE_CASE  (MAX_SCORE, LAMBDA_DEN)
eventos:    PascalCase        (ReputationDecayed)
errores:    PascalCase        (InsufficientCredits)
enums:      PascalCase        (ProviderStatus.ACTIVE)
roles:      UPPER_SNAKE_CASE  (ORACLE_ROLE)
```

### TypeScript (tests y scripts)

- Ethers v6 — no mezclar con v5
- `async/await` — no `.then()` encadenado
- `expect` de Chai — no `assert`
- Nombres de test descriptivos en español o inglés, consistentes dentro de una suite
- Un `describe` por contrato, un `it` por comportamiento verificado
- Usar `time.increase()` de hardhat-network-helpers para simular el paso del tiempo
- No usar `ethers.provider.send("evm_increaseTime")` directamente

---

## Estándares de documentación

### NatSpec obligatorio

Todas las funciones `external` y `public` deben tener:

```solidity
/// @notice  ← qué hace (para humanos, sin jerga técnica)
/// @dev     ← cómo lo hace (para desarrolladores)
/// @param   ← cada parámetro con su descripción
/// @return  ← cada valor de retorno
```

Los `internal` y `private` deben tener al menos `/// @notice` si no son triviales.

### README de módulo

Cada módulo tiene su propio `README.md` con:
- Qué problema resuelve (para no especialistas)
- Fórmulas clave (para especialistas)
- Estructura del contrato
- Notas de integración (qué lee, quién lo lee)

### CHANGELOG

Formato [Keep a Changelog](https://keepachangelog.com/):

```markdown
## [Unreleased]

### Added
- OracleScheduler: función `registerCriticalKey()` para marcar datos críticos

### Changed
- ReputationModule: decay mínimo reducido de 5% a 1%

### Fixed
- CoopetitionEngine: corrección en cálculo de decay con lambdaT > PRECISION
```

---

## Tests obligatorios

Todo PR que modifique un contrato debe incluir tests que cubran:

### Para funciones nuevas

```
✓ Caso feliz: la función hace lo que debe con inputs válidos
✓ Restricciones de acceso: roles incorrectos son rechazados
✓ Validaciones de input: valores fuera de rango son rechazados
✓ Eventos: los eventos correctos son emitidos con los parámetros correctos
✓ Efectos de estado: el estado del contrato cambia como se espera
```

### Para cambios en lógica existente

```
✓ El comportamiento anterior sigue funcionando (no regresiones)
✓ El nuevo comportamiento funciona correctamente
✓ Los casos borde del cambio están cubiertos
```

### Para cambios en el modelo matemático

```
✓ Test con valores conocidos (e.g., decay a 60 días ≈ 50% del valor inicial)
✓ Test de límites: score máximo no se excede, score mínimo no cae a cero absoluto
✓ Test de precisión: la aproximación de Taylor es suficientemente precisa
```

### Cobertura mínima

- Líneas: ≥ 85%
- Ramas: ≥ 80%
- Funciones: ≥ 90%

Un PR que reduce la cobertura requiere justificación explícita.

---

## Revisión por C1

Los expertos de C1 que revisan PRs técnicos verifican:

**Corrección**
- ¿La lógica implementa correctamente la especificación?
- ¿Los casos borde están manejados?
- ¿El modelo matemático es consistente con el resto del sistema?

**Seguridad**
- ¿Hay vectores de reentrancy no protegidos?
- ¿Los roles de acceso son correctos y suficientes?
- ¿El contrato puede ser capturado por un actor con suficiente reputación?
- ¿El cambio introduce algún punto de falla única (single point of failure)?

**Alineación con el Valle**
- ¿El cambio mantiene o mejora la posición de R dentro del Valle?
- ¿El cambio respeta los invariantes del sistema?
- ¿El cambio puede ser revertido si produce efectos adversos?

**Gas y eficiencia**
- ¿Hay operaciones que deberían ser `view` y no lo son?
- ¿Los loops tienen límites de gas razonables?
- ¿La escritura diferida (virtualización) está correctamente implementada?

Un experto C1 **no puede** aprobar su propio PR. La revisión es siempre cruzada.

---

## Código de conducta

### Lo que valoramos

- **Precisión sobre entusiasmo**: una objeción técnica bien argumentada vale más que diez "+1".
- **Desacuerdo productivo**: disentir está bien. Bloquear sin alternativa, no.
- **Memoria finita**: las decisiones pasadas pueden revisarse. No son dogma.
- **Transparencia**: si no entiendes algo, pregunta. Si no sabes algo, dilo.

### Lo que no toleramos

- Ataques personales o descalificaciones
- Aprobar PRs sin revisión real (rubber-stamping)
- Bloquear PRs sin especificar qué cambiaría el voto
- Usar la reputación acumulada como argumento de autoridad en lugar de razones

### Proceso de disputa

Si hay desacuerdo entre un contribuyente y un revisor C1:

1. El contribuyente puede solicitar una segunda revisión de otro experto C1
2. Si el desacuerdo persiste, se abre un Issue con etiqueta `[DISPUTE]`
3. La comunidad delibera durante 7 días
4. Se toma la decisión por mayoría de C1 activos que participen

---

## Configuración del entorno

### Requisitos

```bash
Node.js >= 20.0.0
npm >= 10.0.0
Git >= 2.40.0
```

### Setup inicial

```bash
# Clonar el repositorio
git clone https://github.com/cisnerosmusic/DAO_de_Memoria_Finita_-FMD-DAO-
cd DAO_de_Memoria_Finita_-FMD-DAO-

# Instalar dependencias
npm install

# Copiar variables de entorno
cp .env.example .env
# Editar .env con tus claves (ver sección siguiente)

# Compilar contratos
npx hardhat compile

# Ejecutar tests
npx hardhat test

# Ver cobertura
npx hardhat coverage
```

### Variables de entorno requeridas

```bash
# .env.example

# Red de despliegue
ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc
OPTIMISM_RPC_URL=https://mainnet.optimism.io

# Red de tests (local)
HARDHAT_NETWORK=localhost

# Clave privada del deployer (nunca en producción sin hardware wallet)
DEPLOYER_PRIVATE_KEY=0x...

# Verificación de contratos
ARBISCAN_API_KEY=...
ETHERSCAN_API_KEY=...

# The Graph
SUBGRAPH_DEPLOY_KEY=...

# Chainlink VRF (para tests de integración con VRF real)
CHAINLINK_VRF_COORDINATOR=...
CHAINLINK_KEY_HASH=...
CHAINLINK_SUBSCRIPTION_ID=...
```

### Scripts disponibles

```bash
npx hardhat compile          # compilar contratos
npx hardhat test             # ejecutar todos los tests
npx hardhat test --grep "Oracle"   # tests filtrados
npx hardhat coverage         # cobertura de tests
npx hardhat node             # nodo local
npx hardhat run scripts/deploy/00_deploy_all.ts --network arbitrum
npx hardhat verify --network arbitrum <address>
```

---

## Preguntas frecuentes

**¿Puedo contribuir si no soy experto en Solidity?**
Sí. La documentación, los tests en Python (simulación), el subgraph y el diseño
filosófico son áreas donde el conocimiento técnico de Solidity no es necesario.

**¿Qué pasa si mi PR lleva más de 30 días sin revisión?**
Abre un comment en el PR marcando a un experto C1 específico. Si pasan 7 días
adicionales sin respuesta, el PR puede ser revisado por cualquier experto C1
disponible — la responsabilidad de revisión no es individual sino del colectivo C1.

**¿Puedo proponer cambios al proceso de contribución?**
Sí. Este documento es Nivel 3 — requiere deliberación C2 y aprobación C1.
Abre un Issue con etiqueta `[C2-PROPOSAL]` y la plantilla RFC.

**¿Cómo me convierto en experto C1?**
El proceso es bicameral: necesitas nominación de un experto C1 existente y
aprobación por mayoría de C1 activos. La nominación debe incluir historial
verificable de contribuciones al proyecto o a proyectos de gobernanza relacionados.
La reputación inicial es de 5000 BPS (50% del máximo).

---

*Este documento es un instrumento vivo. La última versión siempre está en `main`.*

*"No le pedimos a los ríos que fluyan cuesta arriba. Construimos canales."*
