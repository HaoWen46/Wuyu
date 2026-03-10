"""Transport interface — abstract base for SSH, stdio, WebSocket, etc.

The transport is responsible for:
  1. Establishing a connection to a Codex App Server process.
  2. Sending JSONL-encoded messages (write lines to the process stdin).
  3. Receiving JSONL-encoded messages (read lines from process stdout).
  4. Lifecycle management (connect, disconnect, health).
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from enum import StrEnum

from wuyu.protocol.jsonrpc import JSONRPCMessage


class ConnectionState(StrEnum):
    DISCONNECTED = "disconnected"
    CONNECTING = "connecting"
    CONNECTED = "connected"
    DISCONNECTING = "disconnecting"
    RECONNECTING = "reconnecting"


class Transport(ABC):
    """Abstract transport for bidirectional JSONL communication."""

    @abstractmethod
    async def connect(self) -> None:
        """Establish connection and start the app-server process.

        Raises TransportError on failure.
        """

    @abstractmethod
    async def disconnect(self) -> None:
        """Gracefully close the connection."""

    @abstractmethod
    async def send(self, message: JSONRPCMessage) -> None:
        """Send a single JSON-RPC message.

        Raises TransportError if not connected.
        """

    @abstractmethod
    async def receive(self) -> JSONRPCMessage:
        """Receive the next JSON-RPC message.

        Blocks until a message is available.
        Raises TransportError on connection loss.
        Raises TransportClosed when the connection is cleanly closed.
        """

    @abstractmethod
    def state(self) -> ConnectionState:
        """Current connection state."""


class TransportError(Exception):
    """Raised when a transport operation fails."""


class TransportClosedError(Exception):
    """Raised when the transport is cleanly closed (EOF)."""
