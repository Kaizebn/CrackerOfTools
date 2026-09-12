"""Mémoire structurée : modèles SQLAlchemy et accès synchrone à SQLite.

L'accès est synchrone ; l'``MemoryManager`` asynchrone l'enveloppe dans
``asyncio.to_thread`` pour ne pas bloquer la boucle événementielle.
"""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import Boolean, DateTime, Integer, String, Text, create_engine, select
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    pass


class Conversation(Base):
    __tablename__ = "conversations"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    started_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)
    summary: Mapped[str | None] = mapped_column(Text, default=None)


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    conversation_id: Mapped[int] = mapped_column(Integer, index=True)
    role: Mapped[str] = mapped_column(String(16))
    content: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)


class Fact(Base):
    __tablename__ = "facts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    text: Mapped[str] = mapped_column(Text)
    category: Mapped[str] = mapped_column(String(64), default="general")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)


class Reminder(Base):
    __tablename__ = "reminders"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    due_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    message: Mapped[str] = mapped_column(Text)
    label: Mapped[str] = mapped_column(String(128), default="")
    fired: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)


class ToolCallLog(Base):
    __tablename__ = "tool_calls"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(64))
    arguments: Mapped[str] = mapped_column(Text)
    ok: Mapped[bool] = mapped_column(Boolean)
    display: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)


class Database:
    """Accès synchrone à la base SQLite."""

    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        # check_same_thread=False : on y accède depuis le pool de threads.
        self._engine = create_engine(
            f"sqlite:///{path}", connect_args={"check_same_thread": False}, future=True
        )
        Base.metadata.create_all(self._engine)

    def _session(self) -> Session:
        return Session(self._engine)

    # --- Conversations / messages ---

    def create_conversation(self) -> int:
        with self._session() as session:
            conversation = Conversation()
            session.add(conversation)
            session.commit()
            return conversation.id

    def add_message(self, conversation_id: int, role: str, content: str) -> None:
        with self._session() as session:
            session.add(Message(conversation_id=conversation_id, role=role, content=content))
            session.commit()

    def set_summary(self, conversation_id: int, summary: str) -> None:
        with self._session() as session:
            conversation = session.get(Conversation, conversation_id)
            if conversation is not None:
                conversation.summary = summary
                session.commit()

    # --- Faits ---

    def add_fact(self, text: str, category: str) -> int:
        with self._session() as session:
            fact = Fact(text=text, category=category)
            session.add(fact)
            session.commit()
            return fact.id

    def delete_fact(self, fact_id: int) -> bool:
        with self._session() as session:
            fact = session.get(Fact, fact_id)
            if fact is None:
                return False
            session.delete(fact)
            session.commit()
            return True

    def list_facts(self) -> list[Fact]:
        with self._session() as session:
            return list(session.scalars(select(Fact).order_by(Fact.created_at.desc())))

    # --- Rappels ---

    def add_reminder(self, due_at: datetime, message: str, label: str) -> int:
        with self._session() as session:
            reminder = Reminder(due_at=due_at, message=message, label=label)
            session.add(reminder)
            session.commit()
            return reminder.id

    def pending_reminders(self) -> list[Reminder]:
        with self._session() as session:
            stmt = select(Reminder).where(Reminder.fired == False).order_by(Reminder.due_at)  # noqa: E712
            return list(session.scalars(stmt))

    def mark_fired(self, reminder_id: int) -> None:
        with self._session() as session:
            reminder = session.get(Reminder, reminder_id)
            if reminder is not None:
                reminder.fired = True
                session.commit()

    def cancel_reminder(self, reminder_id: int) -> bool:
        with self._session() as session:
            reminder = session.get(Reminder, reminder_id)
            if reminder is None:
                return False
            session.delete(reminder)
            session.commit()
            return True

    # --- Journal des outils ---

    def log_tool_call(self, name: str, arguments: str, ok: bool, display: str) -> None:
        with self._session() as session:
            session.add(ToolCallLog(name=name, arguments=arguments, ok=ok, display=display))
            session.commit()
