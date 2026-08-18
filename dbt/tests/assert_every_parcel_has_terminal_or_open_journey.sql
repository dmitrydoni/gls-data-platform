-- Every parcel is either delivered, returned, or still legitimately in flight
-- with a recent scan. A parcel with no terminal milestone and no scan for two
-- weeks is lost to the tracking system - the condition operations most needs
-- surfaced, and the one a row-count check would never catch.

select
    parcel_id,
    last_scan_ts,
    delivery_attempts
from {{ ref('fct_parcel_journey') }}
where
    not is_delivered
    and not is_returned
    and last_scan_ts < (select max(last_scan_ts) - interval 14 day from {{ ref('fct_parcel_journey') }})
