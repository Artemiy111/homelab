output "element_oidc_client_id" {
  description = "Client ID приложения Element для Synapse oidc_providers (положить в Vault kv/element/secrets как OIDC_CLIENT_ID)"
  value       = zitadel_application_v2.element.oidc[0].client_id
  sensitive   = true
}
