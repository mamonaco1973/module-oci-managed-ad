output "dns_server" {
  description = "Private IP address of the Windows AD DC, used as the DNS server for VCN clients."
  value       = oci_core_instance.windows_ad_dc_instance.private_ip
}
