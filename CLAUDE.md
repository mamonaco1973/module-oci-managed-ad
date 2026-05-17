# module-oci-managed-ad

Terraform module deploying a two-DC Windows Server 2022 Active Directory environment on OCI.

## Architecture

- `dc.tf` — DC1 instance, sentinel poller (`wait_for_dc1`), DHCP update (waits for both DCs)
- `dc2.tf` — DC2 instance, sentinel poller (`wait_for_dc2`); does not start until dc1-ready
- `sentinel.tf` — shared OCI Object Storage bucket; DC1 writes `dc1-ready`, DC2 writes `dc2-ready`
- `roles.tf` — compartment-scoped dynamic group + IAM policy (covers both DCs automatically)
- `security.tf` — NSG with all required AD/DC port rules
- `scripts/dc1.userdata.ps1.template` — DC1 bootstrap: accounts, OpenSSH, OCI CLI, `Install-ADDSForest`
- `scripts/dc1.sentinel.ps1.template` — DC1 post-reboot: waits for ADWS, creates Admin account, writes dc1-ready, enables Windows Update
- `scripts/dc2.userdata.ps1.template` — DC2 bootstrap: same as DC1 but points DNS at DC1 and uses `Install-ADDSDomainController`
- `scripts/dc2.sentinel.ps1.template` — DC2 post-reboot: waits for ADWS, writes dc2-ready, enables Windows Update

## Key Design Decisions

### Sentinel pattern
Each DC writes a ready object (`dc1-ready`, `dc2-ready`) to a shared OCI Object Storage bucket
after AD is fully up. Terraform polls for each before updating DHCP. This is the only reliable
signal — AD promotion triggers a reboot and ADWS takes time to initialize after that.

### DC2 ordering
DC2's instance resource has `depends_on = [null_resource.wait_for_dc1]` — it does not boot
until DC1 is confirmed fully promoted. DC2 userdata sets DNS to DC1's IP before running
`Install-ADDSDomainController` so it can find the domain.

### DHCP update
Updated only after both sentinels are confirmed. Lists both DC IPs so clients get DNS
redundancy from the moment they first receive DHCP options.

### Base64 sub-template
`sentinel.ps1.template` is rendered by Terraform (with namespace, bucket, Admin password, DNS
zone baked in), base64-encoded, and passed as `SENTINEL_SCRIPT_B64` into `userdata.ps1.template`.
The userdata script decodes it at runtime and writes it to disk. This avoids needing a second
delivery mechanism for the post-reboot script.

### Dynamic group scoped to compartment
`roles.tf` uses a compartment-scoped matching rule instead of the instance OCID to avoid a
circular dependency (instance needs policy to exist; policy references instance OCID).

### Instance principal auth
The sentinel write uses `--auth instance_principal` — no credentials stored on the instance.
OCI CLI is installed before the promotion reboot so it is available when the sentinel task fires.

## Passwords

All admin account passwords use `override_special = "_-"`. These passwords are interpolated
directly into PowerShell template strings via `${}` — characters like `$`, `"`, and backticks
break the substitution or ConvertTo-SecureString.

Three separate passwords are required:
- `administrator_password` — built-in Windows Administrator, also used as DSRM password
- `admin_domain_password` — `Admin` domain admin account created post-promotion in sentinel
- `windows_local_admin_password` — local fallback account on the DC

## OpenSSH on Windows Server 2022

`Add-WindowsCapability` installs sshd with startup type `Disabled` on Server 2022.
Always call `Set-Service sshd -StartupType Automatic` **before** `Start-Service sshd`.

The default `sshd_config` has `PasswordAuthentication no` and a `Match Group administrators`
block that forces pubkey-only auth for admin accounts. Both must be patched before restarting
sshd or password-based SSH will be rejected at key exchange.

## OCI Quirks

- OCI Bastion rejects ECDSA keys — the bastion tunnel uses a temp RSA 4096 key.
- Windows Server does not run on ARM shapes (A1.Flex). Use `VM.Standard.E4.Flex` (x86).
- Always use `VM.Standard.E4.Flex` as the default shape — do not change to ARM.

## Windows Update

Disabled during provisioning to prevent download contention with OCI CLI install and AD
promotion. Re-enabled in each DC's sentinel script after AD is fully up, with a staggered
patch schedule: DC1 patches Tuesday 2AM (`dc1_patch_day = 3`), DC2 patches Wednesday 2AM
(`dc2_patch_day = 4`) — domain is never fully offline during patching.

## Logs

All bootstrap logs go to `C:\ProgramData\` — not `C:\Windows\Temp\`.
- `C:\ProgramData\dc1-userdata.log` — DC1 cloudbase-init bootstrap
- `C:\ProgramData\dc1-sentinel.log` — DC1 post-reboot sentinel task
- `C:\ProgramData\dc1-oci-install.log` — DC1 OCI CLI installer output
- `C:\ProgramData\dc2-userdata.log` — DC2 cloudbase-init bootstrap
- `C:\ProgramData\dc2-sentinel.log` — DC2 post-reboot sentinel task
- `C:\ProgramData\dc2-oci-install.log` — DC2 OCI CLI installer output
