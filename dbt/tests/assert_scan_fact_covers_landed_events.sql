/*
    The coverage guarantee for the scan fact.

    A routine microbatch run rebuilds a bounded set of event days. A scan that
    the tracking service accepts today but that happened outside that window
    lands in raw and is never selected: the fact undercounts, the service
    scorecard reads slightly better than reality, and nothing anywhere says so.
    Capture lag is only visible on rows that made it in, so the fact cannot
    report its own omissions either.

    This test is what makes that impossible. Every event the loader landed
    inside the fact's declared horizon must be in the fact. When a late arrival
    falls outside the lookback the build goes red and names the events, and the
    repair is the bounded backfill (`just dwh-backfill <start> <end>`) rather
    than a full refresh.
*/

select landed.event_id
from {{ ref('stg_tracking__scan_events') }} landed
where
    landed.event_date >= date '{{ var('scan_history_begin') }}'
    and not exists (
        select 1
        from {{ ref('fct_parcel_scan') }} fct
        where landed.event_id = fct.event_id
    )
