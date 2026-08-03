data "oci_identity_availability_domains" "ads" {
  compartment_id = var.oci_tenancy_ocid
}

# Always-Free Ampere shape is arm64 -- image must match.
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.oci_compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04 Minimal aarch64"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "headscale" {
  compartment_id      = var.oci_compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name
  display_name        = "headscale"
  # Always-Free Ampere shape -- the full current allowance (Oracle halved this in 2026;
  # it used to be 4 OCPU / 24GB). Using it all on one instance since nothing else is
  # planned for this tenancy; split it if a second Always-Free instance is wanted later.
  shape = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
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
