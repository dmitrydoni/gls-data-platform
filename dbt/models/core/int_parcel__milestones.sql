/*
    Type: Intermediate
    Grain: One row per parcel
    Purpose:
        - Collapse the scan event stream into the milestone timestamps that
          define a parcel's journey, ready for the accumulating snapshot

    Milestones take the earliest qualifying scan, not the latest: a parcel that
    is scanned out for delivery three times went out for delivery first on the
    earliest of those days, and its last-mile clock starts there.

    Every parcel is rebuilt from its complete retained history. Reading a recent
    window instead would recompute a long-running parcel's milestones from a
    truncated history and write the truncation back over values that were right -
    the same defect the scan fact avoids by refusing to hold window functions,
    and no less silent here.

    `scan_history_begin` is a predicate on the partition column, so the read
    prunes on BigQuery rather than scanning the fact whole.
*/

{{ config(materialized='view') }}

with scans as (

    select * from {{ ref('fct_parcel_scan') }}
    where event_date >= date '{{ var('scan_history_begin') }}'

),

steps as (
    select * from {{ ref('dim_biz_step') }}
),

locations as (
    select * from {{ ref('dim_location') }}
),

enriched as (

    select
        scans.parcel_id,
        scans.event_ts,
        steps.biz_step,
        steps.disposition,
        steps.step_category,
        locations.is_hub
    from scans
    inner join steps on scans.biz_step__fk = steps.biz_step__sk
    inner join locations on scans.location__fk = locations.location__sk

),

final as (

    select
        parcel_id,
        min(case when biz_step = 'commissioning' then event_ts end) as label_created_ts,
        min(case when biz_step = 'receiving' then event_ts end) as collected_ts,
        min(case when biz_step = 'arriving' and is_hub then event_ts end) as hub_arrival_ts,
        min(case when biz_step = 'departing' and is_hub then event_ts end) as hub_departure_ts,
        min(case when biz_step = 'shipping' then event_ts end) as out_for_delivery_ts,
        min(case when biz_step = 'delivering' then event_ts end) as delivered_ts,
        min(case when disposition = 'returned' then event_ts end) as returned_ts,
        count(case when biz_step = 'shipping' then 1 end) as delivery_attempts,
        count(case when step_category = 'exception' then 1 end) as exception_events,
        count(*) as scan_count,
        max(event_ts) as last_scan_ts
    from enriched
    group by parcel_id

)

select * from final
