"""Tests for Session — request/response correlation, notification dispatch, and handshake.

Uses FakeTransport (in-memory queues) — no SSH required.
"""

from __future__ import annotations

import asyncio

import pytest

from wuyu.protocol.jsonrpc import (
    JSONRPCError,
    JSONRPCErrorResponse,
    JSONRPCMessage,
    JSONRPCNotification,
    JSONRPCRequest,
    JSONRPCResponse,
)
from wuyu.protocol.types import ClientInfo, InitializeResponse
from wuyu.session import Session, SessionError
from wuyu.transport import ConnectionState, Transport, TransportClosedError


class FakeTransport(Transport):
    """In-memory transport for unit testing Session logic.

    Feed inbound messages (from the fake "server") via `put()`.
    Inspect outbound messages (from Session) via `sent`.
    """

    def __init__(self) -> None:
        self._inbox: asyncio.Queue[JSONRPCMessage | BaseException] = asyncio.Queue()
        self.sent: list[JSONRPCMessage] = []
        self._state = ConnectionState.DISCONNECTED

    async def connect(self) -> None:
        self._state = ConnectionState.CONNECTED

    async def disconnect(self) -> None:
        self._state = ConnectionState.DISCONNECTED
        # Signal the pump that the transport closed
        await self._inbox.put(TransportClosedError("transport disconnected"))

    async def send(self, message: JSONRPCMessage) -> None:
        self.sent.append(message)

    async def receive(self) -> JSONRPCMessage:
        item = await self._inbox.get()
        if isinstance(item, BaseException):
            raise item
        return item

    def state(self) -> ConnectionState:
        return self._state

    async def put(self, message: JSONRPCMessage) -> None:
        """Feed a message as if it came from the remote server."""
        await self._inbox.put(message)


class TestSessionLifecycle:
    async def test_start_connects_transport(self) -> None:
        transport = FakeTransport()
        session = Session(transport)
        await session.start()
        assert transport.state() == ConnectionState.CONNECTED
        await session.stop()

    async def test_stop_disconnects_transport(self) -> None:
        transport = FakeTransport()
        session = Session(transport)
        await session.start()
        await session.stop()
        assert transport.state() == ConnectionState.DISCONNECTED

    async def test_start_twice_is_idempotent(self) -> None:
        transport = FakeTransport()
        session = Session(transport)
        await session.start()
        await session.start()  # second call should not raise
        assert transport.state() == ConnectionState.CONNECTED
        await session.stop()


class TestRequestCorrelation:
    async def test_request_sends_message_and_returns_result(self) -> None:
        transport = FakeTransport()
        session = Session(transport)
        await session.start()

        async def respond() -> None:
            await asyncio.sleep(0)
            req = transport.sent[-1]
            await transport.put(JSONRPCResponse(id=req.id, result={"answer": 42}))

        asyncio.create_task(respond())
        result = await session.request("foo/bar", params={"x": 1})
        assert result == {"answer": 42}
        await session.stop()

    async def test_concurrent_requests_are_correlated_correctly(self) -> None:
        transport = FakeTransport()
        session = Session(transport)
        await session.start()

        t1 = asyncio.create_task(session.request("method/a"))
        t2 = asyncio.create_task(session.request("method/b"))
        # Yield so both tasks send their requests
        await asyncio.sleep(0)

        # Reply out of order — second request answered first
        reqs = list(transport.sent)
        await transport.put(JSONRPCResponse(id=reqs[1].id, result="second"))
        await transport.put(JSONRPCResponse(id=reqs[0].id, result="first"))

        r1, r2 = await asyncio.gather(t1, t2)
        assert r1 == "first"
        assert r2 == "second"
        await session.stop()

    async def test_error_response_raises_session_error(self) -> None:
        transport = FakeTransport()
        session = Session(transport)
        await session.start()

        async def respond() -> None:
            await asyncio.sleep(0)
            req = transport.sent[-1]
            await transport.put(
                JSONRPCErrorResponse(
                    id=req.id,
                    error=JSONRPCError(code=-32601, message="Method not found"),
                )
            )

        asyncio.create_task(respond())
        with pytest.raises(SessionError) as exc_info:
            await session.request("unknown/method")
        assert exc_info.value.code == -32601
        assert "Method not found" in str(exc_info.value)
        await session.stop()

    async def test_request_ids_are_unique(self) -> None:
        transport = FakeTransport()
        session = Session(transport)
        await session.start()

        # Fire multiple requests simultaneously
        tasks = [asyncio.create_task(session.request(f"m/{i}")) for i in range(5)]
        await asyncio.sleep(0)

        ids = [msg.id for msg in transport.sent]
        assert len(ids) == len(set(ids)), "request IDs must be unique"

        # Clean up by responding to all
        for msg in transport.sent:
            await transport.put(JSONRPCResponse(id=msg.id, result=None))
        await asyncio.gather(*tasks)
        await session.stop()


