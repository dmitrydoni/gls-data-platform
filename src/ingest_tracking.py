"""Load parcel tracking data from the API into the warehouse."""

from pathlib import Path

import dlt
from dlt.destinations import duckdb

from sources.tracking_source import tracking_source


def _destination():
    """DuckDB locally, the deployment's warehouse elsewhere - chosen by config.

    The orchestrator has to be able to point ingestion at the same warehouse the
    dbt build reads; a destination hardcoded here would make that impossible.
    """
    name = dlt.config["pipeline.destination"]
    if name != "duckdb":
        return name

    path = Path(dlt.config["pipeline.duckdb_path"])
    path.parent.mkdir(parents=True, exist_ok=True)
    return duckdb(str(path))


def run() -> None:
    """Load the tracking source. Safe to retry: merge converges."""
    pipeline = dlt.pipeline(
        pipeline_name=dlt.config["pipeline.pipeline_name"],
        destination=_destination(),
        dataset_name=dlt.config["pipeline.dataset_name"],
        dev_mode=False,
    )
    print(pipeline.run(tracking_source()))


if __name__ == "__main__":
    run()
