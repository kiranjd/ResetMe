# Developing ResetMe

Native AppKit + SwiftUI utility for macOS 14+, with built-in notch and external-display hover support. The Swift package builds the app executable and a small `ResetCore` library. Sparkle provides signed app updates.

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

Choose Codex or Claude in the panel. The choice is remembered. Quotas refresh every minute, after wake, or with the refresh button. Hover over the notch to expand; click a history day for details; move away to close. The menu-bar and panel menus offer show/hide, Check for Updates, and Quit. Only the notch presentation is supported. “Show in menu bar” can be disabled from the status menu or Settings; the choice persists across launches. Restore it through Settings in the notch menu, or by reopening the app. History hover cards include a click hint for opening the day breakdown.

The indicator is quiet by default. Hover always opens it; changed quota percentages reveal the compact indicator for five seconds (at the existing one-minute refresh cadence). Initial reads, unchanged responses, missing data, and provider switches do not count as activity. Settings offers persistent Always on, usage-change reveals, and foreground-app visibility. Installed AI apps/editors are suggested and initially selected; terminals and arbitrary apps can be selected through search or Add App. App identities come from local bundles, not guessed bundle IDs. The menu-bar shortcut “Show while <app> is active” adds/removes the current foreground app. Selection means foreground, not merely running; terminals cover every CLI inside them. This is a visibility trigger, not a new quota integration. Manual Hide overrides all automatic reveals. No process inspection, shell hooks, Accessibility permission, or app inventory upload is required.

`Sources/ResetApp/main.swift` owns the panel, display geometry, menus, and pointer tracking. `UsageStore.swift` owns provider selection, refresh lifetime, history, and presentation state. `PanelView.swift` owns the main interface. The history and day-detail views live beside it. Geometry and usage parsing live under `Sources/ResetCore/`; tests live under `Tests/`.

History statistics preload at launch and on provider changes, and refresh in the background with quota checks and wake events. Hover only reveals the existing data. A provider-and-source-scoped disk cache stores aggregated daily counters for immediate redisplay after relaunch; a fresh scan replaces them without clearing visible rows. Only one history scan may run at a time; stale results from a previous provider are ignored. New calendar days remain unknown until scanned.

### Reset history

Reset history is persisted independently of the 24-hour pace samples in the local `quotaResetHistoryV1` preference. Only weekly allowances (10,080 minutes) are tracked; five-hour resets are excluded. Each provider and weekly allowance bucket has its own baseline. The graph displays every recorded weekly reset within its 14-day range, grouping same-day resets behind a count. Hover shows every reset in that group with its type and time; reset markers have no click action or separate window. Older events remain stored for history continuity.

Scheduled resets use the provider's prior deadline only after a later window is observed. Early cycle changes require both a new deadline and restored allowance; their start is estimated from the new deadline minus the window duration, never presented as a confirmed manual action. Live percentage drops without a cycle change are labeled allowance restorations with an observation interval, since the cause and exact time are unavailable. Deadline jitter, expired or backwards cached windows, plan changes, and unused moving deadlines do not create resets. The hover labels confirmed scheduled boundaries as scheduled weekly resets and other events simply as Reset, followed by the date. Internal timing uncertainty remains stored even though the tooltip omits uncertainty labels. A granted or expired reset credit is not evidence that a reset was used. Do not manufacture periodic events during missing observations.

Codex backfill reads only quota metadata from local `token_count` records in the existing history scan and merges duplicate cycle changes. Session token-counter resets are not subscription resets. Claude history currently has no equivalent quota-event source, so earlier unobserved resets cannot be reconstructed. Neither provider's current usage endpoint supplies a complete manual-reset audit trail. Preserve these limitations when describing coverage.

## Provider contracts

- Codex: a short-lived local `codex app-server` process requests `account/rateLimits/read`. Discovery includes installed Codex/ChatGPT desktop CLI bundles. Prefer distinct limit buckets and preserve missing data. Exclude the separate Spark allowance from display, sampling, and reset reports. Banked resets appear only when reported by Codex.
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

## Prompting surface

The notch has Usage and Prompting tabs. Prompting shows five daily measures, with seven days available through the arrows and a date button to return to today. The main time readout has its meaning on the right, followed by a divided grid for contexts/hour, parallel sessions, total prompts and top-task share. Custom glyphs render at 32 points. There is no footer row. Each metric reuses HistoryHoverPanel with a single-sentence explanation instead of a native help tooltip. The page always describes Codex, independently of the quota provider. Refresh reads current local history in a background actor; unchanged session files reuse in-memory timestamp/identifier summaries. No message text is displayed or persisted. Task metadata is used locally to group contexts; the panel displays only the aggregate. `open work/ResetMe-prompting.app --args --prompting` selects the page for local UI checks; the panel still opens only on hover and closes when the pointer leaves.

