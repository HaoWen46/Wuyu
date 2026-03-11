# Research: Codex App Server Protocol, Farfield, Mobile Apps, and Tech Stack

Date: 2026-03-11

---

## 1. Codex App Server Protocol Summary

### Launch Command and Flags

```
codex app-server [--listen <URL>]
```

- `--listen stdio://` — default, newline-delimited JSON on stdin/stdout
- `--listen ws://IP:PORT` — WebSocket mode (experimental/unsupported for external use)

Environment variables:
- `RUST_LOG` — log verbosity
- `LOG_FORMAT=json` — structured JSON logging to stderr
- `CODEX_APP_SERVER_MANAGED_CONFIG_PATH` — optional managed config (debug builds only)

The stdio transport reads lines from stdin and writes lines to stdout. Each line is a complete JSON-RPC message. The transport spawns separate read and write tasks, communicating via bounded channels (capacity 128 per direction). There is **no `"jsonrpc":"2.0"` field on the wire** — this is by design.

### Wire Format

JSONL (newline-delimited JSON). One JSON object per line. Four message shapes:

| Shape | Fields present | Meaning |
|-------|---------------|---------|
| Request | `method` + `id` + optional `params` | Client to Server RPC call |
| Notification | `method` + optional `params` (no `id`) | Server to Client event |
| Response | `id` + `result` | Server to Client reply |
| Error | `id` + `error` | Server to Client error reply |

RequestId is either a string or 64-bit integer. `error` object has `code`, `message`, optional `data`.

### Initialization Handshake (required before any other RPC)

Step 1 — Client sends `initialize` request:

```json
{
  "method": "initialize",
  "id": 0,
  "params": {
    "clientInfo": {
      "name": "codex_vscode",
      "title": "Codex VS Code Extension",
      "version": "0.1.0"
    },
    "capabilities": {
      "experimentalApi": true,
      "optOutNotificationMethods": ["item/agentMessage/delta"]
    }
  }
}
```

- `clientInfo.name` identifies the integration; enterprise integrations need OpenAI allowlist
- `capabilities.experimentalApi` opts into unstable features
- `capabilities.optOutNotificationMethods` suppresses specific notification methods (exact string match, no wildcards)

Step 2 — Server sends `initialize` response with `id: 0` and a `result` object (user-agent string etc).

Step 3 — Client sends `initialized` notification (no `id`):
```json
{ "method": "initialized" }
```

Server rejects non-initialize requests received before this handshake with "Not initialized" error. Duplicate `initialize` calls get "Already initialized" error. Connection state per transport connection — not global.

### Core Conversation Model

```
Thread (persistent conversation container)
  └── Turn (one unit of agent work, triggered by user input)
        └── Item (atomic input/output unit with lifecycle)
```

### All RPC Methods (Client to Server)

#### Thread Operations

| Method | Description |
|--------|-------------|
| `thread/start` | Create new thread; auto-subscribes to events; emits `thread/started` |
| `thread/resume` | Reopen existing thread by ID |
| `thread/fork` | Branch thread history; optional `ephemeral` flag |
| `thread/list` | Paginated list with filters (model, source, cwd, search, sortKey) |
| `thread/read` | Fetch thread data without resuming |
| `thread/archive` | Archive thread |
| `thread/unarchive` | Unarchive thread |
| `thread/compact/start` | Compress history (context compaction) |
| `thread/metadata/update` | Patch `gitInfo` fields |
| `thread/name/set` | Rename thread |
| `thread/rollback` | Drop N turns from end |

`thread/start` params (all optional): `model`, `modelProvider`, `serviceTier`, `cwd`, `approvalPolicy`, `sandbox`, `config`, `baseInstructions`, `developerInstructions`, `personality`, `ephemeral`, `dynamicTools`.

Example `thread/start` request and response:
```json
{"method": "thread/start", "id": 10, "params": {"model": "gpt-5.1-codex"}}
{"id": 10, "result": {"thread": {"id": "thr_123"}}}
```

#### Turn Operations

