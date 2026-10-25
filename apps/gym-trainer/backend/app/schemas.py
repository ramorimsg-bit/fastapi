from __future__ import annotations

from datetime import date as Date, datetime
from typing import Literal

from pydantic import BaseModel, Field

Sex = Literal["male", "female"]
Goal = Literal["fat_loss", "hypertrophy", "strength", "health", "endurance"]
Experience = Literal["beginner", "intermediate", "advanced"]
ActivityLevel = Literal["sedentary", "light", "moderate", "very_active", "extra_active"]


class UserIn(BaseModel):
    name: str
    sex: Sex
    birth_date: Date
    height_cm: float = Field(gt=100, lt=250)
    goal: Goal
    experience: Experience = "beginner"
    activity_level: ActivityLevel = "moderate"
    days_per_week: int = Field(default=3, ge=2, le=6)
    session_minutes: int = Field(default=60, ge=30, le=120)
    injuries: list[Literal["knee", "lower_back", "shoulder"]] = []
    notes: str = ""


class User(UserIn):
    id: str
    created_at: datetime

    @property
    def age(self) -> int:
        today = Date.today()
        b = self.birth_date
        return today.year - b.year - ((today.month, today.day) < (b.month, b.day))


class Skinfolds(BaseModel):
    """Dobras cutâneas em mm (lado direito, média de 2-3 medidas, adipômetro)."""

    chest: float | None = None
    midaxillary: float | None = None
    triceps: float | None = None
    subscapular: float | None = None
    abdominal: float | None = None
    suprailiac: float | None = None
    thigh: float | None = None


class Circumferences(BaseModel):
    """Circunferências em cm (fita métrica inextensível)."""

    neck: float | None = None
    chest: float | None = None
    waist: float | None = None
    abdomen: float | None = None
    hip: float | None = None
    right_arm: float | None = None
    left_arm: float | None = None
    right_thigh: float | None = None
    left_thigh: float | None = None
    right_calf: float | None = None
    left_calf: float | None = None


class Exams(BaseModel):
    """Exames clínicos e laboratoriais (preenchidos a partir dos laudos)."""

    systolic_bp: int | None = None
    diastolic_bp: int | None = None
    resting_hr: int | None = None
    fasting_glucose: float | None = None  # mg/dL
    hba1c: float | None = None  # %
    total_cholesterol: float | None = None
    ldl: float | None = None
    hdl: float | None = None
    triglycerides: float | None = None
    vitamin_d: float | None = None  # ng/mL
    ferritin: float | None = None
    tsh: float | None = None
    vo2max: float | None = None  # ml/kg/min (Apple Watch ou ergoespirometria)
    medical_clearance: bool | None = None
    conditions: list[str] = []  # ex.: "asma", "hérnia de disco L5-S1"
    medications: list[str] = []


class ParQ(BaseModel):
    """PAR-Q (Physical Activity Readiness Questionnaire) - triagem pré-participação."""

    heart_condition: bool = False
    chest_pain_activity: bool = False
    chest_pain_rest: bool = False
    dizziness_or_fainting: bool = False
    bone_joint_problem: bool = False
    bp_or_heart_medication: bool = False
    other_reason: bool = False

    def any_positive(self) -> bool:
        return any(self.model_dump().values())


class AssessmentIn(BaseModel):
    date: Date = Field(default_factory=Date.today)
    weight_kg: float = Field(gt=30, lt=350)
    skinfolds: Skinfolds = Skinfolds()
    circumferences: Circumferences = Circumferences()
    exams: Exams = Exams()
    parq: ParQ = ParQ()
    # Testes de aptidão
    pushups_max: int | None = None
    plank_seconds: int | None = None
    sit_and_reach_cm: float | None = None
    # Dados vindos do app Saúde (opcional)
    healthkit_body_fat_pct: float | None = None


class Assessment(AssessmentIn):
    id: str
    user_id: str
    results: dict


class WorkoutSet(BaseModel):
    exercise_id: str
    set_number: int
    reps: int | None = None
    weight_kg: float | None = None
    duration_s: int | None = None
    rpe: float | None = Field(default=None, ge=1, le=10)


class HeartRateSample(BaseModel):
    timestamp: datetime
    bpm: float


class WorkoutIn(BaseModel):
    plan_id: str | None = None
    day_label: str | None = None
    started_at: datetime
    ended_at: datetime
    sets: list[WorkoutSet] = []
    heart_rate: list[HeartRateSample] = []
    # Valores medidos pelo Apple Watch (HKLiveWorkoutBuilder), quando disponíveis
    active_energy_kcal: float | None = None
    avg_hr: float | None = None
    max_hr: float | None = None
    source: Literal["apple_watch", "iphone", "manual"] = "manual"
    healthkit_uuid: str | None = None


class Workout(WorkoutIn):
    id: str
    user_id: str
    calories: dict


class HealthSyncIn(BaseModel):
    """Lote de amostras lidas do HealthKit no iPhone."""

    weight_kg: float | None = None
    body_fat_pct: float | None = None
    lean_mass_kg: float | None = None
    resting_hr: float | None = None
    hrv_ms: float | None = None
    vo2max: float | None = None
    steps_today: int | None = None
    active_energy_today_kcal: float | None = None
    workouts: list[WorkoutIn] = []


class ChatMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class ChatIn(BaseModel):
    messages: list[ChatMessage]
