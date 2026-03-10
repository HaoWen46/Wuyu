# Mobile SSH Control App for Agentic CLIs

**Project name:** 无域 (Wuyu)

“无” means *without* or *unconstrained*.  
“域” means *domain, place, or environment*.

The name reflects the goal of the app: controlling coding agents and remote machines **from anywhere**, without being tied to a specific device, terminal, or location.

## What agentic CLIs look like right now

Agentic coding CLIs in 2025–2026 have converged on the same basic shape: a **local (or remote) “harness”** runs the agent loop, executes tools (shell, file edits, etc.), manages session history, and streams a rich event timeline that UIs render.

In the Codex world, **the harness is explicitly treated as a reusable core** that powers multiple “surfaces” (web, CLI, IDE extension, desktop app). OpenAI’s February 4, 2026 engineering post describes Codex as existing across the web app, CLI, IDE extension, and a macOS app, all “powered by the same Codex harness,” and names the “critical link” as the **Codex App Server**—a bidirectional JSON‑RPC API.

That matters for your idea because it means you do **not** need to screen-scrape a terminal or reinvent a protocol just to get a chat UI. The “backend” you want already exists as a stable-ish integration surface, and it was designed to support rich interactions like streaming progress, emitting diffs, and pausing for approvals.

Claude Code has ended up in a similar place, but with a different distribution approach:

- It supports **Local**, **Remote (cloud)**, and **SSH** environments from its Desktop app UI—explicitly stating that SSH sessions run on “a remote machine you connect to over SSH,” and that Claude Code must be installed on that remote machine.
- It also has “Remote Control,” which lets you continue a session from phone/browser while the agent keeps running locally. It shows a session URL / QR code, syncs conversation across devices, and can reconnect after interruptions.

The key lesson across both ecosystems: the winning architecture is **thin clients + a structured event protocol + strong session persistence**; not “phone does the work.”

## How people are doing remote control today

There are basically three patterns in the wild (and the first two are the ones you should care about).

### Vendor-relayed remote control with no inbound ports

Claude Code Remote Control is the cleanest example of this pattern. The docs emphasize:

- your local process makes **outbound HTTPS requests only** and “never opens inbound ports,”
- the session registers and polls, and the server routes messages between mobile/web and the local session over a streaming connection,
- credentials are **short-lived** and scoped.

This solves the hardest “walking outdoors” problem: your phone doesn’t need direct routability to your machine. But it’s also vendor-dependent and not your design goal (you explicitly want SSH control of a host you own).

### Self-hosted controller (web UI) + VPN/tunnel

The Codex community has been building wrappers that run a local server and expose it via something like Tailscale. One very recent example is a Reddit showcase (“Farfield”), which states it built a TS SDK + web UI by interfacing with Codex’s IPC/protocol, then making it externally visible (e.g., via Tailscale) so you can use it from your phone, and specifically calls out the “AFK waiting for approval” pain.

Farfield’s README describes:

- a “thread browser grouped by project,” chat UI controls, live monitoring/interrupts,
- a backend server defaulting to localhost, and guidance to expose it via Tailscale HTTPS proxying.

This pattern works, but it violates one of your core preferences: **you don’t want the host to “be running a server”** (even if it’s bound to localhost) and you don’t want to manage exposure/HTTPS plumbing unless necessary.

### Pure SSH “terminal driving” (tmux + TUI)

This is the old-school “just SSH in and run the CLI” approach. It’s simple, but it’s exactly what you said you don’t want (too much action surface; not chat-native; painful approvals/diffs; terrible UX on a phone).

So: the modern direction is **structured protocol over a safe transport**. And for Codex specifically, OpenAI is telling you the protocol to use.

## What makes your app uniquely hard

Your requirements combine several constraints that fight each other:

You want:

- **SSH to your own host** (no always-on agent server exposed to the internet).
- A **chat room style UI** with directory-based “rooms,” plus a tiny amount of file management.
- Multiple “sessions” you can toggle between.
- The agent to use **server compute**, not the phone.
- Resilience to mobile conditions: flaky network, backgrounding, walking around. (This is the “real” requirement.)

The pain points you’re going to hit immediately if you do this naively:

Authentication
Codex supports both API key auth and “ChatGPT managed” auth. In the App Server protocol, ChatGPT login returns an auth URL with a redirect to `http://localhost:<port>/auth/callback`, with the App Server hosting the local callback.
That’s a problem when initiating login from a phone unless you do local port-forwarding tricks or rely on API keys.

Approvals and “stuck waiting”
Your UI must handle approvals as first-class. Codex App Server defines explicit approval request flows for command execution and file changes, including the message ordering (`item/started`, requestApproval, client decision, etc.) and multiple decision types (`accept`, `acceptForSession`, etc.).

Session persistence vs “no daemon”
A chat UI implies you can leave and come back. OpenAI’s App Server design includes thread lifecycle + persistence (create/resume/fork/archive) so clients can reconnect and render a consistent timeline.
But if you run App Server only as a child process tied to one SSH connection, then when the SSH socket dies your process likely dies too—so in-flight work may stop unless you add a persistence strategy.

