"""Session — protocol layer above Transport.

Responsibilities:
  1. Manage a running message-pump task that reads from the transport.
  2. Correlate outbound requests with inbound responses by request ID.
  3. Queue server-sent notifications (fire-and-forget) for consumers.
  4. Queue server-initiated requests (approvals) separately.
  5. Execute the initialize/initialized handshake.

The Session does NOT know about SSH — it works with any Transport.
"""

from __future__ import annotations

import asyncio
from typing import Any

from wuyu.protocol.jsonrpc import (
    JSONRPCErrorResponse,
    JSONRPCMessage,
    JSONRPCNotification,
    JSONRPCRequest,
    JSONRPCResponse,
)
from wuyu.protocol.types import (
    ClientInfo,
    InitializeParams,
    InitializeResponse,
    RequestId,
)
from wuyu.transport import Transport, TransportClosedError


class SessionError(Exception):
    """Raised when the server returns a JSON-RPC error response."""

    def __init__(self, message: str, code: int) -> None:
        super().__init__(f"[{code}] {message}")
        self.code = code


class Session:
    """Stateful JSON-RPC session over a Transport.

    Usage::

        session = Session(transport)
        await session.start()
        response = await session.initialize(ClientInfo(name="wuyu", version="0.1.0"))
        # ... use session ...
        await session.stop()
    """

    def __init__(self, transport: Transport) -> None:
        self._transport = transport
        self._pending: dict[RequestId, asyncio.Future[Any]] = {}
        self._notifications: asyncio.Queue[JSONRPCNotification] = asyncio.Queue()
        self._server_requests: asyncio.Queue[JSONRPCRequest] = asyncio.Queue()
        self._pump_task: asyncio.Task[None] | None = None
        self._next_id = 0

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    async def start(self) -> None:
        """Connect the transport and start the background message pump."""
        if self._pump_task is not None and not self._pump_task.done():
            return  # already running
        await self._transport.connect()
        self._pump_task = asyncio.create_task(self._pump(), name="session-pump")

    async def stop(self) -> None:
        """Disconnect the transport and stop the pump."""
        await self._transport.disconnect()
        if self._pump_task is not None:
            self._pump_task.cancel()
            try:
                await self._pump_task
            except (asyncio.CancelledError, Exception):
                pass
            self._pump_task = None

    # ------------------------------------------------------------------
    # Client → Server
    # ------------------------------------------------------------------

    def _next_request_id(self) -> int:
        self._next_id += 1
        return self._next_id

    async def request(self, method: str, params: Any = None) -> Any:
        """Send a JSON-RPC request and wait for the response.

        Raises SessionError if the server returns an error response.
        """
        req_id = self._next_request_id()
        loop = asyncio.get_running_loop()
        fut: asyncio.Future[Any] = loop.create_future()
        self._pending[req_id] = fut
        await self._transport.send(JSONRPCRequest(id=req_id, method=method, params=params))
        return await fut

    async def notify(self, method: str, params: Any = None) -> None:
        """Send a JSON-RPC notification (no response expected)."""
        await self._transport.send(JSONRPCNotification(method=method, params=params))

    async def respond(self, request_id: RequestId, result: Any = None) -> None:
        """Respond to a server-initiated request (e.g. approval)."""
        await self._transport.send(JSONRPCResponse(id=request_id, result=result))

    # ------------------------------------------------------------------
    # Server → Client (consuming)
    # ------------------------------------------------------------------

    async def receive_notification(self) -> JSONRPCNotification:
        """Wait for the next server notification (blocking)."""
        return await self._notifications.get()

    async def receive_server_request(self) -> JSONRPCRequest:
        """Wait for the next server-initiated request (blocking)."""
        return await self._server_requests.get()

    # ------------------------------------------------------------------
    # Handshake
    # ------------------------------------------------------------------

    async def initialize(self, client_info: ClientInfo) -> InitializeResponse:
        """Perform the initialize/initialized handshake.

        Sends `initialize` request, waits for the server's InitializeResponse,
        then sends the `initialized` notification to complete the handshake.
        """
        params = InitializeParams(client_info=client_info)
        result = await self.request(
            "initialize",
            params=params.model_dump(by_alias=True, exclude_none=True),
        )
        response = InitializeResponse.model_validate(result)
        await self.notify("initialized")
        return response

    # ------------------------------------------------------------------
    # Internal pump
    # ------------------------------------------------------------------

    async def _pump(self) -> None:
        """Read messages from transport and dispatch them."""
        try:
            while True:
                msg = await self._transport.receive()
                self._dispatch(msg)
        except TransportClosedError:
            self._cancel_pending(reason="transport closed")
        except asyncio.CancelledError:
            self._cancel_pending(reason="session stopped")
            raise
        except Exception as exc:
            self._fail_pending(exc)

    def _dispatch(self, msg: JSONRPCMessage) -> None:
        if isinstance(msg, JSONRPCResponse):
            fut = self._pending.pop(msg.id, None)
            if fut and not fut.done():
                fut.set_result(msg.result)
        elif isinstance(msg, JSONRPCErrorResponse):
            fut = self._pending.pop(msg.id, None)
            if fut and not fut.done():
                fut.set_exception(SessionError(msg.error.message, msg.error.code))
        elif isinstance(msg, JSONRPCNotification):
            self._notifications.put_nowait(msg)
        elif isinstance(msg, JSONRPCRequest):
            # Server-initiated request (approval flows)
            self._server_requests.put_nowait(msg)

    def _cancel_pending(self, reason: str) -> None:
        for fut in self._pending.values():
            if not fut.done():
                fut.cancel(reason)
        self._pending.clear()

    def _fail_pending(self, exc: Exception) -> None:
        for fut in self._pending.values():
            if not fut.done():
                fut.set_exception(exc)
        self._pending.clear()
