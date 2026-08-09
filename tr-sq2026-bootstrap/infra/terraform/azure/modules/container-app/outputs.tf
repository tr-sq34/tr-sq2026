output "container_app_fqdn" {
  value = azurerm_container_app.main.latest_revision_fqdn
}

output "container_app_id" {
  value = azurerm_container_app.main.id
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
