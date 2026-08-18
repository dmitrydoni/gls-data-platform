/*
    The journey is a summary of the scan fact, so it has to agree with it.

    The milestone view inner-joins `dim_biz_step` and `dim_location`, so a scan
    carrying a step or location the dimensions do not hold is dropped from the
    journey rather than rejected. The journey still exists and its milestones
    still look plausible - only the counts disagree, which is visible from
    neither table alone.

    Bounded by `scan_history_begin`, a predicate on the partition column, so the
    read prunes rather than scanning the fact whole.
*/

with fact_scans as (

    select
        parcel_id,
        count(*) as scan_count
    from {{ ref('fct_parcel_scan') }}
    where event_date >= date '{{ var('scan_history_begin') }}'
    group by parcel_id

)

select
    fact_scans.parcel_id,
    fact_scans.scan_count as fact_scan_count,
    journey.scan_count as journey_scan_count
from fact_scans
inner join {{ ref('fct_parcel_journey') }} journey
    on fact_scans.parcel_id = journey.parcel_id
where fact_scans.scan_count != journey.scan_count
