# .notes/

This folder contains working notes accumulated during development — protocol quirks, design decisions, tricky bugs, and gotchas discovered along the way.

It is **not** a changelog or project overview (see `PROJECT_SPEC.md`, `PLAN.md`, and `CLAUDE.md` for those). It is a living knowledge base meant to make future development smoother by recording hard-won lessons in context.

## Structure

Each file covers one topic or concern area. Files are named to be self-describing:

| File | Contents |
|------|----------|
| `protocol-quirks.md` | Edge cases and surprises in the Codex App Server wire protocol |
| `ssh-transport.md` | Notes on SSH library choices, channel exec streaming, lifecycle management |
| `testing-patterns.md` | Patterns for testing async transports, codec edge cases, integration stubs |

Add a new file when a topic grows beyond a few bullet points, or when something took more than 30 minutes to figure out.

## Audience

Future developers (human or AI) picking up this codebase mid-flight.
Write notes as if explaining to someone who has read `CLAUDE.md` but not the commit history.
