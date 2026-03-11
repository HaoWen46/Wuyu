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
| M0 | 🔶 In progress | Flutter scaffold + Dart protocol layer (codec, transport, session) |
| M1 | 🔲 Next | Host pairing + project bootstrap (SSH, TOFU, QR, Codex auth) |
| M2 | 🔲 | Thread lifecycle & basic chat |
| M3 | 🔲 | Approvals & permission UI |
| M4 | 🔲 | Project & session management |
| M5 | 🔲 | Reconnection & offline resilience |
| M6 | 🔲 | Rich item rendering & polish |
| M7 | 🔲 | Job mode & notifications |
| M8 | 🔲 | Hardening & release prep |

**M0 progress:** Dart protocol layer complete (38 tests). Flutter scaffold (`flutter create`) pending Flutter SDK setup.

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
wuyu_dart/                     # Dart protocol layer (production)
└── lib/src/
    ├── protocol/jsonrpc.dart  # JSON-RPC message types
    ├── codec.dart             # JSONL encode/decode, field-presence discrimination
    ├── transport.dart         # Abstract Transport interface
    └── session.dart           # Session — request correlation, queues, handshake

src/wuyu/                      # Python reference implementation
├── protocol/                  # Protocol types (pydantic, camelCase)
├── codec.py                   # JSONL codec
├── transport.py               # Abstract Transport
├── ssh_transport.py           # asyncssh channel exec
└── session.py                 # Session layer
```

See [`PLAN.md`](PLAN.md) for the full milestone plan and [`PROJECT_SPEC.md`](PROJECT_SPEC.md) for the product specification.
