"""Tests for the JSONL codec — encode/decode round-trips and edge cases."""

import json

import pytest

from wuyu.codec import CodecError, decode, encode
from wuyu.protocol.jsonrpc import (
    JSONRPCError,
    JSONRPCErrorResponse,
    JSONRPCNotification,
    JSONRPCRequest,
    JSONRPCResponse,
)


class TestEncode:
    def test_request(self):
        msg = JSONRPCRequest(id=1, method="initialize", params={"key": "val"})
        line = encode(msg)
        assert line.endswith("\n")
        data = json.loads(line)
        assert data == {"id": 1, "method": "initialize", "params": {"key": "val"}}

    def test_request_no_params(self):
        msg = JSONRPCRequest(id="abc", method="thread/list")
        line = encode(msg)
        data = json.loads(line)
        assert data == {"id": "abc", "method": "thread/list"}
        assert "params" not in data  # exclude_none

    def test_notification(self):
        msg = JSONRPCNotification(method="initialized")
        line = encode(msg)
        data = json.loads(line)
        assert data == {"method": "initialized"}

    def test_notification_with_params(self):
        msg = JSONRPCNotification(method="error", params={"message": "oops"})
        line = encode(msg)
        data = json.loads(line)
        assert data == {"method": "error", "params": {"message": "oops"}}

    def test_response(self):
        msg = JSONRPCResponse(id=42, result={"userAgent": "codex/1.0"})
        line = encode(msg)
        data = json.loads(line)
        assert data == {"id": 42, "result": {"userAgent": "codex/1.0"}}

    def test_error_response(self):
        msg = JSONRPCErrorResponse(id=7, error=JSONRPCError(code=-32001, message="overloaded"))
        line = encode(msg)
        data = json.loads(line)
        assert data["id"] == 7
        assert data["error"]["code"] == -32001

    def test_compact_json(self):
        """Encoded JSON should be compact (no extra spaces)."""
        msg = JSONRPCRequest(id=1, method="test", params={"a": 1, "b": 2})
        line = encode(msg)
        assert " " not in line.strip()  # no spaces in compact JSON


class TestDecode:
    def test_request(self):
        line = '{"id": 1, "method": "initialize", "params": {"foo": "bar"}}'
        msg = decode(line)
        assert isinstance(msg, JSONRPCRequest)
        assert msg.id == 1
        assert msg.method == "initialize"
        assert msg.params == {"foo": "bar"}

    def test_request_string_id(self):
        line = '{"id": "req-1", "method": "thread/start"}'
        msg = decode(line)
        assert isinstance(msg, JSONRPCRequest)
        assert msg.id == "req-1"

    def test_notification(self):
        line = '{"method": "initialized"}'
        msg = decode(line)
        assert isinstance(msg, JSONRPCNotification)
        assert msg.method == "initialized"
        assert msg.params is None

    def test_notification_with_params(self):
        line = '{"method": "item/agentMessage/delta", "params": {"delta": "hello"}}'
        msg = decode(line)
        assert isinstance(msg, JSONRPCNotification)
        assert msg.params["delta"] == "hello"

    def test_response(self):
        line = '{"id": 1, "result": {"userAgent": "codex/1.0"}}'
        msg = decode(line)
        assert isinstance(msg, JSONRPCResponse)
        assert msg.id == 1
        assert msg.result == {"userAgent": "codex/1.0"}

    def test_response_null_result(self):
        line = '{"id": 1, "result": null}'
        msg = decode(line)
        assert isinstance(msg, JSONRPCResponse)
        assert msg.result is None

    def test_error_response(self):
        line = '{"id": 5, "error": {"code": -32001, "message": "overloaded"}}'
        msg = decode(line)
        assert isinstance(msg, JSONRPCErrorResponse)
        assert msg.error.code == -32001
        assert msg.error.message == "overloaded"

    def test_error_response_with_data(self):
        line = '{"id": 5, "error": {"code": -32600, "message": "bad", "data": {"detail": "x"}}}'
        msg = decode(line)
        assert isinstance(msg, JSONRPCErrorResponse)
        assert msg.error.data == {"detail": "x"}

    def test_empty_line_raises(self):
        with pytest.raises(CodecError, match="empty"):
            decode("")

    def test_whitespace_only_raises(self):
        with pytest.raises(CodecError, match="empty"):
            decode("   \n")

    def test_invalid_json_raises(self):
        with pytest.raises(CodecError, match="invalid JSON"):
            decode("{broken")

    def test_non_object_raises(self):
        with pytest.raises(CodecError, match="expected JSON object"):
            decode("[1, 2, 3]")

    def test_strips_trailing_newline(self):
        line = '{"method": "initialized"}\n'
        msg = decode(line)
        assert isinstance(msg, JSONRPCNotification)


class TestRoundTrip:
    """Encode then decode should produce an equivalent message."""

    def test_request_roundtrip(self):
        original = JSONRPCRequest(id=99, method="turn/start", params={"text": "hi"})
        restored = decode(encode(original))
        assert isinstance(restored, JSONRPCRequest)
        assert restored.id == original.id
        assert restored.method == original.method
        assert restored.params == original.params

    def test_notification_roundtrip(self):
        original = JSONRPCNotification(method="initialized")
        restored = decode(encode(original))
        assert isinstance(restored, JSONRPCNotification)
        assert restored.method == original.method

    def test_response_roundtrip(self):
        original = JSONRPCResponse(id="r1", result={"data": [1, 2, 3]})
        restored = decode(encode(original))
        assert isinstance(restored, JSONRPCResponse)
        assert restored.id == original.id
        assert restored.result == original.result

    def test_error_roundtrip(self):
        original = JSONRPCErrorResponse(
            id=0, error=JSONRPCError(code=-32700, message="parse error")
        )
        restored = decode(encode(original))
        assert isinstance(restored, JSONRPCErrorResponse)
        assert restored.error.code == original.error.code
        assert restored.error.message == original.error.message