`PromptingMetrics.swift` owns aggregation and `PromptingHistory.swift` owns read-only adapters. Session metadata comes from the configured Codex home's `state_5.sqlite` and its referenced rollout files, including rotated sibling files. Only explicitly user-created tasks are eligible; agent-created tasks, subagents, unknown-origin tasks, CoS automation tasks and inherited events predating task creation are excluded. This conservatively excludes human follow-ups within agent-created tasks too. Message IDs and turn IDs deduplicate repeated records; content fingerprints reconcile modern and legacy user-message representations within two minutes without returning message bodies. Explicit setup/automation and heartbeat messages are excluded, but programmatic user-role follow-ups cannot all be distinguished from human prompts. Only execution intervals with both start and completion/abort markers contribute to parallel runtime; ongoing and orphaned starts remain excluded. Same-task overlaps are merged before measuring wall-clock time with two or more tasks running.

Task switches/hour has been removed. Prompting no longer reads Computer History or the protected Computer Use app-group container. Remaining metrics use local Codex session logs and Screen Time. Contexts/hour is the average distinct context count across prompt-bearing clock hours with fully classified tasks. Unclassified hours are excluded from the average; the existing hover card states the included and excluded hour counts. Idle hours do not dilute it. Project folders and conservative title rules suggest labels. There is no additional context page or click-through. Context labels are estimates, and user-role records cannot prove human authorship of every follow-up. The metric is not a focus or health score.

The main time total comes from this Mac's local Screen Time Biome `App.InFocus/local` records. `ScreenTimeHistory.swift` decodes retained SEGB v1/v2 focus transitions, deduplicates events and splits completed foreground intervals at local midnight. Remote-device streams are excluded. Unmatched final gains are not extended to the current time. Missing/unreadable or unsupported records stay unavailable, with no input-gap fallback. The installed app needs its own Full Disk Access grant; the terminal or Codex grant does not carry over. A permission failure displays “Screen Time access needed” and explains the required setting in the existing hover card. Local OSLog diagnostics contain only error codes and file/event counts, not activity content. This private Apple format can change; foreground time is not proof of continuous typing or attention. Tests use explicit isolated roots and cover both record formats, malformed input, duplicate gains, midnight boundaries and missing data.

Each measure has a short custom hover explanation; unavailable data is described there rather than in a footer. These measures describe recorded patterns, not a health assessment. This view is not account-wide: cloud/remote sessions and unavailable sources remain gaps. Tests cover time boundaries, distinct-task parallelism, eligible-hour rates, prompt concentration, and missing sources. Build and device checks do not establish complete historical coverage.

Prompting's custom glyphs use rounded cream strokes and restrained olive details, without leaf motifs. `PromptingIcon.swift` defines their vector paths and native rendering; decorative icons are hidden from accessibility so labels remain the source of meaning. The editable SVG exports live in `Assets/Brand/Prompting/`. Regenerate them from the same paths with `swiftc Sources/ResetApp/BrandPalette.swift Sources/ResetApp/PromptingIcon.swift scripts/generate-prompting-icons.swift -o /tmp/resetme-generate-prompting-icons && /tmp/resetme-generate-prompting-icons` from the repository root. Native icons need no raster bundle resources.

Local preview bundles built under the repository's `work/` directory are signed with the existing ResetMe Developer ID before replacing the prior bundle. `RESETME_PREVIEW_SIGN_IDENTITY` can supply a different approved identity or enable signing at another destination. Signing failure leaves the previous bundle intact. Keep `local.jd.reset` and the signing team stable across previews for consistent app identity; this does not make foreign app-group consent persistent. Routine ResetMe preview signing was approved for this task and does not require repeated confirmation. This does not change release publication or grant macOS permissions programmatically.

External displays without a hardware notch use an invisible 214pt-wide, 28pt-deep top-center hover target. Their panel reveals only on hover and closes on exit; built-in notch visibility settings retain their existing behavior. The shared panel returns to the built-in notch after the external panel closes.

Parallel sessions displays overlap duration divided by the union of completed eligible task-running intervals; no running time yields unavailable, not zero percent. Contexts/hour shows ≥1 only when eligible prompts exist but no classified hourly average is available; its hover marks this as a lower bound.
