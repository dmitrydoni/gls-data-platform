# Core docs

Conformed dimensions and facts. Source-level column prose is not repeated here;
those blocks live in `models/staging/_staging_docs.md` and are referenced from
both layers.

## Models

{% docs core__dim_date %}
Conformed date dimension. One row per calendar day.
{% enddocs %}

{% docs core__dim_location %}
Conformed network location dimension. One row per depot or hub.
{% enddocs %}

{% docs core__dim_biz_step %}
Conformed EPCIS vocabulary dimension. One row per business step and disposition
pair, because the pair - not the step - carries the meaning: `holding` says
nothing until the disposition says whether the parcel was returned or is waiting.
{% enddocs %}

{% docs core__dim_merchant %}
Conformed merchant dimension. One row per shipper, Type 1 - merchant attributes
are corrections rather than history worth keeping.
{% enddocs %}

{% docs core__dim_parcel %}
Conformed parcel dimension. One row per parcel, carrying what the merchant
declared at label creation.
{% enddocs %}

{% docs core__fct_parcel_scan %}
Transaction fact. One row per parcel scan event - the event spine every
downstream milestone and service metric aggregates from. Built as microbatches
over the event day, so every column is a function of its own row.
{% enddocs %}

{% docs core__fct_parcel_journey %}
Accumulating snapshot. One row per parcel, revisited as each milestone lands,
carrying the durations between them and whether the promise was kept. This is
the fact type Kimball defines for a pipeline process with known milestones, and
it answers the questions the event grain answers badly: how long did it take,
was it on time, how many attempts did it need.
{% enddocs %}

## Keys

{% docs core__date__sk %}
Surrogate key over the calendar day.
{% enddocs %}

{% docs core__date__fk %}
Calendar day of the scan.
{% enddocs %}

{% docs core__date_day %}
The calendar day itself.
{% enddocs %}

{% docs core__location__sk %}
Surrogate key over the GLN.
{% enddocs %}

{% docs core__location__fk %}
Facility where the scan was taken.
{% enddocs %}

{% docs core__destination_location__fk %}
Depot responsible for final delivery.
{% enddocs %}

{% docs core__biz_step__sk %}
Surrogate key over the (biz_step, disposition) pair.
{% enddocs %}

{% docs core__biz_step__fk %}
EPCIS step and disposition pair the scan recorded.
{% enddocs %}

{% docs core__merchant__sk %}
Surrogate key over the merchant id.
{% enddocs %}

{% docs core__merchant__fk %}
Shipper that created the label.
{% enddocs %}

{% docs core__parcel__sk %}
Surrogate key over the S10 identifier.
{% enddocs %}

{% docs core__parcel__fk %}
Parcel the row refers to.
{% enddocs %}

{% docs core__scan__sk %}
Surrogate key over the carrier event id. Declares the grain of the scan fact.
{% enddocs %}

{% docs core__journey__sk %}
Surrogate key over the parcel. Declares the grain of the journey snapshot.
{% enddocs %}

{% docs core__delivered_date__fk %}
Calendar day of delivery. Null while the parcel is in flight - a null, not a
hash of one, so the key cannot orphan against the date dimension.
{% enddocs %}

## Attributes and measures

{% docs core__is_hub %}
True for line-haul hubs, which are measured separately from depots.
{% enddocs %}

{% docs core__step_category %}
Operational phase the step belongs to: origin, linehaul, delivery or exception.
{% enddocs %}

{% docs core__is_terminal %}
True where the step ends the parcel's journey.
{% enddocs %}

{% docs core__merchant_tier %}
Commercial tier, used to weight service breaches.
{% enddocs %}

{% docs core__capture_lag_hours %}
Gap between the scan happening and the tracking service accepting it. The
distribution of this column is what the ingestion lookback is tuned against, so
it is a measure rather than a diagnostic.
{% enddocs %}

{% docs core__total_transit_hours %}
Collection to delivery. Null while the parcel is in flight.
{% enddocs %}

{% docs core__hub_dwell_hours %}
Time held at the line-haul hub, where delay concentrates.
{% enddocs %}

{% docs core__delivery_attempts %}
Times the parcel went out for delivery.
{% enddocs %}

{% docs core__is_on_time %}
Delivered at or before the contracted promise.
{% enddocs %}

{% docs core__is_first_attempt_success %}
Delivered without a repeat attempt. The cost-driving measure: a second attempt is
a second van stop.
{% enddocs %}
