# Modelo de Decay Exponencial para la Cámara de Expertos

> **"Un experto que no contribuye es un eco que se desvanece."**

---

## La metáfora del Valle

Imagina la reputación de un experto como una pelota rodando por el Valle de Resiliencia. Si no recibe impulsos periódicos (contribuciones), la gravedad la llevará inevitablemente hacia el fondo. No se trata de castigar la inactividad, sino de reconocer una verdad termodinámica: **todo sistema vivo necesita flujo constante de energía para mantenerse lejos del equilibrio.**

En la FMD-DAO, este principio se traduce en un **decay exponencial** de la reputación a lo largo de 90 días. No es arbitrario: es el tiempo que toma a un sistema olvidar lo suficiente para no quedar atrapado en el pasado, pero recordar lo necesario para no repetir errores.

---

## ¿Por qué decay exponencial y no lineal?

La diferencia es fundamental:

- **Decay lineal**: Pierdes 1% de reputación cada día → Pérdida constante, predecible, mecánica
- **Decay exponencial**: Pierdes un porcentaje de lo que *aún tienes* cada día → Pérdida proporcional, orgánica, natural

El decay exponencial imita los procesos naturales: el enfriamiento de un café, el olvido de un recuerdo, la desintegración radiactiva. En los primeros días la pérdida es rápida (cuando aún tienes mucho que perder), pero se suaviza con el tiempo. Es una curva que respeta la inercia del conocimiento reciente sin congelar el pasado lejano.

### La curva en acción
```
Día 0:  ████████████████████ 100%  (Contribución reciente)
Día 7:  ███████████████      79%   (Aún muy relevante)
Día 21: ██████████           50%   (Vida media)
Día 45: █████                22%   (Atención requerida)
Día 90: █                    5%    (Renovación obligatoria)
```

---

## La matemática del olvido

### La ecuación fundamental

La reputación de un experto en el día `t` se calcula así:
```
R(t) = R₀ · e^(-λt)
```

Donde:
- **R(t)** = Reputación en el día t (lo que queda)
- **R₀** = Reputación inicial (100% = el punto de partida)
- **λ** = Constante de decaimiento (qué tan rápido olvida el sistema)
- **t** = Tiempo transcurrido en días
- **e** = Constante de Euler (≈ 2.71828)

### Diseñando λ: el ritmo del olvido

Queremos que después de 90 días, la reputación haya decaído al **5%** (umbral de renovación). ¿Cómo encontramos λ?
```
5% = 100% · e^(-λ·90)
0.05 = e^(-λ·90)
ln(0.05) = -λ·90
λ = -ln(0.05)/90
λ ≈ 0.0333
```

Esto significa que cada día pierdes aproximadamente **3.33%** de la reputación *que aún conservas*. 

### Vida media: el punto de inflexión

La **vida media** es el tiempo que tarda tu reputación en caer al 50%:
```
t₁/₂ = ln(2)/λ ≈ 20.8 días
```

Traducción práctica: **si no contribuyes, en 3 semanas habrás perdido la mitad de tu autoridad.** No es punitivo, es realista: el conocimiento técnico en blockchain, IA o ciencias avanza tan rápido que 3 semanas sin actualización te convierten en historia antigua.

---

## Implementación en Solidity

### Arquitectura del contrato

El contrato `ExpertReputationDecay` gestiona tres elementos clave:

1. **Estructura de datos**: Cada experto tiene reputación, timestamp y estado
2. **Motor de decay**: Calcula el decaimiento desde la última actualización
3. **Sistema de renovación**: Permite restaurar reputación mediante contribuciones
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title ExpertReputationDecay
 * @notice Implementa memoria finita mediante decay exponencial
 * @dev La reputación decae al 5% en 90 días sin contribuciones
 * 
 * Filosofía: Un experto debe demostrar continuamente su relevancia.
 * No se trata de acumular autoridad, sino de mantener coherencia 
 * técnica mediante participación activa en la validación.
 */
