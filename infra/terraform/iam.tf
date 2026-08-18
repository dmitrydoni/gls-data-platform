/**
 * Roles, not people. One service account per pipeline with least privilege,
 * human access through a group. No shared credentials, and every grant is
 * answerable here rather than in someone's memory of a console session.
 */

resource "google_service_account" "ingestion" {
  account_id   = "sa-dlt-ingestion-${var.environment}"
  display_name = "dlt ingestion pipeline"
  description  = "Writes landing tables. Has no access to modelled layers."
}

resource "google_service_account" "transformation" {
  account_id   = "sa-dbt-${var.environment}"
  display_name = "dbt transformation"
  description  = "Reads raw, writes core and marts."
}

# Ingestion writes raw and nothing else. If the loader is compromised it cannot
# reach the modelled layers the business reads.
resource "google_bigquery_dataset_iam_member" "ingestion_writes_raw" {
  dataset_id = google_bigquery_dataset.layer["raw"].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.ingestion.email}"
}

resource "google_bigquery_dataset_iam_member" "transformation_reads_raw" {
  dataset_id = google_bigquery_dataset.layer["raw"].dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.transformation.email}"
}

resource "google_bigquery_dataset_iam_member" "transformation_writes_modelled" {
  for_each = toset(["core", "marts"])

  dataset_id = google_bigquery_dataset.layer[each.key].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.transformation.email}"
}

# Attaching a policy tag to a column is `bigquery.tables.setCategory`, which
# Data Editor does not carry - it is a Data Owner permission. Granting Data
# Owner to get it would also hand the pipeline the right to delete the datasets
# it writes into, so the one permission is broken out into a custom role
# instead. Without this, dbt applies the column schema and fails on the tag,
# which is the failure mode where the models build and the masking silently
# never arrives.
resource "google_project_iam_custom_role" "policy_tag_attacher" {
  role_id     = "dbtPolicyTagAttacher${title(var.environment)}"
  title       = "dbt policy tag attacher (${var.environment})"
  description = "Attach and clear column policy tags. Not implied by dataEditor."
  permissions = ["bigquery.tables.setCategory"]
}

resource "google_project_iam_member" "transformation_attaches_tags" {
  project = var.project_id
  role    = google_project_iam_custom_role.policy_tag_attacher.id
  member  = "serviceAccount:${google_service_account.transformation.email}"
}

# Analysts read the modelled layers. They are deliberately not granted on raw:
# a landing table is a schema nobody has promised to keep stable.
resource "google_bigquery_dataset_iam_member" "analysts_read" {
  for_each = toset([
    for layer, config in local.layers : layer if config.analyst_reads
  ])

  dataset_id = google_bigquery_dataset.layer[each.key].dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "group:${var.analyst_group}"
}

# Every BigQuery statement runs as a job, and `bigquery.jobs.create` is a project
# permission that no dataset grant implies. Without this the pipeline accounts
# hold the right data access and still cannot execute: dbt cannot submit a query
# job, dlt cannot submit a load job.
resource "google_project_iam_member" "run_jobs" {
  for_each = toset([
    "group:${var.analyst_group}",
    "serviceAccount:${google_service_account.ingestion.email}",
    "serviceAccount:${google_service_account.transformation.email}",
  ])

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = each.key
}
