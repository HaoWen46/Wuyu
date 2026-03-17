# Slash Commands in Codex App Server

## Key Finding

**Slash commands are client-side TUI shortcuts, NOT protocol features.**

The Codex CLI (`codex` binary) has a rich set of slash commands (`/compact`, `/exit`, `/clear`, etc.)
that appear when the user types `/` in the terminal composer. These are handled entirely by the
Codex TUI (`codex-rs/tui/`) and never touch the app-server protocol.

Wuyu communicates with `codex app-server`, not with the TUI. The app-server protocol has **no
slash command input type** and **no RPC to list or discover commands**.

---

## What the Protocol Does Have

Instead of slash commands, the app-server exposes dedicated RPCs for session management:

| CLI slash command | Protocol RPC | Notes |
|---|---|---|
| `/compact` | `thread/compact/start` | Streams progress via turn/item notifications; emits `contextCompaction` item |
| `/new` | `thread/start` (new) | Just start a fresh thread |
| `/resume` | `thread/resume` | Re-subscribes to events; use `thread/read` for full state |
| `/fork` | `thread/fork` | Clone current thread |
| — | `thread/rollback` | Drop N turns (no CLI equivalent in wuyu context) |
| — | `thread/archive` / `thread/unarchive` | Thread management |
| — | `turn/interrupt` | Cancel an in-progress turn |

The `turn/start` input array supports these types: `text`, `image`, `localImage`, `skill`, `mention`.
There is no `slashCommand` input type.

---

## Codex CLI Slash Commands (for reference)

These exist in the CLI TUI but are NOT part of the app-server protocol:

**Session management:** `/model`, `/personality`, `/new`, `/resume`, `/fork`, `/plan`, `/agent`
**Permissions:** `/permissions`, `/experimental`, `/sandbox-add-read-dir`, `/statusline`
**Inspection:** `/status`, `/debug-config`, `/diff`, `/ps`
**Utilities:** `/copy`, `/mention`, `/review`, `/compact`, `/mcp`, `/apps`, `/clear`, `/init`, `/feedback`, `/logout`, `/quit`/`/exit`

Custom slash commands can be created as `~/.codex/prompts/<name>.md` files. The CLI discovers
them at startup. The protocol never exposes this list.

---

## Implication for Wuyu UI

The mobile app should expose session controls as **native UI elements** (buttons, menus, gestures),
not text slash commands. For example:

- **Compact context** → button in thread action sheet → calls `thread/compact/start`
- **Interrupt turn** → cancel button in app bar (already partially in scope for M3) → calls `turn/interrupt`
- **Fork thread** → long-press thread item → calls `thread/fork`

No slash command autocomplete needed. The protocol doesn't support it and it would be misleading.

---

## Sources

- `codex-rs/tui/src/slash_command.rs` — client-side slash command enum + parsing
- `codex-rs/app-server/README.md` — protocol reference (no slash commands documented)
- Research conducted 2026-03-14
