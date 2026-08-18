# Marts docs

Business-facing scorecards. The rate definitions here are the ones Looker
reproduces; if the two drift, this is the side that is right.

## Models

{% docs marts__mrt_service_performance_daily %}
Carrier service scorecard. One row per delivery date, destination depot and
service level. Counts are additive; rates are valid only at this grain and must
be recomputed from the counts when rolled up - averaging a stored rate over
depots of different size is the standard way this table gets misread.
{% enddocs %}

## Columns

{% docs marts__service_performance__sk %}
Surrogate key over the full grain. Declares uniqueness.
{% enddocs %}

{% docs marts__delivered_date %}
Delivery date the scorecard row covers.
{% enddocs %}

{% docs marts__parcels_delivered %}
Additive denominator for every rate on this row.
{% enddocs %}

{% docs marts__on_time_rate %}
Share delivered at or before the promise.
{% enddocs %}

{% docs marts__first_attempt_rate %}
Share delivered without a repeat attempt.
{% enddocs %}

{% docs marts__exception_rate %}
Share that hit at least one exception step.
{% enddocs %}
