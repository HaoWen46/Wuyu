"""Tests for protocol types — serialization to/from camelCase JSON."""

from wuyu.protocol.types import (
    ClientInfo,
    CommandExecutionApprovalDecision,
    FileChangeApprovalDecision,
    InitializeCapabilities,
    InitializeParams,
    InitializeResponse,
    TurnError,
    TurnStatus,
)


class TestClientInfo:
    def test_basic(self):
        info = ClientInfo(name="wuyu", title="Wuyu Mobile", version="0.1.0")
        assert info.name == "wuyu"
        assert info.title == "Wuyu Mobile"

    def test_title_optional(self):
        info = ClientInfo(name="wuyu", version="0.1.0")
        assert info.title is None

    def test_from_dict(self):
        info = ClientInfo.model_validate({"name": "test", "version": "1.0"})
        assert info.name == "test"


class TestInitializeParams:
    def test_serializes_camel_case(self):
        params = InitializeParams(
            client_info=ClientInfo(name="wuyu", version="0.1.0"),
            capabilities=InitializeCapabilities(experimental_api=True),
        )
        data = params.model_dump(by_alias=True, exclude_none=True)
        assert "clientInfo" in data
        assert "capabilities" in data
        assert data["capabilities"]["experimentalApi"] is True

    def test_deserializes_camel_case(self):
        raw = {
            "clientInfo": {"name": "wuyu", "version": "0.1.0"},
            "capabilities": {"experimentalApi": False},
        }
        params = InitializeParams.model_validate(raw)
        assert params.client_info.name == "wuyu"
        assert params.capabilities.experimental_api is False

    def test_capabilities_optional(self):
        raw = {"clientInfo": {"name": "wuyu", "version": "0.1.0"}}
        params = InitializeParams.model_validate(raw)
        assert params.capabilities is None


class TestInitializeResponse:
    def test_deserializes_camel_case(self):
        raw = {"userAgent": "codex-app-server/0.113.0"}
        resp = InitializeResponse.model_validate(raw)
        assert resp.user_agent == "codex-app-server/0.113.0"

    def test_serializes_camel_case(self):
        resp = InitializeResponse(user_agent="codex/1.0")
        data = resp.model_dump(by_alias=True)
        assert data == {"userAgent": "codex/1.0"}


class TestTurnStatus:
    def test_values(self):
        assert TurnStatus.COMPLETED.value == "completed"
        assert TurnStatus.IN_PROGRESS.value == "inProgress"
        assert TurnStatus.FAILED.value == "failed"
        assert TurnStatus.INTERRUPTED.value == "interrupted"

    def test_from_string(self):
        assert TurnStatus("completed") == TurnStatus.COMPLETED
        assert TurnStatus("inProgress") == TurnStatus.IN_PROGRESS


class TestTurnError:
    def test_deserializes(self):
        raw = {"message": "rate limited", "additionalDetails": "try again"}
        err = TurnError.model_validate(raw)
        assert err.message == "rate limited"
        assert err.additional_details == "try again"
        assert err.codex_error_info is None


class TestApprovalDecisions:
    def test_command_decisions(self):
        assert CommandExecutionApprovalDecision.ACCEPT.value == "accept"
        assert CommandExecutionApprovalDecision.DECLINE.value == "decline"
        assert CommandExecutionApprovalDecision.ACCEPT_FOR_SESSION.value == "acceptForSession"

    def test_file_change_decisions(self):
        assert FileChangeApprovalDecision.ACCEPT.value == "accept"
        assert FileChangeApprovalDecision.CANCEL.value == "cancel"
