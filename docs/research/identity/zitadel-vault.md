# ZITADEL + HashiCorp Vault — OIDC-интеграция

Дата: 2026-11-20.

## 1. Может ли ZITADEL служить OIDC-провайдером для Vault?

**Да.** ZITADEL — сертифицированный OIDC-провайдер; любой провайдер-консьюмер
может использовать generic-OIDC. Собственной документации от HashiCorp под ZITADEL
нет, но схема стандартная (§3).

Ссылки:
- Vault OIDC auth method: https://developer.hashicorp.com/vault/docs/auth/jwt
- Vault OIDC tutorial (Auth0, но паттерн общий): https://developer.hashicorp.com/vault/tutorials/auth-methods/oidc-auth
- Discuss ZITADEL + HCP SSO: https://discuss.hashicorp.com/t/sso-setup-oidc-with-zitadel-cloud/72366

## 2. Конфигурация OIDC-метода аутентификации в Vault

```bash
vault auth enable oidc
vault write auth/oidc/config \
    oidc_discovery_url="https://id.example.com" \
    oidc_client_id="<ZITADEL_APP_CLIENT_ID>" \
    oidc_client_secret="<ZITADEL_APP_CLIENT_SECRET>" \
    default_role="zitadel"

vault write auth/oidc/role/zitadel \
    allowed_redirect_uris="https://vault.example.com/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    user_claim="sub" \
    groups_claim="urn:zitadel:iam:org:project:roles" \
    oidc_scopes="openid,profile,email" \
    token_policies="default" \
    ttl="1h"
```

На стороне ZITADEL (Project → OIDC Application):
1. `app_type = OIDC_APP_TYPE_WEB` (или OIDC для CLI: `OIDC_APP_TYPE_CLI`).
2. Перенаправление — согласно выше (callback URL Vault).
3. В Token Settings — **«User Info inside ID Token»** (Vault берёт claims оттуда).

Также поддерживается конфигурация через Terraform (`vault_auth_backend` — общий аналог человеческого `vault write`).

## 3. Какие claims/roles пробрасывает ZITADEL?

Стандартные claims (always): `sub`, `email`, `email_verified`, `name`,
`given_name`, `family_name`, `preferred_username`, `aud`, `iss`.

Ролевые (если включено): `urn:zitadel:iam:org:project:roles`
(`{"<projectId>": {"<orgId>": "<domain>"}}`),
`urn:zitadel:iam:org:project:<projectid>:roles`,
`urn:zitadel:iam:domain:primary:<domain>`,
`urn:zitadel:iam:user:metadata`, `urn:zitadel:iam:user:resourceowner:id/name`.

Подробные примеры: https://zitadel.com/docs/apis/openidoauth/claims

Для плоского массива (удобнее для Vault): **Actions** — `api.v1.claims.setClaim('zitadel:roles', [...])`
из `ctx.v1.user.grants` (сниппет в конце файла).

## 4. Состояние в стенде

- **Vault OIDC** — не настроен (`VaultAuthGlobal` в `apps/casa/vault/` имеет `defaultAuthMethod: kubernetes`; `infra/casa/terraform/vault/` — аутентификатор `kubernetes`). Вход в UI — локальный `admin`.
- Клиент в ZITADEL для Vault — не заведён (см. [applications.tf](infra/casa/terraform/zitadel/applications.tf)).
- Для подключения: 1) добавить `vault_auth_backend/oidc` + role + projects — через Terraform, 2) завести приложение в ZITADEL, 3) первый `vault login -method=oidc role=zitadel`. `user_claim` нужен такой, какой есть в этом контексте — кандидаты: `sub`, `email`, `preferred_username` (стандартные человеческие claims; если нужна иерархия — добавьте Actions).
- OIDC-сессия: Vault отдаёт короткоживущие токены с TTL (1 ч в примере); нет инфра-интеграции с Vault-клиентами.

## 5. Ссылки

- Vault OIDC Auth: https://developer.hashicorp.com/vault/docs/auth/jwt
- ZITADEL Claims Reference: https://zitadel.com/docs/apis/openidoauth/claims
- ZITADEL Partner Page on HashiCorp: https://www.hashicorp.com/partners/tech/zitadel

---

## 6. Пример: как выглядит mapping для реального клиента

```bash
vault write auth/oidc/role/zitadel \
  allowed_redirect_uris="https://vault.biplane.casa/ui/vault/auth/oidc/oidc/callback" \
  allowed_redirect_uris="http://localhost:8250/oidc/callback" \
  user_claim=sub \
  groups_claim=urn:zitadel:iam:org:project:roles \
  oidc_scopes=openid,profile,email
```

## 7. ZITADEL Actions — flatten roles

```javascript
function flatRoles(ctx, api) {
  if (ctx.v1.user.grants == undefined || ctx.v1.user.grants.count == 0) {
    return;
  }
  let grants = [];
  ctx.v1.user.grants.grants.forEach(claim => {
    claim.roles.forEach(role => {
      grants.push(claim.projectId + ':' + role)
    })
  })
  api.v1.claims.setClaim('zitadel:roles', grants)
}
```

Даёт в токене claim `"zitadel:roles": ["projectId:admin", "projectId:reader"]`.
