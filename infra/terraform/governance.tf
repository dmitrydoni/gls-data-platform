/**
 * Column-level masking for the personal data a carrier unavoidably holds.
 *
 * A delivery address identifies a person, so parcel data is personal data. The
 * design keeps identifying attributes out of the event stream entirely - scan
 * events reference a parcel, never a recipient - which means erasure touches
 * one narrow table rather than the whole fact history.
 *
 * Policy tags cover the residual case: the same column returns a masked value
 * to an analyst and a real one to an authorised role, without maintaining two
 * copies of the table that will drift.
 *
 * Terraform gets the taxonomy, the tags and the masking rules; it does not get
 * the attachment. BigQuery masks a column only once a tag is on that column,
 * and columns belong to dbt here - so the tag names are exported and dbt binds
 * them in `_core_schema.yml`. Everything below is inert until it does.
 */

resource "google_data_catalog_taxonomy" "pii" {
  display_name = "parcel-pii-${var.environment}"
  region       = var.region
  description  = "Personal data classification for parcel recipient attributes."

  activated_policy_types = ["FINE_GRAINED_ACCESS_CONTROL"]
}

resource "google_data_catalog_policy_tag" "recipient_identifying" {
  taxonomy     = google_data_catalog_taxonomy.pii.id
  display_name = "recipient_identifying"
  description  = "Directly identifies a recipient: name, address, phone, email."
}

resource "google_data_catalog_policy_tag" "recipient_pseudonymous" {
  taxonomy     = google_data_catalog_taxonomy.pii.id
  display_name = "recipient_pseudonymous"

  # Pseudonymous identifiers are still personal data under GDPR - the
  # re-identification key exists. Treated as a child of the identifying tag so
  # a role granted the parent implicitly covers it.
  parent_policy_tag = google_data_catalog_policy_tag.recipient_identifying.id
  description       = "Stable surrogate for a recipient. Re-identifiable via the mapping table."
}

# The masking rules themselves. Without a data policy the tag only ever denies
# or fully allows; masking is what lets an analyst keep working on a column they
# must not read.
#
# One per tag, because a data policy binds to exactly one policy tag - a child
# tag inherits its parent's *access* grants, not its masking rule. Tagging the
# tracking number as pseudonymous and stopping there would have left it in the
# clear.
locals {
  masked_tags = {
    recipient_identifying  = google_data_catalog_policy_tag.recipient_identifying.name
    recipient_pseudonymous = google_data_catalog_policy_tag.recipient_pseudonymous.name
  }
}

resource "google_bigquery_datapolicy_data_policy" "masked" {
  for_each = local.masked_tags

  location         = var.region
  data_policy_id   = "${each.key}_masked"
  policy_tag       = each.value
  data_policy_type = "DATA_MASKING_POLICY"

  data_masking_policy {
    # Nulled rather than hashed. A tracking number is a short structured
    # identifier, so an unkeyed digest is recomputable by anyone holding one -
    # the masked column would read back the parcel it is meant to withhold.
    # Grouping and joining are served by the salted surrogate key, which is not
    # recomputable, so nulling the column costs the analyst nothing.
    predefined_expression = "ALWAYS_NULL"
  }
}

# Analysts get the *masked* reader role. `categoryFineGrainedReader` would grant
# the unmasked value - the opposite of the intent - so it is deliberately not
# used here and is reserved for the privileged role below.
# The pipeline that attaches the tags also has to read through them. dbt names
# the taxonomy to attach a tag, and every model downstream of a tagged column
# joins on the real value - so without these two grants the tags land and the
# next build fails on the columns it just classified. Masking is for the human
# audience; a transformation that reads masked keys produces a broken warehouse.
resource "google_data_catalog_taxonomy_iam_member" "transformation_reads_taxonomy" {
  taxonomy = google_data_catalog_taxonomy.pii.name
  role     = "roles/datacatalog.viewer"
  member   = "serviceAccount:${google_service_account.transformation.email}"
}

resource "google_data_catalog_policy_tag_iam_member" "transformation_reads_tagged" {
  for_each = local.masked_tags

  policy_tag = each.value
  role       = "roles/datacatalog.categoryFineGrainedReader"
  member     = "serviceAccount:${google_service_account.transformation.email}"
}

resource "google_bigquery_datapolicy_data_policy_iam_member" "analysts_masked" {
  for_each = google_bigquery_datapolicy_data_policy.masked

  location       = each.value.location
  data_policy_id = each.value.data_policy_id
  role           = "roles/bigquerydatapolicy.maskedReader"
  member         = "group:${var.analyst_group}"
}
