-- `parcel_id` is policy-tagged and masked, so no unmasked column beside it may
-- reconstruct it. Two ways to lose that, both invisible to every other test: an
-- event id built as `<tracking number>-<step>`, and an unsalted digest of the
-- tracking number.

select event_id as offending_value
from {{ ref('fct_parcel_scan') }}
where event_id like '%' || parcel_id || '%'

union all

select parcel__fk
from {{ ref('fct_parcel_scan') }}
where parcel__fk = md5(parcel_id)
