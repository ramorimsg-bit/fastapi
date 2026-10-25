"""Gasto calórico de uma sessão.

Prioridade das fontes:
1. Energia ativa medida pelo Apple Watch (HKQuantityType.activeEnergyBurned via
   HKLiveWorkoutBuilder): usa FC contínua, acelerômetro e o perfil do usuário.
2. Frequência cardíaca média (Keytel et al., 2005).
3. MET da atividade (2024 Adult Compendium) x tempo x peso.
"""

from __future__ import annotations

from . import exercises, science
from .schemas import User, WorkoutIn


def session_calories(user: User, weight_kg: float, w: WorkoutIn) -> dict:
    minutes = (w.ended_at - w.started_at).total_seconds() / 60
    avg_hr = w.avg_hr
    if avg_hr is None and w.heart_rate:
        avg_hr = sum(s.bpm for s in w.heart_rate) / len(w.heart_rate)
    max_hr = w.max_hr or (max(s.bpm for s in w.heart_rate) if w.heart_rate else None)

    by_hr = science.kcal_from_heart_rate(avg_hr, weight_kg, user.age, user.sex, minutes) if avg_hr else None
    cardio_ids = {s.exercise_id for s in w.sets if (ex := exercises.BY_ID.get(s.exercise_id)) and ex.is_cardio}
    met = science.MET_VALUES["strength_moderate"]
    if cardio_ids and len(cardio_ids) == len({s.exercise_id for s in w.sets}):
        met = science.MET_VALUES[exercises.get(next(iter(cardio_ids))).met_key]
    by_met = science.kcal_from_met(met, weight_kg, minutes)

    if w.active_energy_kcal is not None:
        total, source = w.active_energy_kcal, "Apple Watch (energia ativa)"
    elif by_hr is not None:
        total, source = by_hr, "Frequência cardíaca (Keytel 2005)"
    else:
        total, source = by_met, "MET (Compendium 2024)"

    volume = sum((s.reps or 0) * (s.weight_kg or 0) for s in w.sets)
    hr_max = science.hr_max_tanaka(user.age)
    return {
        "kcal": round(total),
        "source": source,
        "estimates": {"heart_rate": by_hr, "met": by_met, "apple_watch": w.active_energy_kcal},
        "duration_min": round(minutes, 1),
        "avg_hr": round(avg_hr) if avg_hr else None,
        "max_hr": round(max_hr) if max_hr else None,
        "avg_intensity_pct_hrmax": round(avg_hr / hr_max * 100) if avg_hr else None,
        "volume_load_kg": round(volume),
        "total_sets": len(w.sets),
    }
