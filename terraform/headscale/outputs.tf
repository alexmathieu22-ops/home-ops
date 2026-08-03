output "public_ip" {
  description = "Public IPv4 address of the Headscale VM"
  value       = oci_core_instance.headscale.public_ip
}

output "headscale_url" {
  description = "URL Headscale is served on"
  value       = "https://${var.headscale_subdomain}.${var.domain}"
}

output "ssh_command" {
  description = "Convenience SSH command"
  value       = "ssh ubuntu@${oci_core_instance.headscale.public_ip}"
}
