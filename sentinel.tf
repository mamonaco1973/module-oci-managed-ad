# ==================================================================================================
# Object Storage sentinel bucket — DC writes "dc-ready" object on bootstrap completion
# Terraform polls for this object instead of blindly sleeping for 20 minutes
# ==================================================================================================

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_id
}

locals {
  sentinel_bucket_name = "ad-dc-sentinel-${lower(var.netbios)}"
}

resource "oci_objectstorage_bucket" "ad_dc_sentinel" {
  compartment_id = var.compartment_id
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = local.sentinel_bucket_name
  access_type    = "NoPublicAccess"
}

# Delete sentinel object before bucket destruction so the bucket destroy succeeds.
# self.triggers used because destroy provisioners cannot reference resource attributes directly.
resource "null_resource" "sentinel_cleanup" {
  triggers = {
    namespace   = data.oci_objectstorage_namespace.ns.namespace
    bucket_name = local.sentinel_bucket_name
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      oci os object delete \
        --namespace-name "${self.triggers.namespace}" \
        --bucket-name "${self.triggers.bucket_name}" \
        --name "dc1-ready" \
        --force 2>/dev/null || true
    EOT
  }

  depends_on = [oci_objectstorage_bucket.ad_dc_sentinel]
}
