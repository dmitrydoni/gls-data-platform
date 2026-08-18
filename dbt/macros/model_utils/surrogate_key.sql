{#-
    Deterministic surrogate key over the listed business-key columns.

    Salted with a deployment secret, because one business key is the masked
    tracking number: an unsalted digest is recomputable by anyone holding one,
    which reads back the journey the policy tag withholds.

    Nulls are coalesced to a sentinel before hashing so that a null component
    produces a stable key rather than a null one - otherwise a single missing
    attribute silently drops the row from every join it participates in.
-#}

{% macro surrogate_key(columns) -%}
    {%- set parts = ["'" ~ var('surrogate_key_salt') ~ "'"] -%}
    {%- for column in columns -%}
        {%- do parts.append("coalesce(cast(" ~ column ~ " as " ~ dbt.type_string() ~ "), '_null_')") -%}
    {%- endfor -%}
    md5({{ parts | join(" || '|' || ") }})
{%- endmacro %}
