# Wuyu — Implementation Plan & Milestones

## What this app actually does

Every other app on the market — Farfield, Happy Coder, claude remote-control — requires the
user to manually SSH into the host, navigate to a project directory, and start the agent CLI
before the mobile app can do anything. That friction kills the "code from anywhere" promise.

**Wuyu's differentiator: it owns the full session lifecycle.**

```
(Pick or pair host) → (Pick or create project) → App launches agent → Chat
```

No manual "cd to the right folder and run codex" step. The app handles it.
The user's only jobs are: (1) choose where, (2) say what.

---

## Guiding principles

1. **Own the bootstrap.** The app starts the agent in the right place. Users never touch a terminal.
2. **Communication first, not a terminal.** The primary loop is: type → agent responds → approve or not. File ops exist only to support this loop.
3. **SSH is the only transport.** No relay servers, no cloud middlemen, no npm/npx setup steps on the server. Raw SSH channel exec.
4. **Vertical slices.** Each milestone produces something testable end-to-end.
5. **Mobile realities from the start.** Reconnection, backgrounding, and local caching are in from day one — not bolted on.
6. **Leave room for Claude Code.** Codex is primary (has a proper app-server protocol). Claude Code has no equivalent yet — but the architecture shouldn't make adding it hard later.

---

## Tech stack

| Concern | Choice | Rationale |
|---|---|---|
| Mobile framework | **Flutter** | One codebase for iOS + Android; idiomatic async streams for JSONL; proven SSH via dartssh2 |
| SSH library | **dartssh2** | Pure Dart, `SSHClient.execute()` → `SSHSession.stdout: Stream<Uint8List>` |
| State management | **Riverpod** | Fine-grained reactive state, async streams, testable |
| Local persistence | **drift (SQLite)** | Host configs, project list, cached thread items |
| JSON | **dart:convert + freezed** | `jsonDecode` + freezed unions for protocol discriminated types |
| Secure storage | **flutter_secure_storage** | Keychain (iOS) / Keystore (Android) for SSH keys |
| Biometrics | **local_auth** | Face ID / Touch ID for key unlock |

**Core JSONL pipeline (Dart):**
```dart
final session = await sshClient.execute('codex app-server');

session.stdout
    .cast<List<int>>()
    .transform(utf8.decoder)
    .transform(const LineSplitter())
    .listen((line) => dispatch(jsonDecode(line)));

session.stdin.add(utf8.encode('${jsonEncode(msg)}\n'));
```

**Bootstrapping new projects in-band** via Codex `command/exec` RPC:
```
SSH exec: codex app-server          ← just this one exec, no manual cd
→ initialize handshake
→ command/exec {command: ["mkdir", "-p", "~/projects/foo"]}
→ command/exec {command: ["git", "init"], cwd: "~/projects/foo"}
→ thread/start                      ← now in the right directory
```
After `codex app-server` is running, `command/exec` handles all setup — no second SSH channel needed.

---

## Prior work (Python protocol reference)

`src/wuyu/` — Python 3.12 prototype used to explore and validate the protocol design.
81 tests covering JSONL codec, Transport ABC, SshTransport, Session (request/response correlation).
Serves as a living specification for the Dart/Flutter implementation. Not the production app.

---

## Session lifecycle (the core flow)

```
1. Host pairing
   └─ Scan QR code from a desktop helper, or enter host/user/key manually
   └─ Host key TOFU: on first connect, show fingerprint, confirm, remember it

2. Project selection (within the app)
   └─ List home dir contents via SSH exec (ls -la ~)
   └─ Pick existing directory
   └─ OR: create new → name it → app runs mkdir + optional git init

3. Agent launch (app does this, not the user)
   └─ SSH exec: codex app-server
   └─ initialize handshake
   └─ initialized notification

4. Chat
   └─ thread/start (with cwd = chosen project dir)
   └─ Send messages → stream agent responses → approve or decline
```

---

## M0 — Flutter scaffold + SSH smoke test

**Goal:** Buildable Flutter app. Open SSH connection, exec `codex app-server`, complete `initialize` handshake, print `userAgent`. Nothing more.

### Tasks
- [ ] `flutter create wuyu_app --org app.wuyu`
- [ ] Add deps: `dartssh2`, `riverpod`, `freezed`, `json_serializable`, `drift`, `flutter_secure_storage`, `local_auth`
- [ ] Port JSONL codec to Dart: `encode(msg)`, `decode(line)`, field-presence discrimination
- [ ] `SshTransport` in Dart (dartssh2 channel exec)
- [ ] `Session` in Dart: request/future correlation, notification queue, approval queue
- [ ] Smoke test: initialize handshake against a mocked or real server
- [ ] CI: GitHub Actions for `flutter analyze` + `flutter test`