Mobile backpressure and streaming
App Server uses bounded queues and can reject requests with a retryable overload error (`-32001`) and recommends exponential backoff.
Mobile networks + backgrounding means you need to treat streaming as lossy and reconnectable, and your client must be robust to bursts and partial order.

The upshot: your app isn’t “an SSH client with a pretty UI.” It’s a **stateful, event-driven client** for an agent protocol—and it needs an opinionated session supervisor story.

## Architecture that actually fits your goals

You basically have two viable architectures. One is a quick prototype. One is the “this could be a real product” path.

### The recommended core: Codex App Server over SSH stdio

OpenAI’s February 4, 2026 post is extremely direct about this: the App Server is a long-lived process hosting Codex core threads and exposing them via a bidirectional JSON-RPC-like protocol, where a single client request can emit many event updates, and the server can initiate requests for approvals and pause until the client responds.

It also explicitly states that across client types “the transport is JSON-RPC over stdio (JSONL),” and that partners have implemented clients in languages including Swift and Kotlin (which is basically your mobile stack).

That is your golden path:

- Mobile app opens an SSH connection.
- Mobile app starts `codex app-server` as a remote process.
- Mobile app speaks JSONL over the SSH channel’s stdin/stdout.
- Mobile app renders Thread/Turn/Item events into a chat UI.

This immediately gives you:

- thread listing, start/resume/fork semantics (session management),
- streaming partial outputs (“delta” events),
- explicit approvals,
- structured tool events (commands, diffs),
- a stable-ish schema you can generate.

Also: the App Server supports generating TypeScript definitions or JSON Schema bundles from the server version you’re running, which is a practical way to match the protocol to the remote binary you’re controlling.

### The mobile UI model: directories as “projects,” threads as “rooms”

Your mental model (“choose directory; each directory has its own agent session”) maps cleanly onto:

- **Project** = `(host, repoPath)` (your app-level grouping)
- **Room** = a Codex **thread**
- **Message stream** = ordered **items** (user text, agent message, tool executions, diffs, approvals, etc.)

OpenAI describes thread lifecycle and persistence as part of what the harness provides, including resuming/forking/archiving and persisting event history so clients can reconnect.
And the App Server protocol exposes “Thread / Turn / Item” as the core primitives, with item lifecycle events like `item/started`, optional streaming deltas, and `item/completed`.

So your app can literally implement:

- a left sidebar “Projects” (directories),
- inside each: “Rooms” (threads),
- main view: chat transcript (items).

This is also exactly what community wrappers are building (e.g., Farfield’s “thread browser grouped by project”).

### The missing piece: staying alive when your phone drops

You said “the host doesn’t actually run the CLI server” and you want to toggle sessions without requiring anything pre-running. That’s realistic for *interactive use while connected*. It’s not realistic for *long-running autonomous work while disconnected* unless you introduce *some* kind of persistence mechanism.

You have three options; each is a conscious trade:

Ephemeral interactive mode

- App Server runs only while SSH is connected.
- Great UX when online; simplest implementation.
- If your phone drops, your running turn may die.
This is acceptable for “quick steering while walking,” but not for “start a 20‑minute refactor and walk away.”

Remote-supervised mode (still “no public server”)

- Start App Server in a supervisor like `tmux` or a user service so it survives SSH disconnects.
- Reattach by starting a **new** App Server and resuming persisted threads, or by keeping a local-only listener and port-forwarding.
- This is closer to how OpenAI describes hosted web sessions: state lives server-side so work continues if the client disappears.
This is the “real remote dev” option, but it forces you to decide how to reconnect to a running process safely.

Job queue mode for “walk away” tasks
OpenAI explicitly positions “Codex Exec” as a non-interactive mode for one-off tasks/CI that runs to completion, streams structured output for logs, and exits with a success/failure signal.
If you support a “Run as job” button, you can:

- launch a job on the server,
- store logs + final result,
- let the phone reconnect later and read status/results.

This matches your outdoors use case best, because it doesn’t require keeping a fragile interactive pipe open. But it’s less “chatty,” and approvals need an opinion (either disallow risky actions or require the job to pause and wait).

A real product usually supports **both**:

- interactive “drive it live,” and
- “fire-and-forget job” for long tasks.

## UI, session switching, and “limited actions” design

### The default screen: chat + explicit approvals

Codex App Server is built for this. It supports:

- streaming progress via notifications after `turn/start`, including “delta” updates, tool progress, etc.
- server-initiated approval requests and pausing until the client responds (OpenAI calls this out explicitly).
- detailed approval payload shapes and decision options.

So your chat UI should treat approvals as “system messages” that cannot be ignored:

- “Approve command execution?” with a preview and a single tap to accept/decline.
- “Approve file changes?” with a diff viewer and accept/decline.

This solves the “AFK got stuck waiting for approval” pain that community projects are explicitly targeting.

### Directory selection that doesn’t turn into a file manager app

