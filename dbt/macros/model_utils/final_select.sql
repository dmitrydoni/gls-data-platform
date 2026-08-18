{#-
    Closing select for every model. Appends the audit columns that make a row
    traceable back to the run that wrote it - which model, which invocation,
    when. Views skip the load timestamp because they carry no stored rows.
-#}

{% macro final_select(cte = 'final', updated_by = '@data-eng') -%}

    {%- set _path = model.path | replace('\\', '/') | replace('.sql', '') -%}
    {%- set _model_path = 'dwh:' ~ (_path | replace('/', ':')) -%}

select
    base.*,
    -- Audit fields
    {% if config.get('materialized') != 'view' -%}
    cast(current_timestamp as {{ dbt.type_timestamp() }}) as dbt_loaded_at,
    {%- endif %}
    cast('{{ updated_by }}' as {{ dbt.type_string() }}) as dbt_updated_by,
    cast('{{ _model_path }}' as {{ dbt.type_string() }}) as dbt_model_path,
    cast('{{ invocation_id }}' as {{ dbt.type_string() }}) as dbt_invocation_id
from {{ cte }} as base

{%- endmacro %}
