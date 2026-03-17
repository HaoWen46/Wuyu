# 无域 (Wuyu)

A mobile app for controlling agentic coding CLIs (primarily [Codex App Server](https://github.com/openai/codex/tree/main/codex-rs)) over SSH from a phone.

The name means *"without domain/place"* — the goal is to code from anywhere.

## What it does

Wuyu connects to a remote host via SSH, starts `codex app-server` as a remote process, and speaks bidirectional JSONL/JSON-RPC over the SSH channel's stdin/stdout. It renders the agent's Thread/Turn/Item event stream into a chat UI with first-class approval flows (command execution, file changes, permissions).

```
Phone ──SSH──▶ Remote host
                 └─ codex app-server (stdin/stdout JSONL)
                      ├─ Thread / Turn / Item events
                      └─ Approval requests (command exec, file changes)
```

## Status

| Milestone | Status | Description |
|-----------|--------|-------------|
| M0 | ✅ Done | Flutter scaffold + SSH stack + Dart protocol layer |
| M1 | 🔶 Partial | Backend services done; full host pairing / auth / project bootstrap UI pending |
| M2 | 🔶 Partial | Core chat + streaming done; thread list / resume UI pending |
| M3 | 🔲 Next | Approvals & permission UI |
| M4 | 🔲 | Project & session management (multi-host, multi-project) |
| M5 | 🔲 | Reconnection & offline resilience |
| M6 | 🔲 | Rich item rendering & polish |
| M7 | 🔲 | Job mode & notifications |
| M8 | 🔲 | Hardening & release prep |

**What's built so far:**
- Dart protocol layer: JSONL codec, Transport, SshTransport, Session — **50 tests**
- Flutter SSH stack: Ed25519 key gen (`SshKeyService`), TOFU host key store (`HostKeyStore`), connection service (`SshConnectionService`), remote runner — **44 Flutter tests**
- Codex backend: `CodexDetector`, `AppServerService` (handshake), `ThreadService` (start/turn/events), `AgentMessageAccumulator` (delta streaming)
- Chat UI: `ChatScreen` (streaming bubbles, turn state, auto-scroll), `DevConnectScreen` (dev-only end-to-end wiring)

## Development

### Dart protocol layer (`wuyu_dart/`)

**Requirements:** [Dart SDK](https://dart.dev/get-dart) 3.11+

```bash
cd wuyu_dart

# Run tests
dart test

# Analyze
dart analyze
```

### Python reference implementation (`src/wuyu/`)

The Python prototype validated the protocol design. It serves as a living specification and is not the production app.

**Requirements:** Python 3.12+, [uv](https://docs.astral.sh/uv/)

```bash
uv sync --all-extras
uv run pytest tests/ -v
uv run ruff check src/ tests/
uv run ruff format src/ tests/
```

## Architecture

```
wuyu_app/lib/                       # Flutter app
├── main.dart                       # Entry point → WuyuApp → DevConnectScreen
├── dev_connect_screen.dart         # Dev-only: wires full SSH + protocol stack
├── ssh/
│   ├── secure_kv.dart              # SecureKv interface (key-value store)
│   ├── flutter_secure_kv.dart      # FlutterSecureStorage adapter
│   ├── ssh_key_service.dart        # Ed25519 key gen + Keychain persistence
│   ├── host_key_store.dart         # TOFU host fingerprint store
│   ├── ssh_connection_service.dart # SSHClient connect + TOFU verification
│   └── remote_runner.dart          # SSH exec for one-shot commands
└── codex/
    ├── codex_detector.dart         # Detect codex binary + app-server capability
    ├── app_server_service.dart     # openTransport() + handshake()
    ├── events.dart                 # Typed AppServerEvent hierarchy
    ├── thread_service.dart         # startThread / startTurn / events stream
    ├── agent_message_accumulator.dart  # Delta accumulation by itemId
    └── chat_screen.dart            # Streaming chat widget (M2)

wuyu_dart/lib/src/                  # Dart protocol layer
├── protocol/jsonrpc.dart           # JSON-RPC message types
├── codec.dart                      # JSONL encode/decode + field-presence discrimination
├── transport.dart                  # Abstract Transport interface
├── ssh_transport.dart              # SshTransport — dartssh2 + fake() for tests
└── session.dart                    # Session — Completer map, _AsyncQueue, handshake

src/wuyu/                           # Python reference implementation (81 tests)
├── protocol/                       # Protocol types (pydantic, camelCase)
├── codec.py                        # JSONL codec
├── transport.py                    # Abstract Transport
├── ssh_transport.py                # asyncssh channel exec
└── session.py                      # Session layer
```

See [`PLAN.md`](PLAN.md) for the full milestone plan and [`PROJECT_SPEC.md`](PROJECT_SPEC.md) for the product specification.
