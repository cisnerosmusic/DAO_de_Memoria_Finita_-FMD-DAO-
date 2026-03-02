"""
FMD-DAO · Simulación Integrada
================================
Simula en paralelo cinco sistemas interdependientes:

  1. Rotación de oráculos       — score, eligibilidad, anti-dictadura
  2. Decay reputacional 5D      — dimensiones con λ diferenciado, 4 patrones
  3. Sistema inmunológico       — Threat Score, severidad, quórum dinámico
  4. Oscilador ideológico       — rigidez, peso de voto ajustado
  5. Valle de Resiliencia       — R = τ × Ω, posición respecto a 1 < R < 3

Autor:  Ernesto Cisneros Cino — FMD-DAO
Repo:   https://github.com/cisnerosmusic/DAO_de_Memoria_Finita_-FMD-DAO-
Modelo: R = τ × Ω, Valle de Resiliencia: 1 < R < 3

Dependencias:
  pip install numpy pandas plotly

Uso:
  python fmd_dao_sim.py            # genera fmd_dao_simulacion.html
  python fmd_dao_sim.py --no-html  # solo resumen en consola
"""

import math
import random
import sys
import numpy as np
import plotly.graph_objects as go
from plotly.subplots import make_subplots

random.seed(42)
np.random.seed(42)

# ─── PARÁMETROS GLOBALES ──────────────────────────────────────────────────────

CICLOS         = 24           # ciclos a simular
DIAS_POR_CICLO = 30           # días por ciclo (ritual trimestral = 90 días = 3 ciclos)
LAMBDA_BASE    = math.log(2) / 60   # λ base: vida media 60 días

# Parámetros del Valle de Resiliencia
TAU_BASE       = 60.0         # memoria base en días
OMEGA_BASE     = 1 / 36.0     # frecuencia base: 1 decisión cada 36 días
VALLEY_LO      = 1.0          # límite inferior del Valle
VALLEY_HI      = 3.0          # límite superior del Valle

# ─── UTILIDADES ───────────────────────────────────────────────────────────────

def decay_exp(score: float, dias: float, lambda_factor: float = 1.0) -> float:
    """Decay exponencial: score × e^(−λ × factor × días)"""
    return score * math.exp(-LAMBDA_BASE * lambda_factor * dias)

def clamp(val: float, lo: float = 0.0, hi: float = 10_000.0) -> float:
    return max(lo, min(hi, val))

def in_valley(R: float) -> bool:
    return VALLEY_LO < R < VALLEY_HI

# ─── 1. ROTACIÓN DE ORÁCULOS ──────────────────────────────────────────────────

class OracleProvider:
    def __init__(self, name: str, initial_score: float, reliability: float):
        self.name            = name
        self.score           = initial_score
        self.reliability     = reliability
        self.cycles_waiting  = 0
        self.status          = "INACTIVE"
        self.last_active     = -999
        self.history         = []

    def eligibility(self) -> float:
        wait_bonus = min(self.cycles_waiting * 500, 3000)
        return clamp(self.score + wait_bonus)

    def record(self):
        self.history.append(round(self.score))

    def apply_inactivity_decay(self, dias: float):
        self.score = clamp(decay_exp(self.score, dias, lambda_factor=0.7))


