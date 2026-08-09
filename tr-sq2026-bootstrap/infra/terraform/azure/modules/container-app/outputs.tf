output "container_app_fqdn" {
  value = azurerm_container_app.main.latest_revision_fqdn
}

output "container_app_id" {
  value = azurerm_container_app.main.id
}

# The stable hostname, unlike container_app_fqdn above, which points at one
# revision and therefore changes on every deploy. Anything wired into another
# app's configuration must use this one. Empty for apps with no ingress.
output "ingress_fqdn" {
  value = try(azurerm_container_app.main.ingress[0].fqdn, "")
}

output "base_url" {
  value = try("https://${azurerm_container_app.main.ingress[0].fqdn}", "")
}

output "managed_identity_client_id" {
  value = azurerm_user_assigned_identity.app.client_id
}

output "managed_identity_principal_id" {
  value = azurerm_user_assigned_identity.app.principal_id
}

output "container_app_environment_id" {
  value = local.container_app_environment_id
}
