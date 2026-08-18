output "dataset_ids" {
  description = "Warehouse datasets by layer."
  value       = { for layer, dataset in google_bigquery_dataset.layer : layer => dataset.dataset_id }
}

output "ingestion_service_account" {
  description = "Service account the dlt pipeline authenticates as."
  value       = google_service_account.ingestion.email
}

output "transformation_service_account" {
  description = "Service account dbt authenticates as."
  value       = google_service_account.transformation.email
}

# The hand-off to dbt. A taxonomy with no column attached to it masks nothing,
# and columns are dbt's to own, so the deploy passes these through:
#
#   dbt build --target prod \
#     --vars "{policy_tag_recipient_pseudonymous: $(terraform output -raw policy_tag_recipient_pseudonymous)}"
output "policy_tag_recipient_pseudonymous" {
  description = "Policy tag dbt attaches to every column carrying a tracking number."
  value       = google_data_catalog_policy_tag.recipient_pseudonymous.name
}

output "policy_tag_recipient_identifying" {
  description = "Policy tag for directly identifying recipient attributes."
  value       = google_data_catalog_policy_tag.recipient_identifying.name
}
