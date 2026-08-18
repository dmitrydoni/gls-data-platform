/*
    Type: Fact (transaction fact)
    Grain: One row per parcel scan event
    Business keys:
        - event_id (degenerate dimension)
    DWH keys:
        - scan__sk
        - parcel__fk
        - location__fk
        - biz_step__fk
        - date__fk
    Purpose:
        - The event spine of the warehouse. Every journey milestone, dwell time
          and service metric downstream is an aggregation of these rows

    Built with the microbatch strategy: dbt splits the run into one bounded query
    per event day and replaces that day's partition atomically. A batch is
    idempotent on its own, so a failed day retries without touching the rest, and
    a correction older than the lookback is a bounded backfill
    (`--event-time-start` / `--event-time-end`) rather than a full refresh.

    Every column here is a function of its own row. A batch sees one day, so any
    attribute needing a parcel's whole history would be computed against a
    truncated window and written back as if it were correct. Those attributes
    belong in the journey model, where the full history is in scope.

    The lookback bounds what a routine run rebuilds, so it also bounds how late a
    scan can arrive and still be picked up unasked. That is not left to trust:
    `assert_scan_fact_covers_landed_events` fails the build when a landed event is
    missing here, and the repair is `just dwh-backfill`.

    `concurrent_batches=false` is a DuckDB constraint, not a design choice:
    DuckDB serialises catalogue writes, so parallel batches collide altering the
    same table. On BigQuery it comes off and the batches run wide.

    The physical layout is declared here rather than in Terraform because
    partitioning is a property of a CREATE and dbt issues the CREATE; a table
    Terraform pre-creates is replaced by the first full build, taking its
    partition spec with it. `event_time` is the partition column, so a batch
    replaces exactly one partition.
*/

{{ config(
    materialized='incremental',
    incremental_strategy='microbatch',
    event_time='event_date',
    batch_size='day',
    lookback=var('scan_capture_lookback_days'),
    begin=var('scan_history_begin'),
    concurrent_batches=false,
    on_schema_change='sync_all_columns',
    labels={'domain': 'tracking', 'grain': 'parcel_scan'},
    tags=['tracking', 'hourly']
) }}

{#- Guarded rather than passed through: `partition_by` is not a BigQuery-only
    key. dbt-duckdb reads it too, for hive-partitioned exports, and rejects the
    dict shape BigQuery requires - so the block only exists on the adapter it is
    written for. Partitioning and clustering are what make the bounded reads
    downstream cheap; `require_partition_filter` is deliberately not set, because
    it would reject dbt's own generic tests, which carry no predicate. -#}
{% if target.type == 'bigquery' %}
    {{ config(
        partition_by={'field': 'event_date', 'data_type': 'date', 'granularity': 'day'},
        cluster_by=['parcel_id', 'biz_step__fk']
    ) }}
{% endif %}

with scans as (

    -- Auto-filtered to the batch being built: the parent declares `event_time`.
    select * from {{ ref('stg_tracking__scan_events') }}

),

final as (

    select
        {{ surrogate_key(['scans.event_id']) }} as scan__sk,
        {{ surrogate_key(['scans.parcel_id']) }} as parcel__fk,
        {{ surrogate_key(['scans.location_gln']) }} as location__fk,
        {{ surrogate_key(['scans.biz_step', 'scans.disposition']) }} as biz_step__fk,
        {{ surrogate_key(['scans.event_date']) }} as date__fk,
        -- Degenerate dimension: the carrier's own event identifier
        scans.event_id,
        scans.parcel_id,
        scans.event_ts,
        scans.event_date,
        scans.record_ts,
        scans.read_point,
        -- Measure
        {{ datediff_hours('scans.event_ts', 'scans.record_ts') }} as capture_lag_hours
    from scans

)

{{ final_select() }}
