output "dns_server" {
  description = "Private IP of DC1 — primary DNS server for VCN clients."
  value       = oci_core_instance.ad_dc1_instance.private_ip
}

output "dc_public_ip" {
  description = "Public IP of DC1. Empty string when assign_public_ip is false."
  value       = oci_core_instance.ad_dc1_instance.public_ip
}

output "dc1_private_ip" {
  description = "Private IP of DC1."
  value       = oci_core_instance.ad_dc1_instance.private_ip
}

output "dc2_private_ip" {
  description = "Private IP of DC2."
  value       = oci_core_instance.ad_dc2_instance.private_ip
}