class OracleSystem:
    def __init__(self):
        self.providers = [
            OracleProvider("Chainlink-VRF",  8500, reliability=0.95),
            OracleProvider("Drand-Beacon",   7800, reliability=0.90),
            OracleProvider("C1-Consenso",    7200, reliability=0.85),
            OracleProvider("API3-QRNG",      6500, reliability=0.80),
            OracleProvider("UMA-Optimistic", 6000, reliability=0.75),
        ]
        self.active_idx   = None
        self.standby_idx  = None
        self.rotation_log = []   # (ciclo, activo, standby)
        self._select_initial()

    def _select_initial(self):
        scores     = [p.eligibility() for p in self.providers]
        sorted_idx = sorted(range(len(scores)), key=lambda i: scores[i], reverse=True)
        self.active_idx  = sorted_idx[0]
        self.standby_idx = sorted_idx[1]
        self.providers[self.active_idx].status  = "ACTIVE"
        self.providers[self.standby_idx].status = "STANDBY"

    def step(self, ciclo: int):
        for i, p in enumerate(self.providers):
            if p.status == "ACTIVE":
                roll = random.random()
                if roll < p.reliability:
                    p.score = clamp(p.score + 100)    # confirmado
                elif roll < p.reliability + 0.08:
                    p.score = clamp(p.score - 50)     # STALE
                else:
                    p.score = clamp(p.score - 300)    # refutado
            elif p.status == "INACTIVE":
                p.apply_inactivity_decay(DIAS_POR_CICLO)
                p.cycles_waiting += 1

        # Suspensión automática
        for p in self.providers:
            if p.score < 1000:
                p.status = "ELIMINATED"
            elif p.score < 3000 and p.status not in ("ACTIVE", "STANDBY", "ELIMINATED"):
                p.status = "SUSPENDED"

        # Degradar activo y standby
        prev_active  = self.active_idx
        prev_standby = self.standby_idx

        self.providers[prev_active].status        = "INACTIVE"
        self.providers[prev_active].cycles_waiting = 0
        if prev_standby != prev_active:
            self.providers[prev_standby].status        = "INACTIVE"
            self.providers[prev_standby].cycles_waiting += 1

        # Seleccionar nuevo par por eligibilityScore (excluir activo previo)
        eligible = [
            (i, p.eligibility())
            for i, p in enumerate(self.providers)
            if p.status not in ("SUSPENDED", "ELIMINATED") and i != prev_active
        ]
        eligible.sort(key=lambda x: x[1], reverse=True)

        if len(eligible) >= 2:
            self.active_idx  = eligible[0][0]
            self.standby_idx = eligible[1][0]
        elif len(eligible) == 1:
            self.active_idx  = eligible[0][0]
            self.standby_idx = eligible[0][0]
        # Si no hay elegibles, mantener (no debería ocurrir con 5 proveedores)

        self.providers[self.active_idx].status        = "ACTIVE"
        self.providers[self.active_idx].cycles_waiting = 0
        if self.active_idx != self.standby_idx:
            self.providers[self.standby_idx].status = "STANDBY"

        self.rotation_log.append((
            ciclo,
            self.providers[self.active_idx].name,
            self.providers[self.standby_idx].name,
        ))

        for p in self.providers:
            p.record()

# ─── 2. DECAY REPUTACIONAL 5D ─────────────────────────────────────────────────

LAMBDA_FACTORS = {
    "Propuesta":    0.80,
    "Validacion":   0.50,
    "Comprension":  1.20,
    "Oscilacion":   0.90,
    "Colaboracion": 0.60,
}


class Member:
    def __init__(self, name: str, pattern: str):
        """
        Patrones de actividad:
          constante  — contribuye uniformemente cada ciclo
          burst      — períodos de alta actividad y silencio
          declinante — empieza fuerte y se desconecta
          emergente  — empieza tarde pero crece con fuerza
        """
        self.name    = name
        self.pattern = pattern
        self.rep     = {dim: 5000.0 for dim in LAMBDA_FACTORS}
        self.history = {dim: [] for dim in LAMBDA_FACTORS}

    def activity_level(self, ciclo: int) -> float:
        if self.pattern == "constante":
            return 0.8 + random.uniform(-0.1, 0.1)
        elif self.pattern == "burst":
            return 0.9 if (ciclo % 12) < 6 else 0.05
        elif self.pattern == "declinante":
            return max(0.05, 0.95 - ciclo * 0.035)
        elif self.pattern == "emergente":
            return min(0.95, 0.05 + ciclo * 0.04)
        return 0.5

    def step(self, ciclo: int):
        level = self.activity_level(ciclo)
        for dim, lf in LAMBDA_FACTORS.items():
            self.rep[dim] = clamp(decay_exp(self.rep[dim], DIAS_POR_CICLO, lf))
            boost         = level * random.uniform(200, 600)
            self.rep[dim] = clamp(self.rep[dim] + boost)
            self.history[dim].append(round(self.rep[dim]))


