# module-oci-managed-ad

Terraform module that deploys a **Windows Server 2022 Active Directory Domain Controller** on OCI.
Built for teams that need real Windows AD — not a managed directory service proxy — with full control
over domain configuration, group policy, POSIX attributes, and account lifecycle.

Suitable for production workloads. High availability via a secondary DC in a second availability
domain is supported via the `highly_available` flag (coming soon).

---

## Features

- Provisions a **Windows Server 2022 compute instance** (VM.Standard.E4.Flex) as a Domain Controller.
- Fully automates DC promotion via **cloudbase-init userdata** (`Install-ADDSForest`).
- Installs and configures **OpenSSH Server** on the DC with password authentication enabled.
- Creates three pre-configured accounts:
  - `Administrator` — built-in Windows account, password explicitly set, never expires.
  - `Admin` — domain admin account created post-promotion, added to Domain Admins.
  - `windows_local_admin` — local account on the DC for fallback access.
- Uses a **sentinel pattern** to signal bootstrap completion: the DC writes a `dc-ready` object to OCI Object Storage after AD services are fully up, blocking dependent resources until ready.
- Uses **instance principal auth** (OCI Dynamic Group + IAM policy) for the sentinel write — no credentials stored on the instance.
- Sets up an **OCI Network Security Group** with all required AD/DC firewall rules including SSH (22) and RDP (3389).
- Updates the **VCN default DHCP options** to direct DNS at the DC only after the sentinel confirms readiness.

---

## Module Structure

```
module-oci-managed-ad/
├── dc.tf               # DC instance, sentinel poller, DHCP update
├── sentinel.tf         # OCI Object Storage sentinel bucket
├── roles.tf            # Dynamic group + IAM policy for instance principal
├── security.tf         # OCI NSG and all AD/DC port rules
├── variables.tf        # Input variable definitions
├── outputs.tf          # Module outputs
└── scripts/
    ├── userdata.ps1.template   # DC bootstrap: roles, OpenSSH, OCI CLI, AD promotion
    └── sentinel.ps1.template  # Post-reboot: waits for ADWS, creates Admin account, writes sentinel
```

---

## How It Works

1. **Terraform renders `sentinel.ps1.template`** with the Object Storage namespace, bucket name, `Admin` domain password, and DNS zone baked in, then base64-encodes the result.
2. **Terraform renders `userdata.ps1.template`** with domain vars, account passwords, and the base64-encoded sentinel script embedded.
3. **cloudbase-init** runs the userdata on first boot:
   - Sets the `Administrator` password and creates `windows_local_admin`.
   - Installs AD DS role and OpenSSH Server (password auth enabled).
   - Installs OCI CLI.
   - Decodes and writes `sentinel.ps1` to disk, registers it as a startup scheduled task.
   - Calls `Install-ADDSForest` → triggers automatic reboot.
4. **Post-reboot**, the `WriteDCSentinel` scheduled task fires:
   - Waits for ADWS service (signals AD DS is fully initialized).
   - Creates the `Admin` domain account and adds it to Domain Admins.
   - Uploads `dc-ready` to Object Storage via instance principal.
   - Unregisters itself.
5. **Terraform** detects the sentinel and proceeds with the DHCP update.

---

## Usage Example

```hcl
module "windows_ad" {
  source = "github.com/mamonaco1973/module-oci-managed-ad"

  compartment_id = var.compartment_ocid
  tenancy_ocid   = var.tenancy_ocid

  # Domain identity
  netbios  = "MCLOUD"
  realm    = "MCLOUD.MIKECLOUD.COM"
  dns_zone = "mcloud.mikecloud.com"

  # Account passwords
  administrator_password       = random_password.administrator_password.result
  admin_domain_password        = random_password.admin_domain_password.result
  windows_local_admin_password = random_password.windows_local_admin_password.result

  # Networking
  vcn_id                      = oci_core_vcn.ad_vcn.id
  vcn_default_dhcp_options_id = oci_core_vcn.ad_vcn.default_dhcp_options_id
  subnet_ocid                 = oci_core_subnet.ad_subnet.id
}
```

---

## Parameters

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `compartment_id` | string | — | OCID of the OCI compartment to deploy into. |
| `tenancy_ocid` | string | — | OCID of the root tenancy — required for dynamic group creation. |
| `dns_zone` | string | — | DNS zone for the AD domain (e.g., `mcloud.mikecloud.com`). |
| `realm` | string | — | Kerberos realm (uppercase form of DNS zone). |
| `netbios` | string | — | NetBIOS short name for the domain. |
| `administrator_password` | string | — | Password for the built-in Administrator account and DSRM. *(Sensitive)* |
| `admin_domain_password` | string | — | Password for the `Admin` domain admin account. *(Sensitive)* |
| `windows_local_admin_password` | string | — | Password for the `windows_local_admin` local account on the DC. *(Sensitive)* |
| `vcn_id` | string | — | OCID of the VCN for NSG association. |
| `vcn_default_dhcp_options_id` | string | — | OCID of the VCN default DHCP options to update with the DC IP. |
| `subnet_ocid` | string | — | OCID of the private subnet for DC placement. |
| `instance_shape` | string | `VM.Standard.E4.Flex` | OCI compute shape. Must be x86 — Windows Server does not run on ARM. |
| `instance_ocpus` | number | `2` | OCPUs for the DC instance (Flex shapes only). |
| `instance_memory_gb` | number | `16` | Memory in GB for the DC instance (Flex shapes only). |
| `dhcp_update` | bool | `true` | Whether to update VCN default DHCP options to point DNS at the DC. |

---

## Outputs

| Name | Description |
|------|-------------|
| `dns_server` | Private IP of the Windows AD DC — use as DNS server and bastion session target. |

---

## Networking

- The DC is placed in a **private subnet** with no public IP.
- All AD traffic is controlled via an **OCI Network Security Group**.
- Management access is via **OCI Bastion Service** port-forwarding to port 22 (SSH) or 3389 (RDP).
- The DHCP update is gated on the sentinel — clients will not receive the DC as their DNS server until AD is fully up.

---

## Roadmap

- **High availability** — secondary DC in a second availability domain (`highly_available = true`), with DHCP pointing at both DCs for DNS failover.
- **OCI Vault integration** — store account passwords in Vault Secrets instead of Terraform state.

## Known Constraints

- Passwords are currently stored in Terraform state. Treat state as sensitive and restrict access accordingly.
- A single DC is a single point of failure for authentication. Use `highly_available = true` for production (coming soon).
