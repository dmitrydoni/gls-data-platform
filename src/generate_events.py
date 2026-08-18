"""Generate a deterministic GS1 EPCIS parcel scan event set.

Stands in for GLS/NXT's scan telemetry. Every parcel walks a realistic carrier
journey - commissioning at the merchant, collection, line-haul between depots via
a hub, then one or more delivery attempts - and each step emits an EPCIS
ObjectEvent answering what / when / where / why.

Deterministic: a fixed seed yields byte-identical output, so warehouse tests can
assert on exact counts.
"""

import json
import random
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

SEED = 20260816
PARCEL_COUNT = 4000
FIRST_LABEL_DAY = datetime(2026, 6, 1, tzinfo=UTC)
LABEL_DAY_SPAN = 60

# EPCIS separates `eventTime` - when the scan happened - from `recordTime` -
# when the capturing system accepted it. Handhelds normally upload within
# minutes, but a depot that loses connectivity buffers and replays hours or days
# later. That gap is why the loader cursors on record time; drawn from its own
# generator so adding it does not perturb the journeys.
CAPTURE_LAG_MINUTES = (1.0, 15.0)
OFFLINE_SCANNER_SHARE = 0.03
OFFLINE_LAG_HOURS = (6.0, 72.0)

# UPU S10 item identifiers use a two-letter service code, eight digits, a check
# digit, and an ISO country code. The check digit is omitted here; it carries no
# analytical meaning and computing it would only obscure the generator.
S10_SERVICE_CODE = "RR"
S10_COUNTRY = "DE"

# EPCIS event identifiers are vendor-assigned UUIDs. Keeping them that way here
# is a privacy property, not cosmetics: the tracking number is policy-tagged in
# the warehouse, so an event id that encoded it would hand analysts an unmasked
# copy of the identifier the tag exists to hide.
EVENT_ID_NAMESPACE = uuid.UUID("6f0d1f3a-9c1e-4a4b-8f2d-0b7a5c3e1d94")

DEPOTS = [
    # (GLN, name, type, city, country)
    ("4260001000019", "Berlin Sud", "depot", "Berlin", "DE"),
    ("4260001000026", "Hamburg Ost", "depot", "Hamburg", "DE"),
    ("4260001000033", "Munchen Nord", "depot", "Munchen", "DE"),
    ("4260001000040", "Koln West", "depot", "Koln", "DE"),
    ("4260001000057", "Frankfurt Sud", "depot", "Frankfurt", "DE"),
    ("4260001000064", "Leipzig Zentral", "hub", "Leipzig", "DE"),
    ("4260001000071", "Neuenstein Hub", "hub", "Neuenstein", "DE"),
    ("4260001000088", "Amsterdam Zuid", "depot", "Amsterdam", "NL"),
    ("4260001000095", "Wien Ost", "depot", "Wien", "AT"),
]
HUBS = [d for d in DEPOTS if d[2] == "hub"]
SPOKES = [d for d in DEPOTS if d[2] == "depot"]

MERCHANTS = [
    # (id, name, segment, tier)
    ("M-1001", "Nordlicht Versand", "fashion", "enterprise"),
    ("M-1002", "Radhaus Direkt", "sports", "mid_market"),
    ("M-1003", "Kuchenwerk", "home", "mid_market"),
    ("M-1004", "PixelParts", "electronics", "enterprise"),
    ("M-1005", "Blumen Sofort", "florist", "small_business"),
    ("M-1006", "Buchkontor", "media", "small_business"),
]

# service level -> (promised transit days, share of volume, line-haul speed factor)
# Express buys priority handling, not a different network: its parcels move
# through the same depots and hub on a shorter clock.
SERVICE_LEVELS = {
    "express": (1, 0.18, 0.55),
    "standard": (2, 0.64, 1.0),
    "economy": (4, 0.18, 1.15),
}

# Delivery rounds load before dawn. A parcel reaching the destination depot
# before this hour makes that morning's van; later arrivals wait a day.
VAN_LOAD_CUTOFF_HOUR = 6

BIZ_STEP_COMMISSIONING = "commissioning"
BIZ_STEP_RECEIVING = "receiving"
BIZ_STEP_DEPARTING = "departing"
BIZ_STEP_ARRIVING = "arriving"
BIZ_STEP_SHIPPING = "shipping"
BIZ_STEP_DELIVERING = "delivering"
BIZ_STEP_HOLDING = "holding"

DISP_ACTIVE = "active"
DISP_IN_PROGRESS = "in_progress"
DISP_IN_TRANSIT = "in_transit"
DISP_IN_POSSESSION = "in_possession"
DISP_NON_SELLABLE = "non_sellable_other"
DISP_RETURNED = "returned"