class ReputationSystem:
    def __init__(self):
        self.members = [
            Member("Ana (constante)",  "constante"),
            Member("Bruno (burst)",    "burst"),
            Member("Clara (declina)",  "declinante"),
            Member("Diego (emerge)",   "emergente"),
        ]

    def step(self, ciclo: int):
        for m in self.members:
            m.step(ciclo)

    def gini(self) -> float:
        """Gini del score agregado de todos los miembros en el ciclo actual"""
        scores = [sum(m.rep.values()) / len(m.rep) for m in self.members]
        n      = len(scores)
        total  = sum(scores)
        if total == 0:
            return 0.0
        diff_sum = sum(
            abs(scores[i] - scores[j])
            for i in range(n) for j in range(n)
        )
        return diff_sum / (2 * n * total)

# ─── 3. SISTEMA INMUNOLÓGICO ──────────────────────────────────────────────────

SEVERITY_MAP = {
    (0,  3):  ("VERDE",    "#2ecc71"),
    (4,  6):  ("AMARILLO", "#f1c40f"),
    (7,  9):  ("NARANJA",  "#e67e22"),
    (10, 16): ("ROJO",     "#e74c3c"),
}

def classify_severity(score: int):
    for (lo, hi), result in SEVERITY_MAP.items():
        if lo <= score <= hi:
            return result
    return ("ROJO", "#e74c3c")

def classify_velocity(dsdt: float) -> str:
    if dsdt < 2:   return "LOGARÍTMICA"
    elif dsdt < 5: return "LINEAL"
    return "EXPONENCIAL"


class ImmuneSystem:
    def __init__(self):
        self.threat_history   = []
        self.severity_history = []
        self.color_history    = []
        self.velocity_history = []
        self.quorum_history   = []
        self.prev_score       = 0

    def _generate_threat(self, ciclo: int) -> int:
        # Crisis aguda ciclos 8–11
        if ciclo == 8:  return random.randint(10, 14)
        if ciclo in (9, 10): return random.randint(6, 10)
        if ciclo == 11: return random.randint(3, 6)
        # Crisis moderada ciclos 17–19
        if ciclo == 17: return random.randint(7, 10)
        if ciclo in (18, 19): return random.randint(4, 8)
        return random.randint(0, 3)

    def step(self, ciclo: int):
        score           = self._generate_threat(ciclo)
        dsdt            = abs(score - self.prev_score)
        label, color    = classify_severity(score)
        velocity        = classify_velocity(dsdt)

        quorum_map = {
            "VERDE":    10,
            "AMARILLO": 15,
            "NARANJA":  25,
        }
        quorum = quorum_map.get(label, 40 if velocity == "EXPONENCIAL" else 30)

        self.threat_history.append(score)
        self.severity_history.append(label)
        self.color_history.append(color)
        self.velocity_history.append(velocity)
        self.quorum_history.append(quorum)
        self.prev_score = score

# ─── 4. OSCILADOR IDEOLÓGICO ──────────────────────────────────────────────────

class IdeologicalMember:
    def __init__(self, name: str, rigidity_tendency: float):
        self.name              = name
        self.rigidity_tendency = rigidity_tendency
        self.vote_history      = []
        self.rigidity_history  = []
        self.weight_history    = []

    def step(self, ciclo: int):
        if not self.vote_history:
            vote = random.randint(0, 1)
        else:
            stay = random.random() < self.rigidity_tendency
            vote = self.vote_history[-1] if stay else 1 - self.vote_history[-1]

        self.vote_history.append(vote)

        window = self.vote_history[-6:]
        if len(window) < 2:
            rigidity = 0.0
        else:
            changes    = sum(1 for i in range(1, len(window)) if window[i] != window[i - 1])
            flexibility = changes / (len(window) - 1)
            rigidity   = 1.0 - flexibility

        alpha  = 0.30
        weight = 10_000 * (1 - alpha * rigidity)
        weight = max(weight, 5_000)   # mínimo 50%

        self.rigidity_history.append(round(rigidity * 100, 1))
        self.weight_history.append(round(weight))


