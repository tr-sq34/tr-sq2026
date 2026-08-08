output "function_app_id" {
  value = azurerm_linux_function_app.main.id
}

output "function_app_default_hostname" {
  value = azurerm_linux_function_app.main.default_hostname
}

output "function_app_name" {
  value = azurerm_linux_function_app.main.name
}

output "managed_identity_client_id" {
  value = azurerm_user_assigned_identity.app.client_id
}

output "managed_identity_principal_id" {
  value = azurerm_user_assigned_identity.app.principal_id
}
