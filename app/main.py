"""API de tarefas do devops-05-platform.

GET /health      liveness, sem tocar no banco; informa versão e ambiente
GET /ready       readiness, confirma a conexão com o banco
GET /tasks       lista tarefas
POST /tasks      cria tarefa
GET /tasks/{id}  busca uma tarefa
DELETE /tasks/{id} remove uma tarefa
"""

import os
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from typing import Annotated
from uuid import uuid4

from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import Boolean, DateTime, String, select, text
from sqlalchemy.orm import Mapped, Session, mapped_column

from db import Base, engine, get_session

APP_VERSION = os.getenv("APP_VERSION", "local")
APP_ENV = os.getenv("APP_ENV", "local")

SessionDep = Annotated[Session, Depends(get_session)]


class Task(Base):
    __tablename__ = "tasks"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    done: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class TaskIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    done: bool = False


class TaskOut(TaskIn):
    model_config = ConfigDict(from_attributes=True)

    id: str
    created_at: datetime


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Uma tabela só; Alembic entra quando o schema começar a evoluir.
    Base.metadata.create_all(engine)
    yield


app = FastAPI(title="devops-05-platform", version=APP_VERSION, lifespan=lifespan)


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "version": APP_VERSION, "environment": APP_ENV}


@app.get("/ready")
def ready(session: SessionDep) -> dict:
    try:
        session.execute(text("SELECT 1"))
    except Exception as exc:
        raise HTTPException(status_code=503, detail="banco indisponível") from exc
    return {"status": "ready"}


@app.get("/tasks", response_model=list[TaskOut])
def list_tasks(session: SessionDep) -> list[Task]:
    return list(session.scalars(select(Task).order_by(Task.created_at)))


@app.post("/tasks", response_model=TaskOut, status_code=201)
def create_task(payload: TaskIn, session: SessionDep) -> Task:
    task = Task(
        id=str(uuid4()),
        title=payload.title,
        done=payload.done,
        created_at=datetime.now(UTC),
    )
    session.add(task)
    session.commit()
    return task


@app.get("/tasks/{task_id}", response_model=TaskOut)
def get_task(task_id: str, session: SessionDep) -> Task:
    task = session.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="tarefa não encontrada")
    return task


@app.delete("/tasks/{task_id}", status_code=204)
def delete_task(task_id: str, session: SessionDep) -> None:
    task = session.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="tarefa não encontrada")
    session.delete(task)
    session.commit()