def _s10(sequence: int) -> str:
    return f"{S10_SERVICE_CODE}{sequence:08d}{S10_COUNTRY}"


def _event(
    event_id: str,
    parcel_id: str,
    occurred_at: datetime,
    recorded_at: datetime,
    biz_step: str,
    disposition: str,
    location: tuple[str, str, str, str, str],
    read_point: str,
) -> dict:
    """Shape one EPCIS ObjectEvent as the tracking API would return it."""
    return {
        "eventID": event_id,
        "eventType": "ObjectEvent",
        "action": "OBSERVE",
        "eventTime": occurred_at.isoformat(),
        "recordTime": recorded_at.isoformat(),
        "eventTimeZoneOffset": "+00:00",
        "epcList": [f"urn:epc:id:gsin:{parcel_id}"],
        "bizStep": f"urn:epcglobal:cbv:bizstep:{biz_step}",
        "disposition": f"urn:epcglobal:cbv:disp:{disposition}",
        "bizLocation": {"id": f"urn:epc:id:sgln:{location[0]}"},
        "readPoint": {"id": f"urn:epc:id:sgln:{location[0]}.{read_point}"},
    }


def _journey(rng: random.Random, lag_rng: random.Random, sequence: int) -> tuple[dict, list[dict]]:
    """Emit one parcel's master data and its ordered scan events."""
    parcel_id = _s10(sequence)
    merchant = rng.choice(MERCHANTS)
    service_level = rng.choices(
        list(SERVICE_LEVELS),
        weights=[share for _, share, _ in SERVICE_LEVELS.values()],
    )[0]
    promised_days, _, speed = SERVICE_LEVELS[service_level]

    origin, destination = rng.sample(SPOKES, 2)
    hub = rng.choice(HUBS)

    labelled_at = (
        FIRST_LABEL_DAY
        + timedelta(days=rng.randrange(LABEL_DAY_SPAN))
        + timedelta(hours=rng.randrange(8, 19), minutes=rng.randrange(60))
    )

    parcel = {
        "parcel_id": parcel_id,
        "merchant_id": merchant[0],
        "merchant_name": merchant[1],
        "merchant_segment": merchant[2],
        "merchant_tier": merchant[3],
        "service_level": service_level,
        "weight_kg": round(rng.uniform(0.2, 24.0), 2),
        "origin_gln": origin[0],
        "destination_gln": destination[0],
        "promised_delivery_at": (
            labelled_at.replace(hour=18, minute=0, second=0, microsecond=0)
            + timedelta(days=promised_days)
        ).isoformat(),
    }

    events: list[dict] = []
    step = 0

    def emit(occurred_at, biz_step, disposition, location, read_point):
        nonlocal step
        step += 1
        if lag_rng.random() < OFFLINE_SCANNER_SHARE:
            lag = timedelta(hours=lag_rng.uniform(*OFFLINE_LAG_HOURS))
        else:
            lag = timedelta(minutes=lag_rng.uniform(*CAPTURE_LAG_MINUTES))
        events.append(
            _event(
                str(uuid.uuid5(EVENT_ID_NAMESPACE, f"{sequence}:{step}")),
                parcel_id,
                occurred_at,
                occurred_at + lag,
                biz_step,
                disposition,
                location,
                read_point,
            )
        )

    now = labelled_at
    emit(now, BIZ_STEP_COMMISSIONING, DISP_ACTIVE, origin, "LABEL")

    # Collection from the merchant onto the origin depot's inbound dock.
    now += timedelta(hours=rng.uniform(1.5, 6.0) * speed)
    emit(now, BIZ_STEP_RECEIVING, DISP_IN_PROGRESS, origin, "DOCK-IN")

    now += timedelta(hours=rng.uniform(0.5, 3.0) * speed)
    emit(now, BIZ_STEP_DEPARTING, DISP_IN_TRANSIT, origin, "DOCK-OUT")

    # Line-haul through the hub. Hub dwell is where delay concentrates, so it
    # carries the long tail that makes the dwell metric worth looking at.
    now += timedelta(hours=rng.uniform(2.0, 6.0) * speed)
    emit(now, BIZ_STEP_ARRIVING, DISP_IN_TRANSIT, hub, "DOCK-IN")

    hub_dwell = rng.uniform(1.0, 4.0) if rng.random() > 0.12 else rng.uniform(8.0, 26.0)
    now += timedelta(hours=hub_dwell * speed)
    emit(now, BIZ_STEP_DEPARTING, DISP_IN_TRANSIT, hub, "DOCK-OUT")

    now += timedelta(hours=rng.uniform(2.0, 6.0) * speed)
    emit(now, BIZ_STEP_ARRIVING, DISP_IN_TRANSIT, destination, "DOCK-IN")

    # Delivery attempts. Most parcels land first time; the rest reattempt the
    # next working morning, and a small share exhaust attempts and go back.
    attempts = 0
    delivered = False
    while attempts < 3 and not delivered:
        attempts += 1
        # The clock only ever moves forward: a reattempt is always the following
        # day, and a first attempt waits a day unless the parcel beat the cutoff.
        days_ahead = 1 if attempts > 1 or now.hour >= VAN_LOAD_CUTOFF_HOUR else 0
        now = (now + timedelta(days=days_ahead)).replace(
            hour=rng.randrange(7, 10), minute=rng.randrange(60), second=0, microsecond=0
        )
        emit(now, BIZ_STEP_SHIPPING, DISP_IN_TRANSIT, destination, "VAN-LOAD")

        now += timedelta(hours=rng.uniform(1.0, 8.0))
        first_attempt_success = rng.random() < 0.87
        if first_attempt_success or attempts == 3:
            if rng.random() < 0.97 or attempts < 3:
                emit(now, BIZ_STEP_DELIVERING, DISP_IN_POSSESSION, destination, "DOORSTEP")
                delivered = True
            else:
                emit(now, BIZ_STEP_HOLDING, DISP_RETURNED, destination, "RETURNS")
        else:
            emit(now, BIZ_STEP_HOLDING, DISP_NON_SELLABLE, destination, "RETURNS")

    return parcel, events


