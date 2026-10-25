"""API do GymTrainer: personal trainer virtual, avaliações, fichas, treinos e sincronização com o app Saúde."""

from __future__ import annotations

from datetime import date, datetime, timezone

from fastapi import Depends, FastAPI, HTTPException

from . import assessment as assessment_service
from . import calories, coach, exercises, planner
from .schemas import (
    Assessment,
    AssessmentIn,
    ChatIn,
    HealthSyncIn,
    User,
    UserIn,
    Workout,
    WorkoutIn,
)
from .storage import Store

app = FastAPI(title="GymTrainer API", version="1.0.0")
store = Store()


def get_store() -> Store:
    return store


def load_user(user_id: str, db: Store = Depends(get_store)) -> User:
    data = db.get("users", user_id)
    if not data:
        raise HTTPException(404, "Usuário não encontrado")
    return User(**data)


def current_weight(user: User, db: Store) -> float:
    health = db.get("health", user.id)
    if health and health.get("weight_kg"):
        return health["weight_kg"]
    assessments = db.list("assessments", user.id)
    if not assessments:
        raise HTTPException(409, "Faça a avaliação física inicial antes de registrar treinos")
    return assessments[-1]["weight_kg"]


# ---------------- Usuários ----------------
@app.post("/users", response_model=User, status_code=201)
def create_user(body: UserIn, db: Store = Depends(get_store)):
    return db.insert("users", {**body.model_dump(mode="json"), "created_at": datetime.now(timezone.utc).isoformat()})


@app.get("/users/{user_id}", response_model=User)
def read_user(user: User = Depends(load_user)):
    return user


@app.put("/users/{user_id}", response_model=User)
def update_user(body: UserIn, user: User = Depends(load_user), db: Store = Depends(get_store)):
    data = {**user.model_dump(mode="json"), **body.model_dump(mode="json")}
    return db.put("users", data)


# ---------------- Exercícios ----------------
@app.get("/exercises")
def list_exercises(pattern: str | None = None):
    return [e.to_dict() for e in exercises.CATALOG if pattern is None or e.pattern == pattern]


@app.get("/exercises/{exercise_id}")
def read_exercise(exercise_id: str):
    if exercise_id not in exercises.BY_ID:
        raise HTTPException(404, "Exercício não encontrado")
    return exercises.get(exercise_id).to_dict()


# ---------------- Avaliações bimestrais ----------------
@app.post("/users/{user_id}/assessments", response_model=Assessment, status_code=201)
def create_assessment(body: AssessmentIn, user: User = Depends(load_user), db: Store = Depends(get_store)):
    history = db.list("assessments", user.id)
    previous = history[-1] if history else None
    results = assessment_service.evaluate(user, body, previous)
    doc = db.insert(
        "assessments",
        {**body.model_dump(mode="json"), "user_id": user.id, "results": results},
        owner=user.id,
        sort_key=body.date.isoformat(),
    )
    # Toda avaliação gera uma nova ficha baseada nos resultados e exames.
    plan = planner.build_plan(user, doc)
    db.insert("plans", {**plan, "created_at": datetime.now(timezone.utc).isoformat()}, owner=user.id,
              sort_key=body.date.isoformat())
    return doc


@app.get("/users/{user_id}/assessments", response_model=list[Assessment])
def list_assessments(user: User = Depends(load_user), db: Store = Depends(get_store)):
    return db.list("assessments", user.id)


@app.get("/users/{user_id}/assessments/status")
def assessment_status(user: User = Depends(load_user), db: Store = Depends(get_store)):
    history = db.list("assessments", user.id)
    if not history:
        return {"due": True, "next_assessment": date.today().isoformat(), "days_left": 0}
    nxt = date.fromisoformat(history[-1]["results"]["next_assessment"])
    days_left = (nxt - date.today()).days
    return {"due": days_left <= 0, "next_assessment": nxt.isoformat(), "days_left": max(days_left, 0)}


# ---------------- Fichas de treino ----------------
@app.get("/users/{user_id}/plans/current")
def current_plan(user: User = Depends(load_user), db: Store = Depends(get_store)):
    plans = db.list("plans", user.id)
    if not plans:
        raise HTTPException(404, "Nenhuma ficha ainda: faça a avaliação física")
    return plans[-1]


@app.post("/users/{user_id}/plans/regenerate", status_code=201)
def regenerate_plan(user: User = Depends(load_user), db: Store = Depends(get_store)):
    history = db.list("assessments", user.id)
    if not history:
        raise HTTPException(409, "Faça a avaliação física antes de gerar a ficha")
    plan = planner.build_plan(user, history[-1])
    return db.insert("plans", {**plan, "created_at": datetime.now(timezone.utc).isoformat()}, owner=user.id,
                     sort_key=datetime.now(timezone.utc).isoformat())


# ---------------- Treinos ----------------
def _save_workout(user: User, body: WorkoutIn, db: Store) -> dict:
    if body.healthkit_uuid:
        for existing in db.list("workouts", user.id):
            if existing.get("healthkit_uuid") == body.healthkit_uuid:
                return existing
    cal = calories.session_calories(user, current_weight(user, db), body)
    return db.insert("workouts", {**body.model_dump(mode="json"), "user_id": user.id, "calories": cal},
                     owner=user.id, sort_key=body.started_at.isoformat())


@app.post("/users/{user_id}/workouts", response_model=Workout, status_code=201)
def log_workout(body: WorkoutIn, user: User = Depends(load_user), db: Store = Depends(get_store)):
    return _save_workout(user, body, db)


@app.get("/users/{user_id}/workouts", response_model=list[Workout])
def list_workouts(user: User = Depends(load_user), db: Store = Depends(get_store)):
    return db.list("workouts", user.id)


@app.get("/users/{user_id}/summary/weekly")
def weekly_summary(user: User = Depends(load_user), db: Store = Depends(get_store)):
    now = datetime.now(timezone.utc)
    recent = [w for w in db.list("workouts", user.id)
              if (now - datetime.fromisoformat(w["started_at"])).days < 7]
    return {
        "workouts": len(recent),
        "planned": user.days_per_week,
        "kcal": sum(w["calories"]["kcal"] for w in recent),
        "minutes": round(sum(w["calories"]["duration_min"] for w in recent)),
        "volume_load_kg": sum(w["calories"]["volume_load_kg"] for w in recent),
    }


# ---------------- Sincronização com o app Saúde / Apple Watch ----------------
@app.post("/users/{user_id}/health/sync")
def health_sync(body: HealthSyncIn, user: User = Depends(load_user), db: Store = Depends(get_store)):
    snapshot = {**(db.get("health", user.id) or {}), **body.model_dump(mode="json", exclude={"workouts"}, exclude_none=True)}
    snapshot |= {"id": user.id, "synced_at": datetime.now(timezone.utc).isoformat()}
    db.put("health", snapshot, owner=user.id)
    saved = [_save_workout(user, w, db)["id"] for w in body.workouts]
    return {"snapshot": snapshot, "workouts_saved": saved}


# ---------------- Coach (IA) ----------------
@app.post("/users/{user_id}/coach/chat")
def coach_chat(body: ChatIn, user: User = Depends(load_user), db: Store = Depends(get_store)):
    plans = db.list("plans", user.id)
    context = coach.build_context(
        user.model_dump(mode="json") | {"idade": user.age},
        db.list("assessments", user.id),
        plans[-1] if plans else None,
        db.list("workouts", user.id),
        db.get("health", user.id),
    )
    reply = coach.chat([m.model_dump() for m in body.messages], context)
    return {"role": "assistant", "content": reply}
