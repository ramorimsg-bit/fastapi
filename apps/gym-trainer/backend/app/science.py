"""Equações validadas de fisiologia do exercício e nutrição.

Referências principais:
- Jackson & Pollock (1978) / Jackson, Pollock & Ward (1980): densidade corporal por dobras cutâneas.
- Siri (1961): conversão de densidade corporal em % de gordura.
- Hodgdon & Beckett (1984), método da Marinha dos EUA: % de gordura por circunferências.
- Mifflin-St Jeor (1990) e Katch-McArdle: taxa metabólica basal.
- Tanaka, Monahan & Seals (2001): FC máxima = 208 - 0,7 x idade.
- Karvonen (1957): zonas por frequência cardíaca de reserva.
- Keytel et al. (2005), J Sports Sci 23(3):289-97: gasto energético pela FC (sem VO2máx).
- 2024 Adult Compendium of Physical Activities (Herrmann et al.): valores de MET.
- ISSN Position Stand (Jäger et al., 2017): proteína de 1,4 a 2,0 g/kg/dia para quem treina.
- OMS: classificação de IMC, relação cintura-quadril e circunferência da cintura.
"""

from __future__ import annotations

import math
from typing import Literal

Sex = Literal["male", "female"]

ACTIVITY_FACTORS = {
    "sedentary": 1.2,
    "light": 1.375,
    "moderate": 1.55,
    "very_active": 1.725,
    "extra_active": 1.9,
}

# MET por modalidade (2024 Adult Compendium of Physical Activities).
MET_VALUES = {
    "strength_light": 3.5,  # 02054 musculação, múltiplos exercícios, 8-15 reps
    "strength_moderate": 5.0,  # 02052 musculação, agachamento/terra, esforço moderado
    "strength_vigorous": 6.0,  # 02050 musculação vigorosa / fisiculturismo
    "treadmill_walk": 4.3,  # caminhada ~5,6 km/h
    "treadmill_incline_walk": 6.0,  # caminhada inclinada
    "treadmill_run": 9.8,  # corrida ~9,7 km/h
    "bike_moderate": 6.8,
    "bike_vigorous": 8.8,
    "elliptical_moderate": 5.0,
    "elliptical_vigorous": 9.0,
    "rower_moderate": 7.0,
    "stair_climber": 9.0,
    "hiit": 8.0,
}


def bmi(weight_kg: float, height_cm: float) -> float:
    h = height_cm / 100
    return round(weight_kg / (h * h), 1)


def bmi_category(value: float) -> str:
    if value < 18.5:
        return "Abaixo do peso"
    if value < 25:
        return "Eutrófico"
    if value < 30:
        return "Sobrepeso"
    if value < 35:
        return "Obesidade grau I"
    if value < 40:
        return "Obesidade grau II"
    return "Obesidade grau III"


def body_density_jp7(sum_mm: float, age: int, sex: Sex) -> float:
    """Jackson & Pollock 7 dobras: peitoral, axilar média, tríceps, subescapular, abdominal, supra-ilíaca, coxa."""
    if sex == "male":
        return 1.112 - 0.00043499 * sum_mm + 0.00000055 * sum_mm**2 - 0.00028826 * age
    return 1.097 - 0.00046971 * sum_mm + 0.00000056 * sum_mm**2 - 0.00012828 * age


def body_density_jp3(sum_mm: float, age: int, sex: Sex) -> float:
    """Jackson & Pollock 3 dobras.

    Homens: peitoral, abdominal, coxa. Mulheres: tríceps, supra-ilíaca, coxa.
    """
    if sex == "male":
        return 1.10938 - 0.0008267 * sum_mm + 0.0000016 * sum_mm**2 - 0.0002574 * age
    return 1.0994921 - 0.0009929 * sum_mm + 0.0000023 * sum_mm**2 - 0.0001392 * age


def siri_body_fat(density: float) -> float:
    return round(495 / density - 450, 1)


def navy_body_fat(
    sex: Sex, height_cm: float, neck_cm: float, waist_cm: float, hip_cm: float | None
) -> float:
    """Método da Marinha dos EUA (Hodgdon & Beckett), fórmula original em polegadas."""
    to_in = 1 / 2.54
    h, n, w = height_cm * to_in, neck_cm * to_in, waist_cm * to_in
    if sex == "male":
        value = 86.010 * math.log10(w - n) - 70.041 * math.log10(h) + 36.76
    else:
        if hip_cm is None:
            raise ValueError("Quadril é obrigatório para mulheres no método da Marinha")
        hp = hip_cm * to_in
        value = 163.205 * math.log10(w + hp - n) - 97.684 * math.log10(h) - 78.387
    return round(value, 1)


