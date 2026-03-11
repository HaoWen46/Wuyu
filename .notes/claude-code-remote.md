# Claude Code Remote Control — Research Notes

Researched: 2026-03-11

---

## 1. Does Claude Code Have an App-Server Equivalent?

### Short answer: No stdio/WebSocket JSON-RPC interface exists for Claude Code itself.

Claude Code does not expose a Codex-style `app-server` with a JSON-RPC protocol that a client can speak to over SSH stdio or WebSocket. Anthropic's programmatic interface for Claude Code comes in two forms:

### 1a. The CLI `-p` / `--print` flag (formerly "headless mode")
Run Claude Code non-interactively from a shell script or CI:

```bash
claude -p "Find and fix the bug in auth.py" --allowedTools "Read,Edit,Bash"
```

Supports `--output-format json` (structured result + session_id) and `--output-format stream-json` (newline-delimited JSON events, i.e. streaming). You can capture session IDs and resume:

```bash
session_id=$(claude -p "Start a review" --output-format json | jq -r '.session_id')
claude -p "Continue that review" --resume "$session_id"
```

This is a fire-and-forget CLI invocation, not a long-lived server process.

### 1b. The Claude Agent SDK (Python + TypeScript)
Renamed from "Claude Code SDK" to "Claude Agent SDK". Published packages:
- Python: `pip install claude-agent-sdk` (v0.1.48 as of March 2026)
- TypeScript: `npm install @anthropic-ai/claude-agent-sdk` (v0.2.71)

The SDK wraps the same agent loop as Claude Code. It spawns the `claude` CLI subprocess internally (or calls the same agent machinery), exposing a `query()` async generator:

```python
from claude_agent_sdk import query, ClaudeAgentOptions

async for message in query(
    prompt="Find and fix the bug in auth.py",
    options=ClaudeAgentOptions(allowed_tools=["Read", "Edit", "Bash"]),
):
    print(message)
```

**Key point for Wuyu**: This SDK is a *local* library, not a server you can connect to remotely. It runs the agent in-process on the machine where you call it. There is no server socket to speak a protocol against.

### 1c. No documented stdio JSON-RPC interface
Unlike Codex's `codex app-server`, there is no `claude app-server` or equivalent long-lived process that a remote client can connect to and exchange JSON-RPC messages with over stdio or WebSocket. Anthropic has not published such an interface.

**Gap**: The exact wire format between the Agent SDK and the `claude` CLI subprocess (if it uses a subprocess) is not publicly documented.

---

## 2. Anthropic's Official Remote Control Feature

### Remote Control (released February 25, 2026 — Research Preview)

**What it is**: An official Anthropic feature that bridges a local `claude` terminal session to `claude.ai/code`, the Claude iOS app, and the Claude Android app.

**How to use it**:
```bash
# Navigate to project directory, then:
claude remote-control
# Or from within an existing session:
/remote-control
/rc
```
Displays a session URL and optional QR code. Press spacebar to toggle QR.

**How it works technically**:
- Claude Code makes **outbound HTTPS requests only** — no inbound ports opened.
- Registers with the Anthropic API, then **polls for work**.
- Anthropic's servers route messages between the web/mobile client and the local session over a streaming connection.
- All traffic through Anthropic API over TLS.
- Multiple short-lived credentials, each scoped to single purpose.

**Key limitations**:
- **One remote session per Claude Code instance** at a time.
- **Terminal must stay open** — if you close it or kill `claude`, session ends.
- **10-minute network outage** causes session timeout/exit.
- `--dangerously-skip-permissions` appears to have no effect in remote-control mode (every action needs approval).
- Requires Pro/Max/Team/Enterprise subscription (not API key).
- No SSH involved — purely HTTPS polling through Anthropic's cloud.

**Available flags for `claude remote-control`**:
- `--name "My Project"` — sets session title in session list
- `--verbose` — detailed connection/session logs
- `--sandbox` / `--no-sandbox` — filesystem/network isolation (off by default)

**Auto-enable for all sessions**:
```
/config → Enable Remote Control for all sessions → true
```

