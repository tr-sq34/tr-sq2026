output "internal_fqdn" {
  description = "Resolvable only from inside the container app environment."
  value       = azurerm_container_app.synapse.ingress[0].fqdn
}

# What the gateway must use for MATRIX_BASE_URL. The public hostname in
# homeserver.yaml (public_baseurl) is only what Synapse puts in the links it
# generates; nothing routes to it.
output "internal_base_url" {
  value = "https://${azurerm_container_app.synapse.ingress[0].fqdn}"
}

output "container_app_name" {
  value = azurerm_container_app.synapse.name
}

output "container_app_id" {
  value = azurerm_container_app.synapse.id
}

output "data_share_name" {
  value = azurerm_storage_share.data.name
}
