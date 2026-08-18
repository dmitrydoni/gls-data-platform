/**
 * Warehouse infrastructure for the GLS/NXT parcel analytics platform.
 *
 * Designed, not applied - there is no GCP project behind this. It is here
 * because "we use infrastructure as code" is a claim, and claims in an
 * assessment should be checkable. `terraform validate` and `terraform fmt`
 * pass; `terraform plan` would need credentials.
 *
 * The rule this encodes: if a dataset, a role binding, or a retention policy
 * was created in a console, it does not exist. Anything a person can click
 * into being is something nobody can review, reproduce, or safely delete.
 */

terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # State is remote and locked: two engineers running apply at once is a
  # recoverable annoyance with locking and a corrupted warehouse without it.
  #
  # The prefix is deliberately absent. A backend block cannot read variables, so
  # a hardcoded prefix is one state file shared by every environment - and the
  # first `init` in prod would load dev's state and plan the deletion of a
  # warehouse it never created. Supplied per environment at init:
  #
  #   terraform init -backend-config="prefix=data-platform/prod"
  backend "gcs" {
    bucket = "gls-nxt-tfstate"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
