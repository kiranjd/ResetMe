# ResetMe website counts

GitHub Pages loads `website/analytics.js` (about 1.3 KB uncompressed) on the homepage.
It sends pageview and download events to `resetme-web-analytics.kiranjd8.workers.dev/event`.
Cloudflare D1 stores daily aggregate counters, split by event, referral hostname,
country and test flag. Dates are UTC. No visitor IDs, IP addresses, cookies, browser
storage, full referrer paths, or individual event rows are stored by the collector.
Worker observability is disabled. Cloudflare and GitHub still process network requests.

Counts are **page views and download clicks**, not unique visitors, successful downloads,
installations or conversion cohorts. Reloads and repeat clicks count again. Blocking,
network failures and disabled JavaScript undercount. Public collection is not authenticated:
Origin validation prevents normal cross-site submissions but is not spoof/bot protection.
Do not interpret these low-volume counts as audited human traffic.

## Read the last 30 days

With existing authenticated Wrangler (or `CLOUDFLARE_API_TOKEN`):

```sh
wrangler d1 execute resetme-web-analytics --remote --config workers/analytics/wrangler.toml --file workers/analytics/report.sql
```

Data is private to the Cloudflare account; the Worker exposes no reporting route.
The D1 console for `resetme-web-analytics` can also run this SQL.

## Test and deploy

```sh
node --test workers/analytics/test.mjs
wrangler d1 execute resetme-web-analytics --remote --config workers/analytics/wrangler.toml --file workers/analytics/schema.sql
wrangler deploy --config workers/analytics/wrangler.toml
```

Open `https://kiranjd.github.io/ResetMe/?analytics=test` for end-to-end browser tests.
Those events have `test=1` and are excluded from reports. `?analytics=off`, Do Not Track
and Global Privacy Control disable collection. Download links always navigate directly
to GitHub; collector failures never block downloads. Privacy details: `website/privacy.html`.

Worker changes require the explicit Wrangler deployment above. Website changes deploy
through the existing GitHub Pages workflow. No app release or native telemetry is involved.
