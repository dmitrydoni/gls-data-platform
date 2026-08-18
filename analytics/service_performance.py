"""Live operator and presentation interface for the GLS/NXT assessment.

The notebook is deliberately thin. It invokes the same Justfile recipe as the
CLI, reads the artifacts that recipe builds, and follows the assessment from
system purpose to implementation detail.
"""

import marimo

__generated_with = "0.20.4"
app = marimo.App(width="full")


@app.cell
def _():
    from pathlib import Path

    import duckdb
    import marimo as mo
    import plotly.express as px
    import polars as pl

    ROOT = Path(__file__).resolve().parent.parent
    DOCS = ROOT / "docs"
    DB = ROOT / "data" / "gls_platform.duckdb"

    INK = "#1F5F8B"
    PALETTE = {"express": "#1F5F8B", "standard": "#5B9BC7", "economy": "#A8C6DF"}

    def q(sql: str) -> pl.DataFrame:
        with duckdb.connect(str(DB), read_only=True) as con:
            return pl.from_arrow(con.execute(sql).arrow())

    def diagram(name: str, caption: str):
        path = DOCS / name
        if not path.exists():
            return mo.callout(
                mo.md(f"Diagram `{name}` is missing. Run `just docs-diagrams`."),
                kind="warn",
            )
        return mo.image(path.read_bytes(), alt=caption, width="100%", caption=caption)

    def styled(fig, height: int = 340):
        fig.update_layout(
            template="plotly_white",
            height=height,
            margin={"l": 10, "r": 10, "t": 52, "b": 10},
            title_font_size=15,
            font_family="Helvetica, Arial, sans-serif",
        )
        return fig

    return DB, INK, PALETTE, ROOT, diagram, mo, px, q, styled


@app.cell
def _(mo):
    run_demo = mo.ui.run_button(
        label="Run complete local prototype",
        kind="success",
        tooltip="Runs the same `just demo-build` contract used by the CLI.",
    )
    return (run_demo,)


