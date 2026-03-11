# SSH Transport Notes

## asyncssh API gotchas

### `known_hosts` parameter
- `asyncssh.load_known_hosts` does NOT exist — the correct name is `asyncssh.read_known_hosts`
- For tests: pass `known_hosts=None` to skip host-key verification (never in production)
- For production: pass a path string or the result of `asyncssh.read_known_hosts("~/.ssh/known_hosts")`
- Default in SshTransport is `None` (disabled) — must be explicitly set for production use

### `create_process` encoding
- `encoding=None` means raw bytes mode — we handle encoding/decoding ourselves via the codec
- Without `encoding=None`, asyncssh returns str lines by default (UTF-8), but we need bytes for predictable control

### `process.stdin.write_eof()`
- Must call this before `process.close()` to signal clean EOF to the remote process
- Without it, the remote process may hang waiting for more input

### `asyncssh.SSHServerProcess` type hints
- The process_factory coroutine receives an `asyncssh.SSHServerProcess` which is generic
- Use `asyncssh.SSHServerProcess` with `# type: ignore[type-arg]` when no generic arg is needed

## Testing approach
- Use `asyncssh.generate_private_key("ssh-rsa")` to generate in-memory key pairs (no files needed)
- `asyncssh.import_authorized_keys(pubkey_str)` converts exported public key to authorized_keys object
- Use `port=0` in `create_server()` — OS assigns a free port, retrieve via `server.sockets[0].getsockname()[1]`
- `process_factory=handler_coro` in `create_server()` is the simplest way to handle exec sessions
  - The factory receives an `SSHServerProcess` with `.stdin`, `.stdout`, `.stderr`
  - Call `process.exit(0)` at the end of the handler

## Connection state machine
- DISCONNECTED → CONNECTING → CONNECTED (normal path)
- CONNECTED → DISCONNECTING → DISCONNECTED (clean disconnect)
- CONNECTED → DISCONNECTED (on EOF/error in receive())
