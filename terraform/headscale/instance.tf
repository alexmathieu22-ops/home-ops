data "oci_identity_availability_domains" "ads" {
  compartment_id = var.oci_tenancy_ocid
}

# TEMPORARY: swapped from the Ampere A1 (arm64) Always-Free shape to the x86 micro
# Always-Free shape -- ca-montreal-1 has had zero Ampere A1 capacity across 500+ retries
# (see retry-apply.sh). E2.1.Micro is a separate Always-Free allowance (up to 2 instances,
# 1/8 OCPU + 1GB RAM each) that doesn't compete for the same scarce Ampere host capacity.
# Revert to VM.Standard.A1.Flex (see git history) once Ampere capacity is available again
# -- 1GB RAM is tight for Headscale + Caddy under any real load.
data "oci_core_images" "ubuntu" {
  compartment_id           = var.oci_compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04 Minimal"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "headscale" {
  compartment_id      = var.oci_compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name
  display_name        = "headscale"
  shape               = "VM.Standard.E2.1.Micro"
  # E2.1.Micro is a fixed shape -- no shape_config block (that's Flex-only). Fixed at
  # 1/8 OCPU / 1GB RAM.

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = 50
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.headscale.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
      headscale_fqdn    = "${var.headscale_subdomain}.${var.domain}"
      root_domain       = var.domain
      headscale_version = var.headscale_version
    }))
  }
}
