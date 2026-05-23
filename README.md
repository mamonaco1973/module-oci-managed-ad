# module-oci-managed-ad

Terraform module that deploys a production-ready two-DC Windows Server 2022 Active Directory
environment on OCI. Both domain controllers are fully automated from zero — no manual steps,
no RDP required to bootstrap.

> **NOTE:** This module has only been tested running Terraform on a Linux host.

## What it deploys

| Resource | Count | Notes |
|---|---|---|
| OCI Compute Instance (Windows Server 2022) | 2 | DC1 and DC2, different availability domains |
| Network Security Group | 1 | All required AD/DC ports, shared by both DCs |
| Object Storage bucket | 1 | Sentinel coordination; logs uploaded post-boot |
| IAM Dynamic Group | 1 | Compartment-scoped; covers both DCs automatically |
| IAM Policy | 1 | Allows DCs to write sentinel objects via instance principal |
| OCI Core Default DHCP Options (optional) | 1 | Updated with both DC IPs after both sentinels confirm |

---

## Prerequisites

- OCI CLI configured locally (used by Terraform `local-exec` sentinel pollers)
- Bash available on the Terraform host (pollers use `bash -c`)
- The subnet must already exist; pass its OCID as `subnet_ocid`
- The VCN must already exist; pass its OCID as `vcn_id`
- If using `dhcp_update = true` (the default), pass the VCN default DHCP options OCID
  as `vcn_default_dhcp_options_id`

---

## Usage

```hcl
module "windows_ad" {
  source = "github.com/mamonaco1973/module-oci-managed-ad"

  # Identity
  compartment_id = var.compartment_id
  tenancy_ocid   = var.tenancy_ocid

  # Domain
  dns_zone = "corp.example.com"
  realm    = "CORP.EXAMPLE.COM"
  netbios  = "CORP"

  # Networking
  subnet_ocid                 = oci_core_subnet.private.id
  vcn_id                      = oci_core_vcn.main.id
  vcn_default_dhcp_options_id = oci_core_vcn.main.default_dhcp_options_id

  # Passwords — see Password Requirements below
  administrator_password       = random_password.administrator.result
  admin_domain_password        = random_password.admin_domain.result
  windows_local_admin_password = random_password.local_admin.result
}
```

### Outputs

| Name | Description |
|---|---|
| `dns_server` | Private IP of DC1 — primary DNS for VCN clients |
| `dc1_private_ip` | Private IP of DC1 |
| `dc2_private_ip` | Private IP of DC2 |

---

## Variables

### Required

| Variable | Type | Description |
|---|---|---|
| `compartment_id` | string | OCID of the compartment to deploy into |
| `tenancy_ocid` | string | Root tenancy OCID — required for dynamic group creation |
| `dns_zone` | string | AD domain name (e.g. `corp.example.com`) |
| `realm` | string | Kerberos realm — typically the uppercase domain (e.g. `CORP.EXAMPLE.COM`) |
| `netbios` | string | NetBIOS short name (e.g. `CORP`) |
| `subnet_ocid` | string | OCID of the subnet where DCs will be placed |
| `vcn_id` | string | OCID of the VCN for NSG association |
| `vcn_default_dhcp_options_id` | string | OCID of the VCN default DHCP options |
| `administrator_password` | string (sensitive) | Built-in Windows Administrator password; also used as DSRM password |
| `admin_domain_password` | string (sensitive) | Password for the `Admin` domain admin account created post-promotion |
| `windows_local_admin_password` | string (sensitive) | Password for the `windows_local_admin` local fallback account |

### Optional

| Variable | Type | Default | Description |
|---|---|---|---|
| `instance_shape` | string | `VM.Standard.E4.Flex` | OCI compute shape. Must be x86 — Windows Server does not run on ARM (A1.Flex) |
| `instance_ocpus` | number | `2` | OCPUs (Flex shapes only) |
| `instance_memory_gb` | number | `8` | Memory in GB (Flex shapes only) |
| `boot_volume_size_gb` | number | `64` | Boot volume size in GB |
| `dhcp_update` | bool | `true` | Update VCN default DHCP options to point DNS at both DCs |
| `primary_availability_domain` | string | `""` | Availability domain for DC1. Auto-picks `AD[0]` if empty |
| `secondary_availability_domain` | string | `""` | Availability domain for DC2. Auto-picks `AD[1]` if empty; falls back to `AD[0]` in single-AD regions |
| `dc1_patch_day` | number | `3` (Tuesday) | Windows Update install day for DC1 (1=Sun … 7=Sat) |
| `dc2_patch_day` | number | `4` (Wednesday) | Windows Update install day for DC2 |

---

## Password Requirements

All password variables are interpolated directly into PowerShell template strings using
`${}` syntax inside double-quoted strings. Certain characters break that substitution or
cause `ConvertTo-SecureString` to fail silently:

- `$` — treated as a PowerShell variable expansion, silently dropping it and the
  characters that follow until the next whitespace
