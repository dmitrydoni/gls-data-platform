/*
    Type: Fact (accumulating snapshot)
    Grain: One row per parcel
    Business keys:
        - parcel_id (UPU S10 item identifier)
    DWH keys:
        - journey__sk
        - parcel__fk
        - merchant__fk
        - origin_location__fk
        - destination_location__fk
        - delivered_date__fk
    Purpose:
        - One row per parcel carrying every journey milestone, the durations
          between them, and whether the service promise was kept

    An accumulating snapshot is the right fact type here because a parcel journey
    is a pipeline process with a known set of milestones: the row is created at
    label scan and revisited as each milestone lands, rather than being appended
    to. Kimball's transaction fact already exists upstream as `fct_parcel_scan`;
    this model answers the questions that a per-event grain answers badly - how
    long did it take, was it on time, how many attempts did it need.

    Rebuilt in full, from the complete retained scan history. An accumulating
    snapshot has mutable rows by definition, and it copies parcel attributes such
    as `promised_delivery_ts` that a master-data correction can change without
    producing any new scan - so a rebuild bounded by recent scan activity would
    silently keep serving the old value. Rebuilding is the cheaper guarantee at
    this volume. Where it stops being cheap, the replacement is a merge on
    `journey__sk` whose selection unions recent scan movement with changed parcel
    keys, not a narrower scan window.
*/

{{ config(
    materialized='table',
    labels={'domain': 'tracking', 'grain': 'parcel'},
    tags=['tracking', 'daily']
) }}

with milestones as (
    select * from {{ ref('int_parcel__milestones') }}
),

parcels as (
    select * from {{ ref('dim_parcel') }}
),

joined as (

    select
        parcels.parcel__sk,
        parcels.merchant__fk,
        parcels.origin_location__fk,
        parcels.destination_location__fk,
        parcels.parcel_id,
        parcels.service_level,
        parcels.weight_kg,
        parcels.weight_band,
        parcels.promised_delivery_ts,
        milestones.label_created_ts,
        milestones.collected_ts,
        milestones.hub_arrival_ts,
        milestones.hub_departure_ts,
        milestones.out_for_delivery_ts,
        milestones.delivered_ts,
        milestones.returned_ts,
        milestones.delivery_attempts,
        milestones.exception_events,
        milestones.scan_count,
        milestones.last_scan_ts
    from parcels
    inner join milestones on parcels.parcel_id = milestones.parcel_id

),

final as (

    select
        {{ surrogate_key(['joined.parcel_id']) }} as journey__sk,
        joined.parcel__sk as parcel__fk,
        joined.merchant__fk,
        joined.origin_location__fk,
        joined.destination_location__fk,
        -- Null while the parcel is in flight. Hashing the null instead would
        -- mint a key that matches no calendar day and still passes a not-null
        -- test - an orphan the star cannot see.
        case
            when joined.delivered_ts is not null
                then {{ surrogate_key(['cast(joined.delivered_ts as date)']) }}
        end as delivered_date__fk,
        joined.parcel_id,
        joined.service_level,
        joined.weight_band,
        -- Milestones
        joined.label_created_ts,
        joined.collected_ts,
        joined.hub_arrival_ts,
        joined.hub_departure_ts,
        joined.out_for_delivery_ts,
        joined.delivered_ts,
        joined.returned_ts,
        joined.promised_delivery_ts,
        joined.last_scan_ts,
        cast(joined.delivered_ts as date) as delivered_date,
        -- Durations between milestones, the reason this fact type exists
        {{ datediff_hours('joined.collected_ts', 'joined.delivered_ts') }} as total_transit_hours,
        {{ datediff_hours('joined.hub_arrival_ts', 'joined.hub_departure_ts') }} as hub_dwell_hours,
        {{ datediff_hours('joined.collected_ts', 'joined.hub_arrival_ts') }} as first_mile_hours,
        {{ datediff_hours('joined.out_for_delivery_ts', 'joined.delivered_ts') }} as last_mile_hours,
        -- Measures
        joined.weight_kg,
        joined.delivery_attempts,
        joined.exception_events,
        joined.scan_count,
        -- Service outcome flags
        joined.delivered_ts is not null as is_delivered,
        joined.returned_ts is not null as is_returned,
        joined.delivered_ts is not null
            and joined.delivered_ts <= joined.promised_delivery_ts as is_on_time,
        joined.delivered_ts is not null
            and joined.delivery_attempts = 1 as is_first_attempt_success,
        joined.exception_events > 0 as has_exception
    from joined

)

{{ final_select() }}
