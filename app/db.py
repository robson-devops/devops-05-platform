"""Conexão com o PostgreSQL. A senha chega por variável de ambiente, injetada
pelo ECS a partir do Secrets Manager."""

import os

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker


def database_url() -> str:
    host = os.environ["DB_HOST"]
    port = os.getenv("DB_PORT", "5432")
    name = os.environ["DB_NAME"]
    user = os.environ["DB_USER"]
    password = os.environ["DB_PASSWORD"]
    # O RDS recusa conexão sem TLS (rds.force_ssl). Local: DB_SSLMODE=disable.
    sslmode = os.getenv("DB_SSLMODE", "require")
    return f"postgresql+psycopg://{user}:{password}@{host}:{port}/{name}?sslmode={sslmode}"


# pool_pre_ping descarta conexões mortas depois de um failover do RDS.
engine = create_engine(
    database_url(),
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=5,
    connect_args={"connect_timeout": 3},
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def get_session():
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()