class TestDispatch:
    async def test_server_notifications_are_queued(self) -> None:
        transport = FakeTransport()
        session = Session(transport)
        await session.start()

        await transport.put(JSONRPCNotification(method="turn/started", params={"turnId": "abc"}))
        await asyncio.sleep(0)

        notification = await session.receive_notification()
        assert notification.method == "turn/started"
        assert notification.params == {"turnId": "abc"}
        await session.stop()

    async def test_server_requests_are_queued_separately(self) -> None:
        transport = FakeTransport()
        session = Session(transport)
        await session.start()

        # A server-initiated request (e.g. approval) has both id and method
        await transport.put(
            JSONRPCRequest(id=99, method="approvals/commandExecution", params={"cmd": "ls"})
        )
        await asyncio.sleep(0)

        server_req = await session.receive_server_request()
        assert server_req.id == 99
        assert server_req.method == "approvals/commandExecution"
        await session.stop()

    async def test_notification_and_server_request_in_same_stream(self) -> None:
        transport = FakeTransport()
        session = Session(transport)
        await session.start()

        await transport.put(JSONRPCNotification(method="turn/started", params={}))
        await transport.put(JSONRPCRequest(id=1, method="approvals/fileChange", params={}))
        await asyncio.sleep(0)

        notif = await session.receive_notification()
        req = await session.receive_server_request()
        assert notif.method == "turn/started"
        assert req.method == "approvals/fileChange"
        await session.stop()


class TestHandshake:
    async def test_initialize_returns_parsed_response(self) -> None:
        transport = FakeTransport()
        session = Session(transport)
        await session.start()

        async def respond() -> None:
            await asyncio.sleep(0)
            req = transport.sent[0]
            await transport.put(JSONRPCResponse(id=req.id, result={"userAgent": "codex/1.0"}))

        asyncio.create_task(respond())
        result = await session.initialize(ClientInfo(name="wuyu", version="0.1.0"))
        assert isinstance(result, InitializeResponse)
        assert result.user_agent == "codex/1.0"
        await session.stop()

    async def test_initialize_sends_request_then_notification(self) -> None:
        transport = FakeTransport()
        session = Session(transport)
        await session.start()

        async def respond() -> None:
            await asyncio.sleep(0)
            req = transport.sent[0]
            await transport.put(JSONRPCResponse(id=req.id, result={"userAgent": "codex/1.0"}))

        asyncio.create_task(respond())
        await session.initialize(ClientInfo(name="wuyu", version="0.1.0"))

        assert len(transport.sent) == 2
        assert transport.sent[0].method == "initialize"  # type: ignore[union-attr]
        assert transport.sent[1].method == "initialized"  # type: ignore[union-attr]
        await session.stop()

    async def test_initialize_params_contain_client_info(self) -> None:
        transport = FakeTransport()
        session = Session(transport)
        await session.start()

        async def respond() -> None:
            await asyncio.sleep(0)
            req = transport.sent[0]
            await transport.put(JSONRPCResponse(id=req.id, result={"userAgent": "codex/1.0"}))

        asyncio.create_task(respond())
        await session.initialize(ClientInfo(name="wuyu", version="0.1.0"))

        params = transport.sent[0].params  # type: ignore[union-attr]
        assert params["clientInfo"]["name"] == "wuyu"
        assert params["clientInfo"]["version"] == "0.1.0"
        await session.stop()

    async def test_respond_sends_response_to_server_request(self) -> None:
        transport = FakeTransport()
        session = Session(transport)
        await session.start()

        await session.respond(request_id=42, result={"decision": "accept"})
        assert len(transport.sent) == 1
        sent = transport.sent[0]
        assert isinstance(sent, JSONRPCResponse)
        assert sent.id == 42
        assert sent.result == {"decision": "accept"}
        await session.stop()
