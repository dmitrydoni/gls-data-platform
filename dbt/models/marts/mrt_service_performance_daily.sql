/*
    Type: Mart (periodic snapshot)
    Grain: One row per delivery date, destination depot and service level
    DWH keys:
        - service_performance__sk
        - destination_location__fk
        - delivered_date__fk
    Purpose:
        - The carrier service scorecard: punctuality, first-attempt success and
          exception rate, cut the three ways operations actually manages them

    Rates are published as both the numerator and the ratio. A dashboard that
    receives only the ratio cannot re-aggregate it across depots without being
    wrong, because the average of per-depot rates is not the network rate.
*/

{{ config(
    materialized='table',
    labels={'domain': 'tracking', 'grain': 'date_location_service'},
    tags=['tracking', 'daily', 'reporting']
) }}

with journeys as (

    select * from {{ ref('fct_parcel_journey') }}
    where is_delivered

),

locations as (
    select * from {{ ref('dim_location') }}
),

aggregated as (

    select
        journeys.delivered_date,
        journeys.destination_location__fk,
        locations.location_name as destination_location_name,
        locations.country as destination_country,
        journeys.service_level,
        count(*) as parcels_delivered,
        sum(case when journeys.is_on_time then 1 else 0 end) as parcels_on_time,
        sum(case when journeys.is_first_attempt_success then 1 else 0 end) as parcels_first_attempt,
        sum(case when journeys.has_exception then 1 else 0 end) as parcels_with_exception,
        sum(journeys.delivery_attempts) as delivery_attempts,
        avg(journeys.total_transit_hours) as avg_transit_hours,
        avg(journeys.hub_dwell_hours) as avg_hub_dwell_hours,
        avg(journeys.last_mile_hours) as avg_last_mile_hours
    from journeys
    inner join locations on journeys.destination_location__fk = locations.location__sk
    group by
        journeys.delivered_date,
        journeys.destination_location__fk,
        locations.location_name,
        locations.country,
        journeys.service_level

),

final as (

    select
        {{ surrogate_key([
            'delivered_date',
            'destination_location__fk',
            'service_level'
        ]) }} as service_performance__sk,
        {{ surrogate_key(['delivered_date']) }} as delivered_date__fk,
        destination_location__fk,
        delivered_date,
        destination_location_name,
        destination_country,
        service_level,
        -- Additive measures
        parcels_delivered,
        parcels_on_time,
        parcels_first_attempt,
        parcels_with_exception,
        delivery_attempts,
        -- Non-additive rates, safe only at this grain
        parcels_on_time * 1.0 / parcels_delivered as on_time_rate,
        parcels_first_attempt * 1.0 / parcels_delivered as first_attempt_rate,
        parcels_with_exception * 1.0 / parcels_delivered as exception_rate,
        avg_transit_hours,
        avg_hub_dwell_hours,
        avg_last_mile_hours
    from aggregated

)

{{ final_select() }}
