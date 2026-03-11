# Wuyu — Implementation Plan & Milestones

## Guiding principles

1. **Wire protocol first.** Get the JSONL/JSON-RPC layer right before touching UI. Every later milestone builds on this.
2. **Vertical slices.** Each milestone produces something testable end-to-end, not a pile of unconnected modules.
3. **Separate concerns early.** Transport (SSH), protocol (JSONL-RPC), state (local model), and UI are distinct layers from day one.
4. **Communication, not terminal.** This is not a shell or terminal emulator. The primary interaction is: type a message → see agent response + approvals. Everything else is secondary.
5. **Mobile realities from the start.** Reconnection, backgrounding, and local caching are designed into the state layer — not bolted on later.

---

## Tech stack

| Concern | Choice | Rationale |
|---|---|---|
| Mobile framework | **Flutter** | One codebase for iOS + Android; idiomatic async streams for JSONL; production-proven SSH via dartssh2 |
| SSH library | **dartssh2** | Pure Dart (no native bindings), `SSHClient.execute()` → `SSHSession` with `stdout: Stream<Uint8List>`, channel exec + stdin/stdout streaming |
| State management | **Riverpod** | Fine-grained reactive state, works well with async streams, testable |
| Local persistence | **SQLite via drift** | Thread metadata, cached items, host configs; type-safe queries |
| JSON | **dart:convert + freezed** | `jsonDecode` + freezed union types for protocol discriminated unions |
| Secure storage | **flutter_secure_storage** | Keychain (iOS) + Keystore (Android) for SSH keys and credentials |
| Auth (biometric) | **local_auth** | Face ID / Touch ID for key unlock |

**JSONL pipeline in Dart** (load-bearing pattern):
```dart
final session = await sshClient.execute('codex app-server');

session.stdout
    .cast<List<int>>()
    .transform(utf8.decoder)
    .transform(const LineSplitter())
    .listen((line) => dispatch(jsonDecode(line)));

session.stdin.add(utf8.encode('${jsonEncode(msg)}\n'));
```

See `.notes/mobile-stack-decision.md` for full rationale and alternatives considered.

---

## Prior work (Python protocol reference)

`src/wuyu/` contains a Python 3.12 prototype used to explore and validate the protocol:
- JSONL codec, Transport ABC, SshTransport (asyncssh), Session (request/response correlation)
- 81 tests passing — serves as a living specification for the Dart implementation
- Keep as reference and testing tooling; not the production app

---

## M0 — Flutter project scaffold & SSH smoke test

**Goal:** Buildable Flutter app that can open an SSH connection, exec `codex app-server`, send `initialize`, and print the server's `userAgent`.

### Tasks
- [ ] `flutter create wuyu_app` — package name `app.wuyu`
- [ ] Add dependencies: `dartssh2`, `riverpod`, `freezed`, `json_serializable`, `drift`, `flutter_secure_storage`, `local_auth`
- [ ] Port JSONL codec to Dart: `encode(msg) → String`, `decode(String) → JsonRpcMessage`
- [ ] Port message classification: field-presence discrimination (id+method → Request, method-only → Notification, etc.)
- [ ] Implement `SshTransport` in Dart using dartssh2 channel exec
- [ ] Implement `Session` in Dart: request/future correlation, notification queue, approval queue
- [ ] Smoke test: connect to a test server, send `initialize`, receive `InitializeResponse`, send `initialized`
- [ ] CI: GitHub Actions for `flutter analyze` + `flutter test`

### Exit criteria
- Flutter app builds for iOS and Android
- `initialize` handshake succeeds against a real or mocked server
- All protocol types round-trip correctly in tests

---

## M1 — Codex installation on remote host

**Goal:** App can detect whether `codex` is installed on the remote host and guide the user through installing it.

### Tasks
- [ ] SSH `exec` (not app-server): run `which codex` or `codex --version` to detect installation
- [ ] If not found: show install instructions UI
  - Display the install command (e.g., `npm install -g @openai/codex` or cargo install)
  - Offer one-tap "run this command" with visible output in a scrollable log view
  - Show progress; detect success/failure from exit code
- [ ] After install: verify by re-running `codex --version`
- [ ] Store detected codex version in host config
- [ ] Handle: codex installed but not on PATH, wrong version, auth not configured

### Exit criteria
- App detects codex presence on connect
- If missing, user can install it without leaving the app
- Version info is shown in host settings

---

## M2 — Thread lifecycle & basic chat

