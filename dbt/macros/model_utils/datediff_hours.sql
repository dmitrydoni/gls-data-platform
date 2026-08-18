{#-
    Fractional hours between two timestamps.

    Built on dbt's cross-database `datediff` so the same model text compiles on
    DuckDB locally and BigQuery in production. Seconds are the unit of record
    because dwell and transit differences of a few minutes matter at parcel
    grain; the division to hours happens once, here.
-#}

{% macro datediff_hours(start_ts, end_ts) -%}
    ({{ dbt.datediff(start_ts, end_ts, 'second') }} / 3600.0)
{%- endmacro %}
