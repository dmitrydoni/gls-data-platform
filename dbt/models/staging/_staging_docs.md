# Staging docs

Column prose lives here rather than in the schema files, so that a column keeps
one definition wherever it surfaces. Blocks prefixed `tracking__` describe source
concepts and are referenced from the core layer as well.

## Sources

{% docs src__tracking %}
Landing tables written by the dlt tracking pipeline: GS1 EPCIS scan events plus
the parcel and network master data they reference. Source-shaped, not a promised
interface - nothing outside the staging layer reads them.
{% enddocs %}

{% docs src__tracking__scan_events %}
One GS1 EPCIS ObjectEvent per parcel scan, contract-checked at load. Every row
here satisfied every column the warehouse declares required; the rows that did
not are in the quarantine table.
{% enddocs %}

{% docs src__tracking__scan_events_quarantine %}
Scan events rejected by the ingestion contract, retained with their original
payload so a source regression is visible and replayable rather than lost.
{% enddocs %}

{% docs src__tracking__parcels %}
Parcel master data as declared by the merchant at label creation.
{% enddocs %}

{% docs src__tracking__locations %}
Depot and hub network master data, keyed by GS1 Global Location Number.
{% enddocs %}

## Staging models

{% docs stg__tracking__scan_events %}
Typed, renamed scan events. One row per GS1 EPCIS ObjectEvent.
{% enddocs %}

{% docs stg__tracking__parcels %}
Parcel master data as declared at label creation. One row per parcel.
{% enddocs %}

{% docs stg__tracking__locations %}
Depot and hub network master data. One row per facility.
{% enddocs %}

{% docs stg__tracking__scan_events_quarantine %}
Scan events rejected by the ingestion contract. Retained rather than dropped, so
that a source regression is visible and replayable.
{% enddocs %}

## Tracking columns

{% docs tracking__event_id %}
The carrier's own event identifier, unique across the scan stream. Carried into
the fact as a degenerate dimension so a warehouse row can be traced back to the
scan that produced it.
{% enddocs %}

{% docs tracking__parcel_id %}
UPU S10 item identifier - two-letter service code, eight digits, ISO country
code. The business key every parcel-grain model joins on.
{% enddocs %}

{% docs tracking__event_ts %}
When the scan physically happened, in UTC. EPCIS `eventTime`.
{% enddocs %}

{% docs tracking__record_ts %}
When the tracking service accepted the scan, in UTC. EPCIS `recordTime`, and the
column the loader cursors on: a handheld that buffers while offline delivers an
old event today, and cursoring on `event_ts` would filter it out before it landed.
{% enddocs %}

{% docs tracking__biz_step %}
EPCIS business step - the *why* of the event. Commissioning, receiving,
departing, arriving, shipping, delivering, holding.
{% enddocs %}

{% docs tracking__disposition %}
EPCIS disposition - the parcel state the step left behind. Meaningful only
alongside the step, which is why the dimension is keyed on the pair.
{% enddocs %}

{% docs tracking__location_gln %}
GS1 Global Location Number of the facility where the scan was taken.
{% enddocs %}

{% docs tracking__merchant_id %}
Shipper that created the label.
{% enddocs %}

{% docs tracking__service_level %}
Contracted service - express, standard or economy. Sets the delivery promise
every punctuality measure is judged against.
{% enddocs %}

{% docs tracking__promised_delivery_ts %}
The service promise. Delivery at or before this timestamp is on time; everything
downstream that says "on time" means this comparison.
{% enddocs %}

{% docs tracking__weight_kg %}
Declared parcel weight, as given by the merchant rather than measured.
{% enddocs %}

{% docs tracking__location_type %}
Whether the facility is a line-haul hub or a spoke depot. Hubs are measured
separately because dwell there is where delay concentrates.
{% enddocs %}

{% docs tracking__quarantine_key %}
Event id where the payload had one, otherwise a digest of the payload. A row can
be quarantined precisely for lacking an event id, so the key cannot depend on it.
{% enddocs %}

{% docs tracking__violation %}
Which contract requirement the payload failed. One value per required column, so
a triager reads the cause rather than inferring it.
{% enddocs %}
