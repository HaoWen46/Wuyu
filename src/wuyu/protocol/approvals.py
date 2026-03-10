"""Approval request/response types for server-initiated requests.

The server sends these as JSON-RPC requests (with an id) and expects a response.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel

from wuyu.protocol._util import CAMEL_CONFIG
from wuyu.protocol.types import CommandExecutionApprovalDecision, FileChangeApprovalDecision

# --- Command execution approval ---


class CommandExecutionRequestApprovalParams(BaseModel):
    thread_id: str
    turn_id: str
    item_id: str
    command: str = ""
    cwd: str | None = None
    reason: str | None = None
    approval_id: str | None = None
    available_decisions: list[str] | None = None
    network_approval_context: dict[str, Any] | None = None
    additional_permissions: dict[str, Any] | None = None

    model_config = CAMEL_CONFIG


class CommandExecutionRequestApprovalResponse(BaseModel):
    decision: CommandExecutionApprovalDecision

    model_config = CAMEL_CONFIG


# --- File change approval ---


class FileChangeRequestApprovalParams(BaseModel):
    thread_id: str
    turn_id: str
    item_id: str
    reason: str | None = None
    grant_root: str | None = None

    model_config = CAMEL_CONFIG


class FileChangeRequestApprovalResponse(BaseModel):
    decision: FileChangeApprovalDecision

    model_config = CAMEL_CONFIG


# --- Permissions approval ---


class PermissionsRequestApprovalParams(BaseModel):
    thread_id: str
    turn_id: str
    item_id: str
    permissions: dict[str, Any] | None = None

    model_config = CAMEL_CONFIG


class PermissionsRequestApprovalResponse(BaseModel):
    granted: bool


# --- Server request method → params type mapping ---

SERVER_REQUEST_PARAMS_MAP: dict[str, type[BaseModel]] = {
    "item/commandExecution/requestApproval": CommandExecutionRequestApprovalParams,
    "item/fileChange/requestApproval": FileChangeRequestApprovalParams,
    "item/permissions/requestApproval": PermissionsRequestApprovalParams,
}


def parse_server_request_params(method: str, params: dict[str, Any] | None) -> BaseModel | None:
    """Parse server request params into a typed object, or None if unknown."""
    cls = SERVER_REQUEST_PARAMS_MAP.get(method)
    if cls is None or params is None:
        return None
    return cls.model_validate(params)
