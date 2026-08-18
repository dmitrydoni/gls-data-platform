# Not deployed by the prototype - there is no Looker instance to run it in.
# Included so the semantic-layer argument in the proposal is concrete.
#
# The point of this file: every rate is defined once, as a measure over the
# additive counts, and never as an average of a pre-computed ratio. That single
# rule is what keeps "on-time delivery" meaning the same number in every
# dashboard, and it can only be enforced if the rate lives here rather than in
# each Look.

view: parcel_journey {
  sql_table_name: `gls_dwh.core_prod.fct_parcel_journey` ;;

  dimension: journey__sk {
    primary_key: yes
    hidden: yes
    type: string
    sql: ${TABLE}.journey__sk ;;
  }

  dimension: parcel_id {
    label: "Parcel ID"
    description: "UPU S10 item identifier."
    type: string
    sql: ${TABLE}.parcel_id ;;
  }

  dimension: service_level {
    label: "Service Level"
    type: string
    sql: ${TABLE}.service_level ;;
  }

  dimension_group: delivered {
    type: time
    timeframes: [raw, date, week, month, quarter, year]
    sql: ${TABLE}.delivered_ts ;;
  }

  dimension: is_delivered {
    type: yesno
    sql: ${TABLE}.is_delivered ;;
  }

  dimension: is_on_time {
    type: yesno
    sql: ${TABLE}.is_on_time ;;
  }

  dimension: is_first_attempt_success {
    type: yesno
    sql: ${TABLE}.is_first_attempt_success ;;
  }

  dimension: hub_dwell_hours {
    type: number
    value_format_name: decimal_1
    sql: ${TABLE}.hub_dwell_hours ;;
  }

  # --- Additive building blocks. Everything below is derived from these. ---

  measure: parcels_delivered {
    label: "Parcels Delivered"
    type: count_distinct
    sql: ${journey__sk} ;;
    filters: [is_delivered: "yes"]
  }

  measure: parcels_on_time {
    hidden: yes
    type: count_distinct
    sql: ${journey__sk} ;;
    filters: [is_delivered: "yes", is_on_time: "yes"]
  }

  measure: parcels_first_attempt {
    hidden: yes
    type: count_distinct
    sql: ${journey__sk} ;;
    filters: [is_delivered: "yes", is_first_attempt_success: "yes"]
  }

  # --- Rates. Ratios of the measures above, so they re-aggregate correctly at
  #     any grain a user drills to. Never an average of a stored rate. ---

  measure: on_time_delivery_rate {
    label: "On-Time Delivery Rate"
    description: "Share of delivered parcels that met the contracted promise."
    type: number
    value_format_name: percent_1
    sql: safe_divide(${parcels_on_time}, ${parcels_delivered}) ;;
  }

  measure: first_attempt_delivery_rate {
    label: "First-Attempt Delivery Rate"
    description: "Share delivered without a repeat attempt. Drives last-mile cost."
    type: number
    value_format_name: percent_1
    sql: safe_divide(${parcels_first_attempt}, ${parcels_delivered}) ;;
  }

  measure: avg_hub_dwell_hours {
    label: "Avg Hub Dwell (h)"
    type: average
    value_format_name: decimal_1
    sql: ${hub_dwell_hours} ;;
  }
}