def build_dataset() -> tuple[list[dict], list[dict]]:
    rng = random.Random(SEED)
    lag_rng = random.Random(SEED + 1)
    parcels: list[dict] = []
    events: list[dict] = []

    for sequence in range(1, PARCEL_COUNT + 1):
        parcel, parcel_events = _journey(rng, lag_rng, sequence)
        parcels.append(parcel)
        events.extend(parcel_events)

    # Five defects the platform must survive, injected deliberately so the
    # quality machinery is exercised rather than merely described:
    #   1. a duplicate delivery of an event the pipeline has already seen
    #   2. an event carrying fields the warehouse has never met, one scalar and
    #      one repeated, so both column-add and nested-table-add are exercised
    #   3. an event missing its identifier, which must be quarantined
    #   4. an event missing its business step, which must also be quarantined -
    #      the contract covers every column the warehouse declares required, not
    #      just the keys
    #   5. an event missing its record time - a column the warehouse requires
    #      and the transport does not, so it must be quarantined once and never
    #      re-served afterwards
    events.append(dict(events[10]))
    events.append(
        {
            **events[20],
            "eventID": f"{events[20]['eventID']}-X",
            "sensorTempC": 4.5,
            "sensorFlags": ["cold_chain"],
        }
    )
    events.append({**events[30], "eventID": f"{events[30]['eventID']}-Y", "epcList": []})
    events.append(
        {k: v for k, v in events[40].items() if k != "bizStep"}
        | {"eventID": f"{events[40]['eventID']}-Z"}
    )
    events.append(
        {k: v for k, v in events[50].items() if k != "recordTime"}
        | {"eventID": f"{events[50]['eventID']}-W"}
    )

    # Ordered by record time, because that is the order a tracking service
    # accepts scans in. An event with no record time sorts first; it was still
    # accepted, the service just cannot say when.
    events.sort(key=lambda event: (event.get("recordTime") or "", event["eventID"]))

    # The feed's own sequence number, stamped on acceptance and never revised.
    # This, not `recordTime`, is what extraction cursors on: a watermark the
    # payload owns is a watermark a malformed payload can be missing.
    for offset, event in enumerate(events, start=1):
        event["feedOffset"] = offset
    return parcels, events


def main() -> None:
    parcels, events = build_dataset()
    raw_dir = Path("data/raw")
    raw_dir.mkdir(parents=True, exist_ok=True)

    locations = [
        {"gln": gln, "name": name, "location_type": kind, "city": city, "country": country}
        for gln, name, kind, city, country in DEPOTS
    ]

    (raw_dir / "parcels.json").write_text(json.dumps(parcels, indent=2), encoding="utf-8")
    (raw_dir / "scan_events.json").write_text(json.dumps(events, indent=2), encoding="utf-8")
    (raw_dir / "locations.json").write_text(json.dumps(locations, indent=2), encoding="utf-8")

    print(f"parcels: {len(parcels)}")
    print(f"scan events: {len(events)}")
    print(f"locations: {len(locations)}")
    print(f"written to: {raw_dir}")


if __name__ == "__main__":
    main()
