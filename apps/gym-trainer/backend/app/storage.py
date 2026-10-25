"""Persistência simples em SQLite (documentos JSON por coleção)."""

from __future__ import annotations

import json
import os
import sqlite3
import threading
import uuid
from typing import Any


class Store:
    def __init__(self, path: str | None = None) -> None:
        self.path = path or os.getenv("GYM_DB", "gym_trainer.db")
        self._lock = threading.Lock()
        self._conn = sqlite3.connect(self.path, check_same_thread=False)
        self._conn.execute(
            "CREATE TABLE IF NOT EXISTS docs ("
            " collection TEXT, id TEXT, owner TEXT, sort_key TEXT, data TEXT,"
            " PRIMARY KEY (collection, id))"
        )

    def insert(self, collection: str, data: dict[str, Any], owner: str = "", sort_key: str = "") -> dict:
        data = {"id": uuid.uuid4().hex[:12], **data}
        with self._lock, self._conn:
            self._conn.execute(
                "INSERT INTO docs VALUES (?, ?, ?, ?, ?)",
                (collection, data["id"], owner, sort_key, json.dumps(data, default=str)),
            )
        return data

    def put(self, collection: str, data: dict[str, Any], owner: str = "", sort_key: str = "") -> dict:
        with self._lock, self._conn:
            self._conn.execute(
                "INSERT OR REPLACE INTO docs VALUES (?, ?, ?, ?, ?)",
                (collection, data["id"], owner, sort_key, json.dumps(data, default=str)),
            )
        return data

    def get(self, collection: str, doc_id: str) -> dict | None:
        row = self._conn.execute(
            "SELECT data FROM docs WHERE collection = ? AND id = ?", (collection, doc_id)
        ).fetchone()
        return json.loads(row[0]) if row else None

    def list(self, collection: str, owner: str) -> list[dict]:
        rows = self._conn.execute(
            "SELECT data FROM docs WHERE collection = ? AND owner = ? ORDER BY sort_key, rowid",
            (collection, owner),
        ).fetchall()
        return [json.loads(r[0]) for r in rows]