### Exit criteria
- Flutter app builds for iOS simulator and Android emulator
- `initialize` handshake succeeds in an automated test
- Protocol types round-trip correctly

---

## M1 — Host pairing + project bootstrap

**Goal:** From a cold start on the phone, a user can pair a host, pick or create a project, and get `codex app-server` running in that directory — without touching a terminal.

### Tasks

**Host pairing:**
- [ ] SSH host config UI: hostname, port, username, auth (password or key)
- [ ] QR code flow: desktop helper (`wuyu-pair`) prints a QR code encoding `ssh://user@host:port` + public key fingerprint; app scans it, saves the host config
- [ ] Host key TOFU: on first connect, show fingerprint, prompt "Trust this host?", persist
- [ ] SSH key management: generate Ed25519 keypair on device, store in Keychain/Keystore; export public key for server's `authorized_keys`

**Codex installation check:**
- [ ] SSH exec `which codex` (or `codex --version`) to detect installation
- [ ] If missing: show install instructions + one-tap "install now" (runs `npm install -g @openai/codex` with visible scrollable output)
- [ ] Verify after install; store detected version in host config

**Project bootstrap:**
- [ ] SSH exec `ls -la ~/` to list the home dir; display as a project picker
- [ ] "New project" flow: enter name → app runs `mkdir -p ~/projects/<name>` + optional `git init` (via SSH exec or `command/exec` after app-server starts)
- [ ] Store project configs locally (host + remote path)

**Session launch:**
- [ ] From project picker: tap a project → app SSH-execs `codex app-server`, completes handshake, opens chat screen automatically

### Exit criteria
- User can go from "just added a host" to "chat screen open" in < 5 taps with no terminal
- New project creation works (mkdir + git init) end-to-end
- Codex install detection and guided install works

---

## M2 — Thread lifecycle & basic chat

**Goal:** User can start a thread, send a message, see a streaming agent response. The core loop.

### Tasks
- [ ] `thread/start` with `cwd` = project directory
- [ ] `turn/start` with text input
- [ ] Handle streaming: `turn/started`, `turn/completed`, `item/started`, `item/completed`, `item/agentMessage/delta`
- [ ] Delta accumulation: `AgentMessageState` buffers deltas by item ID, exposes current text
- [ ] Chat screen: input at bottom, scrolling message list (user right, agent left), streaming indicator, turn status
- [ ] Thread list: `thread/list`, show existing threads for a project, tap to resume (`thread/resume`)

### Exit criteria
- Multi-turn conversation works end-to-end
- Agent responses stream character-by-character
- Existing threads are resumable from the thread list

### Tricky bits
- `thread/resume` re-subscribes to new events only. Use `thread/read` to get full state on reconnect. Don't confuse them.
- Delta accumulation must track by item ID, not just append order.

---

## M3 — Approvals & permission UI

**Goal:** All server-initiated approval requests render and respond correctly. The "approve from your phone while walking" experience.

### Tasks
- [ ] Dispatch server-initiated requests (have `id`, MUST respond):
  - `item/commandExecution/requestApproval` → command card (command, cwd, reason) → Approve / Approve for Session / Abort
  - `item/fileChange/requestApproval` → unified diff with red/green → Approve / Reject
  - `item/tool/requestUserInput` → elicitation (form or URL) → Accept / Decline / Cancel
- [ ] Pending approval tracking: `Map<id, approval>` survives navigation
- [ ] Thread status banner: "⚠ Approval waiting" when `thread/status/changed` fires with `waitingOnApproval: true`
- [ ] Local notification when app is backgrounded and approval arrives
- [ ] Timeout indicator: persistent if user doesn't respond

### Exit criteria
- All 3 approval types render and respond correctly
- `serverRequest/resolved` confirmation received after each response
- Local notification fires within 30s when backgrounded

---

## M4 — Project & session management

**Goal:** Multi-host, multi-project, multi-thread. The "chat rooms" mental model, fully realized.

### Tasks
- [ ] Drift schema: `hosts`, `projects`, `thread_cache` (last 200 items per thread)
- [ ] Hosts list screen: add / edit / remove; show connection status
- [ ] Projects list per host: add / edit / remove remote dirs
- [ ] Threads list per project: from `thread/list` + local cache, sorted by last activity
- [ ] Thread actions: archive (`thread/archive`), rollback (`thread/rollback`), fork (`thread/fork`)
- [ ] Session switching: tap a different thread → suspend current session, launch new one
- [ ] `pull_to_refresh` on thread list syncs from server

### Exit criteria
- Multiple hosts, projects, threads all manageable without leaving the app
- Thread list loads from cache instantly, syncs in background

---

## M5 — Reconnection & offline resilience