contract ExpertReputationDecay is AccessControl {
    
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    
    // Parámetros del modelo (calibrados para 90 días)
    uint256 public constant DECAY_LAMBDA = 333;           // λ * 10000 = 0.0333 * 10000
    uint256 public constant LAMBDA_PRECISION = 10000;     // Precisión decimal
    uint256 public constant DECAY_PERIOD = 90 days;       // Período de renovación
    uint256 public constant RENEWAL_THRESHOLD = 500;      // 5% * 10000
    uint256 public constant REPUTATION_PRECISION = 10000; // 100% = 10000
    
    /**
     * @dev Cada experto es un sistema de memoria finita
     * Su reputación es su "energía" en el Valle de Resiliencia
     */
    struct Expert {
        uint256 reputation;      // Reputación actual (0-10000)
        uint256 lastUpdate;      // Timestamp última actualización
        uint256 contributions;   // Contador de validaciones
        bool active;             // Estado en la Cámara C1
    }
    
    mapping(address => Expert) public experts;
    address[] public expertList;
    
    // Eventos: el sistema comunica su estado
    event ReputationDecayed(
        address indexed expert, 
        uint256 oldReputation, 
        uint256 newReputation,
        uint256 daysElapsed
    );
    
    event ReputationRestored(
        address indexed expert, 
        uint256 boost,
        uint256 newReputation,
        string reason
    );
    
    event ExpertRemoved(
        address indexed expert, 
        uint256 finalReputation,
        uint256 totalContributions
    );
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
    }
```

### El corazón del sistema: calculando el decay

Aquí está la magia matemática. Implementar `e^(-λt)` en Solidity requiere aproximaciones, ya que no hay funciones exponenciales nativas. Usamos la **serie de Taylor**:
```
e^x ≈ 1 + x + x²/2! + x³/3! + x⁴/4! + x⁵/5! + ...
```

Para `x` negativo (decay), la serie converge rápidamente.
```solidity
    /**
     * @notice Calcula el decay exponencial usando la serie de Taylor
     * @param reputation Reputación actual del experto
     * @param timeElapsed Tiempo desde la última actualización (segundos)
     * @return Nueva reputación después del decay
     * 
     * Ejemplo: Si un experto con 10000 (100%) estuvo inactivo 21 días,
     * su reputación decae a ~4970 (49.7%), cerca de la vida media.
     */
    function calculateDecay(uint256 reputation, uint256 timeElapsed) 
        public 
        pure 
        returns (uint256) 
    {
        if (timeElapsed == 0) return reputation;
        
        // Convertir segundos a días con precisión
        uint256 daysElapsed = (timeElapsed * LAMBDA_PRECISION) / 1 days;
        
        // Calcular e^(-λt)
        int256 exponent = -int256((DECAY_LAMBDA * daysElapsed) / LAMBDA_PRECISION);
        uint256 decayFactor = exponentialDecay(exponent);
        
        // Aplicar decay: R(t) = R₀ · e^(-λt)
        return (reputation * decayFactor) / REPUTATION_PRECISION;
    }
    
    /**
     * @notice Aproximación de e^x mediante serie de Taylor (8 términos)
     * @dev Suficientemente precisa para decay exponencial
     * @param x Exponente (negativo para decay)
     * @return e^x * REPUTATION_PRECISION
     */
    function exponentialDecay(int256 x) internal pure returns (uint256) {
        int256 sum = int256(REPUTATION_PRECISION); // Término inicial: 1
        int256 term = int256(REPUTATION_PRECISION);
        
        // Iterar términos de la serie: x^n / n!
        for (uint256 i = 1; i <= 8; i++) {
            term = (term * x) / (int256(i) * int256(REPUTATION_PRECISION));
            sum += term;
            
            // Optimización: salir si el término es despreciable
            if (term < 10 && term > -10) break;
        }
        
        return sum > 0 ? uint256(sum) : 0;
    }
```

### Actualizando el decay: el ritual diario

Cada vez que el sistema consulta la reputación de un experto, **actualiza el decay automáticamente**. Es como una fotografía en tiempo real del estado del sistema.
```solidity
    /**
     * @notice Actualiza el decay de un experto específico
     * @param expertAddress Dirección del experto
     * 
     * Este es el "latido" del sistema: cada consulta actualiza el estado.
     * Si la reputación cae bajo el umbral del 5%, el experto es removido
     * automáticamente de la Cámara C1.
     */
    function updateDecay(address expertAddress) public {
        Expert storage expert = experts[expertAddress];
        require(expert.active, "Experto no activo en C1");
        
        uint256 timeElapsed = block.timestamp - expert.lastUpdate;
        uint256 oldReputation = expert.reputation;
        uint256 newReputation = calculateDecay(oldReputation, timeElapsed);
        
        expert.reputation = newReputation;
        expert.lastUpdate = block.timestamp;
        
        uint256 daysElapsed = timeElapsed / 1 days;
        
        emit ReputationDecayed(
            expertAddress, 
            oldReputation, 
            newReputation,
            daysElapsed
        );
        
        // Umbral crítico: renovación requerida
        if (newReputation < RENEWAL_THRESHOLD) {
            removeExpert(expertAddress);
        }
    }
    
    /**
     * @notice Actualiza todos los expertos activos en batch
     * @dev Llamada por el Oracle cada 24 horas
     */
    function updateAllExperts() external onlyRole(ORACLE_ROLE) {
        for (uint256 i = 0; i < expertList.length; i++) {
            if (experts[expertList[i]].active) {
                updateDecay(expertList[i]);
            }
        }
    }