| Method | Description |
|--------|-------------|
| `turn/start` | Trigger agent work with user input |
| `turn/steer` | Append input to in-flight turn without creating new turn |
| `turn/interrupt` | Cancel active turn |

`turn/start` example:
```json
{
  "method": "turn/start",
  "id": 30,
  "params": {
    "threadId": "thr_123",
    "input": [{"type": "text", "text": "Run the tests"}],
    "model": "gpt-5.1-codex",
    "cwd": "/repo",
    "approvalPolicy": "unlessTrusted"
  }
}
```

Input item types: `text` (field: `text`), `image` (field: `url`), `localImage` (field: `path`), `skill` (fields: `name`, `path`), `mention` (fields: `name`, `path` like `app://id`).

Per-turn override fields: `model`, `effort`, `cwd`, `sandboxPolicy`, `approvalPolicy`, `personality`, `outputSchema`.

`turn/steer` params: `threadId`, `input`, `expectedTurnId` (optimistic concurrency check).

#### Command Execution (outside thread context)

| Method | Description |
|--------|-------------|
| `command/exec` | One-off sandboxed command; supports PTY, streaming I/O, base64 encoding |
| `command/exec/write` | Write to stdin or close it |
| `command/exec/resize` | Resize PTY (rows, cols) |
| `command/exec/terminate` | Kill process |

#### Configuration

| Method | Description |
|--------|-------------|
| `config/read` | Read effective configuration |
| `config/value/write` | Single key update |
| `config/batchWrite` | Atomic multi-key edit |
| `configRequirements/read` | MDM and requirements.toml |

#### Models and Account

| Method | Description |
|--------|-------------|
| `model/list` | Available models with reasoning effort options, disabled reasons |
| `account/read` | Current auth state (email, plan_type, api_key) |
| `account/login/start` | API key or chatgpt flow |
| `account/login/cancel` | Abort OAuth |
| `account/logout` | Sign out |
| `account/rateLimits/read` | Quota status |

#### Skills, Apps, MCP

| Method | Description |
|--------|-------------|
| `skills/list` | Available skills by cwd |
| `skills/config/write` | Enable/disable skills |
| `app/list` | Connectors with metadata |
| `plugin/list` | Discovered marketplaces |
| `mcpServer/oauth/login` | OAuth for configured MCP server |
| `mcpServerStatus/list` | Enumerate servers with tools |
| `config/mcpServer/reload` | Refresh from disk |

#### Reviews and Other

| Method | Description |
|--------|-------------|
| `review/start` | Automated reviewer; delivery: `inline` or `detached`; targets: uncommitted, branch, commit, custom |
| `windowsSandbox/setupStart` | Trigger async Windows sandbox init |
| `fuzzyFileSearch/session/start` (experimental) | Start fuzzy search session |
| `fuzzyFileSearch/session/update` (experimental) | Update query |
| `fuzzyFileSearch/session/stop` (experimental) | Stop session |
| `thread/realtime/*` (experimental) | Realtime session operations |

### Server-Initiated Notifications (Server to Client)

#### Thread Lifecycle
- `thread/started` — includes `thread.status`
- `thread/archived`, `thread/unarchived`, `thread/closed`
- `thread/status/changed` — transitions: `notLoaded`, `idle`, `systemError`, `active` (with `waitingOnApproval` flag)
- `thread/name/updated`

#### Turn Lifecycle
- `turn/started` — turn began running
- `turn/completed` — status: `completed` | `interrupted` | `failed`; `codexErrorInfo` on failure
- `turn/plan/updated` — agent planning steps
- `turn/diff/updated` — aggregated file changes
- `model/rerouted` — backend failover notification

#### Item Lifecycle (within a turn)
- `item/started` — item began
- `item/completed` — final authoritative state
- `item/agentMessage/delta` — streamed text chunk
- `item/commandExecution/outputDelta` — live command stdout/stderr
- `item/fileChange/outputDelta` — patch chunks
- `item/plan/delta` (experimental) — planning mode chunks
- `item/reasoning/*` (experimental) — reasoning summaries
- `command/exec/outputDelta` — for standalone `command/exec` calls

