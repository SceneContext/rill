# SceneContext Edge Analytics (Rill project)

Hourly rollups of the live bidder events in `s3://sc-analytics-445214595912/events/`, built per
`rill-edge-events-rollup-spec.md`. Dashboards read only the rollup tables; raw rows stay in S3.

| Model | Grain |
|---|---|
| `edge_quality_hourly` | hour, node, endpoint, partner, signal, source, has_title, has_segments, has_content_segments |
| `edge_segments_hourly` | hour, node, endpoint, signal, segment (+ segment_family) |
| `edge_unresolved_titles_hourly` | hour, node, endpoint, title (top 500 per endpoint per node-hour) |

## How refresh works

- Each model is incremental and partitioned by S3 directory `dt=*/hour=*/node=ovh-sc-edge-*` (one partition per node-hour).
- The hourly cron (`:10` UTC) lists partitions and re-runs only new ones and ones whose files changed
  (late files included). Re-running a partition replaces its rows.
- Credentials come from the host (EC2 instance role) through the default AWS credential chain. No keys in the project.

## `change_mode: manual` (important)

S3 keeps raw events for 90 days, but the rollups are meant to be kept for 400+ days. With Rill's default
`change_mode: reset`, any edit to a model would drop the table and rebuild it from what is still in S3,
permanently losing older history. With `manual`:

- **First deploy:** run one full refresh (an incremental trigger fails on the first run because the table doesn't exist yet):
  `rill project refresh --local --full --model edge_quality_hourly --model edge_segments_hourly --model edge_unresolved_titles_hourly`.
  Scheduled refreshes start after that.
- **After editing a model:** scheduled refreshes pause until you trigger a refresh. An incremental refresh
  (`--model`) applies the new logic to new/changed partitions only. A full refresh (`--full`) rebuilds from S3 and
  **drops any history older than 90 days**. Only do that deliberately.
- After day 90, the Rill DuckDB files on the EC2 host are the only copy of older rollups. Back them up.

## App catalog (app names in dashboards)

Two new models resolve raw app IDs to human-readable names from the SceneContext app catalog API:

| Model | Type | Refreshes |
|---|---|---|
| `app_catalog` | materialized table | daily 03:05 UTC |
| `app_lookup` | view (on top of `app_catalog`) | on every query |

The catalog (~377 apps, 7 platforms as of Oct 2026) is fetched in pages of 200 from
`https://campaignapi.scenecontext.io/api/v1/service/apps`. Authentication uses the
`APP_CATALOG_KEY` env var (set in `.env` locally and in the EC2 host environment).

Each catalog entry has three candidate keys (`id`, `platform_app_id`, `bundle_id`).
`app_lookup` emits one row per lowercased key pointing to the canonical name; ties resolve
to the most recently updated entry.

**First deploy:** `app_catalog` must be refreshed once manually before the dashboards can
join against it:
```
rill project refresh --local --model app_catalog
```

**Match-rate check** (run after first refresh):
```sql
-- In the Rill DuckDB shell or scripts/
SELECT
  count(*) AS total,
  count(DISTINCT app_bundle) AS distinct_bundles,
  count(DISTINCT CASE WHEN lk.app_name IS NOT NULL THEN app_bundle END) AS matched_bundles,
  round(100.0 * count(DISTINCT CASE WHEN lk.app_name IS NOT NULL THEN app_bundle END)
        / nullif(count(DISTINCT app_bundle), 0), 1) AS match_pct
FROM bid_log_events ble
LEFT JOIN app_lookup lk ON lk.key = lower(trim(ble.app_bundle));
```

**Growing beyond 2 000 apps:** if the `page_window_not_exhausted` test fires, extend the
`unnest([1, 2, ..., N])` list in `models/app_catalog.yaml`.

## Acceptance checks

- Model `tests:` run automatically (non-null flags, latency buckets sum to requests, unique grain, etc.).
- `scripts/reconcile_hour.sql` (ignored by Rill) compares raw row counts for one hour against
  `edge_quality_hourly` and counts exact duplicate lines. See the header of the script for usage.
