# ==================================================================================================
# IAM: instance principal for the DC so it can write the boot sentinel to Object Storage
# Dynamic group is compartment-scoped to avoid circular dependency on instance OCID
# ==================================================================================================

resource "oci_identity_dynamic_group" "windows_ad_dc_dg" {
  # Dynamic groups must live in the root tenancy, not a child compartment
  compartment_id = var.tenancy_ocid
  name           = "windows-ad-dc-${lower(var.netbios)}-dg"
  description    = "DC instance principal — allows sentinel write to Object Storage at boot"
  matching_rule  = "instance.compartment.id = '${var.compartment_id}'"
}

resource "oci_identity_policy" "windows_ad_dc_sentinel_write" {
  compartment_id = var.compartment_id
  name           = "windows-ad-dc-${lower(var.netbios)}-sentinel-write"
  description    = "Allow DC instance to write boot sentinel object to Object Storage"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.windows_ad_dc_dg.name} to manage objects in compartment id ${var.compartment_id} where target.bucket.name = '${local.sentinel_bucket_name}'"
  ]

  depends_on = [oci_identity_dynamic_group.windows_ad_dc_dg]
}