```

### Renovación: el pulso de la contribución

La única forma de contrarrestar el decay es **contribuir**. Cada validación técnica, cada revisión de calidad, cada aporte al conocimiento colectivo restaura la reputación.
```solidity
    /**
     * @notice Restaura reputación mediante contribución
     * @param expertAddress Dirección del experto
     * @param reputationBoost Cantidad a restaurar (0-10000)
     * @param reason Descripción de la contribución
     * 
     * Ejemplos de contribuciones:
     * - Validación técnica de propuesta de C2: +2000 (20%)
     * - Auditoría de código: +3000 (30%)
     * - Publicación de investigación: +4000 (40%)
     * - Mentoría a nuevos expertos: +1500 (15%)
     */
    function boostReputation(
        address expertAddress, 
        uint256 reputationBoost,
        string memory reason
    ) external onlyRole(ORACLE_ROLE) {
        // Primero aplicar el decay acumulado
        updateDecay(expertAddress);
        
        Expert storage expert = experts[expertAddress];
        
        // Si el experto fue removido, reactivarlo
        if (!expert.active) {
            expert.active = true;
            expert.reputation = reputationBoost;
            expert.lastUpdate = block.timestamp;
            expertList.push(expertAddress);
        } else {
            // Incrementar reputación (máximo 100%)
            expert.reputation = Math.min(
                expert.reputation + reputationBoost,
                REPUTATION_PRECISION
            );
        }
        
        expert.contributions++;
        
        emit ReputationRestored(
            expertAddress, 
            reputationBoost,
            expert.reputation,
            reason
        );
    }
    
    /**
     * @notice Remueve un experto que cayó bajo el umbral
     * @dev No es un castigo, es un ciclo natural
     */
    function removeExpert(address expertAddress) internal {
        Expert storage expert = experts[expertAddress];
        expert.active = false;
        
        emit ExpertRemoved(
            expertAddress, 
            expert.reputation,
            expert.contributions
        );
    }
```

### Observabilidad: consultando el estado
```solidity
    /**
     * @notice Obtiene la reputación actual con decay aplicado (sin modificar estado)
     * @param expertAddress Dirección del experto
     * @return Reputación actual en tiempo real
     */
    function getCurrentReputation(address expertAddress) 
        external 
        view 
        returns (uint256) 
    {
        Expert memory expert = experts[expertAddress];
        if (!expert.active) return 0;
        
        uint256 timeElapsed = block.timestamp - expert.lastUpdate;
        return calculateDecay(expert.reputation, timeElapsed);
    }
    
    /**
     * @notice Lista todos los expertos activos en C1
     * @return Array de direcciones de expertos
     */
    function getActiveExperts() external view returns (address[] memory) {
        uint256 activeCount = 0;
        
        // Contar activos
        for (uint256 i = 0; i < expertList.length; i++) {
            if (experts[expertList[i]].active) {
                activeCount++;
            }
        }
        
        // Construir array filtrado
        address[] memory activeExperts = new address[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < expertList.length; i++) {
            if (experts[expertList[i]].active) {
                activeExperts[index] = expertList[i];
                index++;
            }
        }
        
        return activeExperts;
    }
    
    /**
     * @notice Calcula métricas de salud de la Cámara C1
     * @return avgReputation Reputación promedio
     * @return activeCount Número de expertos activos
     * @return totalContributions Contribuciones totales
     */
    function getChamberHealth() 
        external 
        view 
        returns (
            uint256 avgReputation,
            uint256 activeCount,
            uint256 totalContributions
        ) 
    {
        address[] memory actives = this.getActiveExperts();
        activeCount = actives.length;
        
        if (activeCount == 0) return (0, 0, 0);
        
        uint256 sumReputation = 0;
        totalContributions = 0;
        
        for (uint256 i = 0; i < activeCount; i++) {
            Expert memory expert = experts[actives[i]];
            uint256 timeElapsed = block.timestamp - expert.lastUpdate;
            sumReputation += calculateDecay(expert.reputation, timeElapsed);
            totalContributions += expert.contributions;
        }
        
        avgReputation = sumReputation / activeCount;
    }
}
```

---

## Visualizando el decay: Python y gráficas

Para entender intuitivamente el comportamiento del sistema, nada mejor que visualizarlo.
```python
import numpy as np
import matplotlib.pyplot as plt
from datetime import datetime, timedelta

