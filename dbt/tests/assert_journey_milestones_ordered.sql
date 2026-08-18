-- A parcel cannot be delivered before it was collected, leave a hub before it
-- arrived, or be delivered before it went out for delivery. Any of these means
-- the event stream is out of order or a milestone was picked from the wrong scan.

select
    parcel_id,
    collected_ts,
    hub_arrival_ts,
    hub_departure_ts,
    out_for_delivery_ts,
    delivered_ts
from {{ ref('fct_parcel_journey') }}
-- The null-safe half. A comparison against a missing milestone is null, not a
-- failure, so a delivered parcel whose collection scan was dropped satisfies
-- none of the predicates above - while the journey still counts as delivered,
-- reports a null transit time, and lands in the first-attempt denominator as a
-- miss. Missing prerequisites are a data-quality failure, not a bad outcome.

where
    delivered_ts < collected_ts
    or hub_departure_ts < hub_arrival_ts
    or delivered_ts < out_for_delivery_ts
    or (delivered_ts is not null and (collected_ts is null or out_for_delivery_ts is null))
