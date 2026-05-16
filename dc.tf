# ==================================================================================================
# Resolve Ubuntu 24.04 image from Oracle's image catalog
# Filtered by shape + OS version, sorted newest-first for deterministic resolution
# ==================================================================================================

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ==================================================================================================
# OCI Compute Instance: Ubuntu 24.04 for Samba-based mini-AD DC
# - Private subnet only (assign_public_ip = false)
# - NSG controls required AD/DC ports
# - user_data must be base64-encoded for OCI cloud-init
# ==================================================================================================

resource "oci_core_instance" "mini_ad_dc_instance" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_id
  shape               = var.instance_shape
  display_name        = "mini-ad-dc-${lower(var.netbios)}"

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  create_vnic_details {
    subnet_id        = var.subnet_ocid
    assign_public_ip = false
    nsg_ids          = [oci_core_network_security_group.ad_nsg.id]
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/scripts/mini-ad.sh.template", {
      HOSTNAME_DC        = "ad1"
      DNS_ZONE           = var.dns_zone
      REALM              = var.realm
      NETBIOS            = var.netbios
      ADMINISTRATOR_PASS = var.ad_admin_password
      ADMIN_USER_PASS    = var.ad_admin_password
      USERS_JSON         = local.effective_users_json
      BUCKET_NAME        = local.sentinel_bucket_name
      NAMESPACE          = data.oci_objectstorage_namespace.ns.namespace
    }))
  }
}

# ==================================================================================================
# Update VCN default DHCP options to direct instances to this DC for DNS resolution
# Conditional on dhcp_update; applied only after sentinel confirms DC bootstrap is complete
# ==================================================================================================

resource "null_resource" "wait_for_mini_ad" {
  depends_on = [
    oci_core_instance.mini_ad_dc_instance,
    oci_objectstorage_bucket.mini_ad_dc_sentinel,
    oci_identity_policy.mini_ad_dc_sentinel_write,
  ]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      TIMEOUT=900
      START=$(date +%s)
      echo "Waiting for mini-AD DC sentinel in bucket ${local.sentinel_bucket_name}..."
      until oci os object get \
        --namespace-name "${data.oci_objectstorage_namespace.ns.namespace}" \
        --bucket-name "${local.sentinel_bucket_name}" \
        --name "dc-ready" \
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

resource "oci_core_default_dhcp_options" "mini_ad_dns" {
  count = var.dhcp_update ? 1 : 0

  # Modifies the VCN's existing default DHCP options in-place
  manage_default_resource_id = var.vcn_default_dhcp_options_id

  options {
    type        = "DomainNameServer"
    server_type = "CustomDnsServer"
    custom_dns_servers = [oci_core_instance.mini_ad_dc_instance.private_ip]
  }

  options {
    type                = "SearchDomain"
    search_domain_names = [var.dns_zone]
  }

  depends_on = [null_resource.wait_for_mini_ad]
}

# ==================================================================================================
# Render seed users/groups JSON for DC bootstrap
# ==================================================================================================

locals {
  default_users_json = templatefile("${path.module}/scripts/users.json.template", {
    USER_BASE_DN      = var.user_base_dn
    DNS_ZONE          = var.dns_zone
    REALM             = var.realm
    NETBIOS           = var.netbios
    sysadmin_password = var.ad_admin_password
  })
}

locals {
  effective_users_json = coalesce(var.users_json, local.default_users_json)
}