# Parámetros del modelo
LAMBDA = 0.0333  # Constante de decaimiento
DAYS = 90        # Período completo
R0 = 100         # Reputación inicial

def reputation_decay(t, r0=R0, lam=LAMBDA):
    """
    Calcula la reputación en el día t
    R(t) = R₀ · e^(-λt)
    """
    return r0 * np.exp(-lam * t)

def days_to_threshold(threshold, r0=R0, lam=LAMBDA):
    """
    Calcula cuántos días toma llegar a un umbral
    t = -ln(threshold/R₀) / λ
    """
    return -np.log(threshold / r0) / lam

# Generar curva de decay
t = np.linspace(0, DAYS, 1000)
reputation = reputation_decay(t)

# Crear figura con dos gráficas
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))
fig.suptitle('Modelo de Decay Exponencial - Cámara de Expertos (C1)', 
             fontsize=16, fontweight='bold')

# ============================================================
# GRÁFICA 1: Curva principal de decay
# ============================================================
ax1.plot(t, reputation, 'b-', linewidth=2.5, label='Decay exponencial')
ax1.axhline(y=50, color='orange', linestyle='--', linewidth=1.5, 
            label=f'Vida media (50%) → {days_to_threshold(50):.1f} días')
ax1.axhline(y=5, color='red', linestyle='--', linewidth=1.5, 
            label='Umbral renovación (5%) → 90 días')

# Marcar puntos clave
key_days = [0, 7, 21, 45, 90]
for day in key_days:
    rep = reputation_decay(day)
    ax1.plot(day, rep, 'ko', markersize=8)
    ax1.annotate(f'{rep:.1f}%', 
                xy=(day, rep),
                xytext=(day, rep + 8),
                ha='center',
                fontsize=9,
                bbox=dict(boxstyle='round,pad=0.3', facecolor='yellow', alpha=0.7))

ax1.fill_between(t, 0, reputation, alpha=0.2, color='blue')
ax1.set_xlabel('Días transcurridos', fontsize=12, fontweight='bold')
ax1.set_ylabel('Reputación (%)', fontsize=12, fontweight='bold')
ax1.set_title('Decay de Reputación en 90 Días', fontsize=13)
ax1.grid(True, alpha=0.3, linestyle=':', linewidth=0.5)
ax1.legend(loc='upper right', fontsize=10)
ax1.set_xlim(0, DAYS)
ax1.set_ylim(0, 110)

# Sombrear zona crítica
ax1.axhspan(0, 5, alpha=0.15, color='red', label='Zona de renovación')

# ============================================================
# GRÁFICA 2: Comparación de diferentes velocidades de decay
# ============================================================
lambdas = [0.0167, 0.0333, 0.0666]
periods = [180, 90, 45]
labels = ['🐢 Conservador (180 días)', '⚡ Estándar (90 días)', '🔥 Agresivo (45 días)']
colors = ['green', 'blue', 'red']

for lam, period, label, color in zip(lambdas, periods, labels, colors):
    rep = reputation_decay(t, lam=lam)
    ax2.plot(t, rep, linewidth=2.5, label=label, color=color, alpha=0.8)
    
    # Marcar punto de 5%
    day_5pct = days_to_threshold(5, lam=lam)
    if day_5pct <= DAYS:
        ax2.plot(day_5pct, 5, 'o', color=color, markersize=10)

ax2.axhline(y=5, color='gray', linestyle='--', alpha=0.5, linewidth=1.5)
ax2.set_xlabel('Días transcurridos', fontsize=12, fontweight='bold')
ax2.set_ylabel('Reputación (%)', fontsize=12, fontweight='bold')
ax2.set_title('Comparación de Velocidades de Decay', fontsize=13)
ax2.grid(True, alpha=0.3, linestyle=':', linewidth=0.5)
ax2.legend(loc='upper right', fontsize=10)
ax2.set_xlim(0, DAYS)
ax2.set_ylim(0, 110)

