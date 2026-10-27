# dsh-bar (host plugin)

Host half of [DSH Bar](https://github.com/reg4916/dsh-bar): exposes live DeepSeek Harness session state to the macOS menu bar app.

## What it does

- writes `$DSH_HOME/dsh-bar/runtime.json` (`0700` directory, `0600` file) with the loopback origin, a 24-byte Bearer token, the Host pid and the schema version;
- mounts `/dsh-bar` on the Host's existing web server (`ctx.webServer.register({ kind: 'prefix' })`);
- folds `session/event`, `agent/status` and `agent/error` into a state document (idle / thinking / tool / approval / done / error);
- holds `approval/request` and `user-questions/request` waterfalls so the menu bar can answer them; child sessions are skipped so background subagents never colour the icon;
- serves a browser half that opens the exact session via `ctx.uiWorkspace.openSession` when the app asks to focus it;
- never reads message bodies: only titles, tool names and usage counters.

## Endpoints

| Method + path | Auth | Purpose |
|---|---|---|
| `GET /dsh-bar/status` | Bearer | full state document |
| `GET /dsh-bar/health` | Bearer | liveness without session data |
| `POST /dsh-bar/approve` | Bearer | `{id, outcome: "allowed-once" \\| "rejected"}` |
| `POST /dsh-bar/answer` | Bearer | `{id, answers}` |
| `POST /dsh-bar/stop` | Bearer | `{sessionId}` — cancel the running turn |
| `POST /dsh-bar/focus` | Bearer | `{sessionId}` — ask the page half to open a session |
| `GET /dsh-bar/pending-focus` | same-origin / bridge trust | focus wish for the page half |

The token is reused across Host restarts, so an already-running menu bar app keeps working. Native clients must re-read `runtime.json` before each request: Desktop starts the Host with `--port 0`, so the port changes on every restart. `DSH_BAR_RUNTIME_FILE` overrides the path (tests, multiple homes).

## Security

- loopback only (`127.0.0.1`/`::1`), Bearer token on every native route;
- page routes use same-origin trust plus a script-only header, because the Desktop shell strips `Origin`/`cookie`/`sec-fetch-site` when forwarding `dsh-app://app` requests;
- no message text ever crosses the bridge.

## Install

```bash
cd ~/.dsh/profiles/desktop
npx pnpm add dsh-bar
```

Add `"dsh-bar"` to `dsh.profile.bundles`, then reload DSH. The native app downloads from the [latest release](https://github.com/reg4916/dsh-bar/releases/latest).

Approvals only reach the bar when the profile uses the `read-only` or `workspace-write` preset (`danger-full-access` is `approval: never`).

## Tests

```bash
npm test   # 13 node:test cases: state fold, approvals, questions, stop
```

MIT
