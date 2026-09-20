# Стратегии аутентификации для сервисов homelab

Дата проверки: 2026-08-18.

## Область исследования

Источник активного состава — корневой `README.md`, `docs/research/oidc-support.md`
(предыдущая версия этого документа) и `docs/research/authentication-services.md`.
Дополнительно включены Gatus и Navidrome. Старые и экспериментальные каталоги не
анализировались.

IdP: **ZITADEL** (`id.example.com`), issuer:

```text
https://id.example.com
```

## Сводная матрица

Ключ: ✅ — нативная поддержка, ⚠️ — через plugin/расширение, 🔧 — через
proxy/forward-auth, ❌ — нет поддержки.

| Сервис | Версия | OIDC | JIT¹ | SCIM | Proxy mode | Back-Channel Logout | Auto-admin² | Passkey-only вход³ | App Passwords |
|--------|--------|:----:|:----:|:----:|:----------:|:-------------------:|:-----------:|:------------------:|:-------------:|
| **Beszel** | `0.18.7` | ✅ | ✅ | ❌ | ❌ | ❌ | ⚠️⁴ | ✅ | ❌ |
| **Immich** | `v3` | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ |
| **Forgejo** | `16-rootless` | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |
| **Dawarich** | `1.11.0` | ✅ | ✅ | ❌ | ❌ | ❌ | ⚠️⁵ | ✅ | ❌ |
| **Gatus** | `5.36.0` | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **Nextcloud** | `34.0.2` | ⚠️⁶ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅⁷ |
| **Stalwart** | `0.16` | 🔧⁸ | ⚠️⁹ | ❌ | ❌ | ❌ | ⚠️¹⁰ | ✅¹¹ | ✅¹² |
| **Navidrome** | `0.63.1` | ❌ | ❌ | ❌ | 🔧¹³ | ❌ | ❌ | 🔧¹⁴ | ❌ |
| **Jellyfin** | `10` | ⚠️¹⁵ | ❌ | ❌ | ❌ | ❌ | ❌ | ⚠️¹⁵ | ❌ |
| **Uptime Kuma** | `2` | ❌ | ❌ | ❌ | 🔧¹⁶ | ❌ | ❌ | 🔧¹⁶ | ❌ |
| **Pi-hole** | `latest` | ❌ | ❌ | ❌ | 🔧¹⁷ | ❌ | ❌ | ❌ | ❌ |
| **3x-ui** | `3.5.0` | ❌ | ❌ | ❌ | 🔧¹⁷ | ❌ | ❌ | ❌ | ❌ |
| **Jitsi Meet** | `stable-10978` | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Traefik** | `3.7` | ❌¹⁸ | — | — | — | — | — | — | — |
| **Tailscale** | хостовый | ⚠️¹⁹ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Element** | `v1.159.0` | ⚠️²¹ | ⚠️²² | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| **LocalAI** | `v4.8.0` | ✅ | ✅ | ❌ | ❌ | ❌ | ⚠️²³ | ✅ | ❌ |
| **Vault** | `2.0.3` | ✅²⁴ | ❌ | ❌ | ❌ | ❌ | ❌²⁵ | ❌ | ❌ |
| **Infisical** | `latest` | ⚠️²⁶ | ❌ | ⚠️²⁷ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Arcane** | `v2.8.0` | ✅ | ✅ | ❌ | ❌ | ❌ | ✅²⁸ | ✅ | ❌ |
| **Home Assistant** | `stable` | ⚠️²⁹ | ❌ | ❌ | ❌ | ❌ | ❌ | ⚠️³⁰ | ❌ |
| **Pocket ID** | `2.13.0` | —²⁰ | — | — | — | — | — | — | — |

