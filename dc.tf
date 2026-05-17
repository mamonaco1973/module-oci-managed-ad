# ==================================================================================================
# Resolve Windows Server 2022 image from Oracle's image catalog
# Filtered by shape + OS version, sorted newest-first for deterministic resolution
# ==================================================================================================

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

data "oci_core_images" "windows" {
  compartment_id           = var.compartment_id
  operating_system         = "Windows"
  operating_system_version = "Server 2022 Standard"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ==================================================================================================
# OCI Compute Instance: Windows Server 2022 for Windows AD DS Domain Controller
# - Private subnet only (assign_public_ip = false)
# - NSG controls required AD/DC ports
# - user_data must be base64-encoded for OCI cloudbase-init
# ==================================================================================================

resource "oci_core_instance" "ad_dc1_instance" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_id
  shape               = var.instance_shape
  display_name        = "ad-dc1-${lower(var.netbios)}"

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.windows.images[0].id
  }

  create_vnic_details {
    subnet_id        = var.subnet_ocid
    assign_public_ip = false
    nsg_ids          = [oci_core_network_security_group.ad_nsg.id]
  }

  metadata = {
    user_data = base64encode(templatefile("${path.module}/scripts/dc1.userdata.ps1.template", {
      DNS_ZONE                   = var.dns_zone
      NETBIOS                    = var.netbios
      ADMINISTRATOR_PASS         = var.administrator_password
      WINDOWS_LOCAL_ADMIN_PASS   = var.windows_local_admin_password
      # Sentinel script rendered with bucket/namespace and Admin password baked in,
      # then b64-encoded so it embeds safely as a single string in the PS1 template.
      SENTINEL_SCRIPT_B64 = base64encode(templatefile("${path.module}/scripts/dc1.sentinel.ps1.template", {
        NAMESPACE         = data.oci_objectstorage_namespace.ns.namespace
        BUCKET_NAME       = local.sentinel_bucket_name
        ADMIN_DOMAIN_PASS = var.admin_domain_password
        DNS_ZONE          = var.dns_zone
      }))
    }))
  }
}

# ==================================================================================================
# Poll for DC sentinel object — blocks DHCP update until DC signals it is ready
# DC writes "dc-ready" via a post-reboot scheduled task using instance principal auth
# ==================================================================================================

resource "null_resource" "wait_for_dc1" {
  depends_on = [
    oci_core_instance.ad_dc1_instance,
    oci_objectstorage_bucket.ad_dc_sentinel,
    oci_identity_policy.ad_dc_sentinel_write,
  ]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      TIMEOUT=3600
      START=$(date +%s)
      echo "Waiting for Windows AD DC sentinel in bucket ${local.sentinel_bucket_name}..."
      until oci os object get \
        --namespace-name "${data.oci_objectstorage_namespace.ns.namespace}" \
        --bucket-name "${local.sentinel_bucket_name}" \
        --name "dc1-ready" \
        --file /dev/null 2>/dev/null; do
        NOW=$(date +%s)
        ELAPSED=$((NOW - START))
        if [ $ELAPSED -ge $TIMEOUT ]; then
          echo "Timeout: DC sentinel not found after $${TIMEOUT}s" >&2
          exit 1
        fi
        echo "DC not ready ($${ELAPSED}s elapsed), retrying in 30s..."
        sleep 30
      done
      echo "DC sentinel found — bootstrap complete."
    EOT
  }
}

# ==================================================================================================
# Update VCN default DHCP options to direct instances to this DC for DNS resolution
# Conditional on dhcp_update; applied only after sentinel confirms DC bootstrap is complete
# ==================================================================================================

resource "oci_core_default_dhcp_options" "windows_ad_dns" {
  count = var.dhcp_update ? 1 : 0

  # Modifies the VCN's existing default DHCP options in-place
  manage_default_resource_id = var.vcn_default_dhcp_options_id

  options {
    type        = "DomainNameServer"
    server_type = "CustomDnsServer"
    custom_dns_servers = [oci_core_instance.ad_dc1_instance.private_ip]
  }

  options {
    type                = "SearchDomain"
    search_domain_names = [var.dns_zone]
  }

  depends_on = [null_resource.wait_for_dc1]
}