plt.tight_layout()
plt.savefig('expert_decay_visualization.png', dpi=300, bbox_inches='tight')
plt.show()

# ============================================================
# TABLA DE DECAY
# ============================================================
print("\n" + "="*60)
print("  MODELO DE DECAY EXPONENCIAL - CÁMARA DE EXPERTOS (C1)")
print("="*60)
print(f"\nParámetros del sistema:")
print(f"  • Constante λ:             {LAMBDA:.4f}")
print(f"  • Período de renovación:   {DAYS} días")
print(f"  • Reputación inicial:      {R0}%")
print(f"  • Umbral crítico:          5%")
print(f"  • Vida media (50%):        {days_to_threshold(50):.1f} días")
print(f"  • Días hasta umbral (5%):  {days_to_threshold(5):.1f} días")

print(f"\n{'-'*60}")
print(f"{'Día':>5} │ {'Reputación':>11} │ {'Decay':>10} │ {'Estado':<20}")
print(f"{'-'*60}")

milestones = [0, 3, 7, 14, 21, 30, 45, 60, 75, 90]
for day in milestones:
    rep = reputation_decay(day)
    decay = R0 - rep
    
    # Determinar estado
    if rep >= 80:
        status = "✅ Excelente"
    elif rep >= 50:
        status = "✅ Activo"
    elif rep >= 20:
        status = "⚠️  Atención requerida"
    elif rep >= 5:
        status = "🔴 Crítico"
    else:
        status = "❌ Renovación obligatoria"
    
    print(f"{day:>5} │ {rep:>10.2f}% │ {decay:>9.2f}% │ {status}")

print(f"{'-'*60}\n")

# ============================================================
# SIMULACIÓN DE ESCENARIOS
# ============================================================
print("="*60)
print("  SIMULACIÓN DE ESCENARIOS")
print("="*60)

scenarios = [
    {
        'name': 'Experto inactivo (sin contribuciones)',
        'days': [0, 30, 60, 90],
        'boosts': [0, 0, 0, 0]
    },
    {
        'name': 'Experto constante (contribución mensual)',
        'days': [0, 30, 60, 90],
        'boosts': [0, 30, 30, 30]  # +30% cada mes
    },
    {
        'name': 'Experto intermitente (contribución irregular)',
        'days': [0, 20, 50, 90],
        'boosts': [0, 40, 0, 50]  # Picos de actividad
    }
]

for scenario in scenarios:
    print(f"\n{scenario['name']}:")
    print(f"{'-'*40}")
    rep = R0
    for i, day in enumerate(scenario['days']):
        if i > 0:
            days_elapsed = day - scenario['days'][i-1]
            rep = reputation_decay(days_elapsed, r0=rep)
        
        boost = scenario['boosts'][i]
        if boost > 0:
            rep = min(rep + boost, 100)
            print(f"  Día {day:>2}: {rep:>6.2f}% (+{boost}% por contribución)")
        else:
            print(f"  Día {day:>2}: {rep:>6.2f}%")
    
    if rep >= 5:
        print(f"  ✅ Estado final: ACTIVO ({rep:.2f}%)")
    else:
        print(f"  ❌ Estado final: REMOVIDO ({rep:.2f}%)")

print("\n" + "="*60 + "\n")
```

**Salida esperada:**
```
============================================================
  MODELO DE DECAY EXPONENCIAL - CÁMARA DE EXPERTOS (C1)
============================================================

Parámetros del sistema:
  • Constante λ:             0.0333
  • Período de renovación:   90 días
  • Reputación inicial:      100%
  • Umbral crítico:          5%
  • Vida media (50%):        20.8 días
  • Días hasta umbral (5%):  90.0 días

------------------------------------------------------------
  Día │  Reputación │      Decay │ Estado              
------------------------------------------------------------
    0 │     100.00% │      0.00% │ ✅ Excelente
    3 │      90.48% │      9.52% │ ✅ Excelente
    7 │      79.16% │     20.84% │ ✅ Activo
   14 │      62.66% │     37.34% │ ✅ Activo
   21 │      49.61% │     50.39% │ ⚠️  Atención requerida
   30 │      36.79% │     63.21% │ ⚠️  Atención requerida
   45 │      22.31% │     77.69% │ ⚠️  Atención requerida
   60 │      13.53% │     86.47% │ 🔴 Crítico
   75 │       8.21% │     91.79% │ 🔴 Crítico
   90 │       4.98% │     95.02% │ ❌ Renovación obligatoria
