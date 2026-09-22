// Aggregate counts only: no cookies, identifiers, or browser storage.
(() => {
  if (location.hostname !== 'kiranjd.github.io' || !/^\/ResetMe\/(?:index\.html)?$/.test(location.pathname)) return;
  if (navigator.doNotTrack === '1' || navigator.globalPrivacyControl === true) return;
  const mode = new URLSearchParams(location.search).get('analytics');
  if (mode === 'off') return;
  let referrer = '';
  try { referrer = document.referrer ? new URL(document.referrer).origin : ''; } catch {}
  const send = event => {
    const body = JSON.stringify({ event, path: '/ResetMe/', referrer, test: mode === 'test' });
    const endpoint = 'https://resetme-web-analytics.kiranjd8.workers.dev/event';
    try {
      if (navigator.sendBeacon?.(endpoint, body)) return;
      fetch(endpoint, { method: 'POST', body, keepalive: true, credentials: 'omit' }).catch(() => {});
    } catch {} // Analytics must never interrupt navigation or downloads.
  };
  send('pageview');
  document.addEventListener('click', event => {
    if (event.target.closest?.('a[data-track="download"]')) send('download');
  });
})();
