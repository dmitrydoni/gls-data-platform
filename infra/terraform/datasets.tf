/**
 * One dataset per warehouse layer. The layer boundary is the trust boundary:
 * access is granted on datasets, never on individual tables, so a new model
 * inherits the right audience instead of needing a new grant.
 */

locals {
  layers = {
    raw = {
      description   = "Landing tables written by dlt. Source-shaped, not a promised interface."
      expiry_ms     = var.raw_partition_expiry_days * 24 * 60 * 60 * 1000
      analyst_reads = false
    }
    core = {
      description   = "Conformed dimensions and facts. The modelled trust boundary."
      expiry_ms     = null
      analyst_reads = true
    }
    marts = {
      description   = "Business-facing scorecards consumed by Looker."
      expiry_ms     = null
      analyst_reads = true
    }
  }
}

resource "google_bigquery_dataset" "layer" {
  for_each = local.layers

  dataset_id  = "${each.key}_${var.environment}"
  location    = var.region
  description = each.value.description

  # Raw partitions age out; modelled layers persist.
  #
  # This only reaches *partitioned* tables, which is why the dlt source hints
  # `landed_at` on every landing table, master data included - an unpartitioned
  # table inherits nothing and keeps source-shaped data forever while this line
  # suggests otherwise. The column is when the
  # warehouse stored the row, never when the source recorded it: BigQuery drops
  # rows written into an already-expired partition, so expiring on a source
  # timestamp would delete a historical replay the moment it arrived.
  #
  # `default_table_expiration_ms` is not the alternative. It would drop whole
  # tables on a timer, including dlt's own `_dlt_loads` and
  # `_dlt_pipeline_state`, and losing those loses the incremental watermark.
  default_partition_expiration_ms = each.value.expiry_ms

  labels = {
    layer       = each.key
    environment = var.environment
    managed_by  = "terraform"
  }

  # Deleting a dataset that still holds tables should require a deliberate act.
  delete_contents_on_destroy = false
}

/**
 * The scan fact's physical design - partitioning on event date, clustering on
 * parcel id and business step - is deliberately *not* declared here. It lives
 * in `dbt/models/core/fct_parcel_scan.sql`.
 *
 * The reason is not taste. Partitioning and clustering are properties of a
 * CREATE, and dbt issues the CREATE: a table Terraform pre-creates is replaced
 * by the first full build, taking its partition spec with it, and Terraform
 * then reports drift on a table it no longer describes. Declaring a table here
 * would also mean declaring its schema, which is the review bottleneck the
 * split exists to avoid. Ownership follows the writer.
 *
 * What Terraform owns is everything dbt does not create: the datasets above,
 * the IAM in `iam.tf`, the taxonomy and masking policies in `governance.tf`,
 * and the retention configured on this dataset.
 */