class IdeologicalSystem:
    def __init__(self):
        self.members = [
            IdeologicalMember("Elena (flexible)",  rigidity_tendency=0.30),
            IdeologicalMember("Felipe (moderado)", rigidity_tendency=0.55),
            IdeologicalMember("Greta (rígida)",    rigidity_tendency=0.80),
            IdeologicalMember("Héctor (errático)", rigidity_tendency=0.45),
        ]

    def step(self, ciclo: int):
        for m in self.members:
            m.step(ciclo)

# ─── 5. VALLE DE RESILIENCIA ──────────────────────────────────────────────────

class ResilienceValley:
    """
    R = τ × Ω
    τ (tau): memoria efectiva en días — influenciada por el decay reputacional
    Ω (omega): frecuencia de decisiones — influenciada por el sistema inmune
    Valle: 1 < R < 3
    """
    def __init__(self):
        self.tau_history   = []
        self.omega_history = []
        self.R_history     = []
        self.valley_history = []   # True = dentro del Valle

    def step(self, rep_system: ReputationSystem, immune_system: ImmuneSystem):
        # τ: se reduce cuando el decay reputacional es alto
        # Aproximación: τ_efectivo = τ_base × (avg_score / MAX_SCORE)
        scores = [
            sum(m.rep.values()) / len(m.rep)
            for m in rep_system.members
        ]
        avg_score = sum(scores) / len(scores)
        tau = TAU_BASE * (avg_score / 10_000)
        tau = max(tau, 5.0)   # τ mínimo: 5 días

        # Ω: se ajusta por severidad del sistema inmune
        # En crisis: más decisiones urgentes → Ω sube
        severity = immune_system.severity_history[-1] if immune_system.severity_history else "VERDE"
        omega_multipliers = {
            "VERDE":    1.0,
            "AMARILLO": 1.2,
            "NARANJA":  1.6,
            "ROJO":     2.2,
        }
        omega = OMEGA_BASE * omega_multipliers.get(severity, 1.0)

        R = tau * omega

        self.tau_history.append(round(tau, 2))
        self.omega_history.append(round(omega, 4))
        self.R_history.append(round(R, 3))
        self.valley_history.append(in_valley(R))

# ─── SIMULACIÓN PRINCIPAL ─────────────────────────────────────────────────────

def run_simulation():
    oracle   = OracleSystem()
    rep      = ReputationSystem()
    immune   = ImmuneSystem()
    ideo     = IdeologicalSystem()
    valley   = ResilienceValley()

    ciclos = list(range(1, CICLOS + 1))

    for c in ciclos:
        oracle.step(c)
        rep.step(c)
        immune.step(c)
        ideo.step(c)
        valley.step(rep, immune)

    return oracle, rep, immune, ideo, valley, ciclos

# ─── DASHBOARD ────────────────────────────────────────────────────────────────