¹ **JIT** (Just-In-Time) — автоматическое создание аккаунта при первом OIDC входе.
² **Auto-admin** — автоматическое назначение прав администратора по OIDC claims (groups/roles).
³ **Passkey-only вход** — можно ли войти исключительно по passkey без пароля.
⁴ Beszel: первый пользователь = admin, остальные назначаются вручную.
⁵ Dawarich: первый зарегистрированный пользователь = admin автоматически.
⁶ Nextcloud: через официальный plugin `user_oidc`.
⁷ Nextcloud: App Passwords для десктопных/мобильных клиентов (Desktop, Mobile).
⁸ Stalwart: OIDC как directory backend (валидирует OAUTHBEARER токены от почтовых клиентов).
⁹ Stalwart: аккаунт создаётся при первом OIDC входе, но admin-роль назначается вручную.
¹⁰ Stalwart: admin — только через initial setup или CLI.
¹¹ Stalwart WebUI: passkey-only через ZITADEL OIDC login.
¹² Stalwart: App Passwords для Thunderbird/Outlook/Apple Mail (не поддерживают OAUTHBEARER).
¹³ Navidrome: trusted header `Remote-User` от OAuth2 Proxy.
¹⁴ Navidrome: OAuth2 Proxy сессия + passkey в ZITADEL.
¹⁵ Jellyfin: сторонний plugin (alpha, архивирован). OIDC работает в Web UI, не во всех клиентах.
¹⁶ Uptime Kuma: OAuth2 Proxy devant; приложение не знает пользователя.
¹⁷ Pi-hole/3x-ui: proxy gate как дополнительный барьер; собственная auth сохраняется.
¹⁸ Traefik OSS: forwardAuth middleware; OIDC только в Traefik Hub.
¹⁹ Tailscale: требует публичный IdP + WebFinger; неприменимо в текущей сетевой модели.
²⁰ Pocket ID: неприменимо (Provider).
²¹ Element: Synapse поддерживает OIDC через `oidc_providers` в homeserver.yaml или MAS (Matrix Auth Service). Не настроено в текущем compose.
²² Element: JIT через Synapse OIDC или MAS. Требует ручной настройки `oidc_providers` блока.
²³ LocalAI: первый пользователь = admin через OIDC. Требует `LOCALAI_DISABLE_LOCAL_AUTH=true` для OIDC-only.
²⁴ Vault: OIDC auth method через `vault auth enable oidc`. Не настроен; используется token-based auth.
²⁵ Vault: admin — root token. OIDC role mapping требует ручной настройки policies.
²⁶ Infisical: OIDC SSO — платная функция (Pro tier). Требует email domain verification.
²⁷ Infisical: SCIM только с SAML SSO (Enterprise). Не применимо для homelab.
²⁸ Arcane: admin по умолчанию `arcane`/`arcane-admin`. OIDC groups → roles mapping.
²⁹ Home Assistant: нет native OIDC. Community компонент `hass-oidc-auth` через HACS.
³⁰ Home Assistant: passkey-only через community WebAuthn MFA (HACS) + trusted networks.

---

## 1. Native OIDC (приложение = OIDC Relying Party)

Приложение само выполняет OIDC flow, создаёт сессию, знает пользователя.
Это **наиболее полная** интеграция.

### Beszel 0.18.7

Callback:

```text
https://beszel.example.com/api/oauth2-redirect
```

