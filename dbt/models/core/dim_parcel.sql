/*
    Type: Dimension (conformed)
    Grain: One row per parcel
    Business keys:
        - parcel_id (UPU S10 item identifier)
    DWH keys:
        - parcel__sk
        - merchant__fk
        - origin_location__fk
        - destination_location__fk
    Purpose:
        - Carry the parcel attributes declared at label creation, and the service
          promise every downstream punctuality measure is judged against
*/

with parcels as (
    select * from {{ ref('stg_tracking__parcels') }}
),

final as (

    select
        {{ surrogate_key(['parcel_id']) }} as parcel__sk,
        {{ surrogate_key(['merchant_id']) }} as merchant__fk,
        {{ surrogate_key(['origin_gln']) }} as origin_location__fk,
        {{ surrogate_key(['destination_gln']) }} as destination_location__fk,
        parcel_id,
        service_level,
        weight_kg,
        case
            when weight_kg < 2 then 'light'
            when weight_kg < 10 then 'medium'
            else 'heavy'
        end as weight_band,
        origin_gln,
        destination_gln,
        promised_delivery_ts
    from parcels

)

{{ final_select() }}
