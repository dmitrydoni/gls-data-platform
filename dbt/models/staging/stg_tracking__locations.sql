{{ config(materialized='view') }}

with source as (
    select * from {{ source('tracking', 'locations') }}
),

final as (

    select
        gln as location_gln,
        name as location_name,
        location_type,
        city,
        country,
        _dlt_load_id,
        _dlt_id
    from source

)

{{ final_select() }}
