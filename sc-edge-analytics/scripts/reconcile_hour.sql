-- One-off acceptance check against raw S3 data for a single completed hour.
-- Run with the DuckDB CLI on a host that has read access to the bucket (e.g. the Rill EC2 instance):
--   duckdb -c "SET VARIABLE dt = '2026-10-08'; SET VARIABLE hr = '18';" -f scripts/reconcile_hour.sql
-- Compare raw_rows per node with this query in Rill (sum of requests for the same hour):
--   SELECT node, sum(requests) FROM edge_quality_hourly
--   WHERE dt = '2026-10-08' AND hour = '18' GROUP BY node ORDER BY node;
-- Pass criterion: equal within 0.01%.

INSTALL httpfs;
LOAD httpfs;
CREATE OR REPLACE SECRET edge_events (TYPE S3, PROVIDER CREDENTIAL_CHAIN, REGION 'eu-central-1');

CREATE OR REPLACE TEMP TABLE raw_lines AS
SELECT
  regexp_extract(filename, 'node=([^/]+)', 1) AS node,
  json
FROM read_json(
  's3://sc-analytics-445214595912/events/dt=' || getvariable('dt') || '/hour=' || getvariable('hr') || '/node=ovh-sc-edge-*/*.log.gz',
  format = 'newline_delimited',
  compression = 'gzip',
  records = false,
  hive_partitioning = false,
  ignore_errors = true,
  filename = true
);

-- Raw row counts per node, plus exact duplicate lines (the shipper may retry a batch; there is no request ID).
SELECT
  node,
  count(*)                                  AS raw_rows,
  count(*) - count(DISTINCT md5(json::VARCHAR)) AS duplicate_rows
FROM raw_lines
GROUP BY node
ORDER BY node;