def build_dashboard(oracle, rep, immune, ideo, valley, ciclos):

    fig = make_subplots(
        rows=5, cols=2,
        subplot_titles=[
            "Scores de Proveedores de Oráculo",
            "Proveedor Activo por Ciclo",
            "Reputación 5D — Ana (constante)",
            "Reputación 5D — Bruno (burst)",
            "Threat Score y Severidad",
            "Quórum Ajustado por Crisis (%)",
            "Rigidez Ideológica (%)",
            "Peso de Voto Ajustado (BPS)",
            "τ y Ω — Parámetros del Valle",
            "R = τ × Ω — Valle de Resiliencia",
        ],
        vertical_spacing=0.07,
        horizontal_spacing=0.08,
    )

    PALETTE = ["#3498db", "#e74c3c", "#2ecc71", "#f39c12", "#9b59b6", "#1abc9c"]

    # ── 1a. Scores de oráculos ────────────────────────────────────────────────
    for i, p in enumerate(oracle.providers):
        fig.add_trace(go.Scatter(
            x=ciclos, y=p.history,
            name=p.name,
            mode="lines+markers",
            line=dict(color=PALETTE[i], width=2),
            marker=dict(size=4),
            legendgroup="oracle",
            legendgrouptitle_text="Oráculos" if i == 0 else None,
        ), row=1, col=1)

    for umbral, label, color in [(3000, "Suspensión", "#e74c3c"), (1000, "Eliminación", "#7f0000")]:
        fig.add_hline(y=umbral, line_dash="dash", line_color=color,
                      annotation_text=label, annotation_position="right",
                      row=1, col=1)

    # ── 1b. Proveedor activo ──────────────────────────────────────────────────
    nombres  = [p.name for p in oracle.providers]
    activos  = [r[1] for r in oracle.rotation_log]
    y_activos = [nombres.index(a) for a in activos]

    fig.add_trace(go.Scatter(
        x=ciclos, y=y_activos,
        mode="lines+markers",
        name="Proveedor activo",
        line=dict(color="#3498db", width=2, shape="hv"),
        marker=dict(size=8, symbol="diamond"),
        legendgroup="oracle",
        showlegend=False,
        customdata=activos,
        hovertemplate="Ciclo %{x}<br>Activo: %{customdata}<extra></extra>",
    ), row=1, col=2)
    fig.update_yaxes(tickvals=list(range(len(nombres))), ticktext=nombres, row=1, col=2)

    # ── 2. Reputación 5D ──────────────────────────────────────────────────────
    dim_colors = {
        "Propuesta":    "#3498db",
        "Validacion":   "#e74c3c",
        "Comprension":  "#2ecc71",
        "Oscilacion":   "#f39c12",
        "Colaboracion": "#9b59b6",
    }
    for col_i, member in enumerate([rep.members[0], rep.members[1]]):
        for dim, color in dim_colors.items():
            fig.add_trace(go.Scatter(
                x=ciclos, y=member.history[dim],
                name=dim,
                mode="lines",
                line=dict(color=color, width=2),
                legendgroup="rep_" + dim,
                legendgrouptitle_text="Dimensiones" if col_i == 0 and dim == "Propuesta" else None,
                showlegend=(col_i == 0),
            ), row=2, col=col_i + 1)

    # ── 3a. Threat Score (barras con color de severidad) ──────────────────────
    for i in range(len(ciclos)):
        fig.add_trace(go.Bar(
            x=[ciclos[i]], y=[immune.threat_history[i]],
            marker_color=immune.color_history[i],
            showlegend=False,
            hovertemplate=(
                f"Ciclo {ciclos[i]}<br>"
                f"Score: {immune.threat_history[i]}<br>"
                f"Severidad: {immune.severity_history[i]}<br>"
                f"Velocidad: {immune.velocity_history[i]}"
                "<extra></extra>"
            ),
        ), row=3, col=1)

    for y, label, color in [(3, "Verde/Amarillo", "#f1c40f"),
                             (6, "Amarillo/Naranja", "#e67e22"),
                             (9, "Naranja/Rojo", "#e74c3c")]:
        fig.add_hline(y=y, line_dash="dot", line_color=color,
                      annotation_text=label, annotation_position="right",
                      row=3, col=1)

    # ── 3b. Quórum ────────────────────────────────────────────────────────────
    fig.add_trace(go.Scatter(
        x=ciclos, y=immune.quorum_history,
        mode="lines+markers",
        name="Quórum (%)",
        line=dict(color="#9b59b6", width=2),
        marker=dict(color=immune.color_history, size=8, line=dict(width=1, color="white")),
        legendgroup="immune",
    ), row=3, col=2)
    fig.add_hline(y=10, line_dash="dash", line_color="#2ecc71",
                  annotation_text="Normal 10%", row=3, col=2)
    fig.add_hline(y=40, line_dash="dash", line_color="#e74c3c",
                  annotation_text="Crisis 40%", row=3, col=2)

    # ── 4. Oscilador ──────────────────────────────────────────────────────────
    ideo_colors = ["#3498db", "#e74c3c", "#e67e22", "#2ecc71"]
    for i, m in enumerate(ideo.members):
        fig.add_trace(go.Scatter(
            x=ciclos, y=m.rigidity_history,
            name=m.name,
            mode="lines+markers",
            line=dict(color=ideo_colors[i], width=2),
            marker=dict(size=4),
            legendgroup="ideo",
            legendgrouptitle_text="Miembros" if i == 0 else None,
        ), row=4, col=1)
        fig.add_trace(go.Scatter(
            x=ciclos, y=m.weight_history,
            name=m.name,
            mode="lines",
            line=dict(color=ideo_colors[i], width=2),
            legendgroup="ideo",
            showlegend=False,
        ), row=4, col=2)

    fig.add_hline(y=70, line_dash="dash", line_color="#e74c3c",
                  annotation_text="Rigidez alta", row=4, col=1)
    fig.add_hline(y=5000, line_dash="dash", line_color="#e74c3c",
                  annotation_text="Mínimo 50%", row=4, col=2)
    fig.add_hline(y=10000, line_dash="dot", line_color="#2ecc71",
                  annotation_text="Máximo 100%", row=4, col=2)

    # ── 5a. τ y Ω ─────────────────────────────────────────────────────────────
    fig.add_trace(go.Scatter(
        x=ciclos, y=valley.tau_history,
        name="τ (días)",
        mode="lines+markers",
        line=dict(color="#3498db", width=2),
        marker=dict(size=4),
        legendgroup="valley",
        legendgrouptitle_text="Valle R=τ×Ω" ,
    ), row=5, col=1)
    fig.add_trace(go.Scatter(
        x=ciclos,
        y=[round(o * 1000, 2) for o in valley.omega_history],  # ×1000 para legibilidad
        name="Ω × 1000",
        mode="lines+markers",
        line=dict(color="#e74c3c", width=2, dash="dot"),
        marker=dict(size=4),
        legendgroup="valley",
    ), row=5, col=1)

    # ── 5b. R = τ × Ω con banda del Valle ────────────────────────────────────
    valley_colors = ["#2ecc71" if v else "#e74c3c" for v in valley.valley_history]

    fig.add_trace(go.Scatter(
        x=ciclos, y=valley.R_history,
        mode="lines+markers",
        name="R = τ × Ω",
        line=dict(color="#2c3e50", width=2),
        marker=dict(color=valley_colors, size=8, line=dict(width=1, color="white")),
        legendgroup="valley",
        showlegend=False,
        hovertemplate="Ciclo %{x}<br>R = %{y:.3f}<extra></extra>",
    ), row=5, col=2)

    # Banda del Valle (1 < R < 3)
    fig.add_hrect(
        y0=VALLEY_LO, y1=VALLEY_HI,
        fillcolor="rgba(46, 204, 113, 0.12)",
        line_width=0,
        annotation_text="Valle (1 < R < 3)",
        annotation_position="top right",
        row=5, col=2,
    )
    fig.add_hline(y=VALLEY_LO, line_dash="dash", line_color="#27ae60",
                  annotation_text="R = 1", row=5, col=2)
    fig.add_hline(y=VALLEY_HI, line_dash="dash", line_color="#27ae60",
                  annotation_text="R = 3", row=5, col=2)

    # ── Layout ────────────────────────────────────────────────────────────────
    fig.update_layout(
        title=dict(
            text=(
                f"FMD-DAO · Simulación Integrada — {CICLOS} ciclos × {DIAS_POR_CICLO} días"
                "<br><sup>R = τ × Ω · Valle de Resiliencia: 1 &lt; R &lt; 3</sup>"
            ),
            font=dict(size=20, color="#2c3e50"),
            x=0.5,
        ),
        height=1800,
        paper_bgcolor="#f8f9fa",
        plot_bgcolor="#ffffff",
        font=dict(family="monospace", size=11, color="#2c3e50"),
        legend=dict(
            orientation="v",
            x=1.02, y=1,
            bgcolor="rgba(255,255,255,0.9)",
            bordercolor="#bdc3c7",
            borderwidth=1,
        ),
        hovermode="x unified",
    )

    axis_labels = [
        (1, 1, "Score BPS"),   (1, 2, "Proveedor"),
        (2, 1, "Score BPS"),   (2, 2, "Score BPS"),
        (3, 1, "Threat (0–16)"),(3, 2, "Quórum (%)"),
        (4, 1, "Rigidez (%)"), (4, 2, "Peso (BPS)"),
        (5, 1, "τ (días) / Ω×1000"), (5, 2, "R = τ × Ω"),
    ]
    for row, col, ylabel in axis_labels:
        fig.update_yaxes(title_text=ylabel, row=row, col=col, gridcolor="#ecf0f1")
        fig.update_xaxes(title_text="Ciclo",  row=row, col=col, gridcolor="#ecf0f1")

    return fig