#### Approval Requests (Server-Initiated JSON-RPC Requests — have `id`, MUST be responded to)
- `item/commandExecution/requestApproval` — shell command needs decision
- `item/fileChange/requestApproval` — file modification needs decision
- `item/tool/requestUserInput` (experimental) — MCP elicitation

Decision values: `accept`, `acceptForSession`, `decline`, `cancel`, `applyNetworkPolicyAmendment` (with host allowlist).

Server sends `serverRequest/resolved` after client responds. Then `item/completed` with final status.

#### Other Server Notifications
- `skills/changed` — local skill file updates
- `app/list/updated` — app source refresh
- `account/login/completed`, `account/updated`, `account/rateLimits/updated`
- `mcpServer/oauthLogin/completed`
- `windowsSandbox/setupCompleted`
- `fuzzyFileSearch/session/updated`, `fuzzyFileSearch/session/completed` (experimental)

### Thread Item Types (from thread_history.rs)

| Variant | Key fields |
|---------|-----------|
| `UserMessage` | `id`, `content: Vec<UserInput>` |
| `AgentMessage` | `id`, `text`, `phase?` (commentary \| final_answer) |
| `Reasoning` | `id`, `summary: Vec<String>`, `content: Vec<String>` |
| `WebSearch` | `id`, `query`, `action?` |
| `CommandExecution` | `id`, `command`, `cwd`, `process_id`, `status`, `command_actions`, `aggregated_output`, `exit_code`, `duration_ms` |
| `FileChange` | `id`, `changes: Vec<FileUpdateChange>`, `status` |
| `McpToolCall` | `id`, `server`, `tool`, `status`, `arguments`, `result`, `error`, `duration_ms` |
| `DynamicToolCall` (exp.) | `id`, `tool`, `arguments`, `status`, `content_items`, `success`, `duration_ms` |
| `ImageView` | `id`, `path` |
| `ImageGeneration` | `id`, `status`, `revised_prompt`, `result` |
| `CollabAgentToolCall` | `id`, `tool`, `status`, multi-agent coordination fields |
| `ContextCompaction` | `id` |
| `EnteredReviewMode` | `id`, `review` |
| `ExitedReviewMode` | `id`, `review` |

### Key Enums

`AskForApproval`: `UnlessTrusted`, `OnFailure`, `OnRequest`, `Reject`, `Never`

`SandboxMode`: `ReadOnly`, `WorkspaceWrite` (with `writableRoots`), `DangerFullAccess`, `ExternalSandbox` (with `networkAccess`: Enabled | Restricted)

`ThreadStatus`: `notLoaded`, `idle`, `systemError`, `active`

`SessionSource`: `Cli`, `VsCode`, `Exec`, `AppServer`, `SubAgent`

`TurnCompletedStatus`: `completed`, `interrupted`, `failed`

`CodexErrorInfo` variants: `ContextWindowExceeded`, `UsageLimitExceeded`, `HttpConnectionFailed { httpStatusCode }`, `ResponseStreamDisconnected`, `SandboxError`, `InternalServerError`, `Other`

### Backpressure

Error code `-32001`, message "Server overloaded; retry later."

Only triggers on WebSocket transport when bounded input queue is full. Stdio transport waits indefinitely (no disconnect). Clients should use exponential backoff with jitter.

### Transport Architecture (Rust internals)

- **Stdio**: BufReader on stdin line-by-line → parse → bounded channel (128). Writer task reads from channel, serializes, writes `json + "\n"` to stdout. No overload disconnect — waits forever.
- **WebSocket**: Axum HTTP server with `/readyz`, `/healthz` endpoints. Handles multiple concurrent clients. Slow clients disconnected when outbound queue fills. Each connection gets a unique `ConnectionId`.

### Pre-Launch and Reconnection