**Goal:** User can start a thread, send a message, see a streaming agent response. The core loop.

### Tasks
- [ ] Implement `thread/start` → get thread ID
- [ ] Implement `turn/start` with text input
- [ ] Handle streaming notifications:
  - `turn/started` / `turn/completed`
  - `item/started` / `item/completed`
  - `item/agentMessage/delta` → accumulate deltas into full text
- [ ] Delta accumulation: `AgentMessageState` that buffers deltas and exposes current text
- [ ] Chat screen:
  - Text input at bottom
  - Scrolling message list (user messages right, agent messages left)
  - Streaming indicator while turn is in progress (e.g., blinking cursor or animated dots)
  - Turn status: in-progress / completed / failed
- [ ] Wire: tap Send → `turn/start` → stream items → update UI reactively

### Exit criteria
- Multi-turn conversation works end-to-end
- Agent responses stream in real-time (characters appear as deltas arrive)
- Failed turns show error info

### Tricky bits
- **Delta accumulation**: deltas are partial UTF-8 chunks. Buffer correctly at boundaries.
- **Out-of-order items**: items in a turn have IDs; accumulate by item ID, not just append.

---

## M3 — Approvals & permission UI

**Goal:** App responds to all server-initiated approval requests. The core differentiator.

### Tasks
- [ ] Dispatch server-initiated requests (have `id`, MUST respond):
  - `item/commandExecution/requestApproval` → show command + cwd; Approve / Approve for Session / Abort
  - `item/fileChange/requestApproval` → show file path + unified diff; Approve / Reject
  - `item/tool/requestUserInput` → elicitation form or URL; Accept / Decline / Cancel
- [ ] Track pending approvals: Map of request ID → approval state; survive screen navigation
- [ ] Approval UI components:
  - Command card with command string, cwd, reason
  - Diff viewer: unified diff with red/green lines, horizontal scroll for long lines
  - Elicitation: render form fields from schema
- [ ] Thread status indicator: badge/banner when an approval is waiting
- [ ] Local notification when app is backgrounded and approval arrives (iOS + Android)
- [ ] Timeout handling: if no response, show persistent "Approval waiting" indicator