- `"` — breaks the surrounding string literal
- `` ` `` — PowerShell escape character
- Leading `-` — rejected by `ConvertTo-SecureString`

**Recommended pattern** — generate 23 chars and prepend `"A"` via a local. This
guarantees the first character is always a known-safe uppercase letter (satisfying one
Windows complexity class), keeps the final length at 24, and eliminates the leading-dash
risk without relying on Terraform validation alone:

```hcl
# Admin account passwords — restrict specials to characters safe in PS1 templates
resource "random_password" "administrator_password" {
  length           = 23
  special          = true
  override_special = "_-"
}

resource "random_password" "admin_domain_password" {
  length           = 23
  special          = true
  override_special = "_-"
}

resource "random_password" "windows_local_admin_password" {
  length           = 23
  special          = true
  override_special = "_-"
}

locals {
  administrator_password       = "A${random_password.administrator_password.result}"
  admin_domain_password        = "A${random_password.admin_domain_password.result}"
  windows_local_admin_password = "A${random_password.windows_local_admin_password.result}"
}

module "windows_ad" {
  # ...
  administrator_password       = local.administrator_password
  admin_domain_password        = local.admin_domain_password
  windows_local_admin_password = local.windows_local_admin_password
}
```

For domain user passwords passed to `New-ADUser`, also exclude `$` from `override_special`:

```hcl
resource "random_password" "jsmith_password" {
  length           = 23
  special          = true
  override_special = "!@#%"   # $ excluded — breaks PS1 double-quoted interpolation
}

locals {
  jsmith_password = "A${random_password.jsmith_password.result}"
}
```

---

## Bootstrap Sequence

Terraform blocks until both DCs are fully promoted. The total time from `terraform apply`
to DHCP update is typically 45–60 minutes.

```
terraform apply
    │
    ├─► DC1 instance created
    │       cloudbase-init runs dc1.userdata.ps1.template
    │       ├── RDP + NLA enabled
    │       ├── Accounts set (Administrator, windows_local_admin)
    │       ├── OpenSSH installed and configured
    │       ├── AD-Domain-Services role installed
    │       ├── OCI CLI installed
    │       ├── Post-reboot sentinel task registered (WriteDC1Sentinel)
    │       └── Install-ADDSForest → automatic reboot
    │
    ├─► wait_for_dc1 polls Object Storage for "dc1-ready" (up to 60 min)
    │       Post-reboot: WriteDC1Sentinel fires
    │       ├── Waits for ADWS service
    │       ├── Creates Admin domain admin account
    │       ├── Writes "dc1-ready" sentinel object
    │       ├── Re-enables Windows Update (Tuesday 2AM)
    │       └── Uploads logs to sentinel bucket
    │
    ├─► DC2 instance created (depends on wait_for_dc1)
    │       cloudbase-init runs dc2.userdata.ps1.template
    │       ├── RDP + NLA enabled
    │       ├── Accounts set (Administrator, windows_local_admin)
    │       ├── OpenSSH installed and configured
    │       ├── AD-Domain-Services role installed
    │       ├── OCI CLI installed
    │       ├── DNS pointed at DC1 IP + connection-specific suffix set
    │       ├── Waits for DC1 LDAP (port 389) to be reachable
    │       ├── Post-reboot sentinel task registered (WriteDC2Sentinel)
    │       └── Install-ADDSDomainController → automatic reboot
    │
    ├─► wait_for_dc2 polls Object Storage for "dc2-ready" (up to 60 min)
    │       Post-reboot: WriteDC2Sentinel fires
    │       ├── Waits for ADWS service
    │       ├── Writes "dc2-ready" sentinel object
    │       ├── Re-enables Windows Update (Wednesday 2AM)
    │       └── Uploads logs to sentinel bucket
    │
    └─► DHCP options updated with DC1 and DC2 IPs (if dhcp_update = true)
```

---

## Sentinel Pattern

Each DC writes a zero-byte object to a private Object Storage bucket after AD is fully
initialized:

| Object | Written by | Signals |
|---|---|---|
| `dc1-ready` | DC1 post-reboot scheduled task | DC1 promoted, ADWS running, Admin account created |
| `dc2-ready` | DC2 post-reboot scheduled task | DC2 promoted, ADWS running |

Terraform polls for each object using `oci os object get` in a `local-exec` provisioner.
The pollers run on the machine executing `terraform apply` and require the OCI CLI and
credentials configured locally.

The sentinel bucket is also used for log delivery — each DC uploads its bootstrap logs
under `logs/` after sentinel write. This means you can retrieve DC logs without RDP or
bastion access:

```bash
oci os object get \
  --namespace-name <namespace> \
  --bucket-name ad-dc-sentinel-<netbios_lowercase> \
  --name logs/dc1-userdata.log \
  --file dc1-userdata.log
