"""Server notification event types (v2).

These are the params for server-to-client notifications. Each maps to a
"method" string in the ServerNotification union.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel

from wuyu.protocol._util import CAMEL_CONFIG
from wuyu.protocol.items import ThreadItem, parse_thread_item
from wuyu.protocol.types import TurnError, TurnStatus

# --- Thread lifecycle ---


class ThreadStartedNotification(BaseModel):
    thread_id: str

    model_config = CAMEL_CONFIG


class ThreadStatusChangedNotification(BaseModel):
    thread_id: str
    status: str

    model_config = CAMEL_CONFIG


class ThreadNameUpdatedNotification(BaseModel):
    thread_id: str
    name: str

    model_config = CAMEL_CONFIG


class ThreadClosedNotification(BaseModel):
    thread_id: str

    model_config = CAMEL_CONFIG


# --- Turn lifecycle ---


class Turn(BaseModel):
    id: str
    items: list[dict[str, Any]] = []
    status: TurnStatus
    error: TurnError | None = None


class TurnStartedNotification(BaseModel):
    thread_id: str
    turn: Turn

    model_config = CAMEL_CONFIG


class TurnCompletedNotification(BaseModel):
    thread_id: str
    turn: Turn

    model_config = CAMEL_CONFIG


# --- Item lifecycle ---


class ItemStartedNotification(BaseModel):
    """Raw notification — item is a dict, call parse_item() for typed access."""

    item: dict[str, Any]
    thread_id: str
    turn_id: str

    model_config = CAMEL_CONFIG

    def parse_item(self) -> ThreadItem:
        return parse_thread_item(self.item)


class ItemCompletedNotification(BaseModel):
    item: dict[str, Any]
    thread_id: str
    turn_id: str

    model_config = CAMEL_CONFIG

    def parse_item(self) -> ThreadItem:
        return parse_thread_item(self.item)


class AgentMessageDeltaNotification(BaseModel):
    thread_id: str
    turn_id: str
    item_id: str
    delta: str

    model_config = CAMEL_CONFIG


class CommandExecutionOutputDeltaNotification(BaseModel):
    thread_id: str
    turn_id: str
    item_id: str
    stream: str = ""
    delta: str = ""

    model_config = CAMEL_CONFIG


class FileChangeOutputDeltaNotification(BaseModel):
    thread_id: str
    turn_id: str
    item_id: str
    delta: str = ""

    model_config = CAMEL_CONFIG


class ErrorNotification(BaseModel):
    message: str
    code: int | None = None


# --- Mapping from method strings to notification types ---

NOTIFICATION_TYPE_MAP: dict[str, type[BaseModel]] = {
    "thread/started": ThreadStartedNotification,
    "thread/status/changed": ThreadStatusChangedNotification,
    "thread/name/updated": ThreadNameUpdatedNotification,
    "thread/closed": ThreadClosedNotification,
    "turn/started": TurnStartedNotification,
    "turn/completed": TurnCompletedNotification,
    "item/started": ItemStartedNotification,
    "item/completed": ItemCompletedNotification,
    "item/agentMessage/delta": AgentMessageDeltaNotification,
    "item/commandExecution/outputDelta": CommandExecutionOutputDeltaNotification,
    "item/fileChange/outputDelta": FileChangeOutputDeltaNotification,
    "error": ErrorNotification,
}


def parse_notification_params(method: str, params: dict[str, Any] | None) -> BaseModel | None:
    """Parse notification params into a typed object, or None if unknown."""
    cls = NOTIFICATION_TYPE_MAP.get(method)
    if cls is None or params is None:
        return None
    return cls.model_validate(params)
