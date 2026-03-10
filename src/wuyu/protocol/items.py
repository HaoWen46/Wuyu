"""Thread item types — the things that appear in a conversation thread.

These map to the v2 ThreadItem discriminated union from the Codex App Server protocol.
We model the most important variants as concrete classes and provide a fallback
for unknown/future item types.
"""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel


class UserMessageItem(BaseModel):
    type: Literal["userMessage"] = "userMessage"
    id: str
    text: str | None = None


class AgentMessageItem(BaseModel):
    type: Literal["agentMessage"] = "agentMessage"
    id: str
    text: str = ""
    phase: str | None = None


class CommandExecutionItem(BaseModel):
    type: Literal["commandExecution"] = "commandExecution"
    id: str
    command: str = ""
    cwd: str | None = None
    status: str | None = None
    exit_code: int | None = None
    stdout: str = ""
    stderr: str = ""


class FileChangeItem(BaseModel):
    type: Literal["fileChange"] = "fileChange"
    id: str
    file_path: str = ""
    status: str | None = None
    patch: str = ""


class ReasoningItem(BaseModel):
    type: Literal["reasoning"] = "reasoning"
    id: str
    text: str = ""


class WebSearchItem(BaseModel):
    type: Literal["webSearch"] = "webSearch"
    id: str
    query: str = ""


class ImageGenerationItem(BaseModel):
    type: Literal["imageGeneration"] = "imageGeneration"
    id: str


class ContextCompactionItem(BaseModel):
    type: Literal["contextCompaction"] = "contextCompaction"
    id: str


class McpToolCallItem(BaseModel):
    type: Literal["mcpToolCall"] = "mcpToolCall"
    id: str
    tool_name: str = ""
    server_name: str = ""
    arguments: dict[str, Any] | None = None
    result: Any = None


class CollabAgentToolCallItem(BaseModel):
    type: Literal["collabAgentToolCall"] = "collabAgentToolCall"
    id: str


class UnknownItem(BaseModel):
    """Fallback for item types we don't yet handle."""

    type: str
    id: str
    raw: dict[str, Any] = {}


# All known item types, used for parsing.
ITEM_TYPE_MAP: dict[str, type[BaseModel]] = {
    "userMessage": UserMessageItem,
    "agentMessage": AgentMessageItem,
    "commandExecution": CommandExecutionItem,
    "fileChange": FileChangeItem,
    "reasoning": ReasoningItem,
    "webSearch": WebSearchItem,
    "imageGeneration": ImageGenerationItem,
    "contextCompaction": ContextCompactionItem,
    "mcpToolCall": McpToolCallItem,
    "collabAgentToolCall": CollabAgentToolCallItem,
}

ThreadItem = (
    UserMessageItem
    | AgentMessageItem
    | CommandExecutionItem
    | FileChangeItem
    | ReasoningItem
    | WebSearchItem
    | ImageGenerationItem
    | ContextCompactionItem
    | McpToolCallItem
    | CollabAgentToolCallItem
    | UnknownItem
)


def parse_thread_item(data: dict[str, Any]) -> ThreadItem:
    """Parse a raw dict into a typed ThreadItem."""
    item_type = data.get("type", "")
    cls = ITEM_TYPE_MAP.get(item_type)
    if cls is not None:
        return cls.model_validate(data)
    return UnknownItem(type=item_type, id=data.get("id", ""), raw=data)