- **Ephemeral (stdio)**: App Server exits when SSH disconnects. Single-client mode. Simple.
- **WebSocket (experimental)**: Supports multiple concurrent clients, survives individual disconnects. Can be pre-launched in tmux/systemd. On reconnect: new `initialize` handshake, then `thread/resume` to re-subscribe.
- For reconnection: `thread/resume` restores state from persisted thread history. The client must re-request current thread state since it missed notifications during disconnect.
- Graceful shutdown: SIGTERM → drain mode (no new requests, wait for running turns) → second signal → force disconnect.

### Schema Generation

```
codex app-server generate-ts --out DIR [--experimental]
codex app-server generate-json-schema --out DIR [--experimental]
```

Outputs match exactly the installed binary's version.

---

## 2. Farfield Analysis

**Repo**: https://github.com/achimala/farfield

### What It Does

Farfield is a web-based remote control interface for AI coding agents (Codex and OpenCode). It runs a local Node.js/Bun server on port 4311 that proxies between a browser UI and the Codex IPC socket. Users browse threads, send messages, monitor agent activity, and handle approvals.

### Architecture

```
Browser (React/Vite/Tailwind/Shadcn)
    ↓ HTTP + Server-Sent Events (GET /api/unified/events → text/event-stream)
Node.js/Bun Server (port 4311)
    ↓ Unix IPC socket (os.tmpdir()/codex-ipc/ipc-{uid}.sock  or  \\.\pipe\codex-ipc on Windows)
Codex process (running on same machine)
```

NOT SSH-based. Assumes Codex is running locally. Uses Desktop IPC (not the public stdio app-server protocol). The IPC socket is the internal channel used by the VS Code extension.

### Source Structure

```
apps/
  server/src/
    agents/
      adapters/
        codex-agent.ts      # DesktopIpcClient → Codex IPC socket
        opencode-agent.ts   # OpenCode agent adapter
      registry.ts           # AgentRegistry (manages adapters)
      thread-index.ts       # Maps thread IDs to owning agent
      types.ts              # AgentAdapter interface
    unified/
      adapter.ts            # Multi-agent unified adapter
    http-schemas.ts
    index.ts                # HTTP server, SSE endpoint
    logger.ts
  web/src/                  # React frontend
```

### Key Design Decisions

1. **IPC not app-server**: Connects to Codex via `DesktopIpcClient` (internal IPC socket). The IPC messages include `method: "thread-stream-state-changed"` broadcasts and request-type messages for approvals.

2. **SSE for browser**: `GET /api/unified/events` returns `text/event-stream` with 15-second keepalive intervals. Simpler than WebSocket for one-directional server push.

3. **In-memory frame history**: Capped at 2,000 IPC frames per adapter, available in a debug tab showing full IPC message history with method, threadId, direction.

4. **Stream event caching**: Thread stream state cached per `threadId`, last 400 events. Allows new browser connections to get current state immediately.

5. **Multi-agent abstraction**: `AgentRegistry` handles Codex and OpenCode through a common `AgentAdapter` interface. `ThreadIndex` resolves which agent owns each thread ID.

