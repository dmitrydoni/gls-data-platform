/*
    Type: Dimension (conformed)
    Grain: One row per calendar day the warehouse retains facts for
    Business keys:
        - date_day
    DWH keys:
        - date__sk
    Purpose:
        - Conformed date spine shared by every fact in the warehouse

    The lower bound is `scan_history_begin`, not the earliest date still in raw.
    Raw partitions expire; the facts built from them do not. Deriving the spine
    from what raw currently holds means the day a landing partition ages out,
    the calendar row for it disappears while every fact row still points at it -
    a referential break that arrives on a timer, months after the code that
    caused it, and shows up first as a failing relationship test.

    The upper bound is a year past today rather than the newest scan: a promise
    date can fall after the last event, and a spine that stops at the last scan
    would leave the fact pointing at a calendar row that does not exist yet.
*/

with spine as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="date '" ~ var('scan_history_begin') ~ "'",
        end_date=dbt.dateadd("year", 1, "current_date")
    ) }}

),

final as (

    select
        {{ surrogate_key(['cast(date_day as date)']) }} as date__sk,
        cast(date_day as date) as date_day,
        extract(year from date_day) as calendar_year,
        extract(quarter from date_day) as calendar_quarter,
        extract(month from date_day) as calendar_month,
        extract(week from date_day) as calendar_week,
        -- Counted from a known Monday, because every engine numbers its own
        -- weekdays differently and none of them agree on where the week starts.
        mod({{ dbt.datediff("date '1970-01-05'", 'date_day', 'day') }}, 7) as day_of_week,
        mod({{ dbt.datediff("date '1970-01-05'", 'date_day', 'day') }}, 7) >= 5 as is_weekend
    from spine

)

{{ final_select() }}