------------------------------------------------------------
```

---

## Integración con el Valle de Resiliencia

El decay exponencial no es un sistema aislado. Se conecta directamente con el **índice de resiliencia R** de la FMD-DAO:
```
R = τ × Ω
```

Donde:
- **τ (tau)**: memoria del sistema = reputación promedio normalizada
- **Ω (omega)**: frecuencia de revisión = número de expertos activos normalizado
```solidity
/**
 * @notice Calcula el índice R de la Cámara de Expertos
 * @return R normalizado (debe estar entre 1 y 3 para mantener resiliencia)
 * 
 * Interpretación:
 * - R < 1:  Sistema amnésico (muy pocos expertos o muy baja reputación)
 * - 1 < R < 3: Valle de Resiliencia (óptimo)
 * - R > 3: Sistema rígido (demasiados expertos o reputación congelada)
 */
function calculateResilienceIndex() external view returns (uint256) {
    address[] memory actives = this.getActiveExperts();
    uint256 activeCount = actives.length;
    
    if (activeCount == 0) return 0; // Sistema colapsado
    
    // Calcular reputación promedio con decay aplicado
    uint256 avgReputation = 0;
    for (uint256 i = 0; i < activeCount; i++) {
        Expert memory expert = experts[actives[i]];
        uint256 timeElapsed = block.timestamp - expert.lastUpdate;
        avgReputation += calculateDecay(expert.reputation, timeElapsed);
    }
    avgReputation /= activeCount;
    
    // τ (memoria) = reputación promedio normalizada a escala 0-3
    uint256 tau = (avgReputation * 300) / REPUTATION_PRECISION; // 0-3 con 2 decimales
    
    // Ω (frecuencia) = número de expertos normalizado
    // Asumimos óptimo: 10 expertos → Ω = 1.5
    uint256 omega = activeCount >= 20 ? 300 : (activeCount * 15); // 0-3 con 2 decimales
    
    // R = τ × Ω (multiplicar y luego normalizar)
    uint256 R = (tau * omega) / 100; // Resultado en escala 0-9 (equivalente a 0-3 real)
    
    return R;
}

/**
 * @notice Verifica si el sistema está en el Valle de Resiliencia
 * @return inValley True si 1 < R < 3
 * @return currentR Valor actual de R
 */