6. **Approval routing**: Pending `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, `item/tool/requestUserInput` tracked by request ID, resolved via adapter.

7. **Auto-reconnect**: IPC adapter reconnects with configurable delay (default 1000ms) on disconnect. `ipcConnected` + `ipcInitialized` flags exposed for UI.

8. **Security**: No built-in auth. Tailscale VPN recommended for remote access. CORS headers on all responses.

9. **Graceful shutdown**: Signal handling with 4-second forced timeout, closing SSE connections, IPC adapters, and file streams cleanly.

### Tech Stack

- Runtime: Bun 1.2+, Node.js 20+
- Frontend: React, TypeScript, Vite, Tailwind CSS, Shadcn/ui
- Backend: HTTP with SSE (no WebSocket)
- No mobile client — browser only (responsive CSS)
- Supports both Codex and OpenCode agents

### Lessons for Wuyu

- Farfield proves the concept but is a web overlay over local IPC, not remote SSH. Different problem.
- The IPC approach is NOT what Wuyu needs. Wuyu wants the public stdio app-server protocol over SSH.
- The multi-agent adapter pattern is clean; relevant if Wuyu supports both Codex and Claude Code.
- The approval flow tracking pattern (pending requests by ID, resolved via adapter) is directly applicable.
- In-memory event history with a capped size is a smart mobile caching pattern — prevents unbounded growth during long sessions.
- SSE vs WebSocket: for mobile native apps, WebSocket or direct stream reads are better than SSE.
- The thread stream state caching model (snapshot + patches) is good for reconnect UX.

---

## 3. Other Similar Apps Found

### Moshi (iOS, commercial)

**URL**: https://getmoshi.app  
**App Store**: https://apps.apple.com/us/app/moshi-ssh-mosh-terminal/id6757859949

Architecture: Mosh (Mobile Shell) + SSH + tmux. A polished iOS terminal with AI-agent ergonomics:
- Mosh protocol for session resilience across network changes, sleep mode, tunnels
- Deep tmux integration — native window/session switching without typing tmux commands
- On-device voice-to-terminal: Whisper, Apple Intelligence, or default ASR (no cloud, no latency)
- Push notifications (webhook-based) when tasks complete or need input
- Face ID + iOS Keychain for SSH key storage
- Multiple themes (Nord, Dracula, Solarized)
- Dedicated terminal keyboard with Ctrl, Esc, arrow keys, tmux-specific controls

Approach: Still fundamentally a terminal emulator. "AI agent" support means ergonomic improvements for tmux + Claude Code, not structured JSON-RPC. No approval UI — just terminal text.

Lesson: This is the quality bar for "mobile SSH terminal." Wuyu's value proposition must be distinctly different: structured UI for Codex events, typed approval flows, message timeline — not a better terminal.

### Happy Coder (iOS + Android + Web, open source)

**Repo**: https://github.com/slopus/happy  
**App Store**: https://apps.apple.com/us/app/happy-codex-claude-code-app/id6748571505

Architecture: CLI relay with E2E encryption via cloud server.
```
happy CLI (desktop, wraps claude/codex)
    ↓ E2E encrypted relay (Happy Server)
Mobile app (Expo/React Native) + Web
```

Setup: `npm install -g happy-coder`. Run `happy` instead of `claude`/`codex`. First run generates encryption keys, displays QR code. Mobile scans QR, gets shared secret. All traffic encrypted before leaving machine.

Key features:
- QR code pairing — no port forwarding, no VPN config
- E2E encryption using TweetNaCl (Signal-equivalent)
- Push notifications for approvals and task completion
- Offline-first: CLI writes encrypted blobs to object storage; mobile fetches/decrypts async
- Device toggling — any key press on desktop reclaims control
- Voice integration via Eleven Labs STT/TTS
- Expo (React Native) for mobile — iOS + Android cross-platform
- Zero-knowledge relay: server sees only encrypted blobs

Tech: TypeScript (97.6% of codebase), Expo, Happy Server backend.

Lesson: The relay+QR approach solves "no SSH" for most users. Wuyu's SSH-based approach is architecturally different: more direct, no relay server, works air-gapped, requires no extra install on remote machine beyond Codex. SSH is a meaningful differentiator for infrastructure-oriented users.

### claude-code-mobile-ssh (PWA, open source)

**Repo**: https://github.com/aiya000/claude-code-mobile-ssh  
Tech: TypeScript, Next.js, Bun, PWA architecture.  
100+ stars. Graphical client for Claude Code via SSH. Positioned between "just a terminal" and "RDP/VNC." Details on exact SSH integration not documented publicly.

### claude-code-app (Flutter, open source)

**Repo**: https://github.com/9cat/claude-code-app  
Tech: Flutter/Dart (41.7%), Go (13%), WebSocket, Docker, SSH tunnel.  
Architecture: Flutter mobile → SSH tunnel → Docker containers → Claude Code CLI → Anthropic API. More infrastructure-heavy. Go proxy server bridges SSH to WebSocket. Does NOT speak the app-server JSONL protocol — wraps Claude Code CLI differently.

### CloudCLI / claudecodeui (Web, open source)

**Repo**: https://github.com/siteboon/claudecodeui  
Tech: React, Vite, TypeScript, Tailwind, CodeMirror.  
Reads/writes Claude Code config files directly. File explorer, git, shell terminal, session management. Self-hosted or SaaS cloud. No SSH — assumes local access or cloud environment.

### Claude Code Remote Control (official Anthropic, Feb 2026)

Anthropic's own Remote Control feature in Claude Code CLI. Native streaming from phone. Zero port forwarding, zero VPN. Closed ecosystem — requires Claude mobile app and Anthropic cloud. No SSH involvement.

### Harper Reed's blog workflow

URL: https://harper.blog/2026/01/05/claude-code-is-better-on-your-phone/  
Setup: Blink Shell (iOS) + Tailscale + Mosh + tmux + SSH keys. Pure terminal. `cc-start` and `cc-continue` shell aliases. Simple and effective for power users. No specialized app.

---

## 4. Tech Stack Recommendation

### Core Technical Requirements

1. Open SSH connection to remote host (known_hosts, key auth, password auth)
2. `channel.exec("codex app-server")` to get bidirectional stdin/stdout byte streams
3. Split stdout into JSONL lines (read until `\n`)
4. Parse JSON-RPC messages and dispatch to typed handlers
5. Serialize and write outgoing messages as JSON + `\n`
6. Handle async notifications while requests are in flight (concurrent streams)
7. Manage reconnection (re-handshake + thread/resume)
8. Render streaming items (agent text delta, command output)
9. Handle approval requests (server-initiated RPC with `id`, require response)
10. Run on iOS (and ideally Android)

### Option A: Flutter (Dart) + dartssh2 — RECOMMENDED

**SSH Library**: `dartssh2` (pub.dev, MIT, terminal.studio publisher, verified)

API for bidirectional channel exec:
```dart
final client = SSHClient(
  await SSHSocket.connect('host', 22),
  username: 'user',
  identities: await SSHKeyPair.fromPem(pemString),
  onVerifyHostKey: (type, fingerprint) => true, // implement TOFU or known_hosts
);
final session = await client.execute('codex app-server');