Since you want limited actions, don’t build a full remote IDE on a 6-inch screen.

A good structure is:

- Projects list: mostly user-curated directories (“Add project” = paste path, or browse via a minimal picker).
- “Attach context” flow:
  - allow adding a file to context by selecting it (SFTP browse or a server-side `find` run via a command tool),
  - optionally allow uploading a small file/snippet (for patches, config, or notes),
  - everything else should be driven by the agent.

Claude Code’s Desktop UI describes a similar philosophy: the prompt box supports @mentioning files and attaching files, and permission modes determine how autonomous the agent is.
That’s a good mental model for your “limited actions” requirement.

### Session switching should be instant and safe

You want “toggle between sessions” like chat rooms.

Codex’s App Server API surface is explicitly thread-based and includes:

- `thread/start`, `thread/resume`, `thread/fork`, `thread/list`, plus archiving, naming, etc.
So your UI can:
- show a thread list filtered by directory (`cwd` concept),
- allow switching between loaded threads and background threads.

To make switching feel instant on bad networks, you’ll want local caching of:

- thread metadata,
- the last N items,
- last known “turn status.”

This is aligned with OpenAI’s rationale that clients should be able to reconnect and catch up from persisted history rather than rebuilding state.

### Image group for quick grounding

## Security and reliability choices you should bake in early

### Minimize blast radius via permission modes and sandbox defaults

Both ecosystems emphasize permissioning:

- Codex’s agent loop repeatedly alternates between model inference and tool calls that can modify the local environment, meaning the agent’s “output” is often file edits and command execution—not just text.
- Codex App Server’s approval mechanisms are explicit and multi-step, and can even include “additional permissions” requests when experimental APIs are enabled.
- Claude Code’s Desktop app documents multiple permission modes (ask permissions, auto accept edits, etc.).

For an outdoors mobile controller, the safest default is:

- “Ask” mode for commands,
- auto-accept *nothing* unless the user explicitly enables it per project,
- aggressively restrict networking unless needed.

(You don’t want to approve a destructive `terraform destroy` while crossing the street.)

### Authentication ergonomics can make or break the product

Codex App Server supports:

- API key login (`account/login/start` with `type: "apiKey"`),
- ChatGPT managed login (`type: "chatgpt"`) that returns an auth URL with a localhost callback.

From a phone, ChatGPT login is awkward unless you implement an in-app web view plus SSH port-forwarding so `localhost:<port>` routes back to the remote server process. This is solvable, but it’s engineering-heavy and brittle on mobile OS backgrounding.

So your product decision is:

- either require API keys for v1 (fastest),
- or invest early in “ChatGPT login on a remote host from a phone” as a marquee feature (harder, but very differentiated).

### Treat the SSH connection as an unreliable transport

Codex App Server documents overload behavior and tells clients to retry with backoff on a specific overload error.
Claude Code Remote Control documents reconnection behavior as a core promise (session reconnects after sleep/network drop).

You won’t get Claude’s reconnection UX “for free” with SSH. If you want that vibe, you must design for:

- idempotent client requests (or request IDs that the server can tolerate),
- resync after reconnect (re-read thread state; detect in-flight turn),
- OS backgrounding (pause reading; resume; avoid flooding).

### Version skew is reality

OpenAI explicitly says clients often pin to tested server binaries, and that the App Server surface is designed to be backward compatible so older clients can talk to newer servers safely.
But you should still plan for:

- server updates on the host,
- schema changes,
- feature gating (stable vs experimental API opt-in).

A pragmatic approach is:

- on connect: query server version and capabilities,
- generate or bundle schemas per target version when feasible,
- soft-disable UI affordances when unsupported.

### Reality check: the ecosystem is moving weekly

As of today (March 10, 2026), the upstream tools you’re targeting are shipping constantly:

- Codex’s open-source repo shows a fresh release `0.113.0` on March 10, 2026, including App Server improvements like streaming stdin/stdout/stderr plus TTY/PTY support in `command/exec`, and new permission tooling.
- Claude Code also released `v2.1.72` on March 10, 2026, with fixes and improvements explicitly mentioning SSH usability and Remote Control behavior.

That means your app architecture must assume:

- protocols evolve,
- users will update the agent binary on the remote host,
- you need graceful degradation and good telemetry/logging.

## Summary design blueprint

If you want the most direct path to “coding from your phone while walking,” without making the phone do compute and without requiring an always-on exposed server, the cleanest plan is:

Build a mobile client that speaks **Codex App Server over JSONL/stdin/stdout through SSH**, using Codex threads as sessions and a directory→project grouping in the UI. This aligns with OpenAI’s official direction that the App Server is the first-class integration surface for full-fidelity UIs, and it gives you approvals/diffs/streaming as native primitives instead of hacks.

Then add two optional “outdoors survival” layers:

- an execution mode that can survive disconnects (job mode / resumable threads),
- a notification strategy to avoid “stuck waiting for approval,” which is exactly the community pain point driving remote controllers.

