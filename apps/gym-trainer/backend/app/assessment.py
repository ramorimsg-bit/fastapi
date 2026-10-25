"""Avaliação física bimestral: composição corporal, riscos, exames e evolução."""

from __future__ import annotations

from datetime import date, timedelta

from . import science
from .schemas import AssessmentIn, User

REASSESSMENT_DAYS = 60  # avaliações bimestrais


def body_composition(user: User, a: AssessmentIn) -> dict:
    sf, circ, sex, age = a.skinfolds, a.circumferences, user.sex, user.age
    method, body_fat = None, None

    seven = [sf.chest, sf.midaxillary, sf.triceps, sf.subscapular, sf.abdominal, sf.suprailiac, sf.thigh]
    three = [sf.chest, sf.abdominal, sf.thigh] if sex == "male" else [sf.triceps, sf.suprailiac, sf.thigh]
    if all(v is not None for v in seven):
        density = science.body_density_jp7(sum(seven), age, sex)
        method, body_fat = "Jackson & Pollock 7 dobras + Siri", science.siri_body_fat(density)
    elif all(v is not None for v in three):
        density = science.body_density_jp3(sum(three), age, sex)
        method, body_fat = "Jackson & Pollock 3 dobras + Siri", science.siri_body_fat(density)
    elif circ.neck and circ.waist and (sex == "male" or circ.hip):
        method = "Circunferências (Marinha dos EUA)"
        body_fat = science.navy_body_fat(sex, user.height_cm, circ.neck, circ.waist, circ.hip)
    elif a.healthkit_body_fat_pct is not None:
        method, body_fat = "App Saúde (balança/bioimpedância)", a.healthkit_body_fat_pct

    result: dict = {
        "bmi": science.bmi(a.weight_kg, user.height_cm),
        "bmi_category": science.bmi_category(science.bmi(a.weight_kg, user.height_cm)),
        "body_fat_pct": body_fat,
        "body_fat_method": method,
    }
    if body_fat is not None:
        fat_mass = round(a.weight_kg * body_fat / 100, 1)
        result |= {
            "body_fat_category": science.body_fat_category(body_fat, sex),
            "fat_mass_kg": fat_mass,
            "lean_mass_kg": round(a.weight_kg - fat_mass, 1),
        }
    if circ.waist:
        result["waist_risk"] = science.waist_risk(circ.waist, sex)
        if circ.hip:
            ratio, risk = science.waist_hip_risk(circ.waist, circ.hip, sex)
            result |= {"waist_hip_ratio": ratio, "waist_hip_risk": risk}
    return result


def blood_pressure_class(sys: int, dia: int) -> str:
    """Diretrizes Brasileiras de Hipertensão Arterial (SBC, 2020)."""
    if sys >= 180 or dia >= 110:
        return "Hipertensão estágio 3"
    if sys >= 160 or dia >= 100:
        return "Hipertensão estágio 2"
    if sys >= 140 or dia >= 90:
        return "Hipertensão estágio 1"
    if sys >= 130 or dia >= 85:
        return "Pré-hipertensão"
    if sys >= 120 or dia >= 80:
        return "Normal"
    return "Ótima"


