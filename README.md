# DSH Bar

An animated whale in the macOS menu bar for **DeepSeek Harness** — see what the agent is doing without switching windows.

> **Status: M1 (demo).** The native app renders the whale and a mock state sequence.
> The host plugin that feeds real session state, approvals and usage is M2.

## States

| State | Menu bar |
|---|---|
| Idle | still whale, gentle tail |
| Thinking / tool running | swimming whale + spout |
| Waiting for approval | red dot next to the whale |
| Done / error | state in the popover |

Click opens a popover with the session title, current step, tokens, cost, **Open DSH** and **Quit**. Right-click offers the same plus a login-item placeholder.

## Build and run

Requires macOS 13+ and the Xcode command line tools (Swift 5.9+). No paid Apple Developer account is needed: the bundle is signed ad-hoc.

```bash
./scripts/build.sh
open build/DSHBar.app
```

The app is a menu bar agent (`LSUIElement`), so it has no Dock icon and no window. Quit from the right-click menu or `pkill DSHBar`.

## Free distribution

The project is MIT-licensed and distributed for free through GitHub:

- **source**: this repository, buildable with one command;
- **prebuilt releases**: `DSHBar.app` + host plugin tarball in GitHub Releases once M4 lands;
- **no notarization** (a paid Developer ID is not required). On first launch macOS may say the app is from an unidentified developer — right-click the app and choose **Open**, or run `xattr -dr com.apple.quarantine /Applications/DSHBar.app`.

## Roadmap

- **M1** — native shell, animated whale, popover, demo sequence ✅
- **M2** — host plugin (`dsh-bar` on npm): session state stream, approvals, usage, runtime.json
- **M3** — approve/deny from the popover, open session, stop turn, launch at login
- **M4** — universal binary, release packaging, GitHub Actions, screenshots

## License

MIT