# ─── RESUMEN EN CONSOLA ───────────────────────────────────────────────────────

def print_summary(oracle, rep, immune, ideo, valley, ciclos):
    W = 60
    print("\n" + "═" * W)
    print("  FMD-DAO · RESUMEN DE SIMULACIÓN")
    print("═" * W)

    print("\n── ORÁCULOS ──────────────────────────────────────────────")
    for p in oracle.providers:
        bar = "█" * int(p.score / 500) + "░" * (20 - int(p.score / 500))
        print(f"  {p.name:<22} [{bar}] {p.score/100:>5.1f}%  {p.status}")

    rotaciones = {}
    for _, activo, _ in oracle.rotation_log:
        rotaciones[activo] = rotaciones.get(activo, 0) + 1
    print("\n  Rotaciones como ACTIVO:")
    for nombre, veces in sorted(rotaciones.items(), key=lambda x: -x[1]):
        print(f"    {nombre:<22} {veces:>2} ciclos")

    print("\n── REPUTACIÓN 5D ─────────────────────────────────────────")
    for m in rep.members:
        avg = round(sum(m.rep.values()) / len(m.rep))
        dims = "  ".join(f"{d[:3]}:{round(v):>5}" for d, v in m.rep.items())
        print(f"  {m.name:<28} avg:{avg:>5}  [{dims}]")

    print("\n── SISTEMA INMUNE ────────────────────────────────────────")
    scores = immune.threat_history
    print(f"  Score promedio : {sum(scores)/len(scores):.1f}")
    print(f"  Score máximo   : {max(scores)}")
    print(f"  Ciclos ROJO    : {immune.severity_history.count('ROJO')}")
    print(f"  Ciclos NARANJA : {immune.severity_history.count('NARANJA')}")
    print(f"  Ciclos VERDE   : {immune.severity_history.count('VERDE')}")

    print("\n── OSCILADOR IDEOLÓGICO ──────────────────────────────────")
    for m in ideo.members:
        avg_r = sum(m.rigidity_history) / len(m.rigidity_history)
        avg_w = sum(m.weight_history)   / len(m.weight_history)
        print(f"  {m.name:<28} rigidez:{avg_r:>5.1f}%  peso:{round(avg_w):>5} BPS")

    print("\n── VALLE DE RESILIENCIA ──────────────────────────────────")
    R_vals      = valley.R_history
    in_v        = valley.valley_history
    pct_valley  = sum(in_v) / len(in_v) * 100
    print(f"  R promedio     : {sum(R_vals)/len(R_vals):.3f}")
    print(f"  R mínimo       : {min(R_vals):.3f}")
    print(f"  R máximo       : {max(R_vals):.3f}")
    print(f"  Ciclos en Valle: {sum(in_v)}/{len(in_v)} ({pct_valley:.0f}%)")
    print(f"  τ final        : {valley.tau_history[-1]:.1f} días")
    print(f"  Ω final        : {valley.omega_history[-1]:.5f}")

    print("\n" + "═" * W + "\n")

# ─── MAIN ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    no_html = "--no-html" in sys.argv

    print("Ejecutando simulación FMD-DAO...")
    oracle, rep, immune, ideo, valley, ciclos = run_simulation()
    print_summary(oracle, rep, immune, ideo, valley, ciclos)

    if not no_html:
        fig = build_dashboard(oracle, rep, immune, ideo, valley, ciclos)
        output = "fmd_dao_simulacion.html"
        fig.write_html(
            output,
            include_plotlyjs="cdn",
            full_html=True,
            config={"displayModeBar": True, "scrollZoom": True},
        )
        print(f"Dashboard guardado en: {output}")
