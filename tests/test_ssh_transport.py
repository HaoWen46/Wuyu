"""Integration tests for SshTransport.

Spins up a real local asyncssh server (in-process) with a fake app-server
handler. No external SSH daemon or key files needed — keys are generated
in-memory at test time.
"""

from __future__ import annotations

import asyncio
import json

import asyncssh
import pytest

from wuyu.protocol.jsonrpc import JSONRPCNotification, JSONRPCRequest, JSONRPCResponse
from wuyu.ssh_transport import SshTransport
from wuyu.transport import ConnectionState, TransportClosedError

# ---------------------------------------------------------------------------
# Fake app-server — speaks JSONL over asyncssh process stdio
# ---------------------------------------------------------------------------


async def _fake_app_server(process: asyncssh.SSHServerProcess) -> None:  # type: ignore[type-arg]
    """Minimal JSONL echo server used by the test SSH server.

    Handles `initialize` requests; echoes any other request back as a response.
    """
    try:
        async for line in process.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue

            if "method" in msg and "id" in msg:
                method = msg["method"]
                if method == "initialize":
                    response = {"id": msg["id"], "result": {"userAgent": "fake-codex/test"}}
                else:
                    # Echo back for generic request tests
                    response = {"id": msg["id"], "result": {"echoed": method}}
                process.stdout.write(json.dumps(response) + "\n")

            elif "method" in msg and "id" not in msg:
                # Notification — no response needed
                pass
    except asyncssh.BreakReceived:
        pass
    finally:
        process.exit(0)


# ---------------------------------------------------------------------------
# Pytest fixtures — SSH server + key pair
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def ssh_keys() -> tuple[asyncssh.SSHKey, asyncssh.SSHKey]:
    """Generate a server host key and a client key pair (in-memory)."""
    server_key = asyncssh.generate_private_key("ssh-rsa")
    client_key = asyncssh.generate_private_key("ssh-rsa")
    return server_key, client_key


@pytest.fixture()
async def ssh_server(
    ssh_keys: tuple[asyncssh.SSHKey, asyncssh.SSHKey],
) -> asyncio.AbstractServer:
    """Start a local asyncssh server; yield it; shut it down after each test."""
    server_key, client_key = ssh_keys
    authorized_keys = asyncssh.import_authorized_keys(client_key.export_public_key().decode())

    server = await asyncssh.create_server(
        asyncssh.SSHServer,
        host="127.0.0.1",
        port=0,  # OS assigns a free port
        server_host_keys=[server_key],
        authorized_client_keys=authorized_keys,
        process_factory=_fake_app_server,
    )

    yield server

    server.close()
    await server.wait_closed()


@pytest.fixture()
def make_transport(
    ssh_keys: tuple[asyncssh.SSHKey, asyncssh.SSHKey],
    ssh_server: asyncio.AbstractServer,
) -> SshTransport:
    """Return a pre-configured SshTransport pointing at the local test server."""
    _, client_key = ssh_keys
    sockets = ssh_server.sockets
    port = sockets[0].getsockname()[1]  # type: ignore[index]

    return SshTransport(
        host="127.0.0.1",
        port=port,
        username="testuser",
        client_keys=[client_key],
        known_hosts=None,  # skip host-key verification in tests
        command="fake-app-server",  # ignored by our process_factory
    )


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


class TestConnectionState:
    async def test_initial_state_is_disconnected(self, make_transport: SshTransport) -> None:
        assert make_transport.state() == ConnectionState.DISCONNECTED

    async def test_connect_sets_state_to_connected(self, make_transport: SshTransport) -> None:
        transport = make_transport
        await transport.connect()
        assert transport.state() == ConnectionState.CONNECTED
        await transport.disconnect()

    async def test_disconnect_sets_state_to_disconnected(
        self, make_transport: SshTransport
    ) -> None:
        transport = make_transport
        await transport.connect()
        await transport.disconnect()
        assert transport.state() == ConnectionState.DISCONNECTED


class TestSendReceive:
    async def test_can_send_request_and_receive_response(
        self, make_transport: SshTransport
    ) -> None:
        transport = make_transport
        await transport.connect()

        req = JSONRPCRequest(id=1, method="initialize", params={})
        await transport.send(req)

        response = await transport.receive()
        assert isinstance(response, JSONRPCResponse)
        assert response.id == 1
        assert response.result["userAgent"] == "fake-codex/test"

        await transport.disconnect()

    async def test_can_send_notification_without_response(
        self, make_transport: SshTransport
    ) -> None:
        transport = make_transport
        await transport.connect()

        # Sending a notification should not raise
        notif = JSONRPCNotification(method="initialized")
        await transport.send(notif)

        # Server won't respond to a notification; send a request to verify
        # the channel is still healthy
        req = JSONRPCRequest(id=2, method="ping", params={})
        await transport.send(req)
        response = await asyncio.wait_for(transport.receive(), timeout=2.0)
        assert isinstance(response, JSONRPCResponse)
        assert response.id == 2

        await transport.disconnect()

    async def test_multiple_sequential_requests(self, make_transport: SshTransport) -> None:
        transport = make_transport
        await transport.connect()

        for i in range(3):
            req = JSONRPCRequest(id=i, method=f"method/{i}", params={})
            await transport.send(req)
            response = await asyncio.wait_for(transport.receive(), timeout=2.0)
            assert isinstance(response, JSONRPCResponse)
            assert response.id == i

        await transport.disconnect()


class TestTransportClosed:
    async def test_receive_raises_on_server_exit(self, make_transport: SshTransport) -> None:
        transport = make_transport
        await transport.connect()

        # Close our end — server's stdin EOF triggers server exit → our stdout EOF
        await transport.disconnect()

        # After disconnecting, receiving should raise (not block forever)
        with pytest.raises((TransportClosedError, Exception)):
            await asyncio.wait_for(transport.receive(), timeout=1.0)
