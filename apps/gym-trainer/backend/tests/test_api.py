from datetime import date, datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app import science
from app.main import app, get_store
from app.storage import Store


@pytest.fixture
def client(tmp_path):
    db = Store(str(tmp_path / "test.db"))
    app.dependency_overrides[get_store] = lambda: db
    yield TestClient(app)
    app.dependency_overrides.clear()


def make_user(client, **overrides):
    body = {
        "name": "Rafael",
        "sex": "male",
        "birth_date": "1990-05-10",
        "height_cm": 178,
        "goal": "hypertrophy",
        "experience": "intermediate",
        "days_per_week": 4,
    } | overrides
    r = client.post("/users", json=body)
    assert r.status_code == 201
    return r.json()


ASSESSMENT = {
    "date": "2026-08-25",
    "weight_kg": 84,
    "skinfolds": {"chest": 12, "abdominal": 24, "thigh": 16},
    "circumferences": {"neck": 39, "waist": 90, "hip": 100, "right_arm": 36},
    "exams": {"systolic_bp": 124, "diastolic_bp": 80, "resting_hr": 62, "fasting_glucose": 92},
}


def test_science_reference_values():
    # Mifflin-St Jeor: homem 80 kg, 180 cm, 30 anos -> 1780 kcal
    assert science.bmr_mifflin(80, 180, 30, "male") == 1780
    assert science.hr_max_tanaka(30) == 187
    # Siri: densidade 1,06 -> 17,0%
    assert science.siri_body_fat(1.06) == 17.0
    # Keytel: 140 bpm, 80 kg, 30 anos, 60 min -> ~782 kcal
    assert 770 < science.kcal_from_heart_rate(140, 80, 30, "male", 60) < 795
    assert science.kcal_from_met(5.0, 80, 60) == 420.0


def test_assessment_generates_plan(client):
    user = make_user(client)
    r = client.post(f"/users/{user['id']}/assessments", json=ASSESSMENT)
    assert r.status_code == 201
    res = r.json()["results"]
    assert res["composition"]["body_fat_method"].startswith("Jackson & Pollock 3")
    assert 10 < res["composition"]["body_fat_pct"] < 25
    assert res["next_assessment"] == "2026-10-24"
    assert res["nutrition"]["protein_g"] == round(1.8 * 84)

    plan = client.get(f"/users/{user['id']}/plans/current").json()
    assert plan["split"] == ["Superiores A", "Inferiores A", "Superiores B", "Inferiores B"]
    first = plan["days"][0]["exercises"][0]
    assert first["exercise"]["demonstration"]["steps"]
    assert first["exercise"]["demonstration"]["video_url"].startswith("https://")
    assert plan["days"][0]["cardio"]["duration_min"] > 0


def test_restrictions_from_injuries_and_exams(client):
    user = make_user(client, injuries=["lower_back", "knee"], experience="advanced", days_per_week=5)
    body = ASSESSMENT | {"exams": {"systolic_bp": 165, "diastolic_bp": 102}}
    res = client.post(f"/users/{user['id']}/assessments", json=body).json()["results"]
    assert res["needs_medical_clearance"]
    assert "hypertension_uncontrolled" in res["restrictions"]

    plan = client.get(f"/users/{user['id']}/plans/current").json()
    ids = {e["exercise"]["id"] for d in plan["days"] for e in d["exercises"]}
    assert not ids & {"back_squat", "deadlift", "barbell_row", "romanian_deadlift", "bulgarian_split_squat"}
    assert "hiit_option" not in plan["days"][0]["cardio"]


def test_progress_between_assessments(client):
    user = make_user(client)
    client.post(f"/users/{user['id']}/assessments", json=ASSESSMENT)
    second = ASSESSMENT | {"date": "2026-10-24", "weight_kg": 83, "skinfolds": {"chest": 10, "abdominal": 20, "thigh": 14}}
    res = client.post(f"/users/{user['id']}/assessments", json=second).json()["results"]
    assert res["progress"]["days_between"] == 60
    assert res["progress"]["fat_mass_kg"] < 0
    assert len(client.get(f"/users/{user['id']}/assessments").json()) == 2


def test_workout_calories_sources(client):
    user = make_user(client)
    client.post(f"/users/{user['id']}/assessments", json=ASSESSMENT)
    start = datetime(2026, 10, 20, 18, 0, tzinfo=timezone.utc)
    hr = [{"timestamp": (start + timedelta(minutes=i)).isoformat(), "bpm": 120 + i % 20} for i in range(60)]
    base = {"started_at": start.isoformat(), "ended_at": (start + timedelta(minutes=60)).isoformat(),
            "sets": [{"exercise_id": "bench_press", "set_number": 1, "reps": 10, "weight_kg": 60}]}

    w = client.post(f"/users/{user['id']}/workouts", json=base | {"heart_rate": hr}).json()
    assert w["calories"]["source"].startswith("Frequência")
    w = client.post(f"/users/{user['id']}/workouts", json=base | {"active_energy_kcal": 410, "healthkit_uuid": "ABC"}).json()
    assert w["calories"]["kcal"] == 410
    assert w["calories"]["volume_load_kg"] == 600


def test_health_sync_dedupes_watch_workouts(client):
    user = make_user(client)
    client.post(f"/users/{user['id']}/assessments", json=ASSESSMENT)
    start = datetime.now(timezone.utc) - timedelta(hours=2)
    workout = {"started_at": start.isoformat(), "ended_at": (start + timedelta(minutes=50)).isoformat(),
               "active_energy_kcal": 380, "avg_hr": 128, "source": "apple_watch", "healthkit_uuid": "HK-1"}
    payload = {"weight_kg": 83.5, "resting_hr": 60, "vo2max": 44.2, "workouts": [workout]}
    first = client.post(f"/users/{user['id']}/health/sync", json=payload).json()
    second = client.post(f"/users/{user['id']}/health/sync", json=payload).json()
    assert first["workouts_saved"] == second["workouts_saved"]
    summary = client.get(f"/users/{user['id']}/summary/weekly").json()
    assert summary["workouts"] == 1 and summary["kcal"] == 380


def test_coach_without_api_key(client, monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    user = make_user(client)
    r = client.post(f"/users/{user['id']}/coach/chat", json={"messages": [{"role": "user", "content": "Oi"}]})
    assert "ANTHROPIC_API_KEY" in r.json()["content"]


def test_assessment_status_due_without_history(client):
    user = make_user(client)
    status = client.get(f"/users/{user['id']}/assessments/status").json()
    assert status["due"] and status["next_assessment"] == date.today().isoformat()


def test_every_alternative_exists():
    from app import exercises
    from app.planner import DAY_TEMPLATES

    for ex in exercises.CATALOG:
        for alt in ex.alternatives:
            assert alt in exercises.BY_ID, (ex.id, alt)
    for slots in DAY_TEMPLATES.values():
        for slot in slots:
            for cid in slot:
                assert cid in exercises.BY_ID, cid