**Critical constraint for Wuyu**: Remote Control requires the terminal to stay open. The process dies if the terminal closes. There is no "supervisor" mode and no way to pre-launch it in a tmux/systemd fashion that survives the terminal. This means Wuyu would need an SSH connection to start/maintain it — which is the session bootstrap problem Wuyu needs to solve independently.

---

## 3. Claude Code `--resume` and Session Management

### Session IDs and resumption
- `claude --resume <session_id>` — resume a specific session by ID
- `claude --continue` / `claude -c` — continue the most recent conversation
- With `-p` flag: `--resume` and `--continue` work in non-interactive mode too
- Session files stored at: `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`
  - `<encoded-cwd>` = absolute working directory with non-alphanumeric chars replaced by `-`
  - e.g., `/Users/me/proj` → `-Users-me-proj`

### Known bugs (as of March 2026)
- When resuming with `--resume`, the `session_id` provided to hooks is a **new UUID**, not the original
- Sometimes resuming doesn't restore prior conversation history/context
- "No conversation found with session ID" errors after killing the process
- Sessions are local to the machine; resuming on a different host requires manually copying the `.jsonl` file to the same path with the same `cwd`

### Multiple clients: No
There is no mechanism for two separate clients to connect to the same running Claude Code instance simultaneously. The Remote Control feature (section 2) allows one remote session per local instance.

### Agent SDK session management
The SDK provides richer session primitives:
- `resume=session_id` — resume a specific past session
- `continue=True` — resume the most recent session in cwd
- `fork_session=True` — branch a session (creates new session ID, original unchanged)
- `ClaudeSDKClient` (Python) — stateful client that auto-continues same session across calls

Sessions persist conversation history but **not filesystem state**. File changes made by the agent are real and persist on disk; session resumption only restores the conversation transcript.

**Cross-host resumption**: Copy `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` to the same path on the new host. `cwd` must match exactly.

---

## 4. The Session Bootstrap Problem — Community Solutions

The problem: mobile app needs a running Claude/Codex process on the remote machine. Who has solved starting that process elegantly?

### 4a. Anthropic Remote Control (official)
Does **not** solve bootstrap elegantly. Requires user to:
1. Open terminal on their machine
2. `cd` to project
3. Run `claude remote-control`
4. Scan QR or open URL on phone

The bootstrap still requires manual terminal work. Anthropic's feature solves the "control from phone" part but not "start from phone."

### 4b. Farfield (github.com/achimala/farfield)
A WebSocket-based remote control for Codex and OpenCode agents.

**Architecture**:
- Backend server runs at `127.0.0.1:4311`, exposes REST API + live event stream
- Frontend is a web app (hosted at `farfield.app` or self-hosted) that tunnels directly to the server
- Uses Tailscale VPN for secure remote access: `tailscale serve --https=443 http://127.0.0.1:4311`
- Communicates with local agent processes via IPC

**Bootstrap approach**: Farfield does **NOT** bootstrap agents. It requires Codex/OpenCode to already be running. Agent selection is via `--agents` flags at server startup. This is still a manual process.

**Key design note**: Farfield routes directly (Tailscale VPN), not through an external cloud — unlike Remote Control.

### 4c. Happy Coder (github.com/slopus/happy + happy-cli)
A mobile/web client for Codex and Claude Code with E2E encryption.

**Architecture**:
- `happy-cli` (Node.js/TypeScript, `npm install -g happy-coder`) wraps the local Claude Code session
- Displays QR code to connect mobile device
- Routes messages through a cloud server (`happy-api.slopus.com` by default) but with end-to-end encryption — server only stores encrypted blobs
- Push notifications, instant device switching

**Bootstrap approach**: `happy` starts a regular Claude Code session locally. Switching to phone "restarts the session in remote mode"; switching back to computer is press-any-key. This is slightly better UX than farfield but still requires initial local terminal work.

**Self-hostable**: `HAPPY_SERVER_URL` env var points to your own happy-server instance.

