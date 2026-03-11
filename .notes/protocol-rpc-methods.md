# Codex App Server — RPC Methods & Protocol Details

Source: https://github.com/openai/codex/tree/main/codex-rs/app-server-protocol

## Launch

```
codex app-server                   # stdio mode (SSH-safe)
codex app-server --listen ws://... # WebSocket (experimental, not for production)
LOG_FORMAT=json                    # structured logs to stderr (doesn't pollute JSONL stdout)
```

## Wire format

JSONL, one JSON object per `\n`. **No `"jsonrpc":"2.0"` field** on the wire.
Classified by field presence:

| Shape           | Fields              | Direction        |
|-----------------|---------------------|------------------|
| Request         | `method` + `id`     | Client → Server  |
| Notification    | `method`, no `id`   | Client/Server    |
| Response        | `id` + `result`     | Server → Client  |
| Error Response  | `id` + `error`      | Server → Client  |

`RequestId` = `string | i64`.

## Initialization handshake

Must complete before any other RPC. Any other request before this → "Not initialized" error.

1. Client sends `initialize` request:
```json
{
  "method": "initialize",
  "id": 0,
  "params": {
    "clientInfo": {"name": "wuyu", "title": "Wuyu", "version": "0.1.0"},
    "capabilities": {
      "experimentalApi": true,
      "optOutNotificationMethods": ["item/agentMessage/delta"]
    }
  }
}
```

2. Server responds with `{"id": 0, "result": {...}}` (userAgent string).

3. Client sends `initialized` notification (no `id`).

**`optOutNotificationMethods`**: suppress specific notification methods (exact match, no wildcards).
Useful to reduce noise if you don't need streaming deltas (e.g., for background sessions).

## All client → server requests

### Thread
- `thread/start` → `{"thread": {"id": "thr_123"}}`
- `thread/resume` → re-subscribe to events for existing thread
- `thread/fork` → copy thread at a turn
- `thread/list` → list all threads
- `thread/read` → get full thread state (use on reconnect to reconstruct missed events)
- `thread/archive` / `thread/unarchive`
- `thread/compact/start` → context compaction
- `thread/metadata/update`
- `thread/name/set`
- `thread/rollback` → revert to a previous turn

### Turn
- `turn/start` params:
  ```json
  {
    "threadId": "thr_123",
    "input": [{"type": "text", "text": "Run the tests"}],
    "model": "gpt-5.1-codex",
    "cwd": "/repo",
    "approvalPolicy": "unlessTrusted"
  }
  ```
  Input types: `text`, `image` (url), `localImage` (path), `skill`, `mention`.
  Per-turn overrides: `model`, `effort`, `cwd`, `sandboxPolicy`, `approvalPolicy`, `personality`, `outputSchema`.

- `turn/steer` → add input to in-flight turn; `expectedTurnId` for optimistic concurrency
- `turn/interrupt` → cancel in-flight turn

### Config / Account / Models / Skills / MCP
- `config/read`, `config/value/write`, `config/batchWrite`, `configRequirements/read`
- `account/read`, `account/login/start`, `account/login/cancel`, `account/logout`, `account/rateLimits/read`
- `model/list`
- `skills/list`, `skills/config/write`
- `app/list`, `plugin/list`
- `mcpServer/oauth/login`, `mcpServerStatus/list`, `config/mcpServer/reload`
- `command/exec` (with `/write`, `/resize`, `/terminate`) — shell exec for config tasks
- `review/start`

### Experimental (needs `experimentalApi: true` in capabilities)
- `fuzzyFileSearch/session/*`
- `thread/realtime/*`
- `windowsSandbox/setupStart`

## Server → client notifications

### Thread lifecycle
- `thread/started` — `{threadId}`
- `thread/archived` / `thread/unarchived`
- `thread/closed` — `{threadId}`
- `thread/status/changed` — statuses: `notLoaded`, `idle`, `systemError`, `active`
  - `active` has a `waitingOnApproval` flag (approval is pending)
- `thread/name/updated` — `{threadId, name}`

### Turn lifecycle
- `turn/started` — `{threadId, turn: {id, status, items}}`
- `turn/completed` — `{threadId, turn: {id, status, error}}` — status: `completed | interrupted | failed`
  - `codexErrorInfo` on failure
- `turn/plan/updated` — experimental
- `turn/diff/updated` — experimental
- `model/rerouted` — server switched models (e.g., fallback)

### Item lifecycle (streaming)
- `item/started` — `{threadId, turnId, item: {...}}`
- `item/completed` — `{threadId, turnId, item: {...}}`
- `item/agentMessage/delta` — `{threadId, turnId, itemId, delta: str}`
- `item/commandExecution/outputDelta` — `{threadId, turnId, itemId, stream, delta}`
- `item/fileChange/outputDelta` — `{threadId, turnId, itemId, delta}`
- `item/plan/delta` — experimental

### Approval requests (server-initiated, have `id`, MUST respond)
- `item/commandExecution/requestApproval` — show command + cwd + reason
- `item/fileChange/requestApproval` — show file path + diff
- `item/tool/requestUserInput` — experimental

Approval response decisions: `accept`, `acceptForSession`, `decline`, `cancel`.

After responding: `serverRequest/resolved` notification confirms, then `item/completed`.

### Other
- `skills/changed`, `app/list/updated`
- `account/login/completed`, `account/updated`, `account/rateLimits/updated`
- `mcpServer/oauthLogin/completed`
- `error` — `{message, code}`

## ThreadItem variants

`UserMessage`, `AgentMessage` (phase: `commentary | final_answer`), `Reasoning`,
`WebSearch`, `CommandExecution` (command, cwd, process_id, aggregated_output, exit_code, duration_ms),
`FileChange`, `McpToolCall`, `DynamicToolCall` (exp.), `ImageView`, `ImageGeneration`,
`CollabAgentToolCall`, `ContextCompaction`, `EnteredReviewMode`, `ExitedReviewMode`

## Backpressure

Error code `-32001`: "Server overloaded; retry later."
Only on WebSocket. Stdio waits indefinitely. Use exponential backoff with jitter.

## Reconnection pattern

- **Stdio (SSH)**: Server exits when SSH disconnects.
  - Reconnect = new SSH → new `initialize` handshake → `thread/resume`
  - `thread/resume` re-subscribes to new events only. Does NOT replay missed events.
  - Use `thread/read` to get full current state after reconnect.
- **WebSocket**: Supports multiple clients, pre-launchable in tmux/systemd. Same reconnect flow.
