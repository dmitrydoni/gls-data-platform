/*
    Type: Dimension (conformed)
    Grain: One row per merchant
    Business keys:
        - merchant_id
    DWH keys:
        - merchant__sk
    Purpose:
        - Attribute parcel service performance to the shipper, so account teams
          can see the experience their own customers receive

    Type 1: the merchant's most recently promised parcel carries the current
    attributes and overwrites. Selecting distinct combinations instead would emit
    one row per historical tier under a single surrogate key, so a routine
    account upgrade would fail the uniqueness test. Segment and tier do drift; a
    production build would snapshot this into a Type 2 dimension.
*/

with parcels as (
    select * from {{ ref('stg_tracking__parcels') }}
),

merchants as (

    select
        merchant_id,
        merchant_name,
        merchant_segment,
        merchant_tier,
        row_number() over (
            partition by merchant_id order by promised_delivery_ts desc
        ) as recency

    from parcels

),

final as (

    select
        {{ surrogate_key(['merchant_id']) }} as merchant__sk,
        merchant_id,
        merchant_name,
        merchant_segment,
        merchant_tier
    from merchants
    where recency = 1

)

{{ final_select() }}
