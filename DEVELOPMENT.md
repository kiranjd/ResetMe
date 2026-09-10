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

The public site is https://kiranjd.github.io/ResetMe/. `.github/workflows/pages.yml` deploys only `website/` to GitHub Pages when those files change on `main`, or when manually dispatched. Keep canonical, Open Graph, and sitemap URLs aligned if the public address changes. Project-level `robots.txt` does not override the hosting domain’s root crawler policy.

## App behavior

Choose Codex or Claude in the panel. The choice is remembered. Quotas refresh every minute, after wake, or with the refresh button. Hover over the notch to expand; click a history day for details; move away to close. The menu-bar and panel menus offer show/hide, Check for Updates, and Quit. Codex can also expose its separate Spark allowance. Only the notch presentation is supported. “Show in menu bar” can be disabled from the status menu or Settings; the choice persists across launches. Restore it through Settings in the notch menu, or by reopening the app. History hover cards include a click hint for opening the day breakdown.

The indicator is quiet by default. Hover always opens it; changed quota percentages reveal the compact indicator for five seconds (at the existing one-minute refresh cadence). Initial reads, unchanged responses, missing data, and provider switches do not count as activity. Settings offers persistent Always on, usage-change reveals, and foreground-app visibility. Installed AI apps/editors are suggested and initially selected; terminals and arbitrary apps can be selected through search or Add App. App identities come from local bundles, not guessed bundle IDs. The menu-bar shortcut “Show while <app> is active” adds/removes the current foreground app. Selection means foreground, not merely running; terminals cover every CLI inside them. This is a visibility trigger, not a new quota integration. Manual Hide overrides all automatic reveals. No process inspection, shell hooks, Accessibility permission, or app inventory upload is required.

`Sources/ResetApp/main.swift` owns the panel, display geometry, menus, and pointer tracking. `UsageStore.swift` owns provider selection, refresh lifetime, history, and presentation state. `PanelView.swift` owns the main interface. The history and day-detail views live beside it. Geometry and usage parsing live under `Sources/ResetCore/`; tests live under `Tests/`.

History statistics preload at launch and on provider changes, and refresh in the background with quota checks and wake events. Hover only reveals the existing data. A provider-and-source-scoped disk cache stores aggregated daily counters for immediate redisplay after relaunch; a fresh scan replaces them without clearing visible rows. Only one history scan may run at a time; stale results from a previous provider are ignored. New calendar days remain unknown until scanned.

### Reset history

Reset history is persisted independently of the 24-hour pace samples in the local `quotaResetHistoryV1` preference. Only weekly allowances (10,080 minutes) are tracked; five-hour resets are excluded. Each provider and weekly allowance bucket has its own baseline. The graph displays every recorded weekly reset within its 14-day range, grouping same-day resets behind a count. Hover shows every reset in that group with its type and time; reset markers have no click action or separate window. Older events remain stored for history continuity.

Scheduled resets use the provider's prior deadline only after a later window is observed. Early cycle changes require both a new deadline and restored allowance; their start is estimated from the new deadline minus the window duration, never presented as a confirmed manual action. Live percentage drops without a cycle change are labeled allowance restorations with an observation interval, since the cause and exact time are unavailable. Deadline jitter, expired or backwards cached windows, plan changes, and unused moving deadlines do not create resets. The hover labels confirmed scheduled boundaries as scheduled weekly resets and other events simply as Reset, followed by the date. Internal timing uncertainty remains stored even though the tooltip omits uncertainty labels. A granted or expired reset credit is not evidence that a reset was used. Do not manufacture periodic events during missing observations.

Codex backfill reads only quota metadata from local `token_count` records in the existing history scan and merges duplicate cycle changes. Session token-counter resets are not subscription resets. Claude history currently has no equivalent quota-event source, so earlier unobserved resets cannot be reconstructed. Neither provider's current usage endpoint supplies a complete manual-reset audit trail. Preserve these limitations when describing coverage.

## Provider contracts

- Codex: a short-lived local `codex app-server` process requests `account/rateLimits/read`. Discovery includes installed Codex/ChatGPT desktop CLI bundles. Prefer distinct limit buckets and preserve missing data. Banked resets appear only when reported by Codex.
- Claude: read an existing Claude Code OAuth sign-in and make a read-only request to `https://api.anthropic.com/api/oauth/usage`. Expired or inaccessible credentials produce an explanation. Do not start login, refresh stored credentials, or change Keychain access rules.
- Browser-only sessions and API keys do not provide subscription quotas. Do not import browser cookies.
- Keychain access must not prompt. A legacy lookup is bounded to two seconds for the caller, with at most one lookup in flight so a wedged security service cannot accumulate threads. Switching providers cancels requests, clears the prior data, and ignores late responses, including after switching back.
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

## Brand assets

The official mark is the two-leaf silhouette. The palette is olive `#606c38`, forest `#283618`, cream `#fefae0`, sand `#dda15e`, and copper `#bc6c25`. Website surfaces use cream and forest with olive secondary text. The custom native panel uses forest shading, olive bars, cream text, and warm allowance/reset accents; system menus retain native appearance. Native palette constants are in `BrandPalette.swift` and scene defaults in `SceneSettings.swift`. On first launch with this palette, earlier experimental color overrides are backed up under `opticalScene.beforeLeafPalette.v1` and replaced with the approved defaults; scalar tuning remains intact. Subsequent color adjustments are respected.

Editable SVG marks, light/dark monochrome variants, wordmarks, transparent PNGs, iconset and macOS menu templates live in `Assets/Brand/`. Regenerate with `swift scripts/generate-brand.swift`, then `iconutil -c icns Assets/Brand/ResetMe.iconset -o Assets/ResetMe.icns`. `build-app.sh` bundles the menu templates and app icon. Website brand assets and the 1200 × 630 link preview are generated by the same script. Open Graph, X, and structured data reference `social-preview-leaf.png`; the distinct filename avoids reusing the previous preview URL. Third-party platforms may retain existing unfurls after deployment.
