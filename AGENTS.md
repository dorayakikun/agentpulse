## Codex notify debug toggle

`scripts/codex-notify.sh` supports a debug toggle via env var.

Enable for a single run:
```bash
CODEX_NOTIFY_DEBUG=1 codex "hello"
```

Enable persistently in `~/.codex/config.toml`:
```toml
notify = ["bash", "-lc", "CODEX_NOTIFY_DEBUG=1 /path/to/scripts/codex-notify.sh"]
```

Disable:
```bash
unset CODEX_NOTIFY_DEBUG
```

Log file: `/tmp/codex-notify-debug.log`