В Beszel: `/_/#/settings` → коллекция `users` → OAuth2 → custom OIDC provider.
Upstream: [OAuth / OIDC guide](https://beszel.dev/guide/oauth).

### Immich v3

Callbacks для web и mobile:

```text
https://immich.example.com/auth/login
https://immich.example.com/user-settings
app.immich:///oauth-callback
```

HTTPS bridge для mobile: `https://immich.example.com/api/oauth/mobile-redirect`.
Настройки: Administration → Settings → OAuth. Поддерживает auto-register, auto-launch,
role claim и backchannel logout:
[Immich OAuth Authentication](https://docs.immich.app/administration/oauth/).

**Auto-admin**: Immich назначает admin по OIDC claim `groups` или `role`.
В ZITADEL: настроить role mapping для Immich application.

### Forgejo 16-rootless

Callback (если source назвать `Zitadel`):

```text
https://forgejo.example.com/user/oauth2/Zitadel/callback
```

Auto Discovery URL:

```text
https://id.example.com/.well-known/openid-configuration
```

В Forgejo включить OIDC-вход:
- Site Administration → Authentication Sources → Add → OpenID Connect
- Discovery URL: `https://id.example.com/.well-known/openid-configuration`
- Client ID / Secret из ZITADEL
- Enable Auto Registration: ✅
- Admin Group: `admin` (чтобы ZITADEL group `admin` → Forgejo admin)

Также через env в compose:

```yaml
FORGEJO__openid__ENABLE_OPENID_SIGNIN: "true"
FORGEJO__openid__ENABLE_OPENID_SIGNUP: "true"
```

Docs: [Forgejo OAuth2 authentication](https://forgejo.org/docs/latest/admin/authentication/).
Pocket ID example: [Forgejo-compatible flow](https://pocket-id.org/docs/client-examples/forgejo).

### Dawarich 1.11.0

Callback:

```text
https://dawarich.example.com/users/auth/openid_connect/callback
```

Env variables:

```dotenv
OIDC_CLIENT_ID=...
OIDC_CLIENT_SECRET=...
OIDC_ISSUER=https://id.example.com
OIDC_REDIRECT_URI=https://dawarich.example.com/users/auth/openid_connect/callback
OIDC_PROVIDER_NAME=ZITADEL
```

Опциональны `OIDC_AUTO_REGISTER` и `OIDC_PKCE_ENABLED`.
Source: [Dawarich 1.11.0 `lib/oidc_config.rb`](https://github.com/Freika/dawarich/blob/1.11.0/lib/oidc_config.rb).

**Auto-admin**: первый пользователь = admin автоматически. Остальные — вручную.

### Gatus 5.36.0

Callback:

```text
https://uptime.example.com/authorization-code/callback
```

```yaml
security:
  oidc:
    issuer-url: https://id.example.com
    redirect-url: https://uptime.example.com/authorization-code/callback
    client-id: ${GATUS_OIDC_CLIENT_ID}
    client-secret: ${GATUS_OIDC_CLIENT_SECRET}
    scopes: [openid]
```

`allowed-subjects` — ограничение по конкретным `sub`.
Source: [Gatus OIDC reference](https://github.com/TwiN/gatus/blob/v5.36.0/README.md#oidc).

### Nextcloud 34.0.2

Требуется официальный plugin `user_oidc` (8.10.1):
[OpenID Connect user backend](https://apps.nextcloud.com/apps/user_oidc).

Callback:

```text
https://nextcloud.example.com/apps/user_oidc/code
```

CLI настройка:

```bash
occ user_oidc:provider add \
  --provider-name ZITADEL \
  --client-id <CLIENT_ID> \
  --client-secret <CLIENT_SECRET> \
  --discovery-url https://id.example.com/.well-known/openid-configuration
```

Поддерживает auto-provisioning и group provisioning. Отключение других login methods —
только после проверки аварийного admin-доступа и WebDAV/desktop/mobile clients:
[upstream `user_oidc` docs](https://github.com/nextcloud/user_oidc).

### Arcane v2.8.0

OIDC настройка через env variables:

```yaml
OIDC_ENABLED: "true"
OIDC_ISSUER_URL: "https://id.example.com"
OIDC_CLIENT_ID: "<CLIENT_ID>"
OIDC_CLIENT_SECRET: "<CLIENT_SECRET>"
```

Callback:

```text
https://arcane.example.com/auth/oidc/callback
```

Scope: `openid email profile groups`. Поддерживает groups → roles mapping.
Disable local auth: `LOCAL_AUTH_ENABLED=false` для OIDC-only.
Docs: [Arcane OIDC](https://getarcaneapp.com/docs/authentication).

### LocalAI v4.8.0

OIDC настройка через env variables:

```yaml
LOCALAI_OIDC_ISSUER: "https://id.example.com"
LOCALAI_OIDC_CLIENT_ID: "<CLIENT_ID>"
LOCALAI_OIDC_CLIENT_SECRET: "<CLIENT_SECRET>"
LOCALAI_DISABLE_LOCAL_AUTH: "true"
```

Callback:

```text
https://localai.example.com/api/auth/oidc/callback
```

Также поддерживает GitHub OAuth нативно. Scope: `openid profile email`.
Для OIDC-only входа: `LOCALAI_DISABLE_LOCAL_AUTH=true`.
Docs: [LocalAI Authentication](https://localai.io/docs/getting-started/configuration/#authentication).

### HashiCorp Vault 2.0.3

OIDC auth method включается через CLI:

```bash
vault auth enable oidc
vault write auth/oidc/role/default \
  bound_audiences="<CLIENT_ID>" \
  allowed_redirect_uris="https://vault.example.com/ui/vault/auth/oidc/oidc/callback" \
  allowed_redirect_uris="http://localhost:8250/oidc/callback" \
  user_claim=sub \
  groups_claim=groups \
  token_policies=default
```

OIDC конфигурация:

```bash
vault write auth/oidc/config \
  oidc_discovery_url="https://id.example.com" \
  oidc_client_id="<CLIENT_ID>" \
  oidc_client_secret="<CLIENT_SECRET>" \
  default_role=default
```

В UI: Access → Auth Methods → OIDC → Configure. Login: выбрать "OIDC" из dropdown.
Docs: [Vault OIDC Auth Method](https://developer.hashicorp.com/vault/docs/auth/jwt/oidc-provider).
**Важно**: после включения OIDC сохранять root token и unseal keys отдельно.

### Element / Synapse v1.159.0

OIDC настройка в `homeserver.yaml`:

```yaml
oidc_providers:
  - idp_id: zitadel
    idp_name: ZITADEL
    issuer: "https://id.example.com"
    client_id: "<CLIENT_ID>"
    client_secret: "<CLIENT_SECRET>"
    authorization_endpoint: "https://id.example.com/authorize"
    token_endpoint: "https://id.example.com/oauth/v2/token"
    userinfo_endpoint: "https://id.example.com/oauth/v2/userinfo"
    jwks_uri: "https://id.example.com/oauth/v2/keys"
    scopes:
      - openid
      - profile
      - email
    user_mapping_provider:
      config:
        localpart_template: "{{ user.preferred_username }}"
        display_name_template: "{{ user.name }}"
```

Callback:

```text
https://element.example.com/_synapse/client/oidc/callback
```

Альтернатива: **MAS (Matrix Auth Service)** — более современный OIDC-native слой.
Docs: [Synapse OIDC](https://element-hq.github.io/synapse/latest/openid.html),
[MAS](https://element-hq.github.io/matrix-authentication-service/).

**Примечание**: 현재 compose не настроен OIDC. Требует ручной настройки homeserver.yaml.

### Infisical (MIT Community Edition)

OIDC SSO — **платная функция** (Pro tier). В self-hosted:
- Settings → SSO → OIDC → Enable
- Discovery URL: `https://id.example.com/.well-known/openid-configuration`
- Client ID / Secret из ZITADEL
- Требует **email domain verification** перед включением

**Ограничения Community Edition**: OIDC SSO доступен только в Pro/Enterprise.
Для homelab: использовать email/password или Universal Auth (client ID/secret для CLI/SDK).
Docs: [Infisical SSO](https://infisical.com/docs/documentation/platform/sso).

### Home Assistant (stable)

Нет native OIDC. Два варианта:

**Вариант 1: Community OIDC (рекомендуется)**

Через HACS установить `hass-oidc-auth`:
```yaml
# configuration.yaml
auth_oidc:
  client_id: "<CLIENT_ID>"
  client_secret: "<CLIENT_SECRET>"
  discovery_url: "https://id.example.com/.well-known/openid-configuration"
```

Callback:

```text
https://ha.example.com/auth/oidc/callback
```

**Вариант 2: Trusted Networks + TOTP**

```yaml
# configuration.yaml
homeassistant:
  auth_providers:
    - type: homeassistant
  trusted_proxies:
    - 172.20.0.0/16  # Traefik network
  ip_ban_enabled: true
  login_attempts_threshold: 5
```

Docs: [hass-oidc-auth](https://github.com/christiaangoossens/hass-oidc-auth),
[HA Trusted Networks](https://www.home-assistant.io/docs/configuration/trusted_network/).

---

## 2. OIDC как directory backend (Stalwart)

Stalwart v0.16 поддерживает OIDC в两个方向ах:

| Режим | Что делает |
|-------|-----------|
| OIDC Provider | Stalwart сам выступает как IdP |
| **OIDC Client** | Stalwart делегирует аутентификацию внешнему IdP |

Для homelab нужен **OIDC Client** — Stalwart валидирует токены от ZITADEL.

### Настройка OIDC Directory

WebUI Stalwart → Settings → Authentication → Directories → Add → OpenID Connect:

| Поле | Значение |
|------|----------|
| `issuerUrl` | `https://id.example.com` |
| `requireAudience` | `stalwart` (client ID из ZITADEL) |
| `requireScopes` | `{"openid": true, "email": true}` |
| `claimUsername` | `preferred_username` или `email` |
| `usernameDomain` | `example.com` |

Затем: Settings → Authentication → General → `directoryId` → указать OIDC directory.

### Важные ограничения

1. **Аккаунты в Stalwart создаются до первого входа** — иначе письма отклоняются
2. **OAUTHBEARER** — почтовые клиенты (Thunderbird, Outlook) отправляют access token
   через SASL `OAUTHBEARER`. Большинство клиентов это **не поддерживают** → App Passwords
3. **Веб-почта Bulwark** — полноценный OIDC flow в браузере, passkey-only работает
4. **Admin panel Stalwart** — built-in `client_id=stalwart-webui`, OIDC login через ZITADEL

### Bulwark (веб-почта)

OIDC настройка в environment Bulwark:

```yaml
OAUTH_ENABLED: "true"
OAUTH_PROVIDER_NAME: "ZITADEL"
OAUTH_CLIENT_ID: "stalwart"
OAUTH_DISCOVERY_URL: "https://id.example.com/.well-known/openid-configuration"
```

### App Passwords для legacy клиентов

Для Thunderbird/Outlook/Apple Mail:
- Stalwart WebUI → Accounts → пользователь → App Passwords → Generate
- В клиенте: email + сгенерированный пароль

---

## 3. JIT provisioning (автосоздание аккаунтов)

JIT создаёт аккаунт при первом OIDC входе. Не требует SCIM или ручного создания.

| Сервис | JIT | Auto-admin по claims | Примечания |
|--------|:---:|:--------------------:|-----------|
| **Forgejo** | ✅ | ✅ `admin-group` | Site Administration → Auth Sources → Admin Group |
| **Immich** | ✅ | ✅ `groups`/`role` | Auto-register + role claim |
| **Nextcloud** | ✅ | ✅ group provisioning | `user_oidc` plugin |
| **Arcane** | ✅ | ✅ groups → roles | OIDC `groups` scope |
| **LocalAI** | ✅ | ⚠️ | Первый = admin, остальные через invite codes |
| **Beszel** | ✅ | ⚠️ | Первый = admin, остальные вручную |
| **Dawarich** | ✅ | ⚠️ | Первый = admin, остальные вручную |
| **Gatus** | ✅ | ❌ | Только `allowed-subjects` |
| **Stalwart** | ⚠️ | ❌ | JIT создаёт аккаунт, но admin вручную |
| **Element** | ⚠️ | ❌ | Требует ручной настройки Synapse oidc_providers |
| **Vault** | ❌ | ❌ | OIDC auth method: role mapping через policies |
| **Home Assistant** | ❌ | ❌ | Community OIDC: JIT через hass-oidc-auth |

**Критическое замечание**: JIT **не может deprovision**. Если пользователь
отключён в ZITADEL, его локальный аккаунт в приложении остаётся. Для
deprovisioning нужен SCIM или ручное удаление.

---

## 4. SCIM provisioning (push lifecycle)

SCIM позволяет IdP **пушить** create/update/delete в приложения.
Это единственный способ автоматического deprovisioning.

| Сервис | SCIM server (принимает) | SCIM client (пушит) | Примечания |
|--------|:----------------------:|:-------------------:|-----------|
| **ZITADEL** | ✅ (превью) | ❌ | SCIM server v2.69+, только Users |
| **Authentik** | ✅ | ✅ | Полный SCIM provider + consumer |
| **Rauthy** | ❌ | ✅ | SCIM client: push users в downstream apps |
| **Casdoor** | ✅ | ✅ | SCIM server + syncer (pull) |
| **Kanidm** | ✅ | ❌ | SCIM inbound (push users в Kanidm) |
| **Infisical** | ⚠️ | ❌ | SCIM только с SAML SSO (Enterprise/Pro) |
| **Stalwart** | ❌ | ❌ | Нет SCIM |
| **Forgejo** | ❌ | ❌ | Нет SCIM |
| **Immich** | ❌ | ❌ | Нет SCIM |
| **Nextcloud** | ❌ | ❌ | Нет SCIM (только OIDC JIT) |

**Для homelab**: SCIM практически неприменим — ни один из сервисов homelab не
является SCIM server. SCIM ценен для enterprise SaaS (Slack, GitHub Enterprise, Jira).

---

## 5. Proxy / forward-auth (приложения без OIDC)

Для приложений без собственного OIDC: внешний proxy проверяет аутентификацию
и передаёт upstream headers (`X-Auth-Request-User`, `Remote-User`).

| Сервис | Тип защиты | Инструмент | Примечания |
|--------|-----------|-----------|-----------|
| **Navidrome** | Trusted header | OAuth2 Proxy | `Remote-User` от доверенного CIDR; `/rest/*` и `/share/*` исключения |
| **Uptime Kuma** | Proxy gate | OAuth2 Proxy | Отключить внутреннюю auth; приложение не знает пользователя |
| **Pi-hole** | Proxy gate | OAuth2 Proxy | Дополнительный барьер; собственная auth (пароль/2FA) сохраняется |
| **3x-ui** | Proxy gate | OAuth2 Proxy | Дополнительный барьер; панель требует свой login |
| **Traefik Dashboard** | ForwardAuth | OAuth2 Proxy | Заменить BasicAuth на forward-auth |

### OAuth2 Proxy перед ZITADEL

Конфигурация (из `oauth2-proxy/.env`):

```text
--provider=oidc
--oidc-issuer-url=https://id.example.com
--cookie-domain=.example.com
--upstream=static://202
--skip-provider-button=true
--set-xauthrequest=true
```

Traefik middleware:

```yaml
# traefik/dynamic/middleware.yaml
http:
  middlewares:
    oauth2-proxy:
      forwardAuth:
        address: "http://oauth2-proxy:4180"
        trustForwardHeader: true
        authResponseHeaders:
          - X-Auth-Request-User
          - X-Auth-Request-Email
```

### Navidrome: trusted header

```env
ND_EXTAUTH_TRUSTEDSOURCES=<CIDR traefiknet>
ND_EXTAUTH_USERHEADER=Remote-User
ND_EXTAUTH_LOGOUTURL=https://id.example.com/end_session
```

Детали: [Navidrome Externalized Authentication](https://www.navidrome.org/docs/usage/integration/authentication/).

---

## 6. Back-Channel Logout

| Сервис | Back-Channel Logout | Примечания |
|--------|:-------------------:|-----------|
| **Immich** | ✅ | Поддерживает backchannel logout |
| **Element (MAS)** | ✅ | Matrix Auth Service поддерживает BCL |
| **Authelia** | ✅ | OIDC certified, включая logout profiles |
| **Casdoor** | ✅ | Полная поддержка OIDC BCL 1.0 |
| **Rauthy** | ✅ | Полная поддержка, настраиваемые retry/timeout |
| **ZITADEL** | ⚠️ | Экспериментальный feature flag (`enable_back_channel_logout`) |
| **Forgejo** | ❌ | Нет поддержки |
| **Arcane** | ❌ | Нет поддержки |
| **LocalAI** | ❌ | Нет поддержки |
| **Vault** | ❌ | Нет поддержки |
| **Nextcloud** | ❌ | Нет поддержки (plugin `user_oidc`) |
| **Gatus** | ❌ | Нет поддержки |
| **OAuth2 Proxy** | ❌ | [Open issue #1224](https://github.com/oauth2-proxy/oauth2-proxy/issues/1224) |

---

## 7. Приложения без какой-либо SSO поддержки

| Сервис | Единственный вход | Что можно сделать |
|--------|------------------|-------------------|
| **Pi-hole** | Пароль + 2FA | Proxy gate (дополнительный барьер) |
| **3x-ui** | Пароль + TOTP + LDAP | Proxy gate (дополнительный барьер) |
| **Jitsi Meet** | Internal / JWT / LDAP | Custom JWT bridge (сложный) |
| **Infisical** | Email/password (Community) | OIDC SSO — Pro tier (платно) |

---

## 8. Порядок подключения (рекомендация)

### Приоритет 1: сервисы с native OIDC

```
1. Forgejo     — callback, auto-admin через admin group
2. Immich      — web + mobile callbacks, auto-register
3. Arcane      — OIDC env vars, groups → roles
4. Beszel      — callback, первый пользователь = admin
5. Dawarich    — env variables, первый = admin
6. Gatus       — callback, allowed-subjects
7. LocalAI     — OIDC env vars, disable local auth
```

### Приоритет 2: Nextcloud (plugin) + Vault

```
8. Nextcloud — установить user_oidc, callback, проверить WebDAV/desktop/mobile
9. Vault     — vault auth enable oidc, настроить role и policies
```

### Приоритет 3: Stalwart (OIDC directory) + Element

```
10. Stalwart — OIDC directory → ZITADEL, Bulwark OIDC, App Passwords
11. Element  — Synapse oidc_providers в homeserver.yaml
```

### Приоритет 4: proxy-first + Home Assistant

```
12. Navidrome      — OAuth2 Proxy + trusted header
13. Uptime Kuma    — OAuth2 Proxy, отключить внутреннюю auth
14. Traefik        — forward-auth вместо BasicAuth
15. Home Assistant — hass-oidc-auth через HACS
```

### Приоритет 5: экспериментально / отложить

```
16. Jellyfin   — сторонний SSO plugin (alpha)
17. Tailscale  — отложить до публичного IdP
18. Infisical  — OIDC SSO платный (Pro tier)
```

### Не подключать к SSO

```
- Pi-hole  — proxy gate не заменяет пароль
- 3x-ui    — proxy gate не заменяет пароль
- Jitsi    — нет OIDC, custom integration избыточен
```

---

## 9. Passkey-only: что работает, а что нет

| Вход через | Passkey-only | Пароль нужен? | Примечания |
|-----------|:------------:|:-------------:|-----------|
| ZITADEL (web) | ✅ | ❌ | Основной способ |
| Bulwark (веб-почта) | ✅ | ❌ | OIDC → ZITADEL → passkey |
| Stalwart admin panel | ✅ | ❌ | OIDC → ZITADEL → passkey |
| Forgejo | ✅ | ❌ | OIDC → ZITADEL → passkey |
| Immich (web) | ✅ | ❌ | OIDC → ZITADEL → passkey |
| Immich (mobile) | ✅ | ❌ | OIDC → ZITADEL → passkey |
| Nextcloud (web) | ✅ | ❌ | OIDC → ZITADEL → passkey |
| Arcane | ✅ | ❌ | OIDC → ZITADEL → passkey |
| LocalAI | ✅ | ❌ | OIDC → ZITADEL → passkey |
| Element (web) | ✅ | ❌ | OIDC → ZITADEL → passkey (после настройки) |
| Vault (UI) | ⚠️ | ⚠️ | OIDC login через dropdown; не passkey-only по умолчанию |
| Home Assistant | ⚠️ | ⚠️ | Через community hass-oidc-auth + WebAuthn MFA |
| Nextcloud (desktop/mobile) | ❌¹ | ✅ | App Password или token |
| Thunderbird | ❌ | ✅ | App Password (не поддерживает OAUTHBEARER) |
| Outlook | ❌ | ✅ | App Password |
| Apple Mail | ❌ | ✅ | App Password |

¹ Nextcloud desktop/mobile клиенты: OIDC поддерживается в свежих версиях,
но стабильность зависит от клиента. App Password — более надёжный вариант.
