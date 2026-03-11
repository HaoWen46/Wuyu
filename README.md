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
| M0 | ✅ Done | Protocol types, JSONL codec, Transport interface |
| M1 | ✅ Done | SSH transport, session layer, initialize handshake |
| M2 | 🔲 Next | Thread lifecycle & basic chat |
| M3 | 🔲 | Approvals & permission UI |
| M4 | 🔲 | Project & session management |
| M5 | 🔲 | Reconnection & offline resilience |
| M6 | 🔲 | Rich item rendering & polish |
| M7 | 🔲 | Job mode & notifications |
| M8 | 🔲 | Hardening & release prep |

## Development

**Requirements:** Python 3.12+, [uv](https://docs.astral.sh/uv/)

```bash
# Install dependencies (including dev extras)
uv sync --all-extras

# Run tests
uv run pytest tests/ -v

# Lint & format
uv run ruff check src/ tests/
uv run ruff format src/ tests/

# Install pre-commit hooks (runs ruff on commit, pytest on push)
uv run pre-commit install --hook-type pre-commit --hook-type pre-push
```

## Architecture

```
src/wuyu/
├── protocol/          # Codex App Server protocol types (pydantic, camelCase)
│   ├── jsonrpc.py     # JSON-RPC message framing
│   ├── types.py       # Core types (ClientInfo, InitializeResponse, …)
│   ├── items.py       # ThreadItem variants (UserMessage, AgentMessage, …)
│   ├── events.py      # Server notification types
│   └── approvals.py   # Approval request/response types
├── codec.py           # JSONL encode/decode
├── transport.py       # Abstract Transport interface
├── ssh_transport.py   # SshTransport — asyncssh channel exec
└── session.py         # Session — request correlation & handshake
```

See [`PLAN.md`](PLAN.md) for the full milestone plan and [`PROJECT_SPEC.md`](PROJECT_SPEC.md) for the product specification.
