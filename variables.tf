# ==================================================================================================
# Variables for module-oci-mini-ad
# ==================================================================================================

variable "compartment_id" {
  description = "OCID of the OCI compartment to deploy resources into."
  type        = string
}

variable "tenancy_ocid" {
  description = "OCID of the root tenancy — required for dynamic group creation."
  type        = string
}

variable "dns_zone" {
  description = "DNS zone for the Samba AD domain (e.g., mcloud.mikecloud.com)."
  type        = string
}

variable "realm" {
  description = "Kerberos realm (typically uppercase form of DNS zone)."
  type        = string
}

variable "netbios" {
  description = "NetBIOS short name for the domain."
  type        = string
}

variable "user_base_dn" {
  description = "Base DN for user objects in LDAP (e.g., CN=Users,DC=mcloud,DC=mikecloud,DC=com)."
  type        = string
}

variable "instance_shape" {
  description = "OCI compute shape for the AD DC instance."
  type        = string
  # A1.Flex is always-free eligible (ARM); up to 4 OCPUs / 24 GB across all A1 instances
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "Number of OCPUs for the AD DC instance (Flex shapes only)."
  type        = number
  default     = 2
}

variable "instance_memory_gb" {
  description = "Memory in GB for the AD DC instance (Flex shapes only)."
  type        = number
  default     = 2
}

variable "ad_admin_password" {
  description = "Password for the AD Administrator account used in Samba bootstrap."
  type        = string
  sensitive   = true

  validation {
    condition     = !can(regex("^\\-", var.ad_admin_password))
    error_message = "The AD admin password cannot start with a dash (-)."
  }
}

variable "subnet_ocid" {
  description = "OCID of the subnet where the DC instance will be placed."
  type        = string
}

variable "vcn_id" {
  description = "OCID of the VCN for NSG association."
  type        = string
}

variable "vcn_default_dhcp_options_id" {
  description = "OCID of the VCN default DHCP options to update with DC DNS address."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key to authorize on the DC instance."
  type        = string
}

variable "users_json" {
  description = "Pre-rendered JSON string containing user account definitions."
  type        = string
  default     = ""
}

variable "dhcp_update" {
  description = "Update the VCN default DHCP options to point DNS at the DC."
  type        = bool
  default     = true
}
