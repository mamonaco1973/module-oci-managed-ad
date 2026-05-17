output "dns_server" {
  description = "Private IP address of the Windows AD DC, used as the DNS server for VCN clients."
  value       = oci_core_instance.windows_ad_dc_instance.private_ip
}

output "dc_public_ip" {
  description = "Public IP of the DC instance. Empty string when assign_public_ip is false."
  value       = oci_core_instance.windows_ad_dc_instance.public_ip
}
