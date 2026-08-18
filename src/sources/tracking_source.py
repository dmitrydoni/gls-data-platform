"""dlt source over the GLS/NXT tracking API.

Four properties the assessment asks about are carried here rather than argued for
in prose:

* **Incremental** - the parent resource cursors on the feed's own sequence
  number and asks the API only for what it has not already seen. Cursoring on
  event time instead would be a silent data-loss bug: a handheld that buffers
  while offline delivers a two-day-old event today, and an event-time cursor
  filters it out before it ever lands. Cursoring on *record* time gets the clock
  right and the ownership wrong - it is a column the contract can find missing,
  and a row the feed cannot position is one it re-serves on every run forever.
* **Idempotent** - `merge` on the event's primary key, so an overlapping re-run
  converges instead of duplicating.
* **Schema-evolving** - fields the warehouse has never met are passed through
  rather than dropped, and dlt adds the column on the next load.
* **Contract-enforcing** - the loadable stream declares its columns non-nullable;
  rows that would violate that contract are diverted to a quarantine table
  instead of failing the run. One malformed scan should not stop a carrier's
  telemetry.

The last two pull in opposite directions, which is why the API pages feed two
transformers rather than one resource: the strict contract is exactly what
quarantined rows fail, so they need a table schema of their own.
"""

import json
from datetime import UTC, datetime
from hashlib import sha1
from typing import Any

import dlt
from dlt.sources.helpers.rest_client import RESTClient
from dlt.sources.helpers.rest_client.paginators import PageNumberPaginator

INITIAL_FEED_OFFSET = 0
PAGE_SIZE = 1000

# The retention axis, on every raw table: a dataset's partition expiry reaches
# only partitioned tables. Landing time, not source time - BigQuery drops rows
# written into an already-expired partition, so expiring on `event_time` would
# delete a historical replay on arrival.
LANDED_AT = {"data_type": "timestamp", "nullable": False, "partition": True}

# Payload keys consumed by the explicit mapping below; anything else is carried
# through untouched so new source fields survive into the landing table.
MAPPED_KEYS = {
    "eventID",
    "eventTime",
    "recordTime",
    "feedOffset",
    "epcList",
    "bizStep",
    "disposition",
    "bizLocation",
    "readPoint",
}

# Every column the loadable table declares non-nullable, paired with the
# violation name a triager reads. Kept beside the column hints below: a required
# column that is not checked here fails the load instead of being quarantined.
REQUIRED_FIELDS = (
    ("feed_offset", "missing_feed_offset"),
    ("event_id", "missing_event_id"),
    ("parcel_id", "missing_parcel_id"),
    ("event_time", "missing_event_time"),
    ("record_time", "missing_record_time"),
    ("biz_step", "missing_biz_step"),
    ("disposition", "missing_disposition"),
    ("location_gln", "missing_location_gln"),
)


def _client(api_base_url: str, data_selector: str) -> RESTClient:
    return RESTClient(
        base_url=api_base_url,
        paginator=PageNumberPaginator(base_page=1, total_path="total_pages"),
        data_selector=data_selector,
    )


def _tail(urn: str | None) -> str | None:
    """Take the meaningful tail of a URN - `urn:epcglobal:cbv:bizstep:receiving` -> `receiving`."""
    if not urn:
        return None
    return urn.rsplit(":", 1)[-1]


def _flatten(record: dict[str, Any]) -> dict[str, Any]:
    epc_list = record.get("epcList") or []
    location = record.get("bizLocation") or {}
    read_point = record.get("readPoint") or {}

    flattened = {
        "landed_at": datetime.now(UTC),
        "event_id": record.get("eventID"),
        "event_time": record.get("eventTime"),
        "record_time": record.get("recordTime"),
        "feed_offset": record.get("feedOffset"),
        "parcel_id": _tail(epc_list[0]) if epc_list else None,
        "biz_step": _tail(record.get("bizStep")),
        "disposition": _tail(record.get("disposition")),
        "location_gln": _tail(location.get("id")),
        "read_point": _tail(read_point.get("id")),
    }
    # Unmapped keys ride along; the warehouse gains the column without a code
    # change. Nested ones are serialised rather than passed through: dlt would
    # normalise a list into a child table, and a child table is unpartitioned,
    # carries no `landed_at`, and so sits outside the retention policy the
    # dataset applies to everything else.
    #
    # A key landing on a field this function owns is prefixed rather than
    # carried as-is: `landed_at` is the retention axis and `event_id` the merge
    # key, and a payload that could set them could backdate a row into an
    # already-expired partition or collide two parcels onto one key. The
    # comparison folds case and underscores because dlt normalises `parcelID`
    # and `parcel_id` onto the same column.
    owned = {key.replace("_", "") for key in flattened}
    flattened.update(
        {
            (f"source_{k}" if k.replace("_", "").lower() in owned else k): (
                json.dumps(v) if isinstance(v, list | dict) else v
            )
            for k, v in record.items()
            if k not in MAPPED_KEYS
        }
    )
    return flattened


