# OCI Mini Active Directory Module

This Terraform module deploys a **lightweight Active Directory Domain Controller** on OCI using **Samba 4** on Ubuntu 24.04.
It is designed for **labs, demos, and development environments** where you need AD functionality without the overhead and cost of a managed directory service.

> **Note**: This module is not production-ready. It is intended for testing, prototyping, and training purposes.

---

## Features

- Provisions an **Ubuntu 24.04 compute instance** (ARM64, VM.Standard.A1.Flex) running Samba 4 as a Domain Controller.
- Configures **Active Directory, Kerberos, and Samba internal DNS**.
- Sets up an **OCI Network Security Group** with all required AD/DC firewall rules.
- Updates the **VCN default DHCP options** to direct DNS resolution through the DC.
- Uses a **user-data bootstrap script** (`mini-ad.sh.template`) to fully automate provisioning.
- Supports **seed users and groups** via `users.json.template`.
- Installs a **maxids systemd service** for UID/GID management via LDAP.

---

## Module Structure

- `dc.tf` — Domain Controller instance, DHCP update, and time_sleep gate
- `security.tf` — OCI Network Security Group and all AD/DC port rules
- `roles.tf` — (empty) DC bootstraps entirely from user_data; no instance principal needed
- `variables.tf` — Input variable definitions
- `outputs.tf` — Module outputs
- `scripts/mini-ad.sh.template` — Bootstrap script for Samba DC provisioning
- `scripts/users.json.template` — Default seed users and groups
- `scripts/maxids.py` — UID/GID LDAP query service
- `scripts/maxids.service` — systemd unit for maxids

---

## Usage Example

```hcl
module "mini_ad" {
  source = "github.com/mamonaco1973/module-oci-mini-ad"

  compartment_id = var.compartment_ocid

  # Domain identity
  netbios      = "MCLOUD"
  realm        = "MCLOUD.MIKECLOUD.COM"
  dns_zone     = "mcloud.mikecloud.com"
  user_base_dn = "CN=Users,DC=mcloud,DC=mikecloud,DC=com"

  # Authentication
  ad_admin_password = random_password.admin_password.result

  # Networking
  vcn_id                      = oci_core_vcn.vcn.id
  vcn_default_dhcp_options_id = oci_core_vcn.vcn.default_dhcp_options_id
  subnet_ocid                 = oci_core_subnet.private_subnet.id

  # SSH access
  ssh_public_key = tls_private_key.ssh.public_key_openssh
}
```

---

## Parameters

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `compartment_id` | string | — | OCID of the OCI compartment to deploy into. |
| `dns_zone` | string | — | DNS zone for the Samba AD domain (e.g., `mcloud.mikecloud.com`). |
| `realm` | string | — | Kerberos realm (uppercase form of DNS zone). |
| `netbios` | string | — | NetBIOS short name for the domain. |
| `user_base_dn` | string | — | Base DN for user objects in LDAP. |
| `ad_admin_password` | string | — | Password for the AD Administrator account. *(Sensitive)* |
| `vcn_id` | string | — | OCID of the VCN for NSG association. |
| `vcn_default_dhcp_options_id` | string | — | OCID of the VCN default DHCP options to update with the DC IP. |
| `subnet_ocid` | string | — | OCID of the private subnet for DC placement. |
| `ssh_public_key` | string | — | SSH public key to authorize on the DC instance. |
| `users_json` | string | `""` | Pre-rendered JSON string of seed users/groups (uses default template if empty). |
| `instance_shape` | string | `VM.Standard.A1.Flex` | OCI compute shape. A1.Flex is always-free eligible. |
| `instance_ocpus` | number | `2` | OCPUs for the DC instance (Flex shapes only). |
| `instance_memory_gb` | number | `2` | Memory in GB for the DC instance (Flex shapes only). |
| `dhcp_update` | bool | `true` | Whether to update VCN default DHCP options to point DNS at the DC. |

---

## Outputs

| Name | Description |
|------|-------------|
| `dns_server` | Private IP of the AD DC — use as DNS server and bastion session target. |

---

## Networking Notes

- The DC is placed in a **private subnet** with no public IP.
- All AD traffic is controlled via an **OCI Network Security Group** (not a Security List).
- The VCN default DHCP options are updated in-place after a 10-minute delay to ensure the DC is fully provisioned before client instances receive its IP as their DNS server.
- Access for management is via **OCI Bastion Service** (port-forwarding session to port 22).

---

## Limitations

- Single domain controller — no high availability.
- Not suitable for production workloads.
- Passwords are stored in Terraform state (no OCI Vault integration).
