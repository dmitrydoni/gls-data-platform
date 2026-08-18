{#-
    Refuse to build on a warehouse with column-level access control when the
    salt was not supplied.

    `surrogate_key_salt` falls back to a value checked into this repository so a
    local DuckDB build is reproducible. That fallback reaching production would
    make every parcel key recomputable by anyone holding a tracking number,
    which reads back the journey the policy tag withholds - and the build would
    pass, because a weak key is still a valid one.

    The check is on the environment variable rather than the resolved var: the
    deployment error is the secret being absent, and testing for absence keeps
    the fallback value defined in one place.
-#}

{% macro assert_surrogate_key_salt_configured() -%}
    {%- if execute and target.type == 'bigquery' and not env_var('DBT_SURROGATE_KEY_SALT', '') -%}
        {{ exceptions.raise_compiler_error(
            "DBT_SURROGATE_KEY_SALT is unset - supply the deployment secret "
            ~ "before building on BigQuery. The local fallback is public."
        ) }}
    {%- endif -%}
{%- endmacro %}
