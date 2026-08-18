"""Airflow DAG for the parcel tracking pipeline.

Not executed by the prototype - `just` sequences the local run. This is the
production shape the proposal argues for, kept in the repository so the
orchestration claims are concrete rather than described.

The design points worth noting:

* **The SLA is on the business milestone, not the task.** Operations cares that
  yesterday's service scorecard exists by 07:00, not that a particular task ran.
* **Ingestion retries; transformation does not retry blindly.** A failed dlt load
  is usually a transient API problem and worth retrying. A failed dbt test is a
  data problem, and retrying it just delays the alert.
* **Freshness gates the build.** Modelling stale data produces a scorecard that
  looks fine and is wrong, which is worse than no scorecard.
* **One environment per run.** Destination, landing dataset and dbt target are
  named once in `WAREHOUSE_ENV`. A loader configured separately from the build
  lands rows in one warehouse while the gate and the models read another, and
  every task still reports success. The two deployment secrets - `DBT_POLICY_TAG`
  from the Terraform output and `DBT_SURROGATE_KEY_SALT` - come from the worker
  environment rather than from here; a BigQuery build without the tag fails to
  compile rather than publishing unmasked tracking numbers.
* **Data-quality gates live in dbt, not in task return values.** The quarantine
  rate is asserted by `assert_quarantine_rate_within_bounds` over the newest load
  package. A gate fed by the ingestion task's XCom loses its input when that
  worker dies after committing rows and advancing the cursor - the retry sees an
  empty feed and passes the batch that should have failed.
* **Arrival and occurrence are different clocks.** The loader cursors on when a
  scan arrived; the warehouse rebuilds by when it happened. A backlog that lands
  today can be a week old, so the routine lookback is a bound rather than a
  guarantee - `assert_scan_fact_covers_landed_events` fails the build when a
  scan lands outside it, and the repair is `just dwh-backfill <start> <end>`.
  Deliberately a human-run repair: an automatic one would have to carry its own
  pending state across failed runs, and state that only lives in a task's return
  value is lost by the failure it exists to survive.
"""

from datetime import UTC, datetime, timedelta

from airflow.decorators import dag, task
from airflow.exceptions import AirflowFailException
from airflow.operators.bash import BashOperator
from airflow.providers.slack.notifications.slack import send_slack_notification

DBT_DIR = "/opt/airflow/dbt"
DBT_TARGET = "prod"
RAW_DATASET = f"raw_{DBT_TARGET}"

# The one warehouse this run addresses, named once and handed to every task.
# dlt reads it from the environment, dbt from `profiles.yml` and the source
# definition. `raw_prod` is what `infra/terraform/datasets.tf` provisions.
#
# The location is stated rather than defaulted: dlt's BigQuery client falls back
# to the `US` multi-region, and a load job cannot address a dataset in another
# location. It is the region Terraform builds the datasets in.
WAREHOUSE_ENV = {
    "PIPELINE__DESTINATION": "bigquery",
    "PIPELINE__DATASET_NAME": RAW_DATASET,
    "DESTINATION__BIGQUERY__LOCATION": "europe-west3",
    "RAW_DATASET": RAW_DATASET,
    "DBT_TARGET": DBT_TARGET,
}

default_args = {
    "owner": "data-engineering",
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "retry_exponential_backoff": True,
    "max_retry_delay": timedelta(minutes=30),
}


@dag(
    dag_id="parcel_tracking",
    description="GS1 EPCIS parcel scans into the dimensional warehouse",
    schedule="0 * * * *",
    start_date=datetime(2026, 6, 1, tzinfo=UTC),
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    tags=["tracking", "core"],
    on_failure_callback=[
        send_slack_notification(
            channel="#data-alerts",
            text=":rotating_light: `parcel_tracking` failed - {{ ti.log_url }}",
        )
    ],
)
def parcel_tracking():
    @task(retries=5)
    def ingest_scan_events() -> None:
        """Incremental, idempotent load. Safe to retry: merge converges."""
        import os

        from ingest_tracking import run

        os.environ.update(WAREHOUSE_ENV)
        run()

    @task(retries=0)
    def gate_on_freshness() -> None:
        """Stop before modelling if the source has gone stale.

        Deliberately a failure, not a short circuit. A short circuit marks the
        build *skipped*, which Airflow scores as a successful run: the DAG goes
        green, no callback fires, and the scorecard silently does not update.
        Stale input is an incident, so it has to be raised as one.
        """
        import os
        import subprocess

        result = subprocess.run(
            ["dbt", "source", "freshness", "--profiles-dir", ".", "--target", DBT_TARGET],
            cwd=DBT_DIR,
            env={**os.environ, **WAREHOUSE_ENV},
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise AirflowFailException(f"source freshness failed\n{result.stdout[-4000:]}")

    build_warehouse = BashOperator(
        task_id="build_warehouse",
        bash_command=f"cd {DBT_DIR} && dbt build --profiles-dir . --target {DBT_TARGET}",
        env=WAREHOUSE_ENV,
        append_env=True,
        retries=0,
        # Operations reads the scorecard at 07:00; miss that and someone is
        # making decisions on yesterday's picture.
        sla=timedelta(hours=2),
    )

    ingest_scan_events() >> gate_on_freshness() >> build_warehouse


parcel_tracking()
