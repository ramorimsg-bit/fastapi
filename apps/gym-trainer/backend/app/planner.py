"""Montagem de fichas de treino a partir da avaliação física e dos exames.

Base técnica:
- ACSM Position Stand "Progression Models in Resistance Training" (Ratamess et al., 2009):
  frequência 2-3x/sem (iniciante), 3-4x (intermediário), 4-5x (avançado); 8-12 RM para
  iniciantes; progressão de 2-10% na carga ao superar a faixa de repetições em 1-2 reps.
- Schoenfeld et al. (2017): 10+ séries semanais por grupo muscular maximizam hipertrofia.
- ACSM/OMS: 150-300 min/semana de aeróbio moderado (ou 75-150 vigoroso) para saúde e
  controle de peso.
- Ciclo de 8 semanas (mesociclo) alinhado à reavaliação bimestral, com deload nas semanas 4 e 8.
"""

from __future__ import annotations

from . import exercises, science
from .schemas import User

LEVEL = {"beginner": 1, "intermediate": 2, "advanced": 3}

PRESCRIPTION = {
    "hypertrophy": {"sets": 4, "reps": "8-12", "rest_s": 90, "rir": "1-2", "method": "Progressão dupla"},
    "strength": {"sets": 5, "reps": "3-6", "rest_s": 180, "rir": "2-3", "method": "Carga progressiva linear"},
    "fat_loss": {"sets": 3, "reps": "10-15", "rest_s": 60, "rir": "1-3", "method": "Progressão dupla com descanso curto"},
    "health": {"sets": 3, "reps": "10-15", "rest_s": 60, "rir": "2-3", "method": "Progressão dupla"},
    "endurance": {"sets": 3, "reps": "15-20", "rest_s": 45, "rir": "2-3", "method": "Resistência muscular"},
}

ACCESSORY = {"sets": 3, "reps": "10-15", "rest_s": 60}

# Cada slot é uma lista de candidatos em ordem de preferência.
DAY_TEMPLATES: dict[str, list[list[str]]] = {
    "Full body A": [
        ["back_squat", "goblet_squat", "leg_press", "box_squat"],
        ["bench_press", "dumbbell_press", "machine_chest_press", "push_up"],
        ["seated_row", "machine_row", "dumbbell_row"],
        ["romanian_deadlift", "hip_thrust", "glute_bridge"],
        ["lateral_raise"],
        ["dead_bug", "pallof_press"],
    ],
    "Full body B": [
        ["leg_press", "goblet_squat", "box_squat"],
        ["lat_pulldown", "assisted_pull_up"],
        ["incline_dumbbell_press", "machine_chest_press", "push_up"],
        ["hip_thrust", "glute_bridge"],
        ["leg_curl"],
        ["face_pull"],
        ["plank", "dead_bug"],
    ],
    "Superiores A": [
        ["bench_press", "dumbbell_press", "machine_chest_press"],
        ["barbell_row", "seated_row", "machine_row"],
        ["dumbbell_shoulder_press", "landmine_press", "lateral_raise"],
        ["lat_pulldown", "assisted_pull_up"],
        ["dumbbell_curl"],
        ["triceps_pushdown"],
    ],
    "Inferiores A": [
        ["back_squat", "hack_squat", "leg_press", "box_squat"],
        ["romanian_deadlift", "hip_thrust"],
        ["bulgarian_split_squat", "walking_lunge", "leg_press"],
        ["leg_curl"],
        ["calf_raise"],
        ["pallof_press", "dead_bug"],
    ],
    "Superiores B": [
        ["pull_up", "lat_pulldown", "assisted_pull_up"],
        ["incline_dumbbell_press", "machine_chest_press"],
        ["dumbbell_row", "machine_row"],
        ["lateral_raise"],
        ["face_pull"],
        ["hammer_curl"],
        ["overhead_triceps_extension", "triceps_pushdown"],
    ],
    "Inferiores B": [
        ["deadlift", "romanian_deadlift", "hip_thrust"],
        ["leg_press", "goblet_squat"],
        ["hip_thrust", "glute_bridge"],
        ["leg_extension"],
        ["leg_curl"],
        ["calf_raise"],
        ["cable_crunch", "dead_bug"],
    ],
    "Push (empurrar)": [
        ["bench_press", "dumbbell_press", "machine_chest_press"],
        ["dumbbell_shoulder_press", "landmine_press"],
        ["incline_dumbbell_press", "machine_chest_press"],
        ["cable_fly", "machine_chest_press"],
        ["lateral_raise"],
        ["triceps_pushdown"],
        ["overhead_triceps_extension", "triceps_pushdown"],
    ],
    "Pull (puxar)": [
        ["pull_up", "lat_pulldown", "assisted_pull_up"],
        ["barbell_row", "seated_row"],
        ["dumbbell_row", "machine_row"],
        ["face_pull"],
        ["dumbbell_curl"],
        ["hammer_curl"],
    ],
    "Legs (pernas)": [
        ["back_squat", "hack_squat", "leg_press"],
        ["romanian_deadlift", "hip_thrust"],
        ["leg_press", "bulgarian_split_squat"],
        ["leg_extension"],
        ["leg_curl"],
        ["calf_raise"],
        ["cable_crunch", "plank"],
    ],
}

