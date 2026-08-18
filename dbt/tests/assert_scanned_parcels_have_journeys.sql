/*
    Every parcel the warehouse holds scans for must have a journey row.

    The journey fact inner-joins the milestone view, so a parcel the milestone
    read failed to reach is not a wrong row - it is no row, which no test that
    starts from the journey fact can see. That is the shape a rebuild bug takes
    when the milestone read is bounded relative to the clock: the build is
    clean, the tests are green, and the older half of the parcel base is gone.
*/

select parcels.parcel_id
from {{ ref('dim_parcel') }} parcels
where
    exists (
        select 1
        from {{ ref('fct_parcel_scan') }} scans
        where parcels.parcel_id = scans.parcel_id
    )
    and not exists (
        select 1
        from {{ ref('fct_parcel_journey') }} journeys
        where parcels.parcel_id = journeys.parcel_id
    )