function isInResilienceValley() external view returns (bool inValley, uint256 currentR) {
    currentR = this.calculateResilienceIndex();
    inValley = (currentR > 100 && currentR < 300); // 1.00 < R < 3.00
}
```

---

## Testing: validando el modelo
```javascript
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ExpertReputationDecay - Tests del Valle", function () {
  let contract;
  let owner, expert1, expert2, expert3;

  beforeEach(async function () {
    [owner, expert1, expert2, expert3] = await ethers.getSigners();
    const Contract = await ethers.getContractFactory("ExpertReputationDecay");
    contract = await Contract.deploy();
  });

  describe("🧪 Decay exponencial", function () {
    it("Debe decaer al 50% en ~21 días (vida media)", async function () {
      // Inicializar experto con 100%
      await contract.boostReputation(expert1.address, 10000, "Contribución inicial");
      
      // Avanzar 21 días
      await ethers.provider.send("evm_increaseTime", [21 * 24 * 60 * 60]);
      await ethers.provider.send("evm_mine");
      
      // Verificar decay
      const reputation = await contract.getCurrentReputation(expert1.address);
      
      // Debe estar cerca del 50% (±2% de tolerancia)
      expect(reputation).to.be.closeTo(5000, 200);
      console.log(`    ✓ Reputación después de 21 días: ${reputation / 100}%`);
    });

    it("Debe decaer al ~5% en 90 días", async function () {
      await contract.boostReputation(expert1.address, 10000, "Contribución inicial");
      
      // Avanzar 90 días
      await ethers.provider.send("evm_increaseTime", [90 * 24 * 60 * 60]);
      await ethers.provider.send("evm_mine");
      
      const reputation = await contract.getCurrentReputation(expert1.address);
      
      // Debe estar cerca del 5% (±1%)
      expect(reputation).to.be.closeTo(500, 100);
      console.log(`    ✓ Reputación después de 90 días: ${reputation / 100}%`);
    });

    it("Debe remover experto bajo el umbral del 5%", async function () {
      await contract.boostReputation(expert1.address, 10000, "Contribución inicial");
      
      // Avanzar 90 días
      await ethers.provider.send("evm_increaseTime", [90 * 24 * 60 * 60]);
      await ethers.provider.send("evm_mine");
      
      // Actualizar decay (triggerea remoción)
      await contract.updateDecay(expert1.address);
      
      const expert = await contract.experts(expert1.address);
      expect(expert.active).to.be.false;
      console.log(`    ✓ Experto removido automáticamente`);
    });
  });

  describe("🔄 Sistema de renovación", function () {
    it("Debe restaurar reputación con contribuciones", async function () {
      await contract.boostReputation(expert1.address, 5000, "Primera contribución");
      
      // Avanzar 30 días (decay a ~18%)
      await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]);
      
      // Nueva contribución (+30%)
      await contract.boostReputation(expert1.address, 3000, "Validación técnica");
      
      const reputation = await contract.getCurrentReputation(expert1.address);
      expect(reputation).to.be.gte(3000);
      console.log(`    ✓ Reputación restaurada: ${reputation / 100}%`);
    });

    it("Debe reactivar experto removido con nueva contribución", async function () {
      await contract.boostReputation(expert1.address, 10000, "Contribución inicial");
      
      // Avanzar 90 días (remoción automática)
      await ethers.provider.send("evm_increaseTime", [90 * 24 * 60 * 60]);
      await ethers.provider.send("evm_mine");
      await contract.updateDecay(expert1.address);
      
      let expert = await contract.experts(expert1.address);
      expect(expert.active).to.be.false;
      
      // Reactivar con nueva contribución
      await contract.boostReputation(expert1.address, 5000, "Reactivación");
      
      expert = await contract.experts(expert1.address);
      expect(expert.active).to.be.true;
      expect(expert.reputation).to.equal(5000);
      console.log(`    ✓ Experto reactivado con 50% de reputación`);
    });

    it("No debe exceder 100% de reputación", async function () {
      await contract.boostReputation(expert1.address, 8000, "Primera contribución");
      await contract.boostReputation(expert1.address, 5000, "Segunda contribución");
      
      const reputation = await contract.getCurrentReputation(expert1.address);
      expect(reputation).to.equal(10000); // Máximo 100%
      console.log(`    ✓ Reputación limitada al 100%`);
    });
  });

  describe("🏔️ Valle de Resiliencia", function () {
    it("Debe calcular R dentro del valle con múltiples expertos", async function () {
      // Añadir 5 expertos con diferentes reputaciones
      await contract.boostReputation(expert1.address, 8000, "Experto 1");
      await contract.boostReputation(expert2.address, 7000, "Experto 2");
      await contract.boostReputation(expert3.address, 6000, "Experto 3");
      
      const R = await contract.calculateResilienceIndex();
      const inValley = await contract.isInResilienceValley();
      
      console.log(`    ✓ Índice R: ${R / 100}`);
      console.log(`    ✓ En el Valle: ${inValley[0]}`);
      
      expect(inValley[0]).to.be.true;
    });

    it("Debe detectar colapso cuando todos los expertos son removidos", async function () {
      await contract.boostReputation(expert1.address, 10000, "Experto único");
      
      // Avanzar 90 días
      await ethers.provider.send("evm_increaseTime", [90 * 24 * 60 * 60]);
      await ethers.provider.send("evm_mine");
      await contract.updateDecay(expert1.address);
      
      const R = await contract.calculateResilienceIndex();
      expect(R).to.equal(0); // Sistema colapsado
      console.log(`    ✓ Sistema detecta colapso (R = 0)`);
    });
  });

  describe("📊 Métricas de salud", function () {
    it("Debe calcular salud de la cámara correctamente", async function () {
      await contract.boostReputation(expert1.address, 8000, "Contribución 1");
      await contract.boostReputation(expert1.address, 0, "Contribución 2");
      await contract.boostReputation(expert2.address, 6000, "Contribución 3");
      
      const health = await contract.getChamberHealth();
      
      console.log(`    ✓ Reputación promedio: ${health.avgReputation / 100}%`);
      console.log(`    ✓ Expertos activos: ${health.activeCount}`);
      console.log(`    ✓ Contribuciones totales: ${health.totalContributions}`);
      
      expect(health.activeCount).to.equal(2);
      expect(health.totalContributions).to.equal(3);
    });
  });
});
```

**Ejecutar tests:**
```bash
npx hardhat test test/ExpertDecay.test.js
```

---

## Casos de uso reales

### Escenario 1: El experto diligente

**Perfil:** María, científica de datos especializada en modelos climáticos
```
Día 0:   100% - Valida propuesta de reforestación (R_gov = 2.1)
Día 15:  65%  - Contribuye sin compensación adicional
Día 30:  42%  - Publica paper sobre captura de carbono → +40%
Día 30:  82%  - Nueva reputación después del boost
Día 50:  58%  - Mentoría a nuevos expertos → +20%
Día 50:  78%  - Sistema reconoce consistencia
Día 70:  52%  - Audita propuesta técnica → +30%
Día 70:  82%  - Mantiene autoridad técnica
Día 90:  58%  - Aún activa, no requiere renovación
```

**Resultado:** María mantiene su rol en C1 mediante contribuciones regulares y de calidad.

---

### Escenario 2: El experto intermitente

**Perfil:** Carlos, desarrollador blockchain con alta carga de trabajo externa
```
Día 0:   100% - Valida arquitectura de smart contract
Día 30:  37%  - Sin contribuciones (ocupado en proyecto externo)
Día 60:  13%  - Alerta del sistema: reputación crítica
Día 65:  10%  - Carlos regresa, valida urgentemente → +50%
Día 65:  60%  - Recupera posición
Día 90:  30%  - Cae nuevamente por inactividad
Día 95:  25%  - Contribución final → +40%
Día 95:  65%  - Logra mantener el rol
```

**Resultado:** Carlos aprende que la intermitencia tiene costo. El sistema lo obliga a ser más consistente o delegar.

---

### Escenario 3: El experto que abandona

**Perfil:** Lucía, economista que cambia de intereses profesionales
```
Día 0:   100% - Última contribución registrada
Día 30:  37%  - Sin actividad
Día 60:  13%  - Sin actividad
Día 90:  5%   - Sistema activa proceso de remoción
Día 91:  <5%  - Lucía es removida automáticamente de C1
```

**Resultado:** El sistema reconoce naturalmente cuando un experto ya no está activo. No es un castigo, es un ciclo. Lucía puede regresar en el futuro si lo desea.

---

## Configuraciones alternativas

El modelo es paramétrico. Puedes ajustar λ según la naturaleza de tu DAO:

| Tipo de DAO | λ | Período | Vida media | Uso |
|-------------|---|---------|------------|-----|
| **Investigación académica** | 0.0167 | 180 días | ~42 días | Proyectos de largo plazo |
| **Desarrollo tecnológico** | 0.0333 | 90 días | ~21 días | Equilibrio estándar |
| **Respuesta a emergencias** | 0.0666 | 45 días | ~10 días | Alta rotación, urgencia |
| **Governance lenta** | 0.0111 | 270 días | ~62 días | Decisiones estratégicas |

---

## Reflexión final: ¿Por qué esto importa?

En la mayoría de sistemas de gobernanza (desde empresas hasta Estados) la autoridad se acumula sin fricción. Quien llega primero, quien grita más fuerte, quien tiene más capital, **congela su poder**. El resultado inevitable es la rigidez, la captura, el colapso.

La FMD-DAO propone algo radicalmente distinto: **la autoridad como flujo, no como propiedad**. Un experto no "tiene" reputación, la **mantiene activamente** mediante contribución continua. Es termodinámica aplicada a la gobernanza: todo sistema vivo necesita disipar entropía para mantenerse lejos del equilibrio.

El decay exponencial no es un castigo. Es un reconocimiento de que:

1. **El conocimiento caduca** → La blockchain de 2023 no es la de 2025
2. **La participación es prueba de relevancia** → Si no contribuyes, ¿por qué tu voz debería pesar?
3. **El olvido es salud** → Un sistema que recuerda todo colapsa bajo su propio peso

En el Valle de Resiliencia, la memoria finita permite que nuevas voces emerjan sin destruir la sabiduría acumulada. Es el espacio donde **la juventud y la experiencia coexisten en tensión productiva**.

Esto no es solo una DAO. Es un **organismo cognitivo** que respira.

---

## Licencia

MIT License - Ernesto Cisneros Cino

## Contribuciones

Las mejoras a este modelo siguen el principio bicameral de la FMD-DAO:
1. **Propuesta en C2** (Comunes): abre un issue explicando la mejora
2. **Revisión en C1** (Expertos): validación técnica y matemática
3. **Implementación**: merge después de ambas aprobaciones

---

**Autor:** Ernesto Cisneros Cino  
**Contacto:** [ernestocisnerosmusic@gmail.com]  

---

*"Un sistema que no olvida, olvida que debe vivir."*