```

---

## Availability Domain Selection

DC1 and DC2 are placed in different availability domains for redundancy. The module
auto-picks:

- **DC1**: `AD[0]` (first AD in the region)
- **DC2**: `AD[1]` if available; falls back to `AD[0]` in single-AD regions

To override, specify the full AD name:

```hcl
primary_availability_domain   = "abc:US-ASHBURN-AD-1"
secondary_availability_domain = "abc:US-ASHBURN-AD-2"
```

Leave either variable empty to keep the auto-pick behavior for that DC.

---

## Windows Update Schedule

Windows Update is disabled during bootstrap to prevent download contention with
the OCI CLI installer and AD promotion. Each DC's sentinel script re-enables it
with a staggered schedule so both DCs are never patching simultaneously:

| DC | Default patch day | Variable |
|---|---|---|
| DC1 | Tuesday (3) at 2AM | `dc1_patch_day` |
| DC2 | Wednesday (4) at 2AM | `dc2_patch_day` |


---

## Network Security Group

The module creates a single NSG attached to both DCs with the following ingress rules
(source `0.0.0.0/0` — restrict to your subnet CIDR in production):

| Port(s) | Protocol | Purpose |
|---|---|---|
| ICMP | — | Ping and reachability |
| 22 | TCP | SSH (bastion port-forward) |
| 53 | TCP + UDP | DNS |
| 88 | TCP + UDP | Kerberos authentication |
| 123 | UDP | NTP time synchronization |
| 135 | TCP | RPC endpoint mapper |
| 389 | TCP + UDP | LDAP |
| 445 | TCP | SMB (SYSVOL, NETLOGON) |
| 464 | TCP + UDP | Kerberos change/set password |
| 636 | TCP | LDAP over SSL |
| 3268–3269 | TCP | Global Catalog |
| 3389 | TCP | RDP (bastion port-forward) |
| 49152–65535 | TCP | Dynamic RPC |

All outbound traffic is permitted.

---

## IAM — Instance Principal Auth

The DCs write sentinel objects using `--auth instance_principal` — no credentials are
stored on the instances. The module creates:

- A **dynamic group** matching all instances in the compartment
  (`instance.compartment.id = '<compartment_id>'`). Compartment-scoped matching avoids
  a circular dependency — a rule referencing instance OCIDs would require the instances
  to exist before the policy, but the policy must exist before the instances start
  executing.
- An **IAM policy** allowing that dynamic group to manage objects in the sentinel bucket
  only.

---

## Accounts

| Account | Type | Where | Purpose |
|---|---|---|---|
| `Administrator` | Local | Both DCs | Built-in Windows admin; also used as DSRM password |
| `windows_local_admin` | Local | Both DCs | RDP/SSH fallback if domain is unavailable |
| `Admin` | Domain | AD | Domain admin; created by DC1 sentinel post-promotion; used by clients to join the domain and create users |

The `Admin` account is created in the DC1 sentinel script (post-reboot), not during
initial bootstrap. It does not exist until DC1 has fully promoted and the `dc1-ready`
sentinel has been written.

---

## Logs

All bootstrap logs are written to `C:\ProgramData\` on each DC and uploaded to the
sentinel bucket after promotion:

| Log file | DC | Contents |
|---|---|---|
| `dc1-userdata.log` | DC1 | cloudbase-init bootstrap transcript |
| `dc1-sentinel.log` | DC1 | Post-reboot sentinel task transcript |
| `dc1-oci-install.log` | DC1 | OCI CLI installer output |
| `dc2-userdata.log` | DC2 | cloudbase-init bootstrap transcript |
| `dc2-sentinel.log` | DC2 | Post-reboot sentinel task transcript |
| `dc2-oci-install.log` | DC2 | OCI CLI installer output |

Retrieve any log from the sentinel bucket without connecting to the instance:

```bash
oci os object get \
  --namespace-name <namespace> \
  --bucket-name ad-dc-sentinel-<netbios_lowercase> \
  --name logs/<logfile> \
  --file <localpath>
```

---

## Known Quirks

**OCI Bastion rejects ECDSA keys.** Use RSA 4096 for any SSH key used with an OCI
Bastion session.

**Windows Server does not run on ARM.** The default shape is `VM.Standard.E4.Flex`
(x86). Do not change this to `VM.Standard.A1.Flex` — it will fail at instance creation.

**DC2 DNS suffix.** OCI DHCP assigns a search suffix (e.g. `example.com`) to all
instances. Without explicitly overriding the connection-specific DNS suffix on DC2,
FQDNs like `corp.example.com` get resolved as `corp.example.com.example.com`. The
DC2 userdata sets the connection-specific suffix to `dns_zone` before running
`Install-ADDSDomainController`.

**Dynamic group propagation lag.** OCI IAM policy changes can take up to 60 seconds
to propagate. The sentinel write in the post-reboot task will retry if the first
attempt fails with a permissions error.

**Single-AD regions.** If a region has only one availability domain, DC1 and DC2
will both land in `AD[0]`. The `secondary_availability_domain` auto-pick logic uses
`min(1, length(ads) - 1)` to handle this safely.
