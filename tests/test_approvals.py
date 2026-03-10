"""Tests for approval request/response parsing."""

from wuyu.protocol.approvals import (
    CommandExecutionRequestApprovalParams,
    CommandExecutionRequestApprovalResponse,
    FileChangeRequestApprovalParams,
    FileChangeRequestApprovalResponse,
    parse_server_request_params,
)
from wuyu.protocol.types import CommandExecutionApprovalDecision, FileChangeApprovalDecision


class TestCommandExecutionApproval:
    def test_parse_params(self):
        raw = {
            "threadId": "t1",
            "turnId": "turn-1",
            "itemId": "cmd-1",
            "command": "rm -rf /tmp/test",
            "cwd": "/home/user/project",
            "reason": "Agent wants to clean up",
        }
        params = parse_server_request_params("item/commandExecution/requestApproval", raw)
        assert isinstance(params, CommandExecutionRequestApprovalParams)
        assert params.command == "rm -rf /tmp/test"
        assert params.cwd == "/home/user/project"
        assert params.reason == "Agent wants to clean up"

    def test_response_accept(self):
        resp = CommandExecutionRequestApprovalResponse(
            decision=CommandExecutionApprovalDecision.ACCEPT
        )
        data = resp.model_dump(by_alias=True)
        assert data["decision"] == "accept"

    def test_response_decline(self):
        resp = CommandExecutionRequestApprovalResponse(
            decision=CommandExecutionApprovalDecision.DECLINE
        )
        data = resp.model_dump(by_alias=True)
        assert data["decision"] == "decline"


class TestFileChangeApproval:
    def test_parse_params(self):
        raw = {
            "threadId": "t1",
            "turnId": "turn-1",
            "itemId": "fc-1",
            "reason": "Needs write access to /etc",
            "grantRoot": "/etc",
        }
        params = parse_server_request_params("item/fileChange/requestApproval", raw)
        assert isinstance(params, FileChangeRequestApprovalParams)
        assert params.reason == "Needs write access to /etc"
        assert params.grant_root == "/etc"

    def test_response_accept_for_session(self):
        resp = FileChangeRequestApprovalResponse(
            decision=FileChangeApprovalDecision.ACCEPT_FOR_SESSION
        )
        data = resp.model_dump(by_alias=True)
        assert data["decision"] == "acceptForSession"


class TestUnknownServerRequest:
    def test_unknown_method(self):
        result = parse_server_request_params("some/future/approval", {"foo": "bar"})
        assert result is None
