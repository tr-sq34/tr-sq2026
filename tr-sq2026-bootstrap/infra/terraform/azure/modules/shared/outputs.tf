output "resource_group_name" {
  value = azurerm_resource_group.turksquare.name
}

output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "aca_subnet_id" {
  value = azurerm_subnet.aca.id
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "acr_id" {
  value = azurerm_container_registry.main.id
}

output "key_vault_id" {
  value = azurerm_key_vault.main.id
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "application_insights_connection_string" {
  value     = azurerm_application_insights.main.connection_string
  sensitive = true
}

output "servicebus_namespace_id" {
  value = azurerm_servicebus_namespace.main.id
}

output "servicebus_namespace_name" {
  value = azurerm_servicebus_namespace.main.name
}

output "servicebus_connection_string" {
  value     = azurerm_servicebus_namespace_authorization_rule.root.primary_connection_string
  sensitive = true
}

output "postgresql_server_fqdn" {
  value = azurerm_postgresql_flexible_server.main.fqdn
}

# Every service and migration job builds its connection string from this. It
# has to come from here rather than from a variable: the server is set to this
# same value, so the two can never drift the way they did when the password was
# supplied by hand.
output "postgres_admin_password" {
  value     = random_password.postgres_admin.result
  sensitive = true
}

output "postgresql_server_id" {
  value = azurerm_postgresql_flexible_server.main.id
}

output "key_vault_secret_uri" {
  value = "${azurerm_key_vault.main.vault_uri}secrets/"
}

output "servicebus_connection_string_secret_uri" {
  value     = azurerm_key_vault_secret.service_bus_connection_string.versionless_id
  sensitive = true
}

output "storage_account_name" {
  value = azurerm_storage_account.media.name
}

output "storage_account_primary_access_key" {
  value     = azurerm_storage_account.media.primary_access_key
  sensitive = true
}

output "community_media_container_name" {
  value = azurerm_storage_container.community_media.name
}

output "verification_container_name" {
  value = azurerm_storage_container.verification.name
}

output "community_profile_projection_queue_name" {
  value = azurerm_servicebus_queue.community_profile_projection.name
}

output "verification_capability_queue_name" {
  value = azurerm_servicebus_queue.verification_capability.name
}

output "document_scan_queue_name" {
  value = azurerm_servicebus_queue.document_scan.name
}

output "messaging_projection_queue_name" {
  value = azurerm_servicebus_queue.messaging_projection.name
}

output "matrix_database_name" {
  value = azurerm_postgresql_flexible_server_database.matrix.name
}

output "storage_account_id" {
  value = azurerm_storage_account.media.id
}