PATTERNS_MAIN = {"squat", "hinge", "push_h", "push_v", "pull_h", "pull_v", "lunge"}


def choose_split(user: User) -> list[str]:
    d = user.days_per_week
    if user.experience == "beginner" or d <= 3:
        return [("Full body A", "Full body B")[i % 2] for i in range(d)]
    if d == 4 or user.experience == "intermediate":
        days = ["Superiores A", "Inferiores A", "Superiores B", "Inferiores B"]
        return (days + days)[:d]
    return (["Push (empurrar)", "Pull (puxar)", "Legs (pernas)"] * 2)[:d]


def allowed(ex: exercises.Exercise, level: int, restrictions: set[str]) -> bool:
    return ex.level <= level and not (set(ex.restrictions) & restrictions)


def pick(candidates: list[str], level: int, restrictions: set[str], used: set[str]) -> exercises.Exercise | None:
    for cid in candidates:
        ex = exercises.get(cid)
        if cid not in used and allowed(ex, level, restrictions):
            return ex
        for alt in ex.alternatives:
            alt_ex = exercises.get(alt)
            if alt not in used and allowed(alt_ex, level, restrictions):
                return alt_ex
    return None


def cardio_block(user: User, results: dict, restrictions: set[str], weight: float) -> dict:
    goal = user.goal
    zones = list(results["heart_rate"]["zones"].items())
    z2_name, z2 = zones[1]
    z3_name, z3 = zones[2]
    minutes = {"fat_loss": 30, "health": 25, "endurance": 40, "hypertrophy": 15, "strength": 10}[goal]
    if user.session_minutes <= 45:
        minutes = min(minutes, 20)

    order = ["treadmill_incline_walk", "elliptical", "bike", "treadmill_walk"]
    if goal == "endurance" and user.experience != "beginner":
        order.insert(0, "treadmill_run")
    modality = next(exercises.get(m) for m in order if not set(exercises.get(m).restrictions) & restrictions)

    zone_name, zone = (z3_name, z3) if goal == "endurance" else (z2_name, z2)
    block = {
        "exercise": modality.to_dict(),
        "type": "Contínuo (LISS)",
        "duration_min": minutes,
        "warmup_min": 5,
        "target_zone": zone_name,
        "target_hr_bpm": list(zone),
        "estimated_kcal": science.kcal_from_met(science.MET_VALUES[modality.met_key], weight, minutes),
        "when": "Após a musculação (preserva a força para os exercícios principais)",
    }
    hiit_ok = (
        goal in ("fat_loss", "endurance")
        and user.experience != "beginner"
        and not results["needs_medical_clearance"]
        and "hypertension_uncontrolled" not in restrictions
    )
    if hiit_ok:
        z4_name, z4 = zones[3]
        block["hiit_option"] = {
            "description": "1-2x por semana no lugar do contínuo: 8 x (30 s forte + 90 s leve) na bike ou elíptico.",
            "work_zone": z4_name,
            "work_hr_bpm": list(z4),
            "total_min": 21,
            "estimated_kcal": science.kcal_from_met(science.MET_VALUES["hiit"], weight, 21),
        }
    return block


