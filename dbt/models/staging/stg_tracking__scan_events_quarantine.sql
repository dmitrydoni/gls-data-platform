{{ config(materialized='view') }}

with source as (
    select * from {{ source('tracking', 'scan_events_quarantine') }}
),

final as (

    select
        quarantine_key,
        event_id,
        cast(event_time as {{ dbt.type_timestamp() }}) as event_ts,
        violation,
        payload,
        _dlt_load_id,
        _dlt_id
    from source

)

{{ final_select() }}
