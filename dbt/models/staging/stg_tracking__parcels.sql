{{ config(materialized='view') }}

with source as (
    select * from {{ source('tracking', 'parcels') }}
),

final as (

    select
        parcel_id,
        merchant_id,
        merchant_name,
        merchant_segment,
        merchant_tier,
        service_level,
        cast(weight_kg as {{ dbt.type_float() }}) as weight_kg,
        origin_gln,
        destination_gln,
        cast(promised_delivery_at as {{ dbt.type_timestamp() }}) as promised_delivery_ts,
        _dlt_load_id,
        _dlt_id
    from source

)

{{ final_select() }}
