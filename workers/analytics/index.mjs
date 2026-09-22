const origin = 'https://kiranjd.github.io';
export default {
  async fetch(request, env) {
    const headers = { 'Access-Control-Allow-Origin': origin, 'Vary': 'Origin', 'Cache-Control': 'no-store' };
    const reply = status => new Response(null, { status, headers });
    if (new URL(request.url).pathname !== '/event') return reply(404);
    if (request.headers.get('Origin') !== origin) return reply(403);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: { ...headers, 'Access-Control-Allow-Methods': 'POST', 'Access-Control-Allow-Headers': 'Content-Type' } });
    if (request.method !== 'POST') return reply(405);
    if (request.headers.get('DNT') === '1' || request.headers.get('Sec-GPC') === '1') return reply(204);
    if (Number(request.headers.get('Content-Length')) > 1024) return reply(413);
    try {
      const text = await request.text();
      if (text.length > 1024) return reply(413);
      const data = JSON.parse(text);
      if (!['pageview', 'download'].includes(data.event) || data.path !== '/ResetMe/') return reply(400);
      let source = 'direct';
      if (data.referrer) {
        const ref = new URL(data.referrer);
        if (!['http:', 'https:'].includes(ref.protocol)) return reply(400);
        source = ref.hostname === 'kiranjd.github.io' ? 'internal' : ref.hostname.slice(0, 253);
      }
      const country = /^[A-Z]{2}$/.test(request.cf?.country || '') ? request.cf.country : 'XX';
      await env.DB.prepare(`INSERT INTO daily_counts(day,event,source,country,test,count) VALUES(?,?,?,?,?,1)
        ON CONFLICT(day,event,source,country,test) DO UPDATE SET count=count+1`)
        .bind(new Date().toISOString().slice(0,10), data.event, source, country, data.test === true ? 1 : 0).run();
      return reply(204);
    } catch { return reply(400); }
  }
};