def strength_time(items: list[dict]) -> float:
    """Minutos de musculação: ~40 s por série + descanso prescrito."""
    return sum(it["sets"] * (40 + it["rest_s"]) for it in items) / 60


def build_plan(user: User, assessment: dict) -> dict:
    results = assessment["results"]
    restrictions = set(results["restrictions"])
    level = LEVEL[user.experience]
    weight = assessment["weight_kg"]
    base = dict(PRESCRIPTION[user.goal])
    if user.experience == "beginner":
        base["sets"] = max(2, base["sets"] - 1)
        base["reps"] = "10-12" if user.goal in ("hypertrophy", "strength") else base["reps"]
    if results["needs_medical_clearance"]:
        base["rir"] = "3-4"
        base["reps"] = "12-15"

    days = []
    for label in choose_split(user):
        used: set[str] = set()
        items = []
        for i, slot in enumerate(DAY_TEMPLATES[label]):
            ex = pick(slot, level, restrictions, used)
            if ex is None:
                continue
            used.add(ex.id)
            main = ex.pattern in PATTERNS_MAIN and i < 3
            presc = base if main else {**ACCESSORY, "rir": base["rir"]}
            if ex.tempo == "isometria":
                presc = {"sets": 3, "reps": "30-45 s", "rest_s": 45, "rir": "-"}
            items.append({
                "order": len(items) + 1,
                "exercise": ex.to_dict(),
                "sets": presc["sets"],
                "reps": presc["reps"],
                "rest_s": presc["rest_s"],
                "rir": presc["rir"],
                "tempo": ex.tempo,
            })
        cardio = cardio_block(user, results, restrictions, weight)
        # Ajusta a sessão ao tempo disponível: corta acessórios e depois reduz o cardio.
        while strength_time(items) + cardio["duration_min"] + 10 > user.session_minutes and len(items) > 4:
            items.pop()
        strength_minutes = strength_time(items)
        fit = max(10, round(user.session_minutes - strength_minutes - 10))
        if fit < cardio["duration_min"]:
            met_cardio = science.MET_VALUES[exercises.get(cardio["exercise"]["id"]).met_key]
            cardio["duration_min"] = fit
            cardio["estimated_kcal"] = science.kcal_from_met(met_cardio, weight, fit)
            cardio["note"] = "Complete o restante do cardio semanal em dias alternados ou com caminhadas."
        met = science.MET_VALUES["strength_moderate" if user.goal in ("hypertrophy", "strength") else "strength_light"]
        days.append({
            "label": label,
            "warmup": "5 min de cardio leve (Z1) + mobilidade articular + 1-2 séries de aproximação (50-70% da carga) no 1º exercício.",
            "exercises": items,
            "cardio": cardio,
            "cooldown": "5 min de caminhada leve + alongamento estático dos músculos trabalhados (20-30 s cada).",
            "estimated_minutes": round(strength_minutes + cardio["duration_min"] + 10),
            "estimated_kcal": round(science.kcal_from_met(met, weight, strength_minutes) + cardio["estimated_kcal"]),
        })

    return {
        "user_id": user.id,
        "assessment_id": assessment["id"],
        "goal": user.goal,
        "split": [d["label"] for d in days],
        "prescription": base,
        "days": days,
        "periodization": [
            {"weeks": "1-3", "focus": "Acumulação: aumente reps até o topo da faixa e então a carga (+2 a 10%)."},
            {"weeks": "4", "focus": "Deload: mesmas cargas com ~50% das séries (recuperação)."},
            {"weeks": "5-7", "focus": "Intensificação: RIR 0-2 nas últimas séries dos exercícios principais."},
            {"weeks": "8", "focus": "Deload + reavaliação física bimestral e nova ficha."},
        ],
        "progression_rule": (
            f"Ao completar todas as séries com {base['reps'].split('-')[-1]} repetições mantendo a técnica, "
            "aumente a carga em 2-5% (membros superiores) ou 5-10% (inferiores)."
        ),
        "weekly_cardio_min": days[0]["cardio"]["duration_min"] * len(days),
        "weekly_cardio_note": "Meta OMS/ACSM: 150-300 min/semana de atividade moderada. Complete com caminhadas e passos diários.",
        "nutrition": results["nutrition"],
        "alerts": results["alerts"],
        "valid_until": results["next_assessment"],
    }
