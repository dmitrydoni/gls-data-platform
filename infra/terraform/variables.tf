variable "project_id" {
  description = "GCP project. One project per environment - a shared project with naming conventions eventually deletes the wrong table."
  type        = string
}

variable "region" {
  description = "Region for BigQuery datasets and the state bucket."
  type        = string
  default     = "europe-west3"
}

variable "environment" {
  description = "Environment name, suffixed onto every dataset."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "raw_partition_expiry_days" {
  description = <<-EOT
    Retention on raw landing partitions. Raw is retained long enough to rebuild
    a corrupted incremental model from source, and no longer - it holds
    source-shaped personal data nobody has promised to curate.

    This is therefore the replay horizon: raw has to hold every day between the
    warehouse's declared history floor (`scan_history_begin`) and the last day
    the fact publishes. When it stops doing so, `assert_raw_covers_history_floor`
    fails the build rather than letting a rebuild republish a shortened history.
  EOT
  type        = number
  default     = 90
}

variable "analyst_group" {
  description = "Google group granted read access to core and marts."
  type        = string
}
