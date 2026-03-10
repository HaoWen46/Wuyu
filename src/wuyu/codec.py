"""JSONL codec for the Codex App Server protocol.

The wire format is newline-delimited JSON (JSONL/NDJSON). Each line is one
complete JSON-RPC message. No HTTP headers, no Content-Length framing.

Encoding: model → JSON string + newline
Decoding: JSON string → discriminated JSONRPCMessage variant

Discrimination logic (since there's no "jsonrpc" field):
  - Has "id" + "method"  → Request
  - Has "method" only    → Notification
  - Has "id" + "result"  → Response
  - Has "id" + "error"   → ErrorResponse
"""

from __future__ import annotations

import json
from typing import Any

from wuyu.protocol.jsonrpc import (
    JSONRPCError,
    JSONRPCErrorResponse,
    JSONRPCMessage,
    JSONRPCNotification,
    JSONRPCRequest,
    JSONRPCResponse,
)


class CodecError(Exception):
    """Raised when a message cannot be encoded or decoded."""


def encode(message: JSONRPCMessage) -> str:
    """Serialize a JSON-RPC message to a JSONL line (with trailing newline).

    Uses by_alias=True so pydantic models with camelCase aliases serialize
    correctly, and exclude_none=True to omit null optional fields.
    """
    if hasattr(message, "model_dump"):
        data = message.model_dump(by_alias=True, exclude_none=True)
    else:
        data = message  # type: ignore[assignment]
    return json.dumps(data, separators=(",", ":")) + "\n"


def decode(line: str) -> JSONRPCMessage:
    """Parse a single JSONL line into a JSONRPCMessage variant.

    Raises CodecError if the line is not valid JSON or doesn't match any variant.
    """
    line = line.strip()
    if not line:
        raise CodecError("empty line")

    try:
        data: dict[str, Any] = json.loads(line)
    except json.JSONDecodeError as e:
        raise CodecError(f"invalid JSON: {e}") from e

    if not isinstance(data, dict):
        raise CodecError(f"expected JSON object, got {type(data).__name__}")

    return _classify(data)


def _classify(data: dict[str, Any]) -> JSONRPCMessage:
    """Determine the message variant from its fields."""
    has_id = "id" in data
    has_method = "method" in data
    has_result = "result" in data
    has_error = "error" in data

    if has_id and has_error:
        return JSONRPCErrorResponse(
            id=data["id"],
            error=JSONRPCError.model_validate(data["error"]),
        )

    if has_id and has_result:
        return JSONRPCResponse(id=data["id"], result=data.get("result"))

    if has_id and has_method:
        return JSONRPCRequest(
            id=data["id"],
            method=data["method"],
            params=data.get("params"),
        )

    if has_method and not has_id:
        return JSONRPCNotification(
            method=data["method"],
            params=data.get("params"),
        )

    # Response with just id and no result/error — treat as empty result
    if has_id and not has_method and not has_error:
        return JSONRPCResponse(id=data["id"], result=data.get("result"))

    raise CodecError(f"cannot classify message: {data!r}")