// Reading JSONL
session.stdout
    .cast<List<int>>()
    .transform(utf8.decoder)
    .transform(const LineSplitter())
    .listen((line) => dispatch(jsonDecode(line)));

// Writing JSON-RPC
session.stdin.add(utf8.encode(jsonEncode(message) + '\n'));
```

Metrics: 11,000 weekly downloads, 140 pub points, 141 likes, 243 stars, MIT license, 63 open issues.
Last release: 2.13.0 (8 months ago) — active but not extremely fast-moving.

Strengths:
- Pure Dart — no native bindings, works on iOS/Android/macOS/Linux/Web with no compilation complexity
- Clean `Stream<Uint8List>` on stdout maps directly to Dart's async stream combinators
- `onVerifyHostKey` callback for host key verification (implement TOFU manually)
- Key auth: `SSHKeyPair.fromPem()` supports RSA, ECDSA, Ed25519
- Production proof: Flutter Server Box uses dartssh2 for SSH terminal on iOS/Android/desktop/TV
- One codebase covers iOS + Android + macOS

Weaknesses:
- No built-in `known_hosts` file parsing — must implement TOFU or custom verification
- 63 open issues — some edge cases with specific server configurations
- Private key encoding (write) is WIP for some algorithms; reading works fine

Ecosystem packages:
- `flutter_secure_storage` — Keychain (iOS) + Keystore (Android) for SSH keys
- `local_auth` — Face ID / Touch ID biometric unlock
- `riverpod` or `bloc` — state management for streaming events

Performance: Flutter with Impeller (Metal on iOS) offers near-native rendering. AOT compilation. Slightly higher memory than native Swift but negligible for a chat UI. JSON parsing in Dart is fast enough for interactive use.

### Option B: Swift (iOS native) — best if iOS-only is acceptable

**SSH Libraries**:

- **Citadel** (https://github.com/orlandos-nl/Citadel): High-level wrapper over SwiftNIO SSH. `executeCommandStream()` returns `AsyncSequence<CommandOutput>` with stdout/stderr events. 317 commits, 341 stars, active Discord. "In active development by our team of Swift experts."
- **SwiftNIO SSH** (https://github.com/apple/swift-nio-ssh): Apple's official implementation. Latest release 0.12.0 (Nov 2025), requires Swift 6.0+. Low-level `NIOSSHHandler` + child channels. `ExecRequest` for exec. `SSHChannelData` for bidirectional data. Set `allowRemoteHalfClosure: true` for proper EOF. Production-ready at Apple scale.
- **NMSSH / SwiftSH**: libssh2 wrappers (Obj-C/C). Older, synchronous APIs. Not recommended for new code.

Strengths:
- Absolute best iOS performance: native LLVM compilation, direct Metal, lowest memory, fastest startup
- SwiftNIO SSH is Apple-maintained and Swift 6 native (async/await, Sendable)
- `Codable` + `JSONDecoder` for fast native JSON parsing
- Native Keychain APIs for SSH key storage, LocalAuthentication for Face ID
- No cross-platform complexity

Weaknesses:
- iOS-only (would need separate Android development)
- SwiftNIO SSH is lower-level — Citadel helps but adds a dependency
- Smaller talent pool than Flutter if hiring

### Option C: Kotlin Multiplatform — not recommended

No mature pure-KMP SSH library. Android can use JSch/sshj via JVM, but iOS requires Swift interop or bridging. More complexity than benefit for a small team. KMP is excellent for sharing business logic but SSH transport still needs per-platform implementation.

### Option D: React Native (TypeScript) — not recommended

No maintained production-ready SSH library for React Native. `ssh2` (Node.js) requires heavy shimming. `react-native-ssh-sftp` exists but has limited maintenance and no channel exec streaming. JS/native bridge adds overhead for high-throughput streaming. Not suitable.

### Final Recommendation

**Flutter + dartssh2** for the following reasons:

1. One codebase for iOS + Android + macOS — aligns with "minimalist" goal
2. dartssh2's `execute()` → `SSHSession` with `Stream<Uint8List>` stdout is exactly right for JSONL
3. Dart streams + `LineSplitter` + `jsonDecode` is clean, idiomatic, and well-tested
4. No native bindings means no iOS/Android build complexity differences
5. The existing Python codebase for Wuyu (protocol types, codec) translates 1:1 to Dart pydantic → `fromJson` pattern
6. Flutter Server Box proves dartssh2 works in production for SSH on mobile
7. Approvals (server-initiated requests) handled naturally in an event loop with a pending-request Map

**If strictly iOS-only**: Swift + Citadel is a compelling choice. SwiftNIO SSH (Apple-maintained, Swift 6) + Citadel's `executeCommandStream()` gives a clean async pipeline with maximum native performance. Recommend this if you want App Store quality and are comfortable maintaining a separate Android solution later (or skipping it).

---

## Key Sources

- https://developers.openai.com/codex/app-server/ — official protocol documentation
- https://github.com/openai/codex/tree/main/codex-rs/app-server — app-server source
- https://github.com/openai/codex/tree/main/codex-rs/app-server-protocol — protocol types source
- https://github.com/achimala/farfield — Farfield source
- https://github.com/slopus/happy — Happy Coder source
- https://getmoshi.app/ — Moshi iOS app
- https://pub.dev/packages/dartssh2 — dartssh2 package
- https://github.com/orlandos-nl/Citadel — Swift SSH (Citadel)
- https://github.com/apple/swift-nio-ssh — Apple's SwiftNIO SSH
- https://www.infoq.com/news/2026/02/opanai-codex-app-server/ — InfoQ Codex App Server article
- https://harper.blog/2026/01/05/claude-code-is-better-on-your-phone/ — Harper Reed's approach
- https://sealos.io/blog/claude-code-on-phone/ — comprehensive Claude Code on phone guide
- https://github.com/9cat/claude-code-app — Flutter+SSH Claude Code app
- https://github.com/aiya000/claude-code-mobile-ssh — PWA SSH Claude Code client
