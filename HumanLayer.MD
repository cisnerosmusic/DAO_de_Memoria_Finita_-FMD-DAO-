# HumanLayer
### Arquitectura de incentivos para sistemas gobernados por humanos
#### Módulo de la DAO de Memoria Finita (FMD-DAO) · Ernesto Cisneros Cino

---

## Índice

- [El problema que nadie quiere admitir](#el-problema-que-nadie-quiere-admitir)
- [Capa 0 — Fundamentos conceptuales e históricos](#capa-0--fundamentos-conceptuales-e-históricos)
- [Capa 1 — Para no especialistas](#capa-1--para-no-especialistas)
- [Capa 2 — Para especialistas](#capa-2--para-especialistas)
- [Capa 3 — Implementación en Solidity](#capa-3--implementación-en-solidity)
- [Relación con otros módulos](#relación-con-otros-módulos)
- [Licencia](#licencia)

---

## El problema que nadie quiere admitir

La mayoría de los sistemas de gobernanza descentralizada fallan por la misma razón que fallan los parlamentos, las asambleas de vecinos y los equipos de trabajo: **no fueron diseñados para humanos reales**.

Fueron diseñados para humanos ideales — racionales, desinteresados, capaces de separar su ego de sus opiniones, dispuestos a cambiar de posición ante evidencia nueva.

Esos humanos no existen.

Los humanos reales tienen ego, sesgos, tribalismo, aversión a la pérdida y tendencia a la polarización. El HumanLayer no intenta corregir esos defectos. Los acepta como **constantes del sistema** y diseña la arquitectura para que produzcan resultados útiles a pesar de ellos — o gracias a ellos.

> No le pedimos a los ríos que fluyan cuesta arriba.
> Construimos canales.

---

# Capa 0 — Fundamentos conceptuales e históricos

## 1. La coopetición: competencia y colaboración como unidad

La dicotomía competencia/colaboración es falsa. En los sistemas más resilientes de la historia, ambas fuerzas operan simultáneamente.

### Evidencia evolutiva

El biólogo Lynn Margulis demostró en los años 60 que las mitocondrias — el motor de todas las células eucariotas — son antiguas bacterias que en lugar de ser destruidas por sus huéspedes, establecieron una alianza. La vida compleja no emergió de la competencia pura ni de la cooperación pura, sino de su tensión productiva.

Robert Axelrod, en su experimento clásico *The Evolution of Cooperation* (1984), demostró mediante torneos de teoría de juegos que la estrategia más exitosa a largo plazo no es la traición ni la cooperación ciega, sino **Tit-for-Tat**: cooperar primero, castigar la traición inmediatamente, perdonar y volver a cooperar. La reciprocidad iterable supera a la defección oportunista.

### Evidencia institucional

Las repúblicas italianas del siglo XII-XV (Venecia, Florencia, Génova) competían ferozmente entre sí en los mercados mediterráneos y al mismo tiempo desarrollaron los primeros instrumentos financieros colaborativos de la historia moderna: la letra de cambio, la sociedad en comandita, el seguro marítimo. La competencia generó la presión; la colaboración generó las herramientas.

El sistema de patentes, paradójicamente, es un mecanismo de coopetición: obliga a publicar el conocimiento (colaboración) a cambio de protección temporal del monopolio (competencia). Sin esa arquitectura, el conocimiento técnico habría permanecido secreto indefinidamente.

### Aplicación al HumanLayer

La FMD-DAO no pide a sus miembros que renuncien a la ambición o al interés propio. Les ofrece un tablero donde **la forma más eficiente de ganar individualmente requiere contribuir al bien colectivo**. La renuncia no es moral — es estratégica.

---

## 2. El coste del estancamiento ideológico

### El problema de la polarización

Jonathan Haidt en *The Righteous Mind* (2012) documenta cómo el razonamiento moral humano funciona de forma inversa a lo que creemos: primero decidimos emocionalmente, luego construimos argumentos racionales para justificar esa decisión. La deliberación racional es frecuentemente post-hoc.

Esto explica por qué los debates políticos raramente cambian mentes: no son intercambios de argumentos sino de señales de identidad grupal. Cambiar de posición equivale a traicionar al grupo.

Cass Sunstein en *Going to Extremes* (2009) estudió experimentalmente cómo grupos de personas con posiciones similares, al deliberar entre sí, terminan en posiciones más extremas que cualquiera de sus miembros inicialmente sostenía. La deliberación sin fricción externa produce **polarización en cámara de eco**.

### La solución histórica: fricción institucional

El sistema adversarial del common law anglosajón no confía en que jueces o jurados sean sabios — confía en que la **fricción estructurada entre dos posiciones opuestas** produzca algo más cercano a la verdad que cualquiera de las dos por separado.

El Senado Romano clásico (no el tardío) tenía un mecanismo notable: antes de votar una declaración de guerra, se escuchaba obligatoriamente al *advocatus pacis* — un orador designado para argumentar la posición contraria, independientemente de sus convicciones personales. No era virtud cívica. Era arquitectura.

La estructura de la ciencia peer-review, con toda sus imperfecciones, opera bajo el mismo principio: antes de que una afirmación sea aceptada, debe sobrevivir el escrutinio de quienes tienen incentivos para refutarla.

### El oscilador ideológico

Si el estancamiento en una posición es gratuito, los actores no tienen razón para moverse. Si tiene coste, la racionalidad económica los empuja hacia la exploración.

Este principio aparece en sistemas naturales: en ecología, las especies que explotan un solo nicho son vulnerables a cambios ambientales. Las generalistas sobreviven mejor a largo plazo. En mercados financieros, las carteras sin rebalanceo periódico acumulan riesgo concentrado.

El HumanLayer introduce el mismo mecanismo en gobernanza: **el coste del estancamiento no es una sanción moral, es una regla del sistema**, como la gravedad o el decay exponencial.

---

## 3. Entender al contrario como requisito técnico

### La ilusión del conocimiento explicativo

Leonid Rozenblit y Frank Keil (2002) describieron el *Illusion of Explanatory Depth*: las personas creen entender cómo funcionan objetos complejos (un inodoro, una cremallera, una política fiscal) mucho mejor de lo que realmente los entienden. Cuando se les pide que expliquen el mecanismo en detalle, su confianza colapsa.

Lo mismo ocurre con posiciones políticas e ideológicas. Philip Fernbach et al. (2013) demostraron en *Political Extremism is Supported by an Illusion of Understanding* que pedir a personas con posiciones extremas que **expliquen el mecanismo** de las políticas que apoyan — no que las justifiquen moralmente, sino que expliquen cómo funcionan — reduce significativamente su extremismo y aumenta su apertura a posiciones alternativas.

La comprensión mecanística es moderadora. La justificación moral es polarizadora.

### Implicación de diseño

El test de comprensión del HumanLayer no pregunta "¿estás de acuerdo con la posición contraria?" — eso sería pedir virtud. Pregunta "¿puedes explicar cómo funciona el argumento contrario?" — eso es verificar comprensión.

La diferencia es crucial. No se juzga la posición. Se verifica que el votante no opera desde ignorancia.

---

## 4. Reputación visible y el ego como motor

### Economía del reconocimiento

Dan Ariely en *Predictably Irrational* (2008) y Uri Gneezy en múltiples estudios sobre motivación documentan un fenómeno contraintuitivo: en muchos contextos, el reconocimiento social es más motivador que la compensación económica. Los voluntarios de Wikipedia escriben más contenido de calidad que muchos trabajadores pagados. Los donantes anónimos donan menos que los públicos.

El ego no es un defecto a corregir — es un recurso energético a canalizar.

### El problema del reconocimiento vago

Sin embargo, el reconocimiento genérico ("buen contribuidor") es menos motivador que el específico y verificable. Teresa Amabile en *The Progress Principle* (2011) demuestra que la percepción de **progreso concreto y medible** es el principal motor de motivación intrínseca en trabajo cognitivo.

El HumanLayer diseña reputación que es visible, granular, y atribuible — no "participó mucho" sino "su propuesta redujo el tiempo de resolución de disputas en 34%".

---

# Capa 1 — Para no especialistas

## ¿Qué es el HumanLayer?

Es la capa del sistema que reconoce que una DAO no la gobiernan contratos inteligentes — la gobiernan personas. Y las personas tienen ego, opiniones fijas, tendencia a formar bandos y resistencia a cambiar de posición.

El HumanLayer no pide a las personas que sean mejores. Diseña el sistema para que sus características humanas — incluso las problemáticas — produzcan resultados útiles.

## Los tres problemas que resuelve

### Problema 1: La polarización

En cualquier grupo, con el tiempo las posiciones se vuelven más extremas. Los que piensan parecido se juntan, se refuerzan mutuamente y terminan incapaces de comunicarse con el grupo opuesto.

**Solución del HumanLayer:** antes de votar una propuesta, el sistema pide que demuestres que entiendes el argumento contrario. No que estés de acuerdo — solo que puedas explicarlo. Si no puedes, tu voto pesa menos.

### Problema 2: El estancamiento ideológico

Una persona que siempre vota igual, en todas las propuestas, en todos los ciclos, no está deliberando — está aplicando una etiqueta automáticamente. Eso es costoso para el sistema porque congela posibilidades y bloquea síntesis.

**Solución del HumanLayer:** quedarse fijo tiene coste. El peso de tu voto decae si tu historial muestra rigidez absoluta. No pierdes el voto — pierdes influencia gradualmente, como la reputación decae si no contribuyes.

### Problema 3: El ego sin dirección

El ego existe. Ignorarlo no lo elimina — solo lo desplaza hacia comportamientos menos visibles y más dañinos (política de pasillos, capturas silenciosas).

**Solución del HumanLayer:** el ego tiene un canal oficial. La reputación es pública, granular y específica. Si quieres reconocimiento, la forma más eficiente de obtenerlo es contribuir de maneras que el sistema pueda medir y mostrar.

---

## La renuncia estratégica

El sistema pide renuncias — pero no morales. Pide renuncias estratégicas: ceder algo pequeño ahora para ganar algo mayor después.

Un miembro que siempre vota en un solo sentido cede influencia gradualmente. Un miembro que demuestra comprensión del argumento contrario gana peso en sus votos. Un miembro que propone algo que funciona acumula reputación visible.

El sistema convierte la competencia y la colaboración en aliadas, no en enemigas.

---

# Capa 2 — Para especialistas

## Arquitectura del HumanLayer

El HumanLayer opera sobre cuatro mecanismos interdependientes:

```
1. Oscilador Ideológico     →  coste del estancamiento
2. Test de Comprensión      →  verificación on-chain de entender al contrario
3. Reputación Granular      →  ego canalizado hacia contribución medible
4. Coopetición Estructurada →  competencia que requiere colaboración para ganar
```

Ninguno de estos mecanismos modifica los contratos del Sistema Inmune, la Memoria Finita o el Ruido Estabilizador. Los **usa** — lee sus datos, responde a sus estados — pero no escribe en ellos.

---

## Mecanismo 1: Oscilador Ideológico

### Definición

Sea `V_i(t)` el vector de votos del miembro `i` en el período `t`. Se define la **rigidez ideológica** como:

```txt
Rigidez(i, T) = 1 - (varianza de posiciones en T ciclos / varianza máxima posible)

Rango: [0, 1]
  0 = máxima variabilidad (vota diferente en cada propuesta)
  1 = rigidez absoluta (vota siempre igual)
```

### Penalización de peso de voto

```txt
W_voto(i) = W_base * (1 - alpha * Rigidez(i, T))

donde:
  W_base  = peso base del miembro (derivado de su reputación)
  alpha   = parámetro de penalización (recomendado: 0.3)
  T       = ventana de ciclos evaluados (recomendado: últimos 6 ciclos)

Límite inferior:
  W_voto(i) >= W_base * 0.5    // nunca pierde más del 50% de su peso
```

### Oscilación premiada

Un miembro que demuestra cambio de posición **justificado** (acompañado de argumento registrado on-chain) recibe bonificación:

```txt
Si el miembro cambia posición y registra justificación:
  Rigidez(i) se recalcula excluyendo ese ciclo del denominador
  → efecto: el cambio justificado no penaliza, la rigidez no justificada sí
```

### Protección anti-oportunismo

Para evitar que miembros oscilen arbitrariamente solo para evitar la penalización:

```txt
Si la variabilidad de voto es máxima (vota aleatorio):
  el sistema detecta ausencia de coherencia interna
  → penalización por incoherencia, no por rigidez

Coherencia(i) = correlación entre justificaciones registradas y cambios de posición
Si Coherencia(i) < umbral_minimo:
  W_voto(i) = W_base * 0.7   // penalización por incoherencia
```

---

## Mecanismo 2: Test de Comprensión (Proof of Understanding)

### Principio

Antes de votar en propuestas clasificadas como `TIPO_CONTROVERSIAL` (aquellas donde la distribución de votos previos sugiere polarización alta), el sistema requiere que el votante complete un **Proof of Understanding** del argumento contrario a su posición declarada.

### Flujo

```txt
1. Miembro declara intención de voto: FAVOR / CONTRA
2. Sistema detecta si la propuesta es CONTROVERSIAL
   (definición: spread > 60/40 en votación previa o señalada por C1)
3. Si CONTROVERSIAL:
   a. Sistema presenta resumen del argumento contrario (generado off-chain, firmado por C1)
   b. Miembro responde 3 preguntas de comprensión mecanística
      (no de acuerdo — de comprensión del mecanismo)
   c. Respuestas se hashean y registran on-chain
   d. Validación off-chain por oráculo de lenguaje
4. Resultado:
   - Proof válido   →  W_voto completo
   - Proof inválido →  W_voto * 0.6
   - Proof omitido  →  W_voto * 0.4
```

### Garantías

```txt
- El contenido de las respuestas NO es público (solo el hash y el resultado)
- La validación es off-chain pero el resultado se registra on-chain
- No se puede votar sin intentar el test (omitir es una elección con coste)
- Las preguntas rotan por ciclo (evita memorización de respuestas)
```

---

## Mecanismo 3: Reputación Granular

### Estructura del score reputacional

La reputación en el HumanLayer no es un número único — es un **vector de dimensiones**:

```txt
REP(i) = {
  REP_propuesta:    calidad y tasa de éxito de propuestas presentadas,
  REP_validacion:   precisión histórica en validaciones técnicas,
  REP_comprension:  historial de Proof of Understanding completados,
  REP_oscilacion:   índice de oscilación ideológica justificada,
  REP_colaboracion: contribuciones a propuestas de otros miembros
}
```

### Visibilidad pública

Cada dimensión es pública y específica. Los logros se expresan como hechos medibles:

```txt
"Propuesta #47: redujo timelock promedio en 18%"
"Validación #12: predicción correcta en crisis NARANJA de nov-2025"
"Comprensión: 94% de tests completados con validación positiva"
```

No existe un "nivel general" que oculte las dimensiones individuales.

### Badges no-monetarios (Soulbound NFTs)

```txt
PROOF_SEEKER_BRONZE    — 10 tests de comprensión completados
PROOF_SEEKER_SILVER    — 50 tests, tasa >80% validación positiva
PROOF_SEEKER_GOLD      — 100 tests, tasa >90%

OSCILLATOR_ACTIVE      — cambio de posición justificado en últimos 3 ciclos
OSCILLATOR_CONSISTENT  — 6 ciclos con oscilación coherente documentada

COOPETITOR             — propuesta propia + contribución a propuesta ajena en mismo ciclo
BRIDGE_BUILDER         — propuesta aprobada con votos de ambas cámaras >70%
```

Los badges son **Soulbound** (no transferibles). No tienen valor económico directo. Su valor es reputacional — y por eso funcionan.

---

## Mecanismo 4: Coopetición estructurada

### El problema del juego de suma cero

En sistemas donde los recursos son fijos, la competencia se vuelve de suma cero: lo que gana uno, lo pierde otro. Eso incentiva traición, bloqueo y captura.

### La solución: incentivos acoplados

En el HumanLayer, parte de los incentivos de C1 (Expertos) están acoplados al rendimiento de C2 (Comunes) y viceversa:

```txt
Incentivo_C1(i) = base_C1 + bonus * rendimiento_conjunto(C1, C2)
Incentivo_C2(j) = reconocimiento + bonus_social * rendimiento_conjunto(C1, C2)

rendimiento_conjunto = f(tasa de propuestas exitosas, velocidad de resolución,
                         índice de participación, salud del R)
```

Esto hace que **ganar solo sea subóptimo**. El camino de máximo beneficio individual pasa por el éxito colectivo.

### Votos cuadráticos para posiciones extremas

El coste de expresar una posición extrema crece cuadráticamente:

```txt
Coste_de_voto = (intensidad_de_posicion)^2

Escala de intensidad: 1 (leve) a 5 (máxima)

Votar con intensidad 1: cuesta 1 unidad de crédito
Votar con intensidad 3: cuesta 9 unidades
Votar con intensidad 5: cuesta 25 unidades
```

Esto no impide posiciones extremas — las hace costosas. El miembro puede mantener su posición, pero debe pagar por su intensidad.

---

# Capa 3 — Implementación en Solidity

```
HumanLayer/
├── IdeologicalOscillator.sol    # Decay de peso por rigidez
├── ProofOfUnderstanding.sol     # Test de comprensión on-chain
├── GranularReputation.sol       # Vector reputacional multidimensional
├── CoopetitionEngine.sol        # Incentivos acoplados y voto cuadrático
├── SoulboundBadges.sol          # NFTs no transferibles de logros
└── libraries/
    └── HumanMath.sol            # Cálculos de rigidez, coherencia, cuadrático
```

---

## HumanMath.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title HumanMath
/// @notice Librería de cálculos para el HumanLayer
library HumanMath {

    uint256 public constant BPS = 10_000;
    uint256 public constant ALPHA_BPS = 3_000; // 30% penalización máxima por rigidez

    /// @notice Calcula el peso de voto ajustado por rigidez ideológica
    /// @param baseWeight Peso base del miembro (en BPS)
    /// @param rigidityBps Rigidez [0, BPS] donde BPS = rigidez absoluta
    /// @return adjustedWeight Peso ajustado (nunca menor al 50% del base)
    function adjustedVoteWeight(
        uint256 baseWeight,
        uint256 rigidityBps
    ) internal pure returns (uint256 adjustedWeight) {
        uint256 penalty = (baseWeight * ALPHA_BPS * rigidityBps) / (BPS * BPS);
        uint256 minWeight = baseWeight / 2;
        adjustedWeight = baseWeight > penalty
            ? baseWeight - penalty
            : minWeight;
        if (adjustedWeight < minWeight) adjustedWeight = minWeight;
    }

    /// @notice Calcula el coste cuadrático de un voto según su intensidad
    /// @param intensity Intensidad del voto [1, 5]
    /// @return cost Coste en créditos de gobernanza
    function quadraticVoteCost(uint256 intensity)
        internal pure returns (uint256 cost)
    {
        require(intensity >= 1 && intensity <= 5, "HumanMath: invalid intensity");
        cost = intensity * intensity;
    }

    /// @notice Calcula el rendimiento conjunto C1+C2 (normalizado 0-BPS)
    /// @param successRate Tasa de éxito de propuestas (0-BPS)
    /// @param participationRate Tasa de participación (0-BPS)
    /// @param resilienceR Índice R actual (escalado x1000, Valle: 1000-3000)
    /// @return score Puntuación conjunta (0-BPS)
    function jointPerformanceScore(
        uint256 successRate,
        uint256 participationRate,
        uint256 resilienceR
    ) internal pure returns (uint256 score) {
        // R en Valle [1,3] → contribución máxima
        uint256 rContribution = (resilienceR >= 1000 && resilienceR <= 3000)
            ? BPS
            : BPS / 2;

        score = (successRate * 4 + participationRate * 3 + rContribution * 3) / 10;
    }
}
```

---

## IdeologicalOscillator.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/HumanMath.sol";

/// @title IdeologicalOscillator
/// @notice Penaliza el estancamiento ideológico y premia la oscilación justificada
contract IdeologicalOscillator {

    using HumanMath for uint256;

    uint256 public constant EVALUATION_WINDOW = 6; // ciclos
    uint256 public constant BPS = 10_000;

    struct VoteRecord {
        uint8   position;     // 0=contra, 1=favor
        bool    hasJustification;
        bytes32 justificationHash;
        uint256 cycle;
    }

    // member => VoteRecord[]
    mapping(address => VoteRecord[]) public voteHistory;

    // member => rigidityBps cache (actualizado cada ciclo)
    mapping(address => uint256) public rigidityBps;

    event RigidityUpdated(address indexed member, uint256 rigidityBps);
    event JustifiedOscillation(address indexed member, uint256 cycle);

    /// @notice Registra un voto y su justificación opcional
    function recordVote(
        address member,
        uint8 position,
        bytes32 justificationHash,
        uint256 cycle
    ) external {
        bool hasJust = justificationHash != bytes32(0);

        voteHistory[member].push(VoteRecord({
            position: position,
            hasJustification: hasJust,
            justificationHash: justificationHash,
            cycle: cycle
        }));

        _updateRigidity(member);

        if (hasJust) {
            emit JustifiedOscillation(member, cycle);
        }
    }

    /// @notice Devuelve el peso de voto ajustado por rigidez
    function getAdjustedWeight(address member, uint256 baseWeight)
        external view returns (uint256)
    {
        return HumanMath.adjustedVoteWeight(baseWeight, rigidityBps[member]);
    }

    function _updateRigidity(address member) internal {
        VoteRecord[] storage history = voteHistory[member];
        uint256 len = history.length;

        if (len < 2) {
            rigidityBps[member] = 0;
            return;
        }

        uint256 window = len >= EVALUATION_WINDOW ? EVALUATION_WINDOW : len;
        uint256 start = len - window;

        uint256 changes = 0;
        uint256 justifiedChanges = 0;

        for (uint256 i = start + 1; i < len; i++) {
            if (history[i].position != history[i-1].position) {
                changes++;
                if (history[i].hasJustification) justifiedChanges++;
            }
        }

        // Máximo cambios posibles en la ventana
        uint256 maxChanges = window - 1;

        // Si no hay cambios: rigidez máxima
        if (changes == 0) {
            rigidityBps[member] = BPS;
        } else {
            // Rigidez = 1 - (cambios / max_cambios)
            // Los cambios justificados cuentan doble
            uint256 weightedChanges = changes + justifiedChanges;
            uint256 weightedMax = maxChanges + maxChanges; // doble peso posible
            uint256 flexibilityBps = (weightedChanges * BPS) / weightedMax;
            rigidityBps[member] = flexibilityBps >= BPS ? 0 : BPS - flexibilityBps;
        }

        emit RigidityUpdated(member, rigidityBps[member]);
    }
}
```

---

## ProofOfUnderstanding.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ProofOfUnderstanding
/// @notice Gestiona el test de comprensión del argumento contrario antes de votar
/// @dev La validación es off-chain; solo el resultado y el hash se registran on-chain
contract ProofOfUnderstanding {

    uint256 public constant BPS = 10_000;

    // Multiplicadores de peso de voto según resultado del Proof
    uint256 public constant WEIGHT_VALID   = 10_000; // 100% — proof válido
    uint256 public constant WEIGHT_INVALID =  6_000; //  60% — proof inválido
    uint256 public constant WEIGHT_OMITTED =  4_000; //  40% — proof omitido

    enum ProofResult { OMITTED, INVALID, VALID }

    struct ProofRecord {
        bytes32     answersHash;    // hash de las respuestas (privacidad)
        ProofResult result;         // resultado validado por oráculo
        uint256     proposalId;
        uint256     timestamp;
    }

    // member => proposalId => ProofRecord
    mapping(address => mapping(uint256 => ProofRecord)) public proofs;

    // Oráculo autorizado para registrar resultados
    address public validationOracle;

    event ProofSubmitted(address indexed member, uint256 indexed proposalId, bytes32 answersHash);
    event ProofValidated(address indexed member, uint256 indexed proposalId, ProofResult result);

    modifier onlyOracle() {
        require(msg.sender == validationOracle, "PoU: not oracle");
        _;
    }

    constructor(address _oracle) {
        validationOracle = _oracle;
    }

    /// @notice El miembro envía el hash de sus respuestas al test
    function submitProof(uint256 proposalId, bytes32 answersHash) external {
        require(
            proofs[msg.sender][proposalId].timestamp == 0,
            "PoU: already submitted"
        );
        proofs[msg.sender][proposalId] = ProofRecord({
            answersHash:  answersHash,
            result:       ProofResult.OMITTED,
            proposalId:   proposalId,
            timestamp:    block.timestamp
        });
        emit ProofSubmitted(msg.sender, proposalId, answersHash);
    }

    /// @notice El oráculo registra el resultado de la validación off-chain
    function recordResult(
        address member,
        uint256 proposalId,
        ProofResult result
    ) external onlyOracle {
        require(
            proofs[member][proposalId].timestamp > 0,
            "PoU: no proof submitted"
        );
        proofs[member][proposalId].result = result;
        emit ProofValidated(member, proposalId, result);
    }

    /// @notice Devuelve el multiplicador de peso de voto según el Proof
    function getWeightMultiplier(address member, uint256 proposalId)
        external view returns (uint256)
    {
        ProofResult result = proofs[member][proposalId].result;
        if (result == ProofResult.VALID)   return WEIGHT_VALID;
        if (result == ProofResult.INVALID) return WEIGHT_INVALID;
        return WEIGHT_OMITTED;
    }
}
```

---

## SoulboundBadges.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title SoulboundBadges
/// @notice NFTs no transferibles que registran logros en el HumanLayer
/// @dev Transferencia bloqueada por diseño — el badge pertenece a quien lo ganó
contract SoulboundBadges is ERC721 {

    enum BadgeType {
        PROOF_SEEKER_BRONZE,    // 10 tests completados
        PROOF_SEEKER_SILVER,    // 50 tests, >80% validación positiva
        PROOF_SEEKER_GOLD,      // 100 tests, >90%
        OSCILLATOR_ACTIVE,      // cambio justificado en últimos 3 ciclos
        OSCILLATOR_CONSISTENT,  // 6 ciclos con oscilación coherente
        COOPETITOR,             // propuesta propia + contribución ajena en mismo ciclo
        BRIDGE_BUILDER          // propuesta con >70% en ambas cámaras
    }

    struct Badge {
        BadgeType badgeType;
        uint256   awardedAt;
        string    specificAchievement; // descripción medible del logro
    }

    uint256 private _nextTokenId;
    mapping(uint256 => Badge) public badges;
    mapping(address => mapping(BadgeType => bool)) public hasBadge;

    address public minter;

    event BadgeAwarded(
        address indexed to,
        BadgeType badgeType,
        string achievement,
        uint256 tokenId
    );

    modifier onlyMinter() {
        require(msg.sender == minter, "Badges: not minter");
        _;
    }

    constructor(address _minter) ERC721("FMD-DAO HumanLayer Badges", "FMDBADGE") {
        minter = _minter;
    }

    /// @notice Emite un badge soulbound a un miembro
    function awardBadge(
        address to,
        BadgeType badgeType,
        string calldata achievement
    ) external onlyMinter returns (uint256 tokenId) {
        require(!hasBadge[to][badgeType], "Badges: already awarded");

        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);

        badges[tokenId] = Badge({
            badgeType:           badgeType,
            awardedAt:           block.timestamp,
            specificAchievement: achievement
        });

        hasBadge[to][badgeType] = true;
        emit BadgeAwarded(to, badgeType, achievement, tokenId);
    }

    /// @dev Bloquea toda transferencia — los badges son soulbound
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);
        require(from == address(0), "Badges: soulbound, non-transferable");
        return super._update(to, tokenId, auth);
    }
}
```

---

## Notas de integración

```txt
El HumanLayer NO escribe en:
  - ImmunityCore.sol
  - MemoryDecay.sol
  - ResilienceIndex.sol
  - StabilizingNoise.sol

El HumanLayer SÍ lee de:
  - ResilienceIndex → para calcular jointPerformanceScore
  - ImmunityCore    → para ajustar pesos durante inflamación
                      (en crisis ROJA, Proof of Understanding es obligatorio
                       para todas las propuestas, no solo las CONTROVERSIAL)

Costos estimados en L2 (Arbitrum/Optimism):
  Registro de votos con justificación (~2000/año): ~$400
  Proof submissions (~1500/año):                   ~$300
  Proof results del oráculo (~1500/año):           ~$300
  Badge awards (~200/año):                         ~$100
  Total estimado:                                  ~$1,100
```

---

# Relación con otros módulos

```txt
FMD-DAO
├── Memoria Finita          →  HumanLayer hereda el decay reputacional
│                              REP(i) decae igual que autoridad general
│
├── Ruido Estabilizador     →  Los parámetros alpha y EVALUATION_WINDOW
│                              pueden recibir ruido controlado
│                              (±2% variación por ciclo)
│
├── Sistema Inmunológico    →  En crisis ROJA:
│                              Proof of Understanding se vuelve obligatorio
│                              Los pesos de oscilación se congelan temporalmente
│
└── HumanLayer  ◄── este módulo
      ├── Oscilador Ideológico
      ├── Proof of Understanding
      ├── Reputación Granular
      └── Coopetición Estructurada
```

---

## El principio fundamental

El HumanLayer no confía en la virtud de sus miembros.

Confía en que un **tablero bien diseñado** convierte los defectos humanos en comportamientos útiles: el ego en contribución medible, la rigidez en coste evitable, la ignorancia del contrario en penalización calculada, la competencia en motor de colaboración.

> No le pedimos a los ríos que fluyan cuesta arriba.
> Construimos canales.

---

## Referencias

- Axelrod, R. (1984). *The Evolution of Cooperation*. Basic Books.
- Ariely, D. (2008). *Predictably Irrational*. Harper Collins.
- Amabile, T. & Kramer, S. (2011). *The Progress Principle*. Harvard Business Review Press.
- Fernbach, P. et al. (2013). Political Extremism is Supported by an Illusion of Understanding. *Psychological Science*, 24(6), 939-946.
- Haidt, J. (2012). *The Righteous Mind*. Pantheon Books.
- Margulis, L. (1967). On the Origin of Mitosing Cells. *Journal of Theoretical Biology*, 14(3), 225-274.
- Rozenblit, L. & Keil, F. (2002). The Misunderstood Limits of Folk Science. *Cognitive Science*, 26(5), 521-562.
- Sunstein, C. (2009). *Going to Extremes*. Oxford University Press.
- Thaler, R. & Sunstein, C. (2008). *Nudge*. Yale University Press.

---

## Licencia

MIT License · Ernesto Cisneros Cino

---

*Parte del proyecto [DAO de Memoria Finita (FMD-DAO)](https://github.com/cisnerosmusic/DAO_de_Memoria_Finita_-FMD-DAO-)*

*"No le pedimos a los ríos que fluyan cuesta arriba. Construimos canales."*
