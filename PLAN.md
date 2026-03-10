# Wuyu — Implementation Plan & Milestones

## Guiding principles

1. **Wire protocol first.** Get the JSONL/JSON-RPC layer right before touching UI. Every later milestone builds on this.
2. **Vertical slices.** Each milestone produces something testable end-to-end, not a pile of unconnected modules.
3. **Separate concerns early.** Transport (SSH), protocol (JSONL-RPC), state (local cache), and UI are distinct layers from day one. This prevents "fix one thing, break three" later.
4. **Mobile realities are not an afterthought.** Reconnection, backgrounding, and offline cache are designed into the state layer from the start — not bolted on in milestone 5.

---

## Tech stack decision (make before M0)

| Concern | Recommended | Rationale |
|---|---|---|
| Mobile framework | Kotlin Multiplatform + Compose Multiplatform (or Flutter) | OpenAI confirms partners have built clients in Kotlin. KMP shares protocol/state logic across Android/iOS. Flutter is viable if the team prefers Dart. |
| SSH library | Apache MINA SSHD (JVM) / Dartssh2 (Flutter) | Needs channel exec + stdin/stdout streaming, not just terminal emulation. |
| Local persistence | SQLite (via SQLDelight or Drift) | Thread metadata, cached items, host configs. Lightweight, offline-ready. |
| JSON parsing | kotlinx.serialization / json_serializable | Generate from the JSON Schema files in codex-rs. |

---

## M0 — Project scaffolding & protocol types (Week 1–2)

**Goal:** Buildable project with generated protocol types and a test harness that can round-trip JSONL messages.

### Tasks
- [ ] Initialize project (KMP or Flutter), set up CI, linting, test runner
- [ ] Pull JSON Schema files from `codex-rs/app-server-protocol/schema/json/`
- [ ] Generate or hand-write protocol data classes from schemas:
  - `JSONRPCMessage` (Request, Notification, Response, Error — note: no `"jsonrpc":"2.0"` field)
  - `RequestId` (String | Int)
  - `ClientRequest` / `ClientNotification` enums
  - `ServerRequest` / `ServerNotification` enums
- [ ] Implement JSONL codec: `encode(message) → line`, `decode(line) → message`
- [ ] Unit tests: round-trip serialize/deserialize for every message variant
- [ ] Define the `Transport` interface: `suspend fun send(msg)`, `Flow<msg> incoming`, `connect()`, `disconnect()`

### Exit criteria
- All protocol types compile and serialize correctly
- JSONL codec passes round-trip tests against sample messages from codex-rs test fixtures
- Transport interface is defined (no SSH yet — just the contract)

---

## M1 — SSH transport & initialization handshake (Week 3–4)

**Goal:** App can SSH into a real host, start `codex app-server`, complete the `initialize`/`initialized` handshake, and print the server response.

### Tasks
- [ ] Implement `SshTransport` conforming to the `Transport` interface
  - Open SSH connection (host, port, key/password)
  - Exec `codex app-server` (or configurable command)
  - Bridge SSH channel stdin/stdout ↔ JSONL codec
- [ ] Implement the initialization sequence:
  1. Send `initialize` request with `ClientInfo`
  2. Receive `InitializeResponse`
  3. Send `initialized` notification
- [ ] Implement request/response correlation (match response `id` to pending request)
- [ ] Implement connection lifecycle: connect, health check, graceful disconnect
- [ ] Error handling: SSH auth failure, process start failure, handshake timeout
- [ ] Integration test: connect to a real or mocked `codex app-server`, verify handshake

