-- UTC dates. Tests are excluded from every report.
SELECT day, SUM(CASE WHEN event='pageview' THEN count ELSE 0 END) AS pageviews,
 SUM(CASE WHEN event='download' THEN count ELSE 0 END) AS download_clicks
FROM daily_counts WHERE test=0 GROUP BY day ORDER BY day DESC LIMIT 30;
SELECT source, event, SUM(count) AS count FROM daily_counts
WHERE test=0 AND day >= date('now','-29 days') GROUP BY source,event ORDER BY count DESC;
SELECT country, event, SUM(count) AS count FROM daily_counts
WHERE test=0 AND day >= date('now','-29 days') GROUP BY country,event ORDER BY count DESC;
