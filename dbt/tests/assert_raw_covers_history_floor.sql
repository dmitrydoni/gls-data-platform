/*
    The replay guarantee behind every documented rebuild.

    `assert_scan_fact_covers_landed_events` proves the fact holds everything raw
    landed. It cannot prove raw still holds everything the fact claims: raw
    partitions expire, the fact does not, and a full rebuild after they have
    aged out reconstructs only the surviving window. Both tests would stay green
    on the truncated result, because neither side knows what is no longer there.

    So this test is the other direction, and neither end of it is taken from
    raw. Raw must cover every day from the declared history floor to the last
    day the fact publishes - a check against raw's own extremes would accept a
    single surviving row with the months around it gone, since one row is a
    consistent history of itself. A carrier feed with no scan anywhere in a day
    has stopped, so a missing day is a lost day, and an empty result fails
    rather than passing vacuously.

    When this breaks, the recovery paths the design documents - a rebuild after
    a bad merge, a salt rotation - would silently publish a shortened history,
    and the answer is to lengthen `raw_partition_expiry_days` or to raise
    `scan_history_begin` to what is actually retained.
*/

{% set history_begin = "date '" ~ var('scan_history_begin') ~ "'" %}

with published as (
    select max(event_date) as through_date
    from {{ ref('fct_parcel_scan') }}
)

select
    count(*) as landed_events,
    count(distinct landed.event_date) as covered_days,
    max(published.through_date) as published_through
from {{ ref('stg_tracking__scan_events') }} landed
cross join published
where landed.event_date between {{ history_begin }} and published.through_date
having
    count(*) = 0
    or count(distinct landed.event_date)
    != {{ dbt.datediff(history_begin, 'max(published.through_date)', 'day') }} + 1