### Exit criteria
- Can connect to a remote host over SSH and complete the handshake
- Request/response correlation works (concurrent requests don't mix up)
- Clean error reporting for common failures

### Tricky bits to watch
- **SSH key management on mobile** — iOS Keychain / Android Keystore integration. Don't store keys in plaintext. Can defer to password-only auth for M1 and add key auth in M3.
- **Process lifecycle** — if SSH channel closes, the app-server process should die. Verify this.

---

## M2 — Thread lifecycle & basic chat (Week 5–7)

**Goal:** Minimal chat UI. User can create a thread, send a message, see streaming agent responses.

### Tasks
- [ ] Implement thread operations: `thread/start`, `thread/list`, `thread/resume`
- [ ] Implement turn lifecycle: `turn/start`, handle `turn/started`/`turn/completed` notifications
- [ ] Implement streaming: handle `item/started`, `item/agentMessage/delta`, `item/completed`
  - Accumulate deltas into a complete message
  - Handle out-of-order or missing deltas gracefully
- [ ] Build minimal chat UI:
  - Single screen: text input + scrolling message list
  - User messages (right-aligned) and agent messages (left-aligned)
  - Streaming indicator while turn is in progress
  - Turn status display (in-progress, completed, failed)
- [ ] Wire up: UI → turn/start → stream items → render

### Exit criteria
- Can have a multi-turn conversation with Codex through the app
- Agent responses stream in real-time (not block-wait-then-show)
- Thread can be resumed after navigating away and back

### Tricky bits to watch
- **Delta accumulation** — deltas are partial text chunks. Must handle UTF-8 boundaries correctly.
- **Backpressure** — if agent streams faster than UI renders, don't OOM. Use bounded buffers.

---

## M3 — Approvals & permission UI (Week 8–9)

**Goal:** The app can respond to all server-initiated approval requests. This is the core differentiator — "approve from your phone while walking."

### Tasks
- [ ] Handle server-initiated requests (server sends request with `id`, client must respond):
  - **Command execution approval**: show command, cwd, reason; buttons for Approve / Approve for Session / Abort
  - **File change approval**: show diff (path + modification per file); Approve / Reject
  - **Permissions request approval**: show permission details; Grant / Deny
  - **Elicitation**: render form fields or show URL; Accept / Decline / Cancel
- [ ] Build approval UI components:
  - Command preview card with syntax highlighting
  - Diff viewer (doesn't need to be fancy — unified diff with red/green lines is fine)
  - Form renderer for elicitation schemas
- [ ] Approval notifications: badge / local push notification when an approval is waiting
- [ ] Handle approval timeout: what happens if the user doesn't respond? Show a persistent indicator.
- [ ] Test: trigger each approval type via a crafted prompt and verify the flow

### Exit criteria
- All 4 approval types render correctly and the response reaches the server
- Approvals are visually prominent and cannot be accidentally missed
- Local notification fires when app is backgrounded and an approval arrives

### Tricky bits to watch
- **Server requests vs notifications** — approval requests have an `id` and MUST get a response. If the app crashes or disconnects before responding, the server is stuck. Design for this: on reconnect, re-check for pending approvals.
- **Diff rendering on small screens** — keep it simple. Filename + unified diff. Allow horizontal scroll. Don't try to build a full code review UI.

---

## M4 — Project & session management (Week 10–11)

**Goal:** Multi-project, multi-session UI. The "chat rooms" mental model.

### Tasks
- [ ] Local data model: `Host`, `Project` (host + path), `ThreadSummary` (cached metadata)
- [ ] Persist to SQLite: hosts, projects, thread cache (metadata + last N items per thread)
- [ ] UI screens:
  - **Hosts list**: add/edit/remove SSH hosts
  - **Projects list** (per host): add/edit/remove directories
  - **Threads list** (per project): shows threads from `thread/list`, with local cache
  - **Chat screen**: the M2 chat + M3 approvals, scoped to a thread
- [ ] Session switching: tap a different thread → pause current, resume target
- [ ] Thread operations: create new, archive, fork (if supported)
- [ ] SSH key management: import key from file, generate key pair, store securely

### Exit criteria
- Can manage multiple hosts, each with multiple projects, each with multiple threads
- Switching threads is fast (cached metadata, lazy-load full history)
- Adding a new host + project is straightforward

---

## M5 — Reconnection & offline resilience (Week 12–14)

**Goal:** The app survives network drops, backgrounding, and phone sleep gracefully. This is the "outdoors survival" layer.

### Tasks
- [ ] **Connection state machine**: Connected → Disconnecting → Disconnected → Reconnecting → Connected
  - Show connection status in UI (subtle indicator, not a blocking modal)
- [ ] **Auto-reconnect**: on SSH drop, retry with exponential backoff (1s, 2s, 4s, 8s, cap at 30s)
- [ ] **State resync on reconnect**:
  - Re-initialize handshake
  - `thread/list` to refresh thread state
  - Resume current thread; detect if a turn was in-flight
  - Check for pending approvals
- [ ] **Local cache**: write thread items to SQLite as they arrive
  - On reconnect, show cached history immediately, then sync deltas
  - Mark cached-but-unsynced items visually
- [ ] **OS backgrounding**:
  - iOS: request background execution time for pending approvals
  - Android: foreground service for active sessions (with notification)
  - Graceful pause/resume of the JSONL stream
- [ ] **Remote-supervised mode** (optional for M5, can defer):
  - Start app-server in tmux/systemd on the remote host
  - Reconnect to existing process instead of starting a new one
  - Detect if app-server is already running

### Exit criteria
- Kill WiFi mid-conversation → app reconnects and resumes without data loss
- Lock phone for 5 minutes → unlock → app resumes within seconds
- Cached threads are viewable offline (read-only)

### Tricky bits to watch
- **Reconnect to in-flight turn** — if the agent was mid-response when SSH dropped, you've lost those deltas. Options: (a) accept the gap and show "[reconnected — some output may be missing]", (b) re-read thread history from server on resume. Option (b) is cleaner if `thread/resume` returns full history.
- **Duplicate messages on resync** — need item IDs to deduplicate. The protocol uses UUIDs for turns and items.

---

## M6 — Rich item rendering & polish (Week 15–17)

**Goal:** Render all item types properly. Make it feel like a real product.

### Tasks
- [ ] Render all `ThreadItem` variants:
  - `CommandExecution`: show command, exit code, stdout/stderr (collapsible)
  - `FileChange`: syntax-highlighted diff viewer
  - `WebSearch`: show query + results summary
  - `Reasoning`: collapsible "thinking" section
  - `McpToolCall` / `DynamicToolCall`: show tool name + args + result
  - `CollabAgentToolCall`: show sub-agent activity
- [ ] Code rendering: syntax highlighting for code blocks in agent messages
- [ ] Context attachment: "attach file" flow (browse remote files, add to context)
- [ ] Settings screen: permission mode defaults, notification preferences, theme
- [ ] Performance: virtualized list for long conversations, image lazy-loading
- [ ] Accessibility: screen reader labels, dynamic text sizing

### Exit criteria
- Every item type the server can send renders meaningfully (not just raw JSON)
- Conversations with 500+ items scroll smoothly
- App feels polished enough for daily use

---

## M7 — Job mode & notifications (Week 18–19)

**Goal:** "Fire and forget" tasks + push notifications for approvals. The full "walking outdoors" experience.

### Tasks
- [ ] Job mode: "Run as job" button that launches `codex exec` on the server
  - Job runs detached (survives SSH disconnect)
  - Store job ID, poll for status on reconnect
  - Display job result (success/failure + logs) when done
- [ ] Push notifications (optional, requires a relay):
  - Lightweight relay service OR local polling via periodic SSH check
  - Notify on: approval waiting, job completed, turn failed
- [ ] Notification actions: "Approve" / "Reject" directly from notification (Android)

### Exit criteria
- Can start a long-running task, close the app, and see the result later
- Approval notifications arrive within 30 seconds of the server requesting one

---

## M8 — Hardening & release prep (Week 20–22)

- [ ] Security audit: SSH key storage, no plaintext credentials, certificate validation
- [ ] Error handling pass: every failure mode shows a user-friendly message
- [ ] Crash reporting & analytics (opt-in)
- [ ] Version negotiation: query server capabilities on connect, disable unsupported features
- [ ] App store metadata, screenshots, onboarding flow
- [ ] Beta testing with real Codex App Server instances

---

## Dependency graph

```
M0 (protocol types)
 └→ M1 (SSH + handshake)
     └→ M2 (chat)
         ├→ M3 (approvals)      ← can parallel with M4
         ├→ M4 (project mgmt)   ← can parallel with M3
         │   └→ M5 (reconnection)
         │       └→ M7 (job mode)
         └→ M6 (rich rendering) ← can start after M3
             └→ M8 (hardening)
```

M3 and M4 are parallelizable. M6 can start once M3 is done (needs approval UI as foundation). M5 and M7 are sequential (job mode builds on reconnection).

---

## Risk registry

| Risk | Impact | Mitigation |
|---|---|---|
| Codex App Server protocol changes | High — breaks everything | Pin to schema version; generate types from JSON Schema; version-negotiate on connect |
| SSH libraries lack stdin/stdout channel streaming | High — architecture blocked | Spike the SSH library choice in M0, not M1. Verify channel exec + streaming works before committing. |
| Mobile OS kills background SSH connections | Medium — breaks reconnection | Accept it; design for fast reconnect, not "keep alive forever." Use OS-appropriate background modes. |
| Diff rendering performance on large changesets | Low — ugly but functional | Truncate large diffs with "show full diff" button. Don't try to render 10k-line diffs. |
| Auth flow (ChatGPT OAuth) from mobile is brittle | Medium — blocks non-API-key users | Ship M1-M5 with API key auth only. Add OAuth in M6+ once core is stable. |
