# Сводная матрица сравнения Identity Providers

Дата исследования: 2026-08-18.

Дополнение к [authentication-services.md](./authentication-services.md) и
[unified-identity-management.md](./unified-identity-management.md). Здесь —
компактные таблицы по всем параметрам для всех рассматриваемых провайдеров.

## Провайдеры

Группы:
- **Full IdP**: ZITADEL, Keycloak, Authentik, Casdoor
- **Lightweight IdP**: Rauthy, Kanidm, Pocket ID
- **Proxy-first / Auth gateways**: Authelia, Tinyauth, VoidAuth
- **Tooling**: OAuth2 Proxy (не IdP, а компонент)

---

## 1. Протоколы

| Провайдер | OIDC | OIDC certified | SAML 2.0 | LDAP server | LDAP federation | SCIM (server) | SCIM (client) | RADIUS | CAS |
|-----------|:----:|:--------------:|:--------:|:-----------:|:---------------:|:--------------:|:--------------:|:------:|:---:|
| **ZITADEL** | ✅ | ✅ | ✅ | ❌ | ✅ | ✅¹ | ❌ | ❌ | ❌ |
| **Keycloak** | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️² | ❌ | ❌ | ❌ |
| **Authentik** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **Casdoor** | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅³ | ✅ | ✅ |
| **Rauthy** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **Kanidm** | ✅ | ❌ | ❌ | ✅⁴ | ❌ | ✅⁵ | ❌ | ✅⁶ | ❌ |
| **Pocket ID** | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Authelia** | ✅ | ✅⁷ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Tinyauth** | ✅ | ✅⁸ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **VoidAuth** | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |

¹ ZITADEL SCIM server в превью (v2.69+), только Users (без Groups), будет за лицензией при GA.
² Keycloak SCIM — через community extension, не нативный.
³ Casdoor SCIM client — syncer (pull FROM внешних SCIM серверов, не push).
⁴ Kanidm LDAP — read-only LDAPS gateway (не полный LDAP server).
⁵ Kanidm SCIM server — inbound (внешние IdP могут пушить пользователей В Kanidm).
⁶ Kanidm RADIUS — отдельный container.
⁷ Authelia OIDC — сертифицирован на 5 профилей, но upstream всё ещё называет "beta" (процессуально, не по качеству).
⁸ Tinyauth OIDC — OpenID Certified Basic OP с v5.1.

---

## 2. Методы аутентификации

| Провайдер | Пароль | Passkeys/WebAuthn | TOTP | MFA (комбинированный) | Social Login | Device Authorization | Аттестация |
|-----------|:------:|:-----------------:|:----:|:---------------------:|:------------:|:--------------------:|:----------:|
| **ZITADEL** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Keycloak** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Authentik** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Casdoor** | ✅ | ✅ | ✅ | ✅ | ✅⁹ | ✅ | ✅ |
| **Rauthy** | ✅ | ✅ | ✅ | ✅ | ⚠️¹⁰ | ✅ | ❌ |
| **Kanidm** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| **Pocket ID** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Authelia** | ✅ | ✅ | ✅ | ✅¹¹ | ❌ | ✅ | ❌ |
| **Tinyauth** | ✅ | ⚠️¹² | ✅ | ❌ | ✅¹³ | ❌ | ❌ |
| **VoidAuth** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |

⁹ Casdoor поддерживает 50+ social providers (Google, GitHub, GitLab, WeChat, Facebook, Twitter/X, LinkedIn, Azure AD и др.).
¹⁰ Rauthy: social login через "Upstream Authentication Providers" (GitHub задокументирован, расширяемо), статус beta.
¹¹ Authelia: MFA через WebAuthn + TOTP или Duo Push (не комбинированное chaining).
¹² Tinyauth: passkeys через OAuth providers (не нативный WebAuthn на форме логина).
¹³ Tinyauth: social login через OAuth (GitHub, Google, Pocket ID и др.).

---

## 3. Proxy / Forward-auth

