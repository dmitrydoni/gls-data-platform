-- Rates are ratios of counts taken at the same grain, so they must sit in [0, 1]
-- and no component may exceed the denominator. A breach means the aggregation
-- grain and the join grain have diverged - the classic dimensional fan-out.

select
    delivered_date,
    destination_location_name,
    service_level,
    parcels_delivered,
    parcels_on_time,
    on_time_rate
from {{ ref('mrt_service_performance_daily') }}
where
    on_time_rate not between 0 and 1
    or first_attempt_rate not between 0 and 1
    or exception_rate not between 0 and 1
    or parcels_on_time > parcels_delivered
    or parcels_first_attempt > parcels_delivered
    or delivery_attempts < parcels_delivered
