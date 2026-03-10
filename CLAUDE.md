# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**无域 (Wuyu)** — A mobile app for controlling agentic coding CLIs (primarily Codex App Server) over SSH from a phone. The name means "without domain/place," reflecting the goal of coding from anywhere.

## Build & Test Commands

```bash
uv sync --all-extras    # Install all dependencies (including dev)
uv run pytest tests/ -v # Run all tests
uv run ruff check src/ tests/        # Lint
uv run ruff format src/ tests/       # Format
uv run pytest tests/test_codec.py -v # Run a single test file
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
src/wuyu/
├── protocol/          # Codex App Server protocol types (v2)
│   ├── _util.py       # Shared camelCase config for pydantic models
│   ├── jsonrpc.py     # JSON-RPC message framing (Request, Notification, Response, Error)
│   ├── types.py       # Core types (RequestId, ClientInfo, TurnStatus, approval decisions)
│   ├── items.py       # ThreadItem variants (UserMessage, AgentMessage, CommandExecution, etc.)
│   ├── events.py      # Server notification types (turn/item lifecycle, deltas)
│   └── approvals.py   # Server-initiated approval request/response types
├── codec.py           # JSONL codec — encode/decode JSON-RPC messages to/from wire format
└── transport.py       # Abstract Transport interface (ABC) for SSH/stdio/WebSocket
```

### Key design patterns
- **camelCase ↔ snake_case**: All pydantic models use `CAMEL_CONFIG` from `_util.py` for automatic alias generation. Serialize with `by_alias=True` for wire format.
- **Message discrimination**: No `"jsonrpc":"2.0"` field on the wire. The codec classifies messages by inspecting which fields are present (id+method→Request, method-only→Notification, etc.).
- **Forward-compatible items**: Unknown `ThreadItem` types fall back to `UnknownItem` with raw dict preserved.
- **Typed notification parsing**: `events.parse_notification_params()` and `approvals.parse_server_request_params()` dispatch on method string → typed pydantic model.

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
