# Developing ResetMe

Native AppKit + SwiftUI utility for macOS 14+, currently for notched displays. The Swift package builds the app executable and a small `ResetCore` library. Sparkle provides signed app updates.

## Build and verify

Use Xcode command line tools with Swift 6 or later:

```sh
swift test
zsh scripts/check-scene.sh
zsh scripts/check-mesh.sh
zsh build-app.sh
open dist/ResetMe.app
```

The static website needs no build step:

```sh
python3 -m http.server 8774 --directory website
```

## App behavior

Choose Codex or Claude in the panel. The choice is remembered. Quotas refresh every minute, after wake, or with the refresh button. Hover over the notch to expand; click a history day for details; move away to close. The menu-bar and panel menus offer show/hide, Check for Updates, and Quit. Codex can also expose its separate Spark allowance. Only the notch presentation is supported.

`Sources/ResetApp/main.swift` owns the panel, display geometry, menus, and pointer tracking. `UsageStore.swift` owns provider selection, refresh lifetime, history, and presentation state. `PanelView.swift` owns the main interface. The history and day-detail views live beside it. Geometry and usage parsing live under `Sources/ResetCore/`; tests live under `Tests/`.

## Provider contracts

- Codex: a short-lived local `codex app-server` process requests `account/rateLimits/read`. Discovery includes installed Codex/ChatGPT desktop CLI bundles. Prefer distinct limit buckets and preserve missing data. Banked resets appear only when reported by Codex.
- Claude: read an existing Claude Code OAuth sign-in and make a read-only request to `https://api.anthropic.com/api/oauth/usage`. Expired or inaccessible credentials produce an explanation. Do not start login, refresh stored credentials, or change Keychain access rules.
- Browser-only sessions and API keys do not provide subscription quotas. Do not import browser cookies.
- Keychain access must not prompt. Switching providers cancels requests, clears the prior data, and ignores late responses, including after switching back.
- History extracts usage counters and model identifiers from local session files. Keep provider histories separate; honor custom configuration roots; deduplicate streaming records. Missing days stay unknown.
- Codex costs are partial API-equivalent estimates for recognized models, not subscription charges. Leave unknown models unpriced. Claude history shows tokens.
- Local session files may contain private conversation text. Never display, log, commit, or send it. Stored quota samples and preferences remain local.

## Release

`build-app.sh` assembles the app and embeds Sparkle. Inspect the packaging and verification scripts in `scripts/` before releasing. Developer ID signing, notarization, and Sparkle archive signing are separate requirements. Never publish an unsigned development bundle as the downloadable release. Keep private keys, credentials, and local build output out of commits.

For a signed release, set `RESETME_SIGN_IDENTITY` to your Developer ID Application identity and `RESETME_NOTARY_PROFILE` to an existing notarytool keychain profile, then run `zsh scripts/release-signed.sh`. The Sparkle private key stays in Keychain under the project-specific account `resetme.sparkle`; `SPARKLE_KEY_ACCOUNT` overrides that account.

The public update feed must match `SUFeedURL` and `SUPublicEDKey` in the shipped app. Check the signature, notarization, archive contents, download URLs, and live appcast before claiming delivery. A successful build does not prove a downloaded update installs successfully.

## Validation limits

Test provider errors and unavailable data explicitly. An expired Claude login cannot prove live Claude quota success. Local history is not an account-wide audit. Hardware motion, display changes, and full-screen behavior need real-device checks. Reduce Motion must remain supported; unavailable motion input must leave the app usable.

Inspired by [CodexBar](https://github.com/steipete/CodexBar). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for asset and dependency attribution. Code is [MIT licensed](LICENSE).