| Провайдер | Proxy mode | Traefik | NGINX | Caddy | HAProxy | Trusted Headers | Собственный outpost |
|-----------|:----------:|:-------:|:-----:|:-----:|:-------:|:---------------:|:-------------------:|
| **ZITADEL** | ❌ | — | — | — | — | — | ❌ |
| **Keycloak** | ❌ | — | — | — | — | — | ❌¹⁴ |
| **Authentik** | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ (proxy outpost) |
| **Casdoor** | ✅¹⁵ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **Rauthy** | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **Kanidm** | ❌ | — | — | — | — | — | ❌ |
| **Pocket ID** | ❌ | — | — | — | — | — | ❌ |
| **Authelia** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **Tinyauth** | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **VoidAuth** | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **OAuth2 Proxy** | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |

¹⁴ Keycloak HTTP Proxy (Quarkus) существует для conflating, но не является полноценным proxy outpost для web apps.
¹⁵ Casdoor forward-auth — отдельный first-party сервис `casdoor-forward-auth` + Traefik plugin.

---

## 4. Logout и инвалидация сессий

| Провайдер | Back-Channel Logout | Front-Channel Logout | Token Introspection (RFC 7662) | Token Revocation (RFC 7009) | Disable → immediate token reject |
|-----------|:-------------------:|:--------------------:|:------------------------------:|:---------------------------:|:--------------------------------:|
| **ZITADEL** | ⚠️¹⁶ | ✅ | ✅ | ✅ | ✅¹⁷ |
| **Keycloak** | ✅ | ✅ | ✅ | ✅ | ❌¹⁸ |
| **Authentik** | ❌ | ✅ | ✅ | ✅ | ✅ |
| **Casdoor** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Rauthy** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Kanidm** | ❌ | ❌ | ✅ | ✅ | ✅ |
| **Pocket ID** | ❌ | ❌ | ❌ | ❌ | ✅¹⁹ |
| **Authelia** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Tinyauth** | ❌ | ❌ | ❌ | ❌ | ✅²⁰ |
| **VoidAuth** | ❌ | ❌ | ❌ | ❌ | ✅²⁰ |
| **OAuth2 Proxy** | ❌²¹ | ❌ | ❌ | ❌ | ❌²² |

