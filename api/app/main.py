from __future__ import annotations

import hashlib
import hmac
import os
import re
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Iterator

from fastapi import FastAPI, Header, HTTPException, Request
from pydantic import BaseModel, Field

DB_PATH = os.getenv("LAB_DB_PATH", "/data/labcpf.db")
CLIENT_TOKEN = os.getenv("LAB_API_TOKEN", "")
ADMIN_TOKEN = os.getenv("LAB_ADMIN_TOKEN", "")
SEED_CPF = os.getenv("LAB_SEED_CPF", "")
SEED_NAME = os.getenv("LAB_SEED_NAME", "Aluno Teste")

app = FastAPI(title="Lab CPF Auth API", version="7.0.0")


class AuthRequest(BaseModel):
    cpf: str = Field(min_length=1, max_length=32)
    computer: str = Field(min_length=1, max_length=128)


class StudentCreate(BaseModel):
    cpf: str = Field(min_length=1, max_length=32)
    name: str = Field(min_length=1, max_length=200)
    active: bool = True


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def normalize_cpf(value: str) -> str:
    return re.sub(r"\D", "", value or "")


def valid_cpf(value: str) -> bool:
    cpf = normalize_cpf(value)
    if len(cpf) != 11 or cpf == cpf[0] * 11:
        return False

    for pos in (9, 10):
        total = 0
        weight = pos + 1
        for i in range(pos):
            total += int(cpf[i]) * (weight - i)
        digit = (total * 10) % 11
        if digit == 10:
            digit = 0
        if digit != int(cpf[pos]):
            return False
    return True


def secure_equals(a: str, b: str) -> bool:
    return bool(a) and bool(b) and hmac.compare_digest(a.encode(), b.encode())


@contextmanager
def db() -> Iterator[sqlite3.Connection]:
    os.makedirs(os.path.dirname(DB_PATH) or ".", exist_ok=True)
    con = sqlite3.connect(DB_PATH, timeout=5)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA busy_timeout=5000")
    try:
        yield con
        con.commit()
    finally:
        con.close()


def init_db() -> None:
    with db() as con:
        con.executescript(
            """
            CREATE TABLE IF NOT EXISTS students (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                cpf TEXT NOT NULL UNIQUE,
                name TEXT NOT NULL,
                active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS auth_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                cpf TEXT NOT NULL,
                computer TEXT NOT NULL,
                source_ip TEXT,
                authorized INTEGER NOT NULL,
                reason TEXT NOT NULL,
                created_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_auth_logs_created_at
                ON auth_logs(created_at DESC);
            """
        )

        if SEED_CPF:
            cpf = normalize_cpf(SEED_CPF)
            if valid_cpf(cpf):
                con.execute(
                    """
                    INSERT INTO students (cpf, name, active, created_at, updated_at)
                    VALUES (?, ?, 1, ?, ?)
                    ON CONFLICT(cpf) DO NOTHING
                    """,
                    (cpf, SEED_NAME, now_iso(), now_iso()),
                )


@app.on_event("startup")
def startup() -> None:
    if not CLIENT_TOKEN:
        raise RuntimeError("LAB_API_TOKEN nao configurado")
    if not ADMIN_TOKEN:
        raise RuntimeError("LAB_ADMIN_TOKEN nao configurado")
    init_db()


def require_client_token(token: str | None) -> None:
    if not token or not secure_equals(token, CLIENT_TOKEN):
        raise HTTPException(status_code=401, detail="cliente nao autorizado")


def require_admin_token(token: str | None) -> None:
    if not token or not secure_equals(token, ADMIN_TOKEN):
        raise HTTPException(status_code=401, detail="administrador nao autorizado")


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "lab-cpf-auth", "version": "7.0.0"}


@app.post("/auth/cpf")
def auth_cpf(
    payload: AuthRequest,
    request: Request,
    x_lab_token: str | None = Header(default=None),
) -> dict:
    require_client_token(x_lab_token)

    cpf = normalize_cpf(payload.cpf)
    computer = payload.computer.strip()[:128]
    source_ip = request.client.host if request.client else None

    authorized = False
    reason = "cpf_invalido"
    name = None

    if valid_cpf(cpf):
        with db() as con:
            row = con.execute(
                "SELECT cpf, name, active FROM students WHERE cpf = ?",
                (cpf,),
            ).fetchone()

            if row is None:
                reason = "nao_cadastrado"
            elif not bool(row["active"]):
                reason = "inativo"
                name = row["name"]
            else:
                authorized = True
                reason = "autorizado"
                name = row["name"]

            con.execute(
                """
                INSERT INTO auth_logs
                    (cpf, computer, source_ip, authorized, reason, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (cpf, computer, source_ip, int(authorized), reason, now_iso()),
            )
    else:
        with db() as con:
            con.execute(
                """
                INSERT INTO auth_logs
                    (cpf, computer, source_ip, authorized, reason, created_at)
                VALUES (?, ?, ?, 0, ?, ?)
                """,
                (cpf, computer, source_ip, reason, now_iso()),
            )

    return {
        "authorized": authorized,
        "reason": reason,
        "name": name,
    }


@app.get("/admin/students")
def list_students(x_admin_token: str | None = Header(default=None)) -> list[dict]:
    require_admin_token(x_admin_token)
    with db() as con:
        rows = con.execute(
            "SELECT cpf, name, active, created_at, updated_at FROM students ORDER BY name, cpf"
        ).fetchall()
    return [
        {
            "cpf": r["cpf"],
            "name": r["name"],
            "active": bool(r["active"]),
            "created_at": r["created_at"],
            "updated_at": r["updated_at"],
        }
        for r in rows
    ]


@app.post("/admin/students")
def upsert_student(
    payload: StudentCreate,
    x_admin_token: str | None = Header(default=None),
) -> dict:
    require_admin_token(x_admin_token)

    cpf = normalize_cpf(payload.cpf)
    if not valid_cpf(cpf):
        raise HTTPException(status_code=400, detail="CPF invalido")

    with db() as con:
        con.execute(
            """
            INSERT INTO students (cpf, name, active, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(cpf) DO UPDATE SET
                name = excluded.name,
                active = excluded.active,
                updated_at = excluded.updated_at
            """,
            (cpf, payload.name.strip(), int(payload.active), now_iso(), now_iso()),
        )

    return {"ok": True, "cpf": cpf}


@app.delete("/admin/students/{cpf}")
def delete_student(
    cpf: str,
    x_admin_token: str | None = Header(default=None),
) -> dict:
    require_admin_token(x_admin_token)

    normalized = normalize_cpf(cpf)
    with db() as con:
        cur = con.execute("DELETE FROM students WHERE cpf = ?", (normalized,))
    return {"ok": True, "deleted": cur.rowcount > 0}


@app.get("/admin/logs")
def auth_logs(
    limit: int = 100,
    x_admin_token: str | None = Header(default=None),
) -> list[dict]:
    require_admin_token(x_admin_token)
    limit = max(1, min(limit, 1000))

    with db() as con:
        rows = con.execute(
            """
            SELECT cpf, computer, source_ip, authorized, reason, created_at
            FROM auth_logs
            ORDER BY id DESC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()

    return [
        {
            "cpf": r["cpf"],
            "computer": r["computer"],
            "source_ip": r["source_ip"],
            "authorized": bool(r["authorized"]),
            "reason": r["reason"],
            "created_at": r["created_at"],
        }
        for r in rows
    ]
