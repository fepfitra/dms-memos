# Memos

Bar widget for [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) that reads a
[Memos](https://github.com/usememos/memos) server: memo count (or the latest memo text) in the pill,
recent memos in the popout. Click a memo to copy it, the header icon to open the web UI.

## Install

```bash
git clone https://github.com/fitrafep/dms-memos ~/.config/DankMaterialShell/plugins/dms-memos
```

Then Settings → Plugins → Scan for Plugins → enable **Memos**, add it to the bar, `dms restart`.

## Settings

| Key | Meaning |
|---|---|
| Server URL | Base URL, e.g. `https://memos.example.com` |
| Access token | Memos → Settings → Access tokens |
| Refresh interval | Minutes between polls |
| Memos to show | 1-50, also caps blurbs in the popout |
| Show latest memo text in the bar | Off shows the count |

## Notes

- Uses REST `GET /api/memos?pageSize=N` (the old `/api/v1/memos` was removed upstream) via `curl`.
- The token is passed as a curl argv element, so it is visible to processes running as the same
  user. Fine for a desktop session; swap for a stdin config file if you share the account.

MIT.
