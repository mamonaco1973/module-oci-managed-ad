# ==================================================================================================
# Network Security Group: windows-ad-nsg
# OCI NSGs attach per-VNIC (instance-level), matching AWS Security Group semantics.
# NOTE: Open to all IPv4 (0.0.0.0/0) for simplicity — restrict in production.
# ==================================================================================================

resource "oci_core_network_security_group" "ad_nsg" {
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "windows-ad-nsg"
}

# -----------------------------------
# ICMP – ping and reachability testing
# -----------------------------------
resource "oci_core_network_security_group_security_rule" "icmp_ingress" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "1"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
}

# -----------------------------------
# DNS (TCP/UDP 53) – name resolution for clients and AD replication
# -----------------------------------
resource "oci_core_network_security_group_security_rule" "dns_tcp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 53
      max = 53
    }
  }
}

resource "oci_core_network_security_group_security_rule" "dns_udp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  udp_options {
    destination_port_range {
      min = 53
      max = 53
    }
  }
}

# -----------------------------------
# Kerberos Authentication (TCP/UDP 88)
# -----------------------------------
resource "oci_core_network_security_group_security_rule" "kerberos_tcp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 88
      max = 88
    }
  }
}

resource "oci_core_network_security_group_security_rule" "kerberos_udp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  udp_options {
    destination_port_range {
      min = 88
      max = 88
    }
  }
}

# -----------------------------------
# RPC Endpoint Mapper (TCP 135)
# -----------------------------------
resource "oci_core_network_security_group_security_rule" "rpc_tcp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 135
      max = 135
    }
  }
}

# -----------------------------------
# LDAP (TCP/UDP 389) – directory queries and updates
# -----------------------------------
resource "oci_core_network_security_group_security_rule" "ldap_tcp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 389
      max = 389
    }
  }
}

resource "oci_core_network_security_group_security_rule" "ldap_udp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  udp_options {
    destination_port_range {
      min = 389
      max = 389
    }
  }
}

# -----------------------------------
# SMB/CIFS (TCP 445) – AD SYSVOL and NETLOGON shares
# -----------------------------------
resource "oci_core_network_security_group_security_rule" "smb_tcp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 445
      max = 445
    }
  }
}

# -----------------------------------
# Kerberos Change/Set Password (TCP/UDP 464)
# -----------------------------------
resource "oci_core_network_security_group_security_rule" "kpasswd_tcp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 464
      max = 464
    }
  }
}

resource "oci_core_network_security_group_security_rule" "kpasswd_udp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  udp_options {
    destination_port_range {
      min = 464
      max = 464
    }
  }
}

# -----------------------------------
# LDAP over SSL (TCP 636)
# -----------------------------------
resource "oci_core_network_security_group_security_rule" "ldaps_tcp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 636
      max = 636
    }
  }
}

# -----------------------------------
# Global Catalog (TCP 3268/3269) – forest-wide directory searches
# -----------------------------------
resource "oci_core_network_security_group_security_rule" "gc_tcp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 3268
      max = 3269
    }
  }
}

# -----------------------------------
# SSH (TCP 22) – management access via bastion port-forward
# -----------------------------------
resource "oci_core_network_security_group_security_rule" "ssh_tcp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

# -----------------------------------
# RDP (TCP 3389) – management access via bastion port-forward
# -----------------------------------
resource "oci_core_network_security_group_security_rule" "rdp_tcp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 3389
      max = 3389
    }
  }
}

# -----------------------------------
# NTP (UDP 123) – time synchronization
# -----------------------------------
resource "oci_core_network_security_group_security_rule" "ntp_udp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  udp_options {
    destination_port_range {
      min = 123
      max = 123
    }
  }
}

# -----------------------------------
# Ephemeral RPC (TCP 49152–65535) – dynamic RPC communications
# -----------------------------------
resource "oci_core_network_security_group_security_rule" "rpc_ephemeral_tcp" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 49152
      max = 65535
    }
  }
}

# -----------------------------------
# Allow all outbound traffic
# -----------------------------------
resource "oci_core_network_security_group_security_rule" "egress_all" {
  network_security_group_id = oci_core_network_security_group.ad_nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}