**Goal:** App survives network drops, backgrounding, and phone sleep without data loss.

### Tasks
- [ ] Connection state machine: `Connected → Disconnecting → Disconnected → Reconnecting → Connected`
- [ ] Auto-reconnect: exponential backoff (1s, 2s, 4s, 8s, cap 30s)
- [ ] State resync: re-initialize → `thread/resume` → `thread/read` for current state → check pending approvals
- [ ] Write thread items to drift as they arrive; show cached history immediately on reopen
- [ ] OS backgrounding: iOS background execution for pending approvals; Android foreground service
- [ ] "Reconnected — live from here" marker in chat when events were missed during disconnect
- [ ] Remote-supervised mode (optional): detect if app-server already running in tmux; reconnect without re-launching

### Exit criteria
- Kill WiFi mid-conversation → reconnects and resumes without data loss
- Offline threads viewable (read-only) from cache

---

## M6 — Rich item rendering & polish

**Goal:** Every item type renders meaningfully. App feels production-ready.

### Tasks
- [ ] `CommandExecution`: command, exit code, collapsible stdout/stderr
- [ ] `FileChange`: syntax-highlighted unified diff viewer
- [ ] `Reasoning`: collapsible "thinking" block
- [ ] `WebSearch`, `McpToolCall`, `CollabAgentToolCall`: compact summary cards
- [ ] Code blocks in agent messages: syntax highlighting (`flutter_highlight`)
- [ ] Settings screen: default approval policy, notifications, theme
- [ ] Virtualized list (`ListView.builder`) for 500+ item threads

---

## M7 — Job mode & notifications

**Goal:** Fire-and-forget tasks. Close the app, come back to results.

### Tasks
- [ ] "Run as job" → launch `codex exec` (detached, survives SSH disconnect)
- [ ] Store job ID; poll for status on reconnect; show result
- [ ] Push notifications for: approval waiting, job done, turn failed (relay or periodic SSH poll)
- [ ] Android: Approve/Reject directly from notification

---

## M8 — Hardening & release prep

- [ ] Security audit: key storage, no plaintext credentials, TOFU host key persistence
- [ ] Error handling pass: every failure → user-friendly message
- [ ] Version negotiation: query server capabilities on connect
- [ ] App store assets, onboarding, screenshots
- [ ] Beta with real Codex App Server instances

---

## Claude Code compatibility (future)

Claude Code has no `app-server` equivalent (as of March 2026). Current state:
- `claude -p "..." --output-format stream-json` — fire-and-forget, not interactive
- `claude --resume <session_id>` — resume previous session
- `claude remote-control` — HTTPS polling to claude.ai, terminal must stay open (not useful for Wuyu)
- No long-lived stdio JSON-RPC server exists

**Architecture hooks to leave:**
- The `AgentBackend` abstraction (behind the Session layer) should be swappable — Codex vs. something else
- The SSH exec layer that launches `codex app-server` should accept a configurable command
- `command/exec` bootstrapping is Codex-specific; Claude Code would need direct SSH exec for setup

When/if Claude Code ships a protocol interface, plugging it in should touch one file.

---

## Dependency graph

```
M0 (Flutter scaffold)
 └→ M1 (host pairing + bootstrap) ← THE differentiator
     └→ M2 (chat)
         ├→ M3 (approvals)      ← can parallel with M4
         ├→ M4 (project mgmt)   ← can parallel with M3
         │   └→ M5 (reconnection)
         │       └→ M7 (job mode)
         └→ M6 (rich rendering)
             └→ M8 (hardening)
```

---

## Risk registry

| Risk | Impact | Mitigation |
|---|---|---|
| Codex protocol changes | High | Pin schema version; all assumptions documented in `.notes/` |
| dartssh2 limitations | Medium | Spike channel exec + streaming in M0 first |
| Mobile OS kills background SSH | Medium | Design for fast reconnect; OS background modes |
| App store review of SSH tool | Low | Frame as "remote development companion," not terminal |
| Claude Code ships app-server | Low (good problem) | AgentBackend abstraction makes it easy to add |

---

## Key references

- `.notes/protocol-rpc-methods.md` — all Codex RPC methods, notifications, wire format
- `.notes/mobile-stack-decision.md` — Flutter+dartssh2 rationale
- `.notes/claude-code-remote.md` — Claude Code remote control research
- `.notes/ssh-transport.md` — SSH integration gotchas (from Python prototype)
- `src/wuyu/` — Python protocol reference implementation
- Codex RS: https://github.com/openai/codex/tree/main/codex-rs
- dartssh2: https://pub.dev/packages/dartssh2
- Flutter Server Box: https://github.com/lollipopkit/flutter_server_box
- Farfield: https://github.com/achimala/farfield
- Happy Coder: https://github.com/slopus/happy
