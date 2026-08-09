output "resource_group_name" {
  value = module.shared.resource_group_name
}

output "acr_login_server" {
  value = module.shared.acr_login_server
}

output "key_vault_name" {
  value = module.shared.key_vault_name
}

output "key_vault_uri" {
  value = module.shared.key_vault_uri
}

output "postgresql_server_fqdn" {
  value = module.shared.postgresql_server_fqdn
}

output "servicebus_namespace_name" {
  value = module.shared.servicebus_namespace_name
}

output "identity_container_app_fqdn" {
  value = module.identity_container_app.container_app_fqdn
}

output "identity_container_app_id" {
  value = module.identity_container_app.container_app_id
}

output "matrix_synapse_internal_fqdn" {
  value = module.matrix_synapse.internal_fqdn
}

output "matrix_synapse_container_app_name" {
  value = module.matrix_synapse.container_app_name
}

output "email_relay_function_name" {
  value = module.email_relay_function.function_app_name
}

output "email_relay_function_hostname" {
  value = module.email_relay_function.function_app_default_hostname
}

output "password_breach_check_function_name" {
  value = module.password_breach_check_function.function_app_name
}

output "password_breach_check_function_hostname" {
  value = module.password_breach_check_function.function_app_default_hostname
}
