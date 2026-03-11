"""SSH transport — connects to a remote host and execs a Codex App Server process.

The remote process communicates via stdin/stdout using the JSONL wire format.
This transport bridges asyncssh's process stdio to our codec.

Architecture
------------
connect()
  └─ asyncssh.connect() → SSHClientConnection
       └─ conn.create_process(command) → SSHClientProcess
            ├─ send()    → process.stdin.write(encoded line)
            └─ receive() → process.stdout.readline() → decoded message
"""

from __future__ import annotations

from typing import Any

import asyncssh

from wuyu.codec import CodecError, decode, encode
from wuyu.protocol.jsonrpc import JSONRPCMessage
from wuyu.transport import (
    ConnectionState,
    Transport,
    TransportClosedError,
    TransportError,
)


class SshTransport(Transport):
    """Transport that execs `codex app-server` (or a custom command) over SSH.

    Parameters
    ----------
    host:
        SSH server hostname or IP.
    port:
        SSH server port (default 22).
    username:
        SSH username. Defaults to the OS login name if None.
    password:
        Password authentication. Prefer key auth for security.
    client_keys:
        List of private key objects or paths for public-key auth.
    known_hosts:
        Known-hosts file path or asyncssh known-hosts object.
        Pass ``None`` to skip host-key verification (tests only!).
    command:
        Remote command to execute (default: ``"codex app-server"``).
    """

    def __init__(
        self,
        host: str,
        port: int = 22,
        username: str | None = None,
        password: str | None = None,
        client_keys: list[Any] | None = None,
        known_hosts: Any = None,
        command: str = "codex app-server",
    ) -> None:
        self._host = host
        self._port = port
        self._username = username
        self._password = password
        self._client_keys = client_keys
        self._known_hosts = known_hosts
        self._command = command

        self._conn: asyncssh.SSHClientConnection | None = None
        self._process: asyncssh.SSHClientProcess | None = None  # type: ignore[type-arg]
        self._state = ConnectionState.DISCONNECTED

    # ------------------------------------------------------------------
    # Transport interface
    # ------------------------------------------------------------------

    def state(self) -> ConnectionState:
        return self._state

    async def connect(self) -> None:
        """Open SSH connection and exec the app-server command."""
        if self._state == ConnectionState.CONNECTED:
            return

        self._state = ConnectionState.CONNECTING
        try:
            self._conn = await asyncssh.connect(
                self._host,
                port=self._port,
                username=self._username,
                password=self._password,
                client_keys=self._client_keys,
                known_hosts=self._known_hosts,
            )
            self._process = await self._conn.create_process(
                self._command,
                encoding=None,  # raw bytes; we decode ourselves
            )
        except asyncssh.DisconnectError as e:
            self._state = ConnectionState.DISCONNECTED
            raise TransportError(f"SSH disconnect during connect: {e}") from e
        except asyncssh.PermissionDenied as e:
            self._state = ConnectionState.DISCONNECTED
            raise TransportError(f"SSH authentication failed: {e}") from e
        except OSError as e:
            self._state = ConnectionState.DISCONNECTED
            raise TransportError(f"SSH connection error: {e}") from e

        self._state = ConnectionState.CONNECTED

    async def disconnect(self) -> None:
        """Gracefully close the process stdin and SSH connection."""
        if self._state == ConnectionState.DISCONNECTED:
            return

        self._state = ConnectionState.DISCONNECTING
        try:
            if self._process is not None:
                self._process.stdin.write_eof()
                self._process.close()
                self._process = None
            if self._conn is not None:
                self._conn.close()
                await self._conn.wait_closed()
                self._conn = None
        finally:
            self._state = ConnectionState.DISCONNECTED

    async def send(self, message: JSONRPCMessage) -> None:
        """Encode message as JSONL and write to process stdin."""
        if self._state != ConnectionState.CONNECTED or self._process is None:
            raise TransportError("not connected")
        line = encode(message)
        self._process.stdin.write(line.encode())

    async def receive(self) -> JSONRPCMessage:
        """Read one JSONL line from process stdout and decode it.

        Raises TransportClosedError when stdout reaches EOF.
        Raises TransportError on SSH-level errors.
        """
        if self._process is None:
            raise TransportClosedError("not connected")

        try:
            raw = await self._process.stdout.readline()
        except asyncssh.DisconnectError as e:
            self._state = ConnectionState.DISCONNECTED
            raise TransportError(f"SSH disconnected: {e}") from e

        if not raw:
            # EOF — server exited
            self._state = ConnectionState.DISCONNECTED
            raise TransportClosedError("remote process exited (EOF)")

        line = raw.decode(errors="replace")
        try:
            return decode(line)
        except CodecError as e:
            raise TransportError(f"JSONL decode error: {e}") from e