@app.cell
def _(ROOT, run_demo):
    import subprocess

    build_result = None
    if run_demo.value:
        _process = subprocess.run(
            ["just", "demo-build"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        build_result = {
            "returncode": _process.returncode,
            "output": (_process.stdout + _process.stderr)[-16000:],
        }
    return (build_result,)


@app.cell
def _(DB, build_result, mo, run_demo):
    if build_result is None:
        _warehouse_state = "ready" if DB.exists() else "pending"
        _status = mo.callout(
            mo.md(
                f"**Local warehouse:** {_warehouse_state}. Build status appears after the first run."
            ),
            kind="info" if DB.exists() else "warn",
        )
        _log = mo.md("")
    else:
        _ok = build_result["returncode"] == 0
        _status = mo.callout(
            mo.md(
                "**Build passed.** The warehouse and tests completed."
                if _ok
                else f"**Build failed with exit {build_result['returncode']}.** Review the command output."
            ),
            kind="success" if _ok else "danger",
        )
        _log = mo.accordion({"Command output": mo.md(f"```text\n{build_result['output']}\n```")})

    operator_panel = mo.vstack(
        [
            mo.md(
                """
                ### Operate the prototype

                The button calls `just demo-build`: reset generated state, create
                deterministic EPCIS events, ingest them, build the dimensional
                warehouse, and run dbt tests. The `Justfile` owns the pipeline
                logic.

                The exported HTML is a presentation snapshot. Execution uses the
                live notebook via `just app-notebook`.
                """
            ),
            run_demo,
            _status,
            _log,
        ],
        gap=0.8,
    )
    return (operator_panel,)


@app.cell
def _(diagram, mo, operator_panel):
    overview = mo.vstack(
        [
            mo.md(
                """
                # GLS/NXT parcel analytics platform

                A target design for governed parcel analytics, backed by an
                executable local prototype. Operational sources land through a
                contract boundary, dbt produces conformed facts and dimensions,
                and governed metrics serve operations, analytics, and data
                science.

                **Review path:** functional architecture first, then the five
                assessment tasks in order. Target-state design and executed
                executed prototype are labelled separately.
                """
            ),
            diagram(
                "architecture.png",
                "C4-style container view. Solid paths are the primary flow; dashed elements are conditional.",
            ),
            mo.md(
                """
                | Concern | Target state | Prototype implementation |
                |---|---|---|
                | Ingestion | dlt batch lane; conditional Kafka consumer | REST-shaped API to dlt |
                | Storage | BigQuery raw, core, and marts | DuckDB schemas with the same layers |
                | Transformation | dbt Core on BigQuery | The dbt project executes locally |
                | Operation | Airflow scheduling, gates, and alerts | Shared `just demo-build` command |
                | Serving | Looker / LookML and governed SQL | Marimo output; LookML is source-only |
                | Infrastructure | Terraform-managed GCP controls | Configuration validated; deployment pending |
                """
            ),
            operator_panel,
        ],
        gap=1.0,
    )
    return (overview,)


@app.cell
def _(mo):
    task1 = mo.md(
        """
        ## 1. Scalable platform architecture

        ### Engineering stance

        | Principle | Applied here |
        |---|---|
        | Purpose and boundary first | The parcel analytics platform is the system of interest; operational sources, human consumers, and group systems form its environment. |
        | Function before construction | The flow is ingest, govern, model, and serve before it is mapped to products. |
        | Multiple views | Containers, runtime interactions, information structure, and parcel state are separate models. |
        | Close the feedback loop | Contract, freshness, and coverage failures return actionable context to an operator. |
        | State the truth condition | Every material claim is target state, executed prototype, or an assumption. |
        | Prefer reversible decisions | Batch, rebuild, and local-tool choices carry explicit replacement triggers. |

        This stance combines the data engineering lifecycle from Reis and
        Housley, system properties from Kleppmann, and grain-first dimensional
        design from Kimball and Ross.

        ### Functional responsibilities

        | Boundary | Responsibility | Owned control |
        |---|---|---|
        | Source services | Publish scans, parcel master data, and product events | Source schema and transport sequence |
        | dlt / stream consumer | Extract, normalize, validate, and load | Cursor, merge key, quarantine routing |
        | BigQuery raw | Preserve source-shaped and rejected records | Landing retention and replay horizon |
        | dbt Core | Conform, test, and document analytical data | Model schema, table layout, quality gates |
        | BigQuery core + marts | Publish stable facts, dimensions, and aggregates | Access, partitioning, clustering |
        | Looker | Define reusable measures and governed exploration | Metric semantics and audience access |
        | Airflow | Schedule work and expose failure state | Retries, freshness gate, SLA, alert context |

        ### Batch versus streaming

        The batch lane is the default. Kafka becomes justified by sustained
        throughput above 50k events/s, a genuine sub-minute consumer, or at least
        three independent consumers of the same stream. Until then, a scheduled
        incremental load is the smaller operational system.
        """
    )
    return (task1,)


@app.cell
def _(diagram, mo):
    task2 = mo.vstack(
        [
            mo.md(
                """
                ## 2. Pipeline design and orchestration

                The transport-owned `feedOffset` defines the feed cursor.
                Offline scanners may deliver an old event after the latest event
                already loaded. The cursor admits that event; merge on
                `event_id` makes replay converge.
                """
            ),
            diagram(
                "pipeline-sequence.png",
                "UML sequence: scheduled ingestion, durable load state, dbt gates, and operator feedback.",
            ),
            mo.md(
                '''
                **Executed source:** `src/sources/tracking_source.py`

                ```python
                @dlt.resource(selected=False)
                def scan_event_pages(
                    api_base_url: str = dlt.config.value,
                    feed_offset=dlt.sources.incremental(
                        "feedOffset", initial_value=INITIAL_FEED_OFFSET
                    ),
                ):
                    """Page the tracking API from the incremental watermark forward."""
                    params = {"per_page": PAGE_SIZE, "since_offset": feed_offset.last_value}
                    yield from _client(api_base_url, "events").paginate(
                        "/v1/scan-events", params=params
                    )
                ```

                | Condition | Detection | System response | Recovery |
                |---|---|---|---|
                | Duplicate or replay | Existing `event_id` | Merge converges | Idempotent retry |
                | Contract violation | Required field check | Route to quarantine | Correct producer; replay retained input |
                | Stale source | dbt source freshness | Fail before publishing | Restore source, then rerun |
                | Event outside lookback | Fact coverage test | Keep build red | `just dwh-backfill <start> <end>` |
                | Transient API failure | Task exception | Airflow retry with backoff | Alert after retry budget |

                Durable warehouse state is authoritative for quality gates and
                survives worker failure.
                '''
            ),
        ],
        gap=0.9,
    )
    return (task2,)


@app.cell
def _(diagram, mo):
    task3 = mo.vstack(
        [
            mo.md(
                """
                ## 3. Data modeling and warehousing

                Grain is declared before dimensions and measures.

                | Model | Pattern | Grain | Update policy |
                |---|---|---|---|
                | `fct_parcel_scan` | Transaction fact | One row per scan event | Daily microbatches; bounded lookback |
                | `fct_parcel_journey` | Accumulating snapshot | One row per parcel | Full rebuild from retained scans |
                | `mrt_service_performance_daily` | Periodic aggregate | Delivery date × depot × service level | Rebuilt downstream of journeys |

                Conformed dimensions are parcel, location, business step, date,
                and merchant. The transaction fact preserves events; the journey
                fact answers milestone and duration questions at one row per
                parcel.
                """
            ),
            diagram(
                "data-model.png",
                "Crow's-foot ERD: conformed dimensions, transaction fact, accumulating snapshot, and daily mart.",
            ),
            diagram(
                "parcel-lifecycle.png",
                "UML state model: parcel milestones and the repeat-delivery loop.",
            ),
            mo.md(
                """
                **Executed model:** `dbt/models/core/fct_parcel_scan.sql`

                ```sql
                {{ config(
                    materialized='incremental',
                    incremental_strategy='microbatch',
                    event_time='event_date',
                    batch_size='day',
                    lookback=var('scan_capture_lookback_days'),
                    begin=var('scan_history_begin'),
                    concurrent_batches=false,
                    on_schema_change='sync_all_columns',
                    labels={'domain': 'tracking', 'grain': 'parcel_scan'},
                    tags=['tracking', 'hourly']
                ) }}
                ```

                | Decision | Reason | Replacement trigger |
                |---|---|---|
                | Microbatch scan fact | Each event day is independently retryable | Adapter or volume requires a different batch strategy |
                | Rebuild journey fact | Parcel-master changes arrive independently of scans | Rebuild cost justifies a parcel-master snapshot and changed-key union |
                | Layout owned by dbt | dbt issues the table `CREATE` | Another engine becomes the sole table creator |
                | Raw retention defines replay | Retained input bounds reconstruction | Archive or longer replay SLA is funded |
                """
            ),
        ],
        gap=0.9,
    )
    return (task3,)


@app.cell
def _(DB, INK, PALETTE, build_result, mo, px, q, styled):
    _ = build_result
    if not DB.exists():
        _analytics = mo.callout(
            mo.md("Run the local prototype to materialize Task 4 analytical results."),
            kind="warn",
        )
    else:
        _k = q(
            """
            select
                count(*) as parcels,
                avg(case when is_on_time then 1.0 else 0.0 end) as on_time_rate,
                avg(case when is_first_attempt_success then 1.0 else 0.0 end) as first_attempt_rate,
                avg(case when has_exception then 1.0 else 0.0 end) as exception_rate,
                median(hub_dwell_hours) as median_dwell
            from core_dev.fct_parcel_journey
            where is_delivered
            """
        ).row(0, named=True)
        _stats = mo.hstack(
            [
                mo.stat(f"{_k['parcels']:,}", label="Delivered", bordered=True),
                mo.stat(f"{_k['on_time_rate']:.1%}", label="On-time", bordered=True),
                mo.stat(
                    f"{_k['first_attempt_rate']:.1%}",
                    label="First attempt",
                    bordered=True,
                ),
                mo.stat(f"{_k['exception_rate']:.1%}", label="Exceptions", bordered=True),
                mo.stat(f"{_k['median_dwell']:.1f} h", label="Median dwell", bordered=True),
            ],
            widths="equal",
            gap=0.5,
        )

        _by_service = q(
            """
            select
                service_level,
                avg(case when is_on_time then 1.0 else 0.0 end) as on_time_rate
            from core_dev.fct_parcel_journey
            where is_delivered
            group by service_level
            order by service_level
            """
        )
        _service_fig = styled(
            px.bar(
                _by_service,
                x="service_level",
                y="on_time_rate",
                color="service_level",
                color_discrete_map=PALETTE,
                text=[f"{value:.1%}" for value in _by_service["on_time_rate"]],
                labels={"on_time_rate": "On-time rate", "service_level": "Service level"},
                title="On-time delivery by service level",
            )
        )
        _service_fig.update_layout(showlegend=False, yaxis_tickformat=".0%")

        _daily = q(
            """
            select
                delivered_date,
                sum(parcels_on_time) * 1.0 / sum(parcels_delivered) as on_time_rate
            from marts_dev.mrt_service_performance_daily
            group by delivered_date
            having sum(parcels_delivered) >= 20
            order by delivered_date
            """
        )
        _daily_fig = styled(
            px.line(
                _daily,
                x="delivered_date",
                y="on_time_rate",
                markers=True,
                labels={"delivered_date": "Delivery date", "on_time_rate": "On-time rate"},
                title="Network on-time rate by delivery date",
            )
        )
        _daily_fig.update_traces(line_color=INK)
        _daily_fig.update_layout(yaxis_tickformat=".0%")

        _effect = q(
            """
            select
                hub_dwell_hours > 8 as long_dwell,
                count(*) as parcels,
                avg(case when is_on_time then 1.0 else 0.0 end) as on_time_rate
            from core_dev.fct_parcel_journey
            where service_level = 'express'
              and hub_dwell_hours is not null
              and is_delivered
            group by long_dwell
            order by long_dwell
            """
        )
        _short = _effect.filter(~_effect["long_dwell"]).row(0, named=True)
        _long = _effect.filter(_effect["long_dwell"]).row(0, named=True)

        _quality = q(
            """
            select
                (select count(*) from core_dev.fct_parcel_scan) as scans,
                (select count(*) from raw.scan_events_quarantine) as quarantined
            """
        ).row(0, named=True)
        _total = _quality["scans"] + _quality["quarantined"]

        _analytics = mo.vstack(
            [
                _stats,
                mo.hstack([_service_fig, _daily_fig], widths="equal", gap=0.8),
                mo.md(
                    f"""
                    **Traceable finding:** Express parcels with hub dwell above
                    eight hours are on time **{_long["on_time_rate"]:.1%}**
                    ({_long["parcels"]:,} parcels), versus
                    **{_short["on_time_rate"]:.1%}** below that threshold
                    ({_short["parcels"]:,} parcels).

                    | Quality check | Value |
                    |---|---:|
                    | Scan events modeled | {_quality["scans"]:,} |
                    | Records quarantined | {_quality["quarantined"]} ({_quality["quarantined"] / _total:.3%}) |
                    """
                ),
            ],
            gap=0.8,
        )

    task4 = mo.vstack(
        [
            mo.md(
                """
                ## 4. Visualization and business enablement

                Looker is the target semantic and exploration surface. Marimo is
                the prototype's operator and analytical interface. Both read the
                same modeled facts and marts, preserving one semantic definition.

                **Designed semantic layer:** `looker/views/parcel_journey.view.lkml`

                ```lookml
                measure: parcels_delivered {
                  label: "Parcels Delivered"
                  type: count_distinct
                  sql: ${journey__sk} ;;
                  filters: [is_delivered: "yes"]
                }

                measure: on_time_delivery_rate {
                  label: "On-Time Delivery Rate"
                  description: "Share of delivered parcels that met the contracted promise."
                  type: number
                  value_format_name: percent_1
                  sql: safe_divide(${parcels_on_time}, ${parcels_delivered}) ;;
                }
                ```
                """
            ),
            _analytics,
        ],
        gap=0.9,
    )
    return (task4,)


@app.cell
def _(mo):
    task5 = mo.md(
        """
        ## 5. Cross-cutting controls

        | Concern | Target-state control | Prototype implementation |
        |---|---|---|
        | Data contract | Versioned schema, required fields, compatibility policy | dlt column hints and quarantine fan-out |
        | Data quality | Ingestion, freshness, schema, business-rule, and anomaly layers | 97 passing dbt build resources and checks |
        | Security | Least privilege, policy tags, null masking, salted surrogate keys | Terraform and dbt configuration; deployment pending |
        | Retention | Partition expiry on landing time; replay horizon monitored | Partition hints and raw-history coverage test |
        | Lineage | Source-to-metric lineage in dbt and Looker | dbt graph, docs blocks, shared metric inputs |
        | CI/CD | Lint, parse, test, render, and infrastructure validation | Local commands mirror proposed pipeline gates |
        | Observability | Run state, freshness, failures, affected dates, and cost | Live command status; Airflow DAG designed only |
        | Ownership | Producer contract; platform controls; semantic owner | Responsibilities are explicit in Task 1 |

        ### Operating invariants

        1. A successful run means ingestion committed, freshness passed, models
           built, and tests passed.
        2. A control that must survive task failure reads durable state.
        3. A table's creator owns its schema and physical layout.
        4. Raw retention defines the replay horizon; an archive extends it.
        5. The prototype proves local behavior only. Cloud controls remain
           target-state configuration until deployed and queried.

        ### Implementation artifacts

        | Artifact | Purpose |
        |---|---|
        | `docs/proposal.pdf` | Standalone technical specification |
        | `analytics/service_performance.py` | Live guided interface |
        | `analytics/service_performance.html` | Static presentation snapshot |
        | `orchestration/dags/parcel_tracking_dag.py` | Target orchestration shape |
        | `infra/terraform/` | Target GCP controls |
        | `openspec/changes/gls-assessment-submission/` | Decisions, requirements, and verification record |
        """
    )
    return (task5,)


@app.cell
def _(mo, overview, task1, task2, task3, task4, task5):
    mo.ui.tabs(
        {
            "Overview": overview,
            "1 · Architecture": task1,
            "2 · Pipeline": task2,
            "3 · Data model": task3,
            "4 · Enablement": task4,
            "5 · Controls": task5,
        },
        value="Overview",
        orientation="vertical",
    )
    return


if __name__ == "__main__":
    app.run()
