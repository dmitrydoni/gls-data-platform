/*
    Type: Dimension (conformed)
    Grain: One row per GS1 EPCIS business step and disposition pair
    Business keys:
        - (biz_step, disposition)
    DWH keys:
        - biz_step__sk
    Purpose:
        - Translate the EPCIS vocabulary into the carrier's operational language,
          and mark which pairs terminate a parcel's journey

    The pair is the grain, not the step alone: `holding` means a failed delivery
    attempt under one disposition and a return to sender under another, and the
    two carry opposite operational meaning.
*/

with reference as (
    select * from {{ ref('biz_step_reference') }}
),

final as (

    select
        {{ surrogate_key(['biz_step', 'disposition']) }} as biz_step__sk,
        biz_step,
        disposition,
        step_label,
        step_category,
        cast(is_terminal as boolean) as is_terminal,
        cast(step_sequence as {{ dbt.type_int() }}) as step_sequence
    from reference

)

{{ final_select() }}
