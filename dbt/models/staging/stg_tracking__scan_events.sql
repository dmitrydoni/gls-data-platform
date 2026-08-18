{#- `event_time` declares the model's time column so that a downstream microbatch
    model filters this ref to the batch it is building instead of scanning the
    whole view once per batch. -#}
{{ config(materialized='view', event_time='event_ts') }}

{#- Staging is a contract, so it names only columns the source contract
    declares. Fields the warehouse has never met still land - dlt adds the raw
    column on the next load - but propagating one before it is declared makes
    every downstream build depend on an optional field being present. -#}

with source as (
    select * from {{ source('tracking', 'scan_events') }}
),

final as (

    select
        event_id,
        parcel_id,
        cast(event_time as {{ dbt.type_timestamp() }}) as event_ts,
        cast(event_time as date) as event_date,
        -- When the tracking service accepted the scan, which is what the loader
        -- cursors on. The gap to event_ts is the capture lag.
        cast(record_time as {{ dbt.type_timestamp() }}) as record_ts,
        biz_step,
        disposition,
        location_gln,
        read_point,
        _dlt_load_id,
        _dlt_id
    from source

)

{{ final_select() }}
