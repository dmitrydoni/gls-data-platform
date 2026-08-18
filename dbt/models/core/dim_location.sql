/*
    Type: Dimension (conformed)
    Grain: One row per network location (depot or hub), identified by GLN
    Business keys:
        - location_gln
    DWH keys:
        - location__sk
    Purpose:
        - Resolve every scan's `bizLocation` to a named facility, and separate
          hubs from depots so line-haul dwell can be measured apart from
          first- and last-mile handling
*/

with locations as (
    select * from {{ ref('stg_tracking__locations') }}
),

final as (

    select
        {{ surrogate_key(['location_gln']) }} as location__sk,
        location_gln,
        location_name,
        location_type,
        city,
        country,
        location_type = 'hub' as is_hub
    from locations

)

{{ final_select() }}