def health_screening(user: User, a: AssessmentIn, bmi: float) -> tuple[list[str], list[str], bool]:
    """Retorna (alertas para o aluno, restrições para a ficha, precisa de liberação médica)."""
    ex = a.exams
    alerts: list[str] = []
    restrictions: set[str] = set()
    clearance = a.parq.any_positive()

    if clearance:
        alerts.append("PAR-Q positivo: apresente liberação médica antes de treinos de alta intensidade.")
    if ex.systolic_bp and ex.diastolic_bp:
        cls = blood_pressure_class(ex.systolic_bp, ex.diastolic_bp)
        alerts.append(f"Pressão arterial {ex.systolic_bp}/{ex.diastolic_bp} mmHg: {cls}.")
        if ex.systolic_bp >= 160 or ex.diastolic_bp >= 100:
            restrictions.add("hypertension_uncontrolled")
            clearance = True
            alerts.append("Evite manobra de Valsalva, isometrias longas e cargas máximas; intensidade moderada.")
        if ex.systolic_bp >= 200 or ex.diastolic_bp >= 110:
            alerts.append("PA de repouso muito elevada: NÃO treine hoje e procure um médico.")
    if ex.fasting_glucose is not None or ex.hba1c is not None:
        g, h = ex.fasting_glucose or 0, ex.hba1c or 0
        if g >= 126 or h >= 6.5:
            alerts.append("Glicemia/HbA1c na faixa de diabetes: monitore glicemia antes e após o treino e leve carboidrato de rápida absorção.")
            clearance = True
        elif g >= 100 or h >= 5.7:
            alerts.append("Glicemia/HbA1c na faixa de pré-diabetes: musculação + aeróbio melhoram a sensibilidade à insulina.")
    if ex.ldl and ex.ldl >= 160:
        alerts.append("LDL elevado: priorize aeróbio regular (150+ min/semana) e fibras solúveis.")
    hdl_min = 40 if user.sex == "male" else 50
    if ex.hdl and ex.hdl < hdl_min:
        alerts.append("HDL baixo: exercício aeróbio e redução de gordura visceral tendem a elevá-lo.")
    if ex.triglycerides and ex.triglycerides >= 150:
        alerts.append("Triglicerídeos elevados: reduza açúcares/álcool e mantenha aeróbio frequente.")
    if ex.vitamin_d is not None and ex.vitamin_d < 20:
        alerts.append("Vitamina D baixa: converse com seu médico sobre suplementação.")
    if ex.ferritin is not None and ex.ferritin < 30:
        alerts.append("Ferritina baixa: pode reduzir o desempenho aeróbio; avalie com seu médico.")

    injury_map = {"knee": "knee_severe", "lower_back": "lower_back", "shoulder": "shoulder"}
    restrictions |= {injury_map[i] for i in user.injuries}
    if bmi >= 35:
        restrictions.add("obesity_high_impact")
        alerts.append("IMC ≥ 35: cardio de baixo impacto (bike, elíptico, caminhada inclinada) para proteger as articulações.")
    if user.age >= 65:
        restrictions.add("balance")
    return alerts, sorted(restrictions), clearance


def compare(previous: dict | None, current: dict, weight_now: float) -> dict | None:
    if not previous:
        return None
    prev = previous["results"]["composition"]
    cur = current["composition"]
    delta: dict = {"days_between": (date.fromisoformat(current["date"]) - date.fromisoformat(previous["date"])).days,
                   "weight_kg": round(weight_now - previous["weight_kg"], 1)}
    for key in ("body_fat_pct", "fat_mass_kg", "lean_mass_kg"):
        if prev.get(key) is not None and cur.get(key) is not None:
            delta[key] = round(cur[key] - prev[key], 1)
    prev_c, cur_c = previous.get("circumferences", {}), current.get("circumferences", {})
    delta["circumferences_cm"] = {
        k: round(cur_c[k] - prev_c[k], 1) for k in cur_c if cur_c.get(k) and prev_c.get(k)
    }
    verdict = []
    if delta.get("lean_mass_kg", 0) > 0:
        verdict.append("ganho de massa magra")
    if delta.get("fat_mass_kg", 0) < 0:
        verdict.append("redução de gordura")
    if delta.get("fat_mass_kg", 0) > 0.5:
        verdict.append("aumento de gordura: revisar dieta")
    if delta.get("lean_mass_kg", 0) < -0.5:
        verdict.append("perda de massa magra: aumentar proteína/volume de treino")
    delta["summary"] = ", ".join(verdict) or "manutenção"
    return delta


def evaluate(user: User, a: AssessmentIn, previous: dict | None) -> dict:
    composition = body_composition(user, a)
    alerts, restrictions, clearance = health_screening(user, a, composition["bmi"])

    lean = composition.get("lean_mass_kg")
    bmr = science.bmr_katch_mcardle(lean) if lean else science.bmr_mifflin(a.weight_kg, user.height_cm, user.age, user.sex)
    tdee = round(bmr * science.ACTIVITY_FACTORS[user.activity_level])
    resting_hr = a.exams.resting_hr or 70

    results = {
        "date": a.date.isoformat(),
        "composition": composition,
        "circumferences": a.circumferences.model_dump(exclude_none=True),
        "energy": {
            "bmr_kcal": bmr,
            "bmr_method": "Katch-McArdle" if lean else "Mifflin-St Jeor",
            "tdee_kcal": tdee,
        },
        "nutrition": science.nutrition_targets(tdee, a.weight_kg, user.goal, lean),
        "heart_rate": {
            "hr_max": science.hr_max_tanaka(user.age),
            "resting_hr": resting_hr,
            "zones": science.karvonen_zones(user.age, resting_hr),
        },
        "alerts": alerts,
        "restrictions": restrictions,
        "needs_medical_clearance": clearance,
        "next_assessment": (a.date + timedelta(days=REASSESSMENT_DAYS)).isoformat(),
    }
    results["progress"] = compare(previous, results, a.weight_kg)
    return results
