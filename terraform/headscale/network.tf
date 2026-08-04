resource "oci_core_vcn" "headscale" {
  compartment_id = var.oci_compartment_ocid
  display_name   = "headscale-vcn"
  cidr_blocks    = ["10.20.0.0/16"]
  dns_label      = "headscale"
}

resource "oci_core_internet_gateway" "headscale" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.headscale.id
  display_name   = "headscale-igw"
  enabled        = true
}

resource "oci_core_route_table" "headscale" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.headscale.id
  display_name   = "headscale-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.headscale.id
  }
}

resource "oci_core_security_list" "headscale" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.headscale.id
  display_name   = "headscale-sl"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol = "6" # TCP -- Let's Encrypt HTTP-01 challenge
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol = "6" # TCP -- Headscale control server (terminates TLS itself, no proxy)
    source   = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
  }

  ingress_security_rules {
    protocol = "17" # UDP -- embedded DERP relay (STUN)
    source   = "0.0.0.0/0"
    udp_options {
      min = 3478
      max = 3478
    }
  }

  # Tailscale client's default WireGuard port. Not strictly required (falls back to a
  # random port + DERP relay), but this VM is also an exit node, so a direct path here
  # matters for latency.
  ingress_security_rules {
    protocol = "17" # UDP
    source   = "0.0.0.0/0"
    udp_options {
      min = 41641
      max = 41641
    }
  }
}

resource "oci_core_subnet" "headscale" {
  compartment_id             = var.oci_compartment_ocid
  vcn_id                     = oci_core_vcn.headscale.id
  cidr_block                 = "10.20.0.0/24"
  display_name               = "headscale-subnet"
  dns_label                  = "hssub"
  route_table_id             = oci_core_route_table.headscale.id
  security_list_ids          = [oci_core_security_list.headscale.id]
  prohibit_public_ip_on_vnic = false
}