### Exit criteria
- All approval types render and respond correctly
- Approvals are visually prominent (can't be accidentally missed)
- Local notification fires within 30s of approval request when app is backgrounded

---

## M4 — Project & session management

**Goal:** Multi-host, multi-project, multi-thread management. The "chat rooms" mental model.

### Tasks
- [ ] Data model: `Host` (host, port, username, auth method), `Project` (host + remote path), `ThreadSummary` (cached metadata)
- [ ] Drift schema: hosts, projects, thread cache (last 200 items per thread)
- [ ] UI screens:
  - **Hosts list**: add / edit / remove SSH hosts; auth: password or key
  - **Projects list** (per host): add / edit / remove remote directories
  - **Threads list** (per project): from `thread/list` + local cache, sorted by last activity
  - **Chat screen**: M2 chat + M3 approvals, scoped to thread
- [ ] SSH key management: import key from clipboard/file, generate Ed25519 key pair, store in Keychain/Keystore
- [ ] `thread/archive` and `thread/rollback` actions from thread list
- [ ] `thread/list` refresh on pull-to-refresh

### Exit criteria
- Multiple hosts and projects manageable in the app
- Thread list loads from cache instantly, syncs from server in background
- Adding a new host is a < 30-second flow

---

## M5 — Reconnection & offline resilience

**Goal:** App survives network drops, backgrounding, and phone sleep without data loss.

### Tasks
- [ ] Connection state machine: `Connected → Disconnecting → Disconnected → Reconnecting → Connected`
  - Subtle status indicator in UI (not a blocking modal)
- [ ] Auto-reconnect: exponential backoff (1s, 2s, 4s, 8s, cap 30s)
- [ ] State resync on reconnect:
  - Re-initialize handshake
  - `thread/list` to refresh
  - `thread/resume` for active thread; then `thread/read` to get full state
  - Re-check for pending approvals in thread status
- [ ] Local cache write: write thread items to drift as they arrive
  - Show cached history immediately on open; sync in background
- [ ] OS backgrounding:
  - iOS: background execution time for pending approvals
  - Android: foreground service for active sessions
- [ ] Remote-supervised mode (optional for M5):
  - Detect if app-server already running in tmux/systemd
  - Reconnect to existing process instead of starting a new one

### Exit criteria
- Kill WiFi mid-conversation → reconnects and resumes without data loss
- Lock phone 5 minutes → unlock → resumes within 5 seconds
- Cached threads viewable offline (read-only)

### Tricky bits
- **Missed events on reconnect**: `thread/resume` does NOT replay missed events.
  Use `thread/read` to get current state, then show "[reconnected — live from here]" marker.
- **Duplicate items on resync**: deduplicate by item ID (UUID).

---

## M6 — Rich item rendering & polish

**Goal:** Render all item types meaningfully. App feels like a real product.

### Tasks
- [ ] `CommandExecution`: command, exit code, stdout/stderr (collapsible)
- [ ] `FileChange`: syntax-highlighted diff viewer
- [ ] `Reasoning`: collapsible "thinking" section
- [ ] `WebSearch`: query + summary
- [ ] `McpToolCall` / `DynamicToolCall`: tool name + args + result
- [ ] `CollabAgentToolCall`: sub-agent activity indicator
- [ ] Code blocks in agent messages: syntax highlighting (`flutter_highlight`)
- [ ] Context attachment: browse remote files, add to turn input
- [ ] Settings screen: default approval policy, notification preferences, theme (dark/light)
- [ ] Virtualized list for long conversations (Flutter `ListView.builder`)

### Exit criteria
- Every item type renders meaningfully (not raw JSON)
- 500+ item conversations scroll smoothly
- App usable for daily work sessions

---

## M7 — Job mode & notifications

**Goal:** Fire-and-forget tasks. The full "walking outside" experience.

### Tasks
- [ ] "Run as job" flow: launch `codex exec` (detached), store job ID
- [ ] Poll for job status on reconnect; display result when done
- [ ] Push notifications (options: lightweight relay OR periodic SSH polling)
  - Notify on: approval waiting, job done, turn failed
- [ ] Notification actions: Approve/Reject directly from notification (Android)

---

## M8 — Hardening & release prep

- [ ] Security audit: key storage, no plaintext credentials, host key verification (TOFU)
- [ ] Error handling pass: every failure mode shows a user-friendly message
- [ ] Version negotiation: query server capabilities on connect
- [ ] Crash reporting & analytics (opt-in)
- [ ] App store metadata, screenshots, onboarding
- [ ] Beta testing with real Codex App Server instances

---

## Dependency graph

```
M0 (Flutter scaffold + SSH + protocol)
 └→ M1 (codex installation detection)
     └→ M2 (basic chat)
         ├→ M3 (approvals)      ← can parallel with M4
         ├→ M4 (project mgmt)   ← can parallel with M3
         │   └→ M5 (reconnection)
         │       └→ M7 (job mode)
         └→ M6 (rich rendering) ← start after M3
             └→ M8 (hardening)
```

---

## Risk registry

| Risk | Impact | Mitigation |
|---|---|---|
| Codex protocol changes | High | Pin to schema version; document all assumptions in `.notes/` |
| dartssh2 limitations | Medium | Spike channel exec + streaming in M0 before committing |
| Mobile OS kills background SSH | Medium | Design for fast reconnect, not keep-alive; use OS background modes |
| Diff rendering on small screens | Low | Truncate large diffs; "show full" button; horizontal scroll |
| Codex auth (OAuth) from mobile | Medium | Ship M0-M5 with API key auth only; add OAuth in M6+ |
| App store SSH security review | Low | Frame as "remote development tool," not "SSH terminal" |

---

## Key references

- `.notes/protocol-rpc-methods.md` — all RPC methods, notifications, wire format
- `.notes/mobile-stack-decision.md` — tech stack rationale and alternatives
- `.notes/ssh-transport.md` — SSH integration gotchas (from Python prototype)
- `PROJECT_SPEC.md` — product specification and architectural rationale
- `src/wuyu/` — Python protocol reference implementation (M0/M1 validated design)
- Codex RS: https://github.com/openai/codex/tree/main/codex-rs
  - `app-server` — the binary
  - `app-server-protocol` — all JSON-RPC types, schemas
  - `app-server-protocol/schema/json/` — 38 JSON Schema files
  - `app-server-protocol/schema/typescript/` — 230+ TypeScript definitions
- dartssh2: https://pub.dev/packages/dartssh2
- Flutter Server Box (dartssh2 reference app): https://github.com/lollipopkit/flutter_server_box
- Farfield (web Codex UI, design patterns): https://github.com/achimala/farfield
- Happy Coder (Flutter Codex mobile app): https://github.com/slopus/happy
