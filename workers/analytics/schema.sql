CREATE TABLE IF NOT EXISTS daily_counts (
  day TEXT NOT NULL,
  event TEXT NOT NULL CHECK(event IN ('pageview', 'download')),
  source TEXT NOT NULL,
  country TEXT NOT NULL,
  test INTEGER NOT NULL DEFAULT 0 CHECK(test IN (0,1)),
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day,event,source,country,test)
);
