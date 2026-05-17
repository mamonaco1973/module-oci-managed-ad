# ==================================================================================================
# Variables for module-oci-managed-ad
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
  description = "DNS zone for the Windows AD domain (e.g., mcloud.mikecloud.com)."
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

variable "instance_shape" {
  description = "OCI compute shape for the AD DC instance."
  type        = string
  # E4.Flex is x86 — Windows Server does not run on ARM (A1.Flex)
  default     = "VM.Standard.E4.Flex"
}

variable "instance_ocpus" {
  description = "Number of OCPUs for the AD DC instance (Flex shapes only)."
  type        = number
  default     = 2
}

variable "instance_memory_gb" {
  description = "Memory in GB for the AD DC instance (Flex shapes only)."
  type        = number
  default     = 8
}

variable "administrator_password" {
  description = "Password for the built-in Windows Administrator account and DSRM."
  type        = string
  sensitive   = true

  validation {
    condition     = !can(regex("^\\-", var.administrator_password))
    error_message = "The Administrator password cannot start with a dash (-)."
  }
}

variable "admin_domain_password" {
  description = "Password for the 'Admin' domain admin account created post-promotion."
  type        = string
  sensitive   = true

  validation {
    condition     = !can(regex("^\\-", var.admin_domain_password))
    error_message = "The Admin domain password cannot start with a dash (-)."
  }
}

variable "windows_local_admin_password" {
  description = "Password for the windows_local_admin local account on the DC."
  type        = string
  sensitive   = true

  validation {
    condition     = !can(regex("^\\-", var.windows_local_admin_password))
    error_message = "The windows_local_admin password cannot start with a dash (-)."
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

variable "dhcp_update" {
  description = "Update the VCN default DHCP options to point DNS at the DC."
  type        = bool
  default     = true
}


