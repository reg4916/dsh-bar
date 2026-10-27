# DSH Bar

[![CI](https://github.com/reg4916/dsh-bar/actions/workflows/ci.yml/badge.svg)](https://github.com/reg4916/dsh-bar/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

An animated whale in the macOS menu bar for **DeepSeek Harness** — see and steer the agent without switching windows.

![DSH Bar popover](docs/popover.png)

## What it does

| State | Menu bar |
|---|---|
| Idle | still whale |
| Thinking / tool running | swimming whale + spout |
| Waiting for approval | red dot (and a count when questions are also waiting) |
| Done | short "done" flash, then idle |
| Error | stays until the next turn starts |
| DSH not running | dimmed whale, popover says why |

Left click opens the popover: session title, current step/tool, model, tokens, **Approve/Deny** for a held tool approval, **Stop** for a running turn, **Open DSH**, **Quit**. Right-click: Open DSH, Stop Current Turn, Launch at Login, Quit.

The app never blocks DSH: it polls a loopback endpoint every 0.8 s and re-reads `runtime.json` before each request (Desktop starts the Host with `--port 0`, so the port changes on every restart). The whale is drawn in code as a template image, so it follows light/dark menu bars without shipping sprites.

## Download and install (free)

Two halves, both MIT — the native app and the host plugin.

1. **Download the app** from the latest [GitHub release](https://github.com/reg4916/dsh-bar/releases/latest): `DSHBar-0.1.0-macos-universal.zip` (arm64 + x86_64).
2. Unzip and move `DSHBar.app` to `/Applications`. The bundle is **ad-hoc signed** (no paid Apple Developer ID), so on first launch right-click the app and choose **Open**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/DSHBar.app
   ```
3. **Install the host plugin into a profile** — from the plugin market, or:
   ```bash
   cd ~/.dsh/profiles/desktop
   npx pnpm add dsh-bar
   ```
   Add `"dsh-bar"` to `dsh.profile.bundles` in that profile's `package.json` and reload DSH (the plugin writes `~/.dsh/dsh-bar/runtime.json` on boot; the app picks it up within a second).

Verify the download against `SHA256SUMS` in the release. Build from source instead: `./scripts/build.sh --universal`, then `open build/DSHBar.app`.

## Architecture

- **`plugin/` — `dsh-bar` host plugin** (npm). Writes `$DSH_HOME/dsh-bar/runtime.json` (`0700`/`0600`), mounts `/dsh-bar` on the Host web server, folds session events into a small state document, holds `approval/request` and `user-questions/request` waterfalls so the menu bar can answer them, and serves a browser half that opens a session through `ctx.uiWorkspace.openSession`.
- **`app/` — native menu bar app** (Swift, AppKit). Reads `runtime.json`, polls `GET /dsh-bar/status` with a Bearer token, posts approvals/stop/focus.

Security: loopback only, Bearer token on every native route, page routes use same-origin/bridge trust instead of putting the token in page JS. Only titles, tool names and usage counters cross the bridge — never message bodies.

**Approvals note:** the shipped `danger-full-access` preset uses `approval: never`, so approvals never reach the bar. Use the `read-only` or `workspace-write` preset to see Approve/Deny. Questions are surfaced as a badge; answering them from the popover is the next step (open DSH to answer today).

## Endpoints

| Method + path | Auth | Purpose |
|---|---|---|
| `GET /dsh-bar/status` | Bearer | state document |
| `GET /dsh-bar/health` | Bearer | liveness |
| `POST /dsh-bar/approve` | Bearer | `{id, outcome: "allowed-once" \\| "rejected"}` |
| `POST /dsh-bar/answer` | Bearer | `{id, answers}` |
| `POST /dsh-bar/stop` | Bearer | `{sessionId}` |
| `POST /dsh-bar/focus` | Bearer | `{sessionId}` — ask the page half to open a session |
| `GET /dsh-bar/pending-focus` | page trust | focus wish for the page half |

## Development

```bash
cd plugin && npm test          # 13 state/approval tests
cd .. && ./scripts/build.sh    # current-arch app
./scripts/package.sh           # universal zip + plugin tgz + SHA256SUMS
```

Debug the bridge without the menu bar: `build/DSHBar.app/Contents/MacOS/DSHBar --dump-status`. Environment overrides: `DSH_BAR_RUNTIME_FILE`, `DSH_BAR_DEMO=1`.

## Roadmap

- **M1** — native shell, animated whale, popover ✅
- **M2** — host plugin, runtime.json, live state, polling ✅
- **M3** — approvals, stop, open session, launch at login ✅
- **M4** — universal binary, CI, release, npm publish ✅

## License

MIT
