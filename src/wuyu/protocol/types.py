"""Core protocol types shared across messages."""

from __future__ import annotations

from enum import StrEnum

from pydantic import BaseModel

from wuyu.protocol._util import CAMEL_CONFIG

# RequestId can be a string or an integer, matching the upstream definition.
RequestId = str | int


class ClientInfo(BaseModel):
    name: str
    title: str | None = None
    version: str


class InitializeCapabilities(BaseModel):
    """Client-declared capabilities negotiated during initialize."""

    experimental_api: bool = False
    opt_out_notification_methods: list[str] | None = None

    model_config = CAMEL_CONFIG


class InitializeParams(BaseModel):
    client_info: ClientInfo
    capabilities: InitializeCapabilities | None = None

    model_config = CAMEL_CONFIG


class InitializeResponse(BaseModel):
    user_agent: str

    model_config = CAMEL_CONFIG


class TurnStatus(StrEnum):
    COMPLETED = "completed"
    INTERRUPTED = "interrupted"
    FAILED = "failed"
    IN_PROGRESS = "inProgress"


class TurnError(BaseModel):
    message: str
    codex_error_info: dict | None = None
    additional_details: str | None = None

    model_config = CAMEL_CONFIG


class AskForApproval(StrEnum):
    UNLESS_TRUSTED = "unlessTrusted"
    ON_FAILURE = "onFailure"
    ON_REQUEST = "onRequest"
    REJECT = "reject"
    NEVER = "never"


class SandboxPolicy(StrEnum):
    DANGER_FULL_ACCESS = "dangerFullAccess"
    READ_ONLY = "readOnly"
    WORKSPACE_WRITE = "workspaceWrite"
    EXTERNAL_SANDBOX = "externalSandbox"


class FileChangeApprovalDecision(StrEnum):
    ACCEPT = "accept"
    ACCEPT_FOR_SESSION = "acceptForSession"
    DECLINE = "decline"
    CANCEL = "cancel"


class CommandExecutionApprovalDecision(StrEnum):
    ACCEPT = "accept"
    ACCEPT_FOR_SESSION = "acceptForSession"
    ACCEPT_WITH_EXECPOLICY_AMENDMENT = "acceptWithExecpolicyAmendment"
    APPLY_NETWORK_POLICY_AMENDMENT = "applyNetworkPolicyAmendment"
    DECLINE = "decline"
    CANCEL = "cancel"