### 4d. Harper Reed's approach (harper.blog/2026/01/05/claude-code-is-better-on-your-phone/)
Before official Remote Control:
1. Keep a desktop running Claude Code at home
2. Use Tailscale for private network
3. Install Termux (Android) or Blink (iOS) for SSH client
4. SSH into desktop
5. Use tmux to keep sessions alive when phone locks

This is the classical approach — Wuyu is essentially a productized version of this pattern with better UX.

### 4e. aiya000/claude-code-mobile-ssh (WIP)
A PWA (TypeScript/Next.js) for mobile Claude Code control over SSH. Uses SSH as transport. Still under development; bootstrap details not yet documented.

### 4f. Summary: Who elegantly solves "no bootstrap"?
**Nobody has cleanly solved** the problem of: (pick host) → (pick/create project dir) → (app starts the agent) without manual terminal work. All existing solutions require the user to manually start the agent first. This is a real gap that Wuyu could address by using SSH exec to start `codex app-server` or `claude remote-control` as part of session creation.

---

## 5. Codex `command/exec` RPC Method

### What it does
`command/exec` executes a standalone shell command within the app-server's sandbox environment. It does **not** require an active thread/turn — it's independent of the conversation. Designed for utilities and validation.

### Is it a general shell exec or sandboxed?
**Sandboxed** — but the sandbox level is configurable per-call. With `sandboxPolicy: "dangerFullAccess"` it has full unrestricted access to the filesystem. With `workspaceWrite` it's scoped to specified writable roots.

### Parameters
```jsonc
{
  "command": ["git", "init"],          // Required: argv array; empty array rejected
  "cwd": "/path/to/dir",               // Optional; defaults to server working dir
  "env": { "KEY": "value" },           // Optional; merges/overrides server env
  "sandboxPolicy": "dangerFullAccess", // Optional; defaults to user config
  "timeoutMs": 30000,                  // Optional; server default if omitted
  "disableTimeout": false,             // Cannot combine with timeoutMs
  "outputBytesCap": 1048576,           // Optional; default 1 MiB per stream
  "disableOutputCap": false,           // Cannot combine with outputBytesCap
  "processId": "my-proc-123",          // Optional; required for streaming/PTY
  "tty": false,                        // Boolean; enables PTY mode
  "streamStdin": false,                // Boolean; enables stdin streaming
  "streamStdoutStderr": false,         // Boolean; enables stdout/stderr streaming
  "size": { "rows": 24, "cols": 80 }  // Only valid with tty: true
}
```

### Response (buffered mode)
```jsonc
{ "exitCode": 0, "stdout": "...", "stderr": "..." }
```

### Streaming mode
Emits `command/exec/outputDelta` notifications:
```jsonc
{ "processId": "...", "stream": "stdout", "deltaBase64": "...", "capReached": false }
```

Follow-up methods: `command/exec/write` (send stdin), `command/exec/resize` (PTY), `command/exec/terminate` (kill).

### Can it create dirs, git init, etc.?
**Yes** — with appropriate sandbox policy. `command/exec` with `sandboxPolicy: "dangerFullAccess"` can run arbitrary shell commands: `mkdir -p`, `git init`, `git clone`, etc. This means the app-server can self-bootstrap a new project directory without a separate SSH exec channel.

### Important limitation: connection-scoped
`command/exec/outputDelta` notifications are **connection-scoped** and not shared across clients. If the connection drops, running processes are terminated. There is no way to reconnect to a running `command/exec` process.

---

## 6. Pre-Launch Patterns for Codex App-Server (tmux/systemd)

### WebSocket mode status
`codex app-server --listen ws://IP:PORT` is **experimental and unsupported** for production. Recent improvements (as of late 2025):
- Thread listeners survive disconnects
- Ctrl-C waits for in-flight turns before restarting
- SIGTERM treated like Ctrl-C (graceful shutdown)
- `permessage-deflate` clients now connect successfully

### Multiple clients on one WebSocket server?
The protocol is designed for one active connection at a time with backpressure via error code `-32001` ("Server overloaded; retry later"). There is no documented multi-client multiplexing. OpenAI has indicated multi-client/configurable-endpoint support is "a direction we're actively exploring."

