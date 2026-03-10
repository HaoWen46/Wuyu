"""JSON-RPC message types for the Codex App Server protocol.

Note: The Codex App Server uses a non-standard JSON-RPC 2.0 — it omits the
"jsonrpc": "2.0" field. Messages are one of: Request, Notification, Response, Error.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel

from wuyu.protocol.types import RequestId


class JSONRPCRequest(BaseModel):
    """A request from client to server (or server to client for approvals).
    Expects a response with the same id."""

    id: RequestId
    method: str
    params: dict[str, Any] | None = None


class JSONRPCNotification(BaseModel):
    """A fire-and-forget message (no id, no response expected)."""

    method: str
    params: dict[str, Any] | None = None


class JSONRPCError(BaseModel):
    """Error detail within an error response."""

    code: int
    message: str
    data: Any | None = None


class JSONRPCResponse(BaseModel):
    """Successful response to a request."""

    id: RequestId
    result: Any = None


class JSONRPCErrorResponse(BaseModel):
    """Error response to a request."""

    id: RequestId
    error: JSONRPCError


# Discriminated union of all message types.
# We use a tagged union approach for deserialization — see codec.py for the
# parse logic that inspects fields to determine the variant.
JSONRPCMessage = JSONRPCRequest | JSONRPCNotification | JSONRPCResponse | JSONRPCErrorResponse


# Well-known error codes
ERROR_SERVER_OVERLOADED = -32001
ERROR_PARSE_ERROR = -32700
ERROR_INVALID_REQUEST = -32600
ERROR_METHOD_NOT_FOUND = -32601
