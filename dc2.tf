# ==================================================================================================
# OCI Compute Instance: Windows Server 2022 — Additional Domain Controller (DC2)
# - Different availability domain from DC1 for redundancy
# - Does not start until dc1-ready sentinel confirms DC1 is fully promoted
# - Uses Install-ADDSDomainController (join existing domain, not new forest)
# ==================================================================================================

resource "oci_core_instance" "ad_dc2_instance" {
  availability_domain = var.secondary_availability_domain != "" ? var.secondary_availability_domain : data.oci_identity_availability_domains.ads.availability_domains[
    min(1, length(data.oci_identity_availability_domains.ads.availability_domains) - 1)
  ].name
  compartment_id      = var.compartment_id
  shape               = var.instance_shape
  display_name        = "ad-dc2-${lower(var.netbios)}"

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.windows.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  create_vnic_details {
    subnet_id        = var.subnet_ocid
    assign_public_ip = false
    nsg_ids          = [oci_core_network_security_group.ad_nsg.id]
  }

  metadata = {
    user_data = base64encode(templatefile("${path.module}/scripts/dc2.userdata.ps1.template", {
      DNS_ZONE                 = var.dns_zone
      NETBIOS                  = var.netbios
      ADMINISTRATOR_PASS       = var.administrator_password
      WINDOWS_LOCAL_ADMIN_PASS = var.windows_local_admin_password
      ADMIN_DOMAIN_PASS        = var.admin_domain_password
      # DC1 IP injected so DC2 can point DNS at DC1 before promotion
      DC1_IP = oci_core_instance.ad_dc1_instance.private_ip
      SENTINEL_SCRIPT_B64 = base64encode(templatefile("${path.module}/scripts/dc2.sentinel.ps1.template", {
        NAMESPACE   = data.oci_objectstorage_namespace.ns.namespace
        BUCKET_NAME = local.sentinel_bucket_name
        DNS_ZONE    = var.dns_zone
        PATCH_DAY   = var.dc2_patch_day
      }))
    }))
  }

  # DC2 must not start until DC1 is fully promoted and responding
  depends_on = [null_resource.wait_for_dc1]
}

# ==================================================================================================
# Poll for DC2 sentinel object — blocks DHCP update until DC2 signals it is ready
# DC2 writes "dc2-ready" via a post-reboot scheduled task using instance principal auth
# ==================================================================================================

resource "null_resource" "wait_for_dc2" {
  depends_on = [
    oci_core_instance.ad_dc2_instance,
    oci_objectstorage_bucket.ad_dc_sentinel,
    oci_identity_policy.ad_dc_sentinel_write,
  ]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      TIMEOUT=3600
      START=$(date +%s)
      echo "Waiting for Windows AD DC2 sentinel in bucket ${local.sentinel_bucket_name}..."
      until oci os object get \
        --namespace-name "${data.oci_objectstorage_namespace.ns.namespace}" \
        --bucket-name "${local.sentinel_bucket_name}" \
        --name "dc2-ready" \
        --file /dev/null 2>/dev/null; do
        NOW=$(date +%s)
        ELAPSED=$((NOW - START))
        if [ $ELAPSED -ge $TIMEOUT ]; then
          echo "Timeout: DC2 sentinel not found after $${TIMEOUT}s" >&2
          exit 1
        fi
        echo "DC2 not ready ($${ELAPSED}s elapsed), retrying in 30s..."
        sleep 30
      done
      echo "DC2 sentinel found — bootstrap complete."
    EOT
  }
}
