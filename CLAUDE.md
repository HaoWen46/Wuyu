# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**无域 (Wuyu)** — A mobile app for controlling agentic coding CLIs (primarily Codex App Server) over SSH from a phone. The name means "without domain/place," reflecting the goal of coding from anywhere.

## Build & Test Commands

### Flutter app
```bash
cd wuyu_app
flutter pub get        # Install dependencies
flutter analyze        # Static analysis
flutter test           # Run widget/unit tests
```

### Dart protocol layer (production)
```bash
cd wuyu_dart
dart test              # Run all Dart tests (50 tests — codec, transport, SshTransport, session)
dart analyze           # Static analysis
dart test test/codec_test.dart  # Run a single test file
```

### Python reference implementation
```bash
uv sync --all-extras           # Install all dependencies (including dev)
uv run pytest tests/ -v        # Run all tests (81 tests)
uv run ruff check src/ tests/  # Lint
uv run ruff format src/ tests/ # Format
```

## Architecture

The app is a **stateful, event-driven mobile client** that speaks Codex App Server's JSONL/JSON-RPC protocol over SSH stdio. It is NOT a terminal emulator or SSH client with a pretty UI.

### Core data model
- **Project** = `(host, repoPath)` — a remote directory on a specific host
- **Room** = a Codex **thread** — a conversation session within a project
- **Message stream** = ordered **items** (user text, agent messages, tool executions, diffs, approvals)

### Communication flow
1. Mobile app opens SSH connection to remote host
2. Starts `codex app-server` as a remote process
3. Speaks bidirectional JSONL over SSH channel's stdin/stdout
4. Renders Thread/Turn/Item events into a chat UI

### Package structure

```
wuyu_app/lib/                           # Flutter app
├── main.dart                           # Entry point → WuyuApp → DevConnectScreen
├── dev_connect_screen.dart             # Dev-only: full SSH+protocol stack wiring (not production UX)
├── ssh/
│   ├── secure_kv.dart                  # SecureKv interface
│   ├── flutter_secure_kv.dart          # FlutterSecureStorage adapter (production)
│   ├── ssh_key_service.dart            # Ed25519 key gen + Keychain persistence
│   ├── host_key_store.dart             # TOFU host fingerprint store
│   ├── ssh_connection_service.dart     # SSHClient connect + TOFU callback
│   └── remote_runner.dart              # SSH exec for one-shot remote commands
└── codex/
    ├── codex_detector.dart             # Detect codex binary + app-server capability
    ├── app_server_service.dart         # openTransport() + handshake() static methods
    ├── events.dart                     # Typed AppServerEvent hierarchy (sealed class)
    ├── thread_service.dart             # startThread / startTurn / events stream
    ├── agent_message_accumulator.dart  # Delta accumulation by itemId (StringBuffer map)
    └── chat_screen.dart                # Streaming chat widget (M2); uses ThreadService

wuyu_dart/lib/src/                      # Dart production code (protocol layer)
├── protocol/jsonrpc.dart               # JSON-RPC types (final classes, no subclassing)
├── codec.dart                          # JSONL encode/decode + CodecError
├── transport.dart                      # abstract interface Transport
├── ssh_transport.dart                  # SshTransport — dartssh2 channel exec, fake() for tests
└── session.dart                        # Session (Completer map, _AsyncQueue, handshake)

src/wuyu/                               # Python reference implementation (81 tests)
├── protocol/                           # Codex App Server protocol types (pydantic, camelCase)
│   ├── _util.py                        # Shared CAMEL_CONFIG for pydantic models
│   ├── jsonrpc.py                      # JSON-RPC message framing
│   ├── types.py                        # Core types (RequestId, ClientInfo, TurnStatus, …)
│   ├── items.py                        # ThreadItem variants (UserMessage, AgentMessage, …)
│   ├── events.py                       # Server notification types
│   └── approvals.py                    # Approval request/response types
├── codec.py                            # JSONL codec
├── transport.py                        # Abstract Transport ABC
├── ssh_transport.py                    # SshTransport — asyncssh channel exec
└── session.py                          # Session — request correlation & handshake
```

### Key design patterns
- **Message discrimination**: No `"jsonrpc":"2.0"` field on the wire. Codec classifies by field presence (id+method→Request, method-only→Notification, etc.). Same logic in both Dart and Python.
- **Dart types**: `final class` (not sealed) for message variants — type-checked in dispatcher via `is`. No subclassing.
- **Dart session**: `Completer<Object?>` map for request correlation; `_AsyncQueue<T>` (Queue of items + Queue of waiters) for blocking notification consumption.
- **SshTransport testability**: Internal constructor takes raw `Stream<List<int>>` + `void Function(Uint8List)` write callback + close callback. `SshTransport.fake()` injects in-memory fakes; `SshTransport.connect()` passes `session.stdout.cast<List<int>>()` and `session.stdin.add` (tear-off).
- **Flutter event subscription**: `ChatScreen` uses `StreamSubscription<AppServerEvent>` (not `StreamBuilder`) — required for imperative list accumulation, scroll-to-bottom, and `cancel()` in `dispose()`.
- **`AgentMessageAccumulator`**: `Map<itemId, StringBuffer>` for delta accumulation. `textFor(itemId)` returns `''` before first delta (triggers `LinearProgressIndicator` in bubble). Never cleared between turns — itemIds are unique per session.
- **`SecureKv` interface**: All secure storage goes through this thin interface (`read`/`write`/`delete`). `FlutterSecureKv` is the production adapter; tests inject `MemorySecureKv`. This pattern lets every service that touches secrets be unit-tested without platform plugins.
- **Python types**: pydantic `BaseModel` with `CAMEL_CONFIG` for camelCase aliases. Serialize with `by_alias=True, exclude_none=True`.
- **Forward-compatible items (Python)**: Unknown `ThreadItem` types fall back to `UnknownItem` with raw dict preserved.

### Key design constraints
- Phone does NO compute — all agent work runs on the server
- No always-on server exposed to the internet — SSH is the transport
- Must handle mobile realities: flaky networks, OS backgrounding, lossy streaming
- Approvals (command execution, file changes) are first-class UI primitives, not afterthoughts
- SSH connection is treated as unreliable — needs idempotent requests, resync on reconnect, local caching

### Session persistence modes
- **Ephemeral**: App Server lives only while SSH is connected (simplest)
- **Remote-supervised**: App Server in tmux/user service, survives disconnects (production path)
- **Job queue**: Fire-and-forget tasks via `codex exec`, reconnect later for results

## Key references
- `PROJECT_SPEC.md` — full product specification and architectural rationale
- `PLAN.md` — milestone-based implementation plan (M0–M8)
- **Codex RS backend**: https://github.com/openai/codex/tree/main/codex-rs
  - `app-server` — the binary; stdio or WebSocket transport, 3-task async architecture
  - `app-server-protocol` — all JSON-RPC types, v1/v2 schemas, JSON Schema + TS codegen
  - `app-server-client` — typed Rust client (reference for protocol usage)
  - `protocol` — lower-level Op/EventMsg between core and frontends
  - `app-server-protocol/schema/json/` — 38 machine-generated JSON Schema files
  - `app-server-protocol/schema/typescript/` — 230+ TypeScript type definitions
- Claude Code Remote Control pattern (for reconnection UX inspiration)
