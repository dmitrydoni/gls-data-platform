-- A rising quarantine rate means the source contract is drifting, and that is a
-- data-quality signal rather than a load failure - the load succeeded.
--
-- Scoped to the newest load package, not to the table: a cumulative ratio
-- dilutes a bad batch against every good one before it, so a source that starts
-- rejecting half its payloads would read as a rounding error for weeks.
--
-- Evaluated here rather than in the orchestrator because the answer has to
-- survive a retry. A gate reading counts returned by the ingestion task loses
-- them when that worker dies after the rows are already committed; the next
-- attempt sees an empty feed and passes. Committed data is the durable record.

with loads as (

    select _dlt_load_id, 0 as is_quarantined
    from {{ source('tracking', 'scan_events') }}

    union all

    select _dlt_load_id, 1 as is_quarantined
    from {{ source('tracking', 'scan_events_quarantine') }}

)

select
    count(*) as rows_landed,
    sum(is_quarantined) as rows_quarantined
from loads
where _dlt_load_id = (select max(_dlt_load_id) from loads)
having sum(is_quarantined) > count(*) * {{ var('max_quarantine_rate') }}