def body_fat_category(body_fat: float, sex: Sex) -> str:
    """Faixas do American Council on Exercise (ACE)."""
    limits = (
        [(6, "Gordura essencial"), (14, "Atleta"), (18, "Fitness"), (25, "Média")]
        if sex == "male"
        else [(14, "Gordura essencial"), (21, "Atleta"), (25, "Fitness"), (32, "Média")]
    )
    for limit, label in limits:
        if body_fat < limit:
            return label
    return "Acima do recomendado"


def waist_hip_risk(waist_cm: float, hip_cm: float, sex: Sex) -> tuple[float, str]:
    ratio = round(waist_cm / hip_cm, 2)
    threshold = 0.90 if sex == "male" else 0.85
    return ratio, ("Risco cardiometabólico elevado" if ratio > threshold else "Adequada")


def waist_risk(waist_cm: float, sex: Sex) -> str:
    high, very_high = (94, 102) if sex == "male" else (80, 88)
    if waist_cm >= very_high:
        return "Risco muito aumentado"
    if waist_cm >= high:
        return "Risco aumentado"
    return "Adequada"


def bmr_mifflin(weight_kg: float, height_cm: float, age: int, sex: Sex) -> float:
    base = 10 * weight_kg + 6.25 * height_cm - 5 * age
    return round(base + (5 if sex == "male" else -161))


def bmr_katch_mcardle(lean_mass_kg: float) -> float:
    return round(370 + 21.6 * lean_mass_kg)


def hr_max_tanaka(age: int) -> int:
    return round(208 - 0.7 * age)


def karvonen_zones(age: int, resting_hr: int) -> dict[str, tuple[int, int]]:
    """Zonas de treino pela FC de reserva (Karvonen)."""
    hr_max = hr_max_tanaka(age)
    reserve = hr_max - resting_hr

    def at(pct: float) -> int:
        return round(resting_hr + reserve * pct)

    return {
        "Z1 Recuperação (50-60%)": (at(0.50), at(0.60)),
        "Z2 Aeróbio base / queima de gordura (60-70%)": (at(0.60), at(0.70)),
        "Z3 Aeróbio moderado (70-80%)": (at(0.70), at(0.80)),
        "Z4 Limiar (80-90%)": (at(0.80), at(0.90)),
        "Z5 VO2máx (90-100%)": (at(0.90), hr_max),
    }


def kcal_from_heart_rate(
    avg_hr: float, weight_kg: float, age: int, sex: Sex, minutes: float
) -> float:
    """Keytel et al. (2005), modelo sem VO2máx. A equação retorna kJ/min."""
    if sex == "male":
        kj_min = -55.0969 + 0.6309 * avg_hr + 0.1988 * weight_kg + 0.2017 * age
    else:
        kj_min = -20.4022 + 0.4472 * avg_hr - 0.1263 * weight_kg + 0.074 * age
    return round(max(kj_min, 0) / 4.184 * minutes, 1)


def kcal_from_met(met: float, weight_kg: float, minutes: float) -> float:
    """kcal = MET x 3,5 x kg / 200 por minuto (ACSM)."""
    return round(met * 3.5 * weight_kg / 200 * minutes, 1)


def nutrition_targets(
    tdee: float, weight_kg: float, goal: str, lean_mass_kg: float | None = None
) -> dict[str, float]:
    """Meta calórica e de macronutrientes.

    - Emagrecimento: déficit de ~20% (perda de 0,5-1% do peso/semana preservando massa magra).
    - Hipertrofia: superávit de ~10% (ganho magro).
    - Proteína: 2,0 g/kg no déficit e 1,8 g/kg nos demais casos (ISSN 1,4-2,0 g/kg;
      até 2,3-3,1 g/kg de massa magra em déficit, Helms et al. 2014).
    - Gordura: 0,9 g/kg (mínimo de ~20% das kcal para saúde hormonal).
    """
    factor = {"fat_loss": 0.80, "hypertrophy": 1.10, "strength": 1.05}.get(goal, 1.0)
    kcal = round(tdee * factor)
    protein_per_kg = 2.0 if goal == "fat_loss" else 1.8
    protein = round(protein_per_kg * weight_kg)
    if lean_mass_kg and goal == "fat_loss":
        protein = max(protein, round(2.3 * lean_mass_kg))
    fat = round(max(0.9 * weight_kg, kcal * 0.20 / 9))
    carbs = round(max((kcal - protein * 4 - fat * 9) / 4, 0))
    return {
        "kcal": kcal,
        "protein_g": protein,
        "carbs_g": carbs,
        "fat_g": fat,
        "water_ml": round(35 * weight_kg),
        "fiber_g": round(kcal / 1000 * 14),
    }