¹⁶ ZITADEL Back-Channel Logout — экспериментальный feature flag, с ~v2.69+.
¹⁷ ZITADEL: деактивированный пользователь не получает новые токены; существующие JWT валидны до `exp`.
¹⁸ Keycloak: отключение пользователя НЕ инвалидирует активные сессии (by design, issue #37981). Refresh/introspection отклоняют.
¹⁹ Pocket ID: отключение = нет новых OIDC sessions; существующие cookie-based сессии живут до истечения.
²⁰ Tinyauth/VoidAuth: отключение = отказ при следующей проверке (cookie-based сессии).
²¹ OAuth2 Proxy: open issue #1224.
²² OAuth2 Proxy: не инвалидирует сессии при refresh failure без патча (issue #1945).

---

## 5. Multi-tenancy и авторизация

| Провайдер | Multi-tenancy | RBAC | Группы в OIDC claims | Делегированное управление | Self-service (пользователь) |
|-----------|:-------------:|:----:|:--------------------:|:-------------------------:|:---------------------------:|
| **ZITADEL** | ✅²³ | ✅ | ✅ | ✅ | ✅ |
| **Keycloak** | ✅²⁴ | ✅ | ✅ | ✅ | ✅ |
| **Authentik** | ⚠️²⁵ | ✅ | ✅ | ✅ | ✅ |
| **Casdoor** | ✅²⁶ | ✅²⁷ | ✅ | ✅ | ✅ |
| **Rauthy** | ❌ | ✅²⁸ | ✅ | ⚠️²⁹ | ✅ |
| **Kanidm** | ❌ | ⚠️³⁰ | ✅ | ❌ | ✅ |
| **Pocket ID** | ❌ | ❌ | ✅ | ❌ | ❌³¹ |
| **Authelia** | ❌ | ⚠️³² | ✅ | ❌ | ⚠️³³ |
| **Tinyauth** | ❌ | ❌ | ⚠️³⁴ | ❌ | ❌ |
| **VoidAuth** | ❌ | ⚠️³⁵ | ✅ | ❌ | ✅ |

²³ ZITADEL: Instance → Organization → Project → Application. Настоящий multi-tenancy.
²⁴ Keycloak: Realms. Multi-tenancy через разные realms.
²⁵ Authelik: Базовый multi-tenancy (не first-class как ZITADEL).
²⁶ Casdoor: Organizations с org-level SSO, ролями, branding.
²⁷ Casdoor: ACL, RBAC, ABAC через Casbin. Самая гибкая модель авторизации.
²⁸ Rauthy: Custom roles, custom groups, group-prefix restrictions per client.
²⁹ Rauthy: Делегированные group admin'ы, admin API keys с fine-grained access.
³⁰ Kanidm: Group-based scope mapping (не классический RBAC).
³¹ Pocket ID: Self-service registration отключён по умолчанию; passkey management через UI.
³² Authelia: Rule-based ACL (per-subdomain, per-user, per-group, per-network). Не традиционный RBAC.
³³ Authelia: Self-service — password reset через email. Без self-registration.
³⁴ Tinyauth: LDAP groups используются только для proxy ACL, не в OIDC claims.
³⁵ VoidAuth: Groups-based (security groups, admin group).

---

## 6. Технические характеристики

| Провайдер | Язык | БД | RAM (idle) | Docker image | Лицензия |
|-----------|------|----|-----------:|-------------:|----------|
| **ZITADEL** | Go | PostgreSQL | ~100 MB | ~50 MB | AGPL-3.0³⁶ |
| **Keycloak** | Java (Quarkus) | PostgreSQL/MySQL/H2 | ≥750 MB–2 GB | ~400 MB | Apache-2.0 |
| **Authentik** | Python | PostgreSQL | ~300 MB | ~500 MB | MIT + Enterprise |
| **Casdoor** | Go + React | MySQL/PG/SQLServer/SQLite | ~150 MB | ~100 MB | Apache-2.0 |
| **Rauthy** | Rust | Hiqlite³⁷ / PostgreSQL | ~35–57 MB | ~10–20 MB | Apache-2.0 |
| **Kanidm** | Rust | Embedded (file-backed) | ~50 MB | ~30 MB | MPL-2.0 |
| **Pocket ID** | Go | SQLite | ~10 MB | ~15 MB | AGPL-3.0 |
| **Authelia** | Go | PostgreSQL/MySQL/SQLite + Redis | ~50–100 MB | ~30 MB | Apache-2.0 |
| **Tinyauth** | Go + TS | SQLite (optional) | ~5 MB | ~20 MB | AGPL-3.0 |
| **VoidAuth** | Node.js | PostgreSQL/SQLite | ~100 MB | ~150 MB | AGPL-3.0 |

³⁶ ZITADEL AGPL-3.0 с Apache-2.0/MIT исключениями для SDK.
³⁷ Hiqlite — встроенный embedded SQLite + Raft consensus для HA.

---

## 7. Развёртывание и сопровождение

| Провайдер | Helm chart (офиц.) | K8s docs | Docker Compose | CLI admin | Web admin UI | Самостоятельный signup |
|-----------|:------------------:|:--------:|:--------------:|:---------:|:------------:|:----------------------:|
| **ZITADEL** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅³⁸ |
| **Keycloak** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Authentik** | ❌³⁹ | ✅ | ✅ | ❌ | ✅ | ✅ |
| **Casdoor** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Rauthy** | ⚠️⁴⁰ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Kanidm** | ⚠️⁴⁰ | ✅ | ✅ | ✅ | ❌⁴¹ | ✅ |
| **Pocket ID** | ❌ | ❌ | ✅ | ❌ | ✅ | ⚠️⁴² |
| **Authelia** | ✅ | ✅ | ✅ | ❌⁴³ | ❌⁴³ | ❌⁴⁴ |
| **Tinyauth** | ⚠️⁴⁰ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **VoidAuth** | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |

³⁸ ZITADEL: self-service registration через hosted login UI; passkey-only registration через API.
³⁹ Authentik: официального Helm chart нет; развертывание через Kustomize/manifests.
⁴⁰ Community Helm chart доступен, но не official.
⁴¹ Kanidm: WebUI для user self-service, admin — через CLI.
⁴² Pocket ID: self-service отключён по умолчанию; one-time signup links.
⁴³ Authelia: конфигурация через YAML файлы, нет web admin UI.
⁴⁴ Authelia: пользователи создаются через LDAP или файл, self-registration нет.

---

## 8. Сводная оценка для homelab

| Провайдер | Homelab | Работа (enterprise IAM) | Главное преимущество | Главный недостаток |
|-----------|:-------:|:-----------------------:|---------------------|-------------------|
| **ZITADEL** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Enterprise набор при малом footprint | Нет proxy mode |
| **Keycloak** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Самый зрелый, максимальное покрытие | Тяжёлый (Java RAM) |
| **Authentik** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | Proxy outpost + flows/stages | Тяжелее ZITADEL по RAM |
| **Casdoor** | ⭐⭐⭐ | ⭐⭐⭐ | Широчайший набор протоколов (SAML, CAS, SCIM, LDAP, RADIUS) | Много движущихся частей |
| **Rauthy** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | Минимальный footprint + SCIM client + forward-auth | Нет SAML/LDAP/multi-tenancy |
| **Kanidm** | ⭐⭐⭐ | ⭐⭐⭐⭐ | LDAP gateway + passkeys + Rust performance | CLI-first, нет proxy mode |
| **Pocket ID** | ⭐⭐⭐⭐ | ⭐⭐ | Простейший passkey-only OIDC | Узкий функционал |
| **Authelia** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | Proxy-first + OIDC certified | Нет admin UI, конфиг через YAML |
| **Tinyauth** | ⭐⭐⭐⭐ | ⭐⭐ | Минимальный footprint + OIDC certified | Нет self-service, нет RBAC |
| **VoidAuth** | ⭐⭐⭐ | ⭐⭐ | LDAP server + OIDC + forward-auth в одном | Молодой, нет security audit |
| **OAuth2 Proxy** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | De facto standard для proxy auth | Не IdP, нет logout orchestration |

---

## 9. Матрица решений: какой IdP для какой задачи

| Задача | Лучший выбор | Зачем |
|--------|-------------|-------|
| **Единый IdP для всего homelab** | **ZITADEL** | OIDC-certified, SCIM, RBAC, modern UI, 100 MB RAM |
| **Proxy для приложений без OIDC** | **Authentik outpost** или **OAuth2 Proxy** | Authentik: полноценный proxy с SCIM. OAuth2 Proxy: проще, уже развёрнут |
| **Минимум ресурсов** | **Rauthy** (35 MB) или **Pocket ID** (10 MB) | Rust/Go, embedded DB, zero config |
| **LDAP для NAS/Samba/SSSD** | **Kanidm** или **Casdoor** | Kanidm: read-only LDAPS gateway. Casdoor: полный LDAP server |
| **Максимум протоколов (SAML+LDAP+SCIM+CAS+RADIUS)** | **Casdoor** | Единственный с полным набором |
| **Proxy-first без admin UI** | **Authelia** | YAML-конфиг, OIDC certified, проверенный |
| **Enterprise IAM опыт для резюме** | **Keycloak** | Самый известный,最大的 экосистема |
| **SCIM provisioning из ZITADEL** | **ZITADEL** (server) → **Rauthy** (client) | ZITADEL push, Rauthy push下游 |
| **Passkey-only (максимальная простота)** | **Pocket ID** | Один passkey, без пароля, без лишнего |
| **Первый SSO в homelab (quickstart)** | **Authelia** + LDAP | Простейший путь: file/LDAP users + forward-auth + OIDC |

---

## 10. Что покрыто в других документах

- [authentication-services.md](./authentication-services.md) — полный обзор 21 сервиса с описаниями,
  учебный маршрут, рекомендации
- [oidc-support.md](./oidc-support.md) — матрица поддержки OIDC в конкретных сервисах homelab
  (Beszel, Immich, Gitea, Dawarich, Gatus, Nextcloud, Navidrome, Jellyfin и др.)
- [unified-identity-management.md](./unified-identity-management.md) — SCIM, JML lifecycle,
  Back-Channel Logout, «один клик — отключён везде», token introspection/revocation
