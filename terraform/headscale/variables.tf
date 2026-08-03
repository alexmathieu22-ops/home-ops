variable "oci_tenancy_ocid" {
  description = "OCI tenancy OCID (Console -> profile menu -> Tenancy)"
  type        = string
}

variable "oci_user_ocid" {
  description = "OCI user OCID (Console -> profile menu -> User settings)"
  type        = string
}

variable "oci_fingerprint" {
  description = "Fingerprint of the API signing key added under the user's API Keys section"
  type        = string
}

variable "oci_private_key_path" {
  description = "Local path to the private key half of the OCI API signing key (never committed)"
  type        = string
}

variable "oci_region" {
  description = "OCI region, e.g. us-ashburn-1"
  type        = string
}

variable "oci_compartment_ocid" {
  description = "Compartment to create resources in (the tenancy's root compartment is fine for a single-VM personal setup)"
  type        = string
}

variable "availability_domain_index" {
  description = "Which of the region's availability domains (0-indexed) to place the instance in. Always-Free Ampere capacity is scarce -- if `tofu apply` fails with 'Out of host capacity', try a different index."
  type        = number
  default     = 0
}

variable "ssh_public_key" {
  description = "SSH public key installed for the `ubuntu` user"
  type        = string
}

variable "domain" {
  description = "Base domain (must be the Cloudflare zone already used elsewhere in this repo)"
  type        = string
  default     = "alexandremathieu.com"
}

variable "headscale_subdomain" {
  description = "Subdomain Headscale is served on, i.e. <headscale_subdomain>.<domain>"
  type        = string
  default     = "headscale"
}

variable "headscale_version" {
  description = "Headscale release to install (arm64 .deb) -- check https://github.com/juanfont/headscale/releases"
  type        = string
  default     = "0.29.3"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token, scoped to DNS edit on the zone -- reuse the same token stored in 1Password for cert-manager (docs/runbooks/cloudflare-setup.md), or a separate one scoped identically"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Zone ID for `domain`, from the Cloudflare dashboard's zone overview page"
  type        = string
}