### Thread persistence across disconnects
Unlike `command/exec` processes, **thread history does persist**. Threads are stored as JSONL on disk. Methods:
- `thread/list` — enumerate stored threads
- `thread/read` — read a thread's full history
- `thread/resume` — continue a thread by ID
- `thread/fork` — branch a thread

This means: if app-server is pre-launched in WebSocket mode, a client can reconnect and use `thread/resume` to continue a conversation even after the connection dropped.

### tmux pre-launch pattern (community)
No official pattern exists. Community approaches:
1. Pre-launch app-server in a tmux window:
   ```bash
   tmux new-session -d -s codex-server -c /path/to/project \
     'codex app-server --listen ws://127.0.0.1:4311'
   ```
2. Expose via Tailscale: `tailscale serve --https=443 http://127.0.0.1:4311`
3. Mobile app connects via WebSocket to the Tailscale URL

The codex-cli-farm project (github.com/waskosky/codex-cli-farm) is a tmux session management system for multiple Codex CLI instances with logging and monitoring.

### systemd pre-launch
Not officially documented. A user-level systemd service would look like:
```ini
[Unit]
Description=Codex App Server

[Service]
ExecStart=/usr/bin/codex app-server --listen ws://127.0.0.1:4311
WorkingDirectory=/path/to/project
Restart=on-failure

[Install]
WantedBy=default.target
```

The `codex-add` tool can install systemd user services for autosave, suggesting systemd integration exists at some level.

### Can `command/exec` be used to bootstrap sessions?
**Yes, this is a key insight for Wuyu**: once connected to a pre-launched app-server (even in an empty project), you can use `command/exec` to:
- Create directories: `mkdir -p /path/to/project`
- Initialize git repos: `git init`
- Clone repos: `git clone <url>`
- Then start a new thread in that directory

This eliminates the need for a separate "session bootstrap" SSH exec channel.

---

## Key Takeaways for Wuyu Architecture

1. **No `claude app-server`**: Wuyu's SSH-based approach to Codex is the right call. Claude Code lacks an equivalent persistent JSON-RPC server interface.

2. **Remote Control is not Wuyu's competition**: Anthropic's Remote Control requires terminal to stay open, requires HTTPS polling through Anthropic's cloud, and doesn't solve the bootstrap problem. Wuyu's SSH-based, self-hosted approach has distinct advantages.

3. **Session bootstrap is unsolved**: Nobody elegantly solves "(pick host) → (pick project) → agent starts" without manual terminal work. This is Wuyu's differentiator opportunity. The approach: SSH exec to start `codex app-server` in tmux/screen or as a managed process, then connect via stdin/stdout.

4. **`command/exec` reduces SSH surface area**: Once the app-server is running, `command/exec` can handle dir creation, git init, etc. — no need for a persistent separate SSH exec channel for setup tasks.

5. **WebSocket is not yet reliable enough**: For Wuyu's use case (mobile, flaky networks), stdio over SSH is more reliable than WebSocket. WebSocket mode is still experimental. The `thread/resume` persistence model works with WebSocket reconnects but the connection-scoped `command/exec` does not survive disconnects.

6. **Claude Agent SDK is irrelevant to Wuyu's server-side**: The SDK is a local Python/TypeScript library that runs agents in-process. It's not a server protocol. For a mobile app controlling a remote agent, the Codex app-server protocol is the right interface.

7. **Session resumption via `thread/resume`**: Pre-launching app-server in tmux/systemd + using `thread/resume` on reconnect is the production path for Wuyu. Thread history persists on disk; clients can reconnect and resume seamlessly.

---

## Gaps / What Could Not Be Found

- Exact wire format of Agent SDK ↔ `claude` CLI subprocess (not publicly documented)
- Whether Claude Code's internal architecture will ever expose a Codex-style app-server
- Confirmed multi-client support for Codex app-server WebSocket (described as in-progress by OpenAI)
- aiya000/claude-code-mobile-ssh bootstrap details (repo is WIP)
- Official Anthropic position on supporting `claude app-server` style interface
- Whether `codex app-server` in WebSocket mode can handle concurrent connections from multiple phones (unconfirmed)
