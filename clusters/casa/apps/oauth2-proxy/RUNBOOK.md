# OAuth2 Proxy: эксплуатация

## Настройка

1. В ZITADEL создать OIDC-приложение с redirect URI
   `https://oauth.example.com/oauth2/callback`.
2. В Vault по путям `kv/oauth2-proxy/cookie` (`OAUTH2_PROXY_COOKIE_SECRET`),
   `kv/oauth2-proxy/oidc` (client_id и client_secret из шага 1).