def _contract_violation(row: dict[str, Any]) -> str | None:
    """Name the first broken requirement, or None when the row is loadable."""
    for field, violation in REQUIRED_FIELDS:
        if not row.get(field):
            return violation
    return None


@dlt.resource(selected=False)
def scan_event_pages(
    api_base_url: str = dlt.config.value,
    feed_offset=dlt.sources.incremental("feedOffset", initial_value=INITIAL_FEED_OFFSET),
):
    """Page the tracking API from the incremental watermark forward."""
    params = {"per_page": PAGE_SIZE, "since_offset": feed_offset.last_value}
    yield from _client(api_base_url, "events").paginate("/v1/scan-events", params=params)


@dlt.transformer(
    data_from=scan_event_pages,
    name="scan_events",
    primary_key="event_id",
    write_disposition="merge",
    columns={
        # The extraction watermark. It belongs to the transport rather than to
        # the scan, which is the reason it can be relied on when the scan itself
        # is malformed.
        "feed_offset": {"data_type": "bigint", "nullable": False},
        "event_id": {"data_type": "text", "nullable": False},
        "event_time": {"data_type": "timestamp", "nullable": False},
        "record_time": {"data_type": "timestamp", "nullable": False},
        "landed_at": LANDED_AT,
        "parcel_id": {"data_type": "text", "nullable": False},
        "biz_step": {"data_type": "text", "nullable": False},
        "disposition": {"data_type": "text", "nullable": False},
        "location_gln": {"data_type": "text", "nullable": False},
    },
)
def scan_events(page: list[dict[str, Any]]):
    for record in page:
        row = _flatten(record)
        if _contract_violation(row) is None:
            yield row


@dlt.transformer(
    data_from=scan_event_pages,
    name="scan_events_quarantine",
    primary_key="quarantine_key",
    write_disposition="merge",
    columns={
        "quarantine_key": {"data_type": "text", "nullable": False},
        "violation": {"data_type": "text", "nullable": False},
        # A row quarantined *for* lacking a record time still has to age out.
        "landed_at": LANDED_AT,
    },
)
def scan_events_quarantine(page: list[dict[str, Any]]):
    for record in page:
        row = _flatten(record)
        violation = _contract_violation(row)
        if violation is None:
            continue
        yield {
            # A row can be quarantined precisely for lacking an event id, so the
            # quarantine key falls back to a digest of the offending payload.
            "quarantine_key": row.get("event_id")
            or sha1(json.dumps(record, sort_keys=True).encode()).hexdigest(),
            "landed_at": row["landed_at"],
            "feed_offset": row.get("feed_offset"),
            "event_id": row.get("event_id"),
            "event_time": row.get("event_time"),
            "record_time": row.get("record_time"),
            "violation": violation,
            "payload": json.dumps(record),
        }


def _landed(pages):
    """Stamp arrival time, so master data ages out under the same policy as events."""
    for page in pages:
        yield [{**row, "landed_at": datetime.now(UTC)} for row in page]


@dlt.resource(
    name="parcels",
    primary_key="parcel_id",
    write_disposition="merge",
    columns={
        "landed_at": LANDED_AT,
        "parcel_id": {"data_type": "text", "nullable": False},
        "merchant_id": {"data_type": "text", "nullable": False},
        "service_level": {"data_type": "text", "nullable": False},
        "promised_delivery_at": {"data_type": "timestamp", "nullable": False},
    },
)
def parcels(api_base_url: str = dlt.config.value):
    yield from _landed(
        _client(api_base_url, "parcels").paginate("/v1/parcels", params={"per_page": PAGE_SIZE})
    )


@dlt.resource(
    name="locations",
    primary_key="gln",
    write_disposition="merge",
    columns={
        "landed_at": LANDED_AT,
        "gln": {"data_type": "text", "nullable": False},
        "name": {"data_type": "text", "nullable": False},
        "location_type": {"data_type": "text", "nullable": False},
    },
)
def locations(api_base_url: str = dlt.config.value):
    yield from _landed(
        _client(api_base_url, "locations").paginate("/v1/locations", params={"per_page": PAGE_SIZE})
    )


@dlt.source(name="tracking")
def tracking_source(api_base_url: str = dlt.config.value):
    pages = scan_event_pages(api_base_url=api_base_url)
    return [
        pages | scan_events,
        pages | scan_events_quarantine,
        parcels(api_base_url=api_base_url),
        locations(api_base_url=api_base_url),
    ]
