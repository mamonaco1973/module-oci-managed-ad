# module-oci-managed-ad

Terraform module deploying a Windows Server 2022 Active Directory Domain Controller on OCI.

## Architecture

- `dc.tf` — DC instance, sentinel poller (`null_resource`), DHCP update
- `sentinel.tf` — OCI Object Storage bucket for the dc-ready bootstrap signal
- `roles.tf` — Dynamic group + IAM policy for instance principal auth
- `security.tf` — NSG with all required AD/DC port rules
- `scripts/userdata.ps1.template` — cloudbase-init bootstrap: accounts, OpenSSH, OCI CLI, AD promotion
- `scripts/sentinel.ps1.template` — post-reboot: waits for ADWS, creates Admin domain account, writes sentinel

## Key Design Decisions

### Sentinel pattern
The DC writes a `dc-ready` object to OCI Object Storage after AD is fully up. Terraform polls
for it in `null_resource.wait_for_windows_ad` before updating DHCP options. This is the only
reliable signal — AD promotion triggers a reboot and ADWS takes time to initialize after that.

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

## Logs

All bootstrap logs go to `C:\ProgramData\` — not `C:\Windows\Temp\`.
- `C:\ProgramData\dc1-userdata.log` — cloudbase-init bootstrap
- `C:\ProgramData\dc1-sentinel.log` — post-reboot sentinel task
- `C:\ProgramData\oci-install.log` — OCI CLI installer output
