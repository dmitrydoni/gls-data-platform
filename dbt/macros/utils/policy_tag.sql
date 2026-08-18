{#-
    Refuse to build on a warehouse with column-level access control when the
    policy tag is unset.

    An empty tag compiles to an untagged `parcel_id`: a dataset of readable
    tracking numbers that passes every test in this project. Empty is correct on
    a warehouse that has no such control - DuckDB here - so the guard is on the
    adapter, and it runs from `on-run-start` because schema YAML renders without
    access to project macros.
-#}

{% macro assert_policy_tag_configured() -%}
    {%- if execute and target.type == 'bigquery' and not var('policy_tag_recipient_pseudonymous') -%}
        {{ exceptions.raise_compiler_error(
            "policy_tag_recipient_pseudonymous is empty - pass the Terraform "
            ~ "output as DBT_POLICY_TAG before building on BigQuery."
        ) }}
    {%- endif -%}
{%- endmacro %}
