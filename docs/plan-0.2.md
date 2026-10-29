# dsh-bar 0.2 — plan

One bigger release instead of three small ones. Scope chosen 2026-10-29: "everything at once".

## Goal

Close the interaction loop and make the bar a real control surface:

1. answer questions from the popover (single, multi, free text);
2. native notifications for approval / question / done / error, with actions;
3. approvals queue (1 of N), not just the first one;
4. session list from `status.rows`, switch and stop per session;
5. settings window (notifications, animation / Reduce Motion, launch at login, menu bar display);
6. update check against GitHub Releases;
7. localization en / ru / zh-Hans;
8. native tests (decode, answer encoding, notification dedupe) in CI;
9. distribution: Homebrew tap + release 0.2.0.

Out of scope for 0.2: SSE push (stays 0.3), Sparkle auto-update (manual check + download link), paid signing/notarization.

## Contract facts (verified in DSH sources)

`GET /dsh-bar/status` already returns everything native needs:

- `rows[]`: every session with `state`, `title`, `detail`, `model`, `tokens`, `busy`, `approval`, `ask`
- `approvals[]`: every held approval with `sessionId`, `title`, `toolName`, `reason`
- `questions[]`: every held ask with `sessionId`, `title`, and `questions[]` carrying `id`, `question`, `detail`, `header`, `options[{label,description}]`, `multiSelect`

`POST /dsh-bar/answer` body:

```json
{"id":"<held-id>","answers":[{"id":"q1","selected":["label A"],"custom":"free text"}]}
```

Rules: one answer per question, ids exactly once; `selected` holds option **labels**; single-select with `custom` sends `selected: []`; multi-select keeps labels plus `custom`. Empty selection is a valid skip.

## Milestones

- **M0 contracts (done)** — branch, this plan, answer schema verified.
- **M1 data layer** — decode `rows`, full questions/options; answer encoder; unit tests (SwiftPM test target).
- **M2 popover interaction** — question composer (radio/checkbox/custom text), approvals queue 1/N, session list with focus/stop.
- **M3 notifications** — `UNUserNotificationCenter`; categories/actions Approve / Deny / Open; dedupe by held ids; denied-permission fallback; test on ad-hoc build.
- **M4 settings & chrome** — settings window, UserDefaults, Reduce Motion, menu bar display mode, About/version, update checker.
- **M5 localization** — en / ru / zh-Hans via `.lproj`, no hardcoded strings, number/date formatters.
- **M6 tests & CI** — Swift tests for decode/answer/dedupe; workflow runs them; plugin tests updated for answer shapes.
- **M7 distribution & release** — Homebrew tap cask, README/screenshots, 0.2.0 universal build, GitHub release, npm plugin 0.2.0 if host changed, catalog entry unchanged.

## Acceptance

- A held question is answered from the bar; agent receives the answer; the GUI answerer is aborted cleanly; covered by tests.
- Notifications appear for approval/question/done, actions work, no duplicates, toggle persists; if denied, the popover still shows the item.
- All N approvals are reachable; sessions switch correctly; stop targets the right session.
- Settings persist across launches; Reduce Motion turns the whale static; update check reports a newer release.
- UI has no hardcoded English; three locales render.
- CI green with native tests; tap installs the same 0.2.0; SHA256SUMS published.

## Risks

- **Notifications with ad-hoc signature** — likely fine (permission is user-level, not Developer ID), but must be proven early; fallback: in-popover badge + sound.
- **Answer race** — GUI and bar can answer simultaneously; host settles first and aborts the loser; tests must cover 404 / already-settled.
- **Localization scope** — three locales multiply strings; keep strings short and reuse existing labels.
- **Homebrew official cask** — notarization is required, so ship a tap (`reg4916/homebrew-dsh-bar`), not homebrew-cask.
