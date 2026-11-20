# Матрица провайдеров IdP, протоколов и жизненный цикл учёток

Дата проверки: 2026-11-20 (сравнение провайдеров — 2026-08-18; состояние
стенда — 2026-11-20).

Компактные таблицы сравнения всех параметров провайдеров, практика
«одного клика — отключён везде», сводная матрица решений и жизненный
цикл учёток. Дополнение к [per-service-auth-strategies.md](per-service-auth-strategies.md)
— матрица поддержки OIDC в конкретных сервисах homelab и состояние
стенда на сегодня.

---

## 0. Состояние стенда на 2026-11-20

- **ZITADEL v4.20.0** — основной IdP. Организация `homelab`, проект,
  OIDC-приложения и политики логина описаны в Terraform
  (`infra/casa/terraform/zitadel/`). Вход — по домену `id.example.com`
  (Login V2).
- **ZITADEL + HashiCorp Vault** — исследование:
  [zitadel-vault.md](zitadel-vault.md). В стенде Vault приложениям
  сейчас в основном входит через аутентификатор `kubernetes`
  (`infra/casa/terraform/vault/k8s.tf`): человеческий доступ — root-токен,
  пользователь в человеческом интерфейсе — локальный администратор.
- **Authentik** — развёрнут как тестовый стенд (`apps/casa/authentik/`).
  Ни один из приложений не смотрит его пользователей.
- **OAuth2 Proxy v7.15.5** — перед приложениями без своей
  аутентификации (список в §3). Подключён к ZITADEL через OIDC-клиент
  `Oauth Proxy` (Terraform `applications.tf`), сессии — в cookie (без
  Redis), callback — `https://oauth.example.com/oauth2/callback`.
- **Argo CD** — локальный вход через admin (`server.secretkey` +
  `admin.enabled`), OIDC-конфиг настраивается руками через эти строки
  `values.yaml` в `platform/casa/argocd/` (в git закомментирован, заморожен).

### Текущие OIDC-клиенты ZITADEL (`infra/casa/terraform/zitadel/applications.tf`)

| Клиент | Сейчас в кластере | Для чего |
|---|---|---|
| **Oauth Proxy** | ✅ в использовании (ForwardAuth, секрет в `kv/oauth2-proxy/oidc`) | Structurizr, Grafana, Filestash, OpenList, Element Admin, Trivy Operator Dashboard |
| **Beszel** | ⚠️ клиент создан, приложение выведено из эксплуатации | BackupHub |
| **GlitchTip** | ✅ | Push-вход в GlitchTip |
| **Home Assistant** | ✅ (`hass-oidc-auth`, пароль отключён) | См. per-service-auth-strategies.md |
| **Immich** | ✅ (OCR, mobile redirect, backchannel_logout_uri) | Файлы и датачи |
| **Zot** | ⚠️ клиент создан, но реестр анонимный | CI-кэши |
| **Element (Synapse)** | ⚠️ клиент есть, вход через **MAS**, приложение legacy | Основной вход — MAS |
| **Matrix Authentication Service** | ✅ (upstream `oidc-zitadel`) | Вход в матрицу |
| **Forgejo** | ✅ (account-linking, admin group, локальный вход остаётся) | GitOps |

---

## 1. Терминология

Источник порядов: [SSO](https://en.wikipedia.org/wiki/Single_sign-on),
[OAuth 2.0 RFC 6749](https://datatracker.ietf.org/doc/html/rfc6749),
[OIDC Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html).

| Механизм | Что решает | Насколько нужен в homelab | Насколько полезен на работе |
| --- | --- | --- | --- |
| **OIDC** | Web/mobile SSO поверх OAuth 2.0; ID Token + верификация по JWKS | **Основной выбор** | **Обязателен** для IAM/backend |
| **OAuth 2.0** | Делегированный доступ к API | Нужен как основа OIDC | **Обязателен** |
| **SAML 2.0** | XML-федерация входа | Только лаборатории/старые SaaS | **Очень полезен** в enterprise |
| **LDAP/LDAPS** | Доступ к каталогу (NAS/Samba/SSSD) | Нужен лишь для legacy/NAS | **Полезен** для AD/legacy |
| **SCIM 2.0** | Провижининг/депровижининг пользователей | Редко избыточен | **Очень полезен** для lifecycle |
| **WebAuthn/passkeys** | Phishing-resistant вход пользователя | **Рекомендуется** | Растёт практическая ценность |
| **TOTP** | 2-й фактор по секрету | Полезный fallback | Распространён, слабее passkeys |
| **Forward auth** | Reverse proxy спрашивает внешний сервис перед пропуском | Удобен для старых UI | Не внутренний вход приложения |
| **Back-Channel Logout / Introspection / Revocation** | Инвалидация сессий и отзыв | Важно для lifecycle | Важно |

Где каждый пункт по важности: **SSO (OIDC/SAML) — «кто вошёл»; SCIM —
«должна ли учётка существовать»; Back-Channel Logout — «вышел — и везде
вышел»**. Три слоя не заменяют друг друга (см. §7).

Оценка «работа» — **переносимость изученных концепций** из enterprise на
работе, не статистика вакансий: 5/5 — прямой опыт; 1/5 — узкий сценарий.

---

## 2. Провайдеры: каталог (сравнение обновлено 2026-08-18)

### Группы

- **Full IdP**: ZITADEL, Keycloak, Authentik, Casdoor
- **Lightweight IdP**: Rauthy, Kanidm, Pocket ID
- **Proxy-first / Auth gateways**: Authelia, Tinyauth, VoidAuth
- **Tooling**: OAuth2 Proxy (не IdP, а компонент)

### 2.1 Протоколы

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

¹ ZITADEL SCIM server в превью (v2.69+), только Users (без Groups).
² Keycloak SCIM — через community extension, не нативный.
³ Casdoor SCIM client — syncer (pull FROM внешних SCIM серверов).
⁴ Kanidm LDAP — read-only LDAPS gateway.
⁵ Kanidm SCIM server — inbound.
⁶ Kanidm RADIUS — отдельный container.
⁷ Authelia OIDC — сертифицирован, но upstream всё ещё называет «beta».
⁸ Tinyauth OIDC — OpenID Certified Basic OP с v5.1.

### 2.2 Методы аутентификации

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

⁹ Casdoor поддерживает 50+ social providers.
¹⁰ Rauthy: social login через «Upstream Authentication Providers» (beta).
¹¹ Authelia: WebAuthn + TOTP или Duo Push (не chaining).
¹² Tinyauth: passkeys через OAuth-провайдеры, не нативные на форме.
¹³ Tinyauth: social login через OAuth (GitHub, Pocket ID, др.).

### 2.3 Proxy / forward-auth

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

¹⁴ Keycloak HTTP Proxy (Quarkus) для conflating, но не полноценный proxy outpost.
¹⁵ Casdoor forward-auth — отдельный сервис `casdoor-forward-auth` + Traefik plugin.

### 2.4 Логаут и инвалидация сессий

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

¹⁶ ZITADEL BCL — экспериментальный feature flag, с ~v2.69+ (v4.20.0 деплоится с LoginV2; Immich имеет registered `backchannel_logout_uri`).
¹⁷ ZITADEL: при деактивации JWT не получают новые токены (RFC-комплаенс); существующие JWT валидны до `exp`.
¹⁸ Keycloak: отключение пользователя НЕ инвалидирует активные сессии (by design).
¹⁹ Pocket ID: отключение = нет новых OIDC sessions; cookie-сессии живут до истечения.
²⁰ Tinyauth/VoidAuth: отключение = отказ при следующей проверке (cookie-сессии).
²¹ OAuth2 Proxy: open issue #1224.
²² OAuth2 Proxy: не инвалидирует сессии при refresh failure без патча (issue #1945).

### 2.5 Multi-tenancy и авторизация

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
²⁴ Keycloak: Realms.
²⁵ Authelia: Базовый multi-tenancy (не first-class как ZITADEL).
²⁶ Casdoor: Organizations с org-level SSO, ролями, branding.
²⁷ Casdoor: ACL, RBAC, ABAC через Casbin. Самая гибкая модель авторизации.
²⁸ Rauthy: Custom roles, custom groups, group-prefix restrictions.
²⁹ Rauthy: Делегированные group admin'ы, admin API keys.
³⁰ Kanidm: Group-based scope mapping.
³¹ Pocket ID: self-service отключён по умолчанию; passkey management через UI.
³² Authelia: Rule-based ACL (per-subdomain, per-user, per-group, per-network).
³³ Authelia: Self-service — password reset через email. Без self-registration.
³⁴ Tinyauth: LDAP groups используются только для proxy ACL, не в OIDC claims.
³⁵ VoidAuth: Groups-based (security groups, admin group).

### 2.6 Технические характеристики

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

³⁶ ZITADEL AGPL-3.0 с Apache/MIT исключениями для SDK.
³⁷ Hiqlite — встроенный embedded SQLite + Raft consensus.

### 2.7 Развёртывание и сопровождение

| Провайдер | Helm chart (офиц.) | K8s docs | Docker Compose | CLI admin | Web admin UI | Самостоятельный signup |
|-----------|:------------------:|:--------:|:--------------:|:---------:|:------------:|:----------------------:|
| **ZITADEL** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅³⁸ |
| **Keycloak** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Authentik** | ❌³⁹ | ✅ | ✅ | ❌ | ✅ | ✅ |
| **Casdoor** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Rauthy** | ⚠️⁴⁰ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Kanidm** | ⚠️⁴⁰ | ✅ | ✅ | ❌⁴¹ | ✅⁴² | ✅ |
| **Pocket ID** | ❌ | ❌ | ✅ | ❌ | ✅ | ⚠️⁴³ |
| **Authelia** | ✅ | ✅ | ✅ | ❌⁴⁴ | ❌⁴⁵ | ❌⁴⁶ |
| **Tinyauth** | ⚠️⁴⁰ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **VoidAuth** | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |

³⁸ ZITADEL: self-service registration через hosted login UI; passkey-only через API.
³⁹ Authentik: официального Helm chart нет; развёртывание через Kustomize/manifests.
⁴⁰ Community Helm chart есть, но не official.
⁴¹ Kanidm: WebUI для user self-service, admin — через CLI.
⁴² Pocket ID: неприменимо (Provider).
⁴³ Pocket ID: self-service отключён по умолчанию; one-time signup links.
⁴⁴ Authelia: конфигурация через YAML, нет web admin UI.
⁴⁵ Authelia: пользователи — через LDAP/файл, self-registration нет.
⁴⁶ Authelia: пользователи создаются из LDAP или файла.

### 2.8 Сводная оценка для homelab

| Провайдер | Homelab | Работа (enterprise IAM) | Главный преимущество | Главный недостаток |
|-----------|:-------:|:-----------------------:|---------------------|-------------------|
| **ZITADEL** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Enterprise набор при малом footprint | Нет proxy mode |
| **Keycloak** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Самый зрелый, максимальное покрытие | Тяжёлый (Java RAM) |
| **Authentik** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | Proxy outpost + flows/stages | Тяжелее ZITADEL по RAM |
| **Casdoor** | ⭐⭐⭐ | ⭐⭐⭐ | Широчайший набор протоколов | Много движущихся частей |
| **Rauthy** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | Минимальный footprint + SCIM client + forward-auth | Нет SAML/LDAP/multi-tenancy |
| **Kanidm** | ⭐⭐⭐ | ⭐⭐⭐⭐ | LDAP gateway + passkeys + Rust performance | CLI-first, нет proxy mode |
| **Pocket ID** | ⭐⭐⭐⭐ | ⭐⭐ | Простейший passkey-only OIDC | Узкий функционал |
| **Authelia** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | Proxy-first + OIDC certified | Нет admin UI, конфиг через YAML |
| **Tinyauth** | ⭐⭐⭐⭐ | ⭐⭐ | Минимальный footprint + OIDC certified | Нет self-service, нет RBAC |
| **VoidAuth** | ⭐⭐⭐ | ⭐⭐ | LDAP server + OIDC + forward-auth в одном | Молодой, нет security audit |
| **OAuth2 Proxy** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | De facto standard для proxy auth | Не IdP, нет logout orchestration |

### 2.9 Матрица решений: какой IdP для какой задачи

| Задача | Лучший выбор | Зачем |
|--------|-------------|-------|
| **Единый IdP для всего homelab** | **ZITADEL** | OIDC-certified, RBAC, modern UI, ~100 MB RAM |
| **Proxy для приложений без OIDC** | **OAuth2 Proxy** | Уже деплоится, CNCF Sandbox, подключен к ZITADEL |
| **Минимум ресурсов** | **Rauthy** (35 MB) или **Pocket ID** (10 MB) | Rust/Go, embedded DB, zero config |
| **LDAP для NAS/Samba/SSSD** | **Kanidm** (read-only) или **Casdoor** (full server) | |
| **Максимум протоколов (SAML+LDAP+SCIM+CAS+RADIUS)** | **Casdoor** | |
| **Proxy-first без admin UI** | **Authelia** | YAML-конфиг, OIDC certified |
| **Enterprise IAM опыт для резюме** | **Keycloak** | Самый известный в энтерпрайзе |
| **Passkey-only (максимальная простота)** | **Pocket ID** | Один passkey, без пароля |
| **Первый SSO в homelab (quickstart)** | **Authelia** + LDAP | Самый простой путь |
| **SCIM provisioning из ZITADEL** | **ZITADEL** → **Rauthy** | ZITADEL push, Rauthy push дальше |
| **Вход в собственный product SaaS** | **ZITADEL** / **Logto** / **FusionAuth** | |

---

## 3. OAuth2 Proxy — как подключён сейчас

Запущен: `quay.io/oauth2-proxy/oauth2-proxy:v7.15.5`
(`apps/casa/oauth2-proxy/manifests/deployment.yaml`).

- **Режим**: forwardAuth для Traefik (`upstream=static://202`) — oauth2-proxy не
  проксирует приложение, а проверяет аутентификацию.
- **IdP**: ZITADEL (`--oidc-issuer-url=https://id.example.com`), клиент
  `Oauth Proxy`; callback — `https://oauth.example.com/oauth2/callback`.
- **Сессии**: в cookie (`--upstream`-стиль, без Redis). Без
  `--cookie-refresh` и без патча для fatal refresh errors — ссылки в документе
  выше остаются актуальны (issues #1945, #1224).
- **Передаёт upstream**: `X-Auth-Request-User`, `X-Auth-Request-Email`,
  `X-Forwarded-User`, `X-Forwarded-Email`, `X-Forwarded-Groups`.
- **Сейчас подключён** к: Structurizr, Grafana, Filestash, OpenList,
  Element Admin, Trivy Operator Dashboard, VictoriaMetrics, Longhorn,
  Traefik dashboard (`platform/casa/traefik/manifests/oauth2-proxy.middleware.yaml`).
- **Страховочные тексты уже закладываются**: Redis + `--cookie-refresh=30s`
  — и после обновления будет видно, что меняется.
- **Приложения, на которые обязательно посмотреть**: [per-service-auth-strategies.md](per-service-auth-strategies.md).

---

## 4. Жизненный цикл учёток (2026-11-20)

Источник — собственное исследование: рефы в коде (`infra/casa/terraform/zitadel/`,
манифесты приложений) + ссылки на документацию провайдеров. Ключевой сайт
приоритета — ZITADEL-техника, потому что все приложения, кроме Argo CD и
Authentik, аутентифицируются в нём; OAuth2 Proxy отдельно — [§3](#3-oauth2-proxy--как-подключён-сейчас).

### 4.1 Три функциональных слоя

| Слой | Протокол | Вопрос | Стандарт |
|------|----------|--------|----------|
| **Аутентификация** | OIDC / SAML | «Кто это?» | [OIDC Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html) |
| **Provisioning** | SCIM 2.0 | «Должна ли учётка существовать?» | [RFC 7643](https://datatracker.ietf.org/doc/html/rfc7643) |
| **Инвалидация сессий** | Back-Channel Logout | «Вышел — и везде вышел» | [OIDC BCL 1.0](https://openid.net/specs/openid-connect-backchannel-1_0.html) |

### 4.2 SCIM 2.0 (провизионинг)

Поддержка IdP: Authentik (нативный), ZITADEL (превью), Casdoor
(sync pull/push), Rauthy (client push), Kanidm (inbound).

Практический вывод для homelab: ни один из наших приложений не принимает
SCIM, ни одно из них не является SCIM-сервером — это enterprise SaaS
(Slack, GitHub Enterprise, Jira). Но JIT и SCIM не взаимоисключающие:
типичный паттерн для нашей траектории: пока JIT на нескольких приложениях,
добавить SCIM при появлении lifecycle. Когда оба — SCIM must be source of
truth, JIT отключается (ссылка на матрицу сравнения —
[SCIM vs JIT](https://workos.com/guide/scim-vs-jit)).

### 4.3 JML (Joiner-Mover-Leaver)

Сейчас не реализовано как единая система (полное отключение в день
увольнения ~34%, без SCIM ~50% — источник: статья в документации lifecycle).
Траектория для homelab:

1. Администратор отключает в ZITADEL → нет новых токенов.
2. SCIM-push `active: false` в поддерживающих приложениях.
3. Back-Channel Logout — POST /backchannel_logout_uri.
4. Очистка сессий и отзыв refresh-токенов.
5. Страховочный сет: lifetime токенов 5 минут.

### 4.4 Что происходит при отключении пользователя в ZITADEL

1. `deactivated` — новые токены не выдаются.
2. Существующие сессии НЕ инвалидируются мгновенно (окно = lifetime
   активного токена).
3. Back-Channel Logout — только экспериментально (v4.x); возможно включать
   позже вручную.

**Проблема JWT для OAuth2 Proxy и приложений без BCL**: токен валиден до
`exp`; проверка `active: false` — только через introspection.

### 4.5 Стратегия «одно клик — отключён везде»

| Приоритет | Смысл |
|-----------|-------|
| Приоритет 1 | Для ZITADEL-приложений: короткие lifetime токенов (5 мин access, 24 ч refresh). Список для ручной правки — в `infra/casa/terraform/zitadel/` |
| Приоритет 2 | Immich — зарегистрировать `backchannel_logout_uri` (уже в Terraform) |
| Приоритет 3 | OAuth2 Proxy — Redis, `--cookie-refresh=30s` + патч #3333 |
| Приоритет 4 | SCIM в ZITADEL (превью) |
| Приоритет 5 | Аудит: ZITADEL event stream, раз в квартал |

### 4.6 Окна уязвимости (homelab, ZITADEL-цепочка)

| Тип приложения | Окно | Как минимизировать |
|---|---|---|
| Приложение с OIDC | Зависит от BCL; fallback 5-минное (access lifetime) | Ждать GA BCL |
| Structurizr / Filestash / OpenList / Element Admin / Trivy Operator Dashboard и др. через OAuth2 Proxy | 30 сек (cookie_refresh=30s) | Проксить только приложения с OIDC, если есть силы на обновление |
| Без OIDC вообще (Pi-hole, 3x-ui, etc.) | Не мигрируют, пока не подключены | — |

### 4.7 Standards

[RFC 6749](https://datatracker.ietf.org/doc/html/rfc6749),
[OIDC Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html),
[OIDC BCL 1.0](https://openid.net/specs/openid-connect-backchannel-1_0.html),
[RFC 7662 Introspection](https://www.rfc-editor.org/rfc/rfc7662),
[RFC 7009 Revocation](https://www.rfc-editor.org/rfc/rfc7009),
[RFC 9700 OAuth 2.0 Security BCP](https://datatracker.ietf.org/doc/html/rfc9700),
[WebAuthn/FIDO2](https://www.w3.org/TR/webauthn-3/),
[RFC 6238 TOTP](https://datatracker.ietf.org/doc/html/rfc6238),
[RFC 4511 LDAP](https://datatracker.ietf.org/doc/html/rfc4511),
[OASIS SAML 2.0](https://docs.oasis-open.org/security/saml/v2.0/).

### 4.8 Текущий homelab под одной крышей

```
User —passkey/WebAuthn→ ZITADEL —OIDC→ Native OIDC apps (Forgejo, Immich,
                                          GlitchTip, MAS, Home Assistant)
                                      |
                                      +--OIDC--> OAuth2 Proxy —forwardAuth→
                                                 Structurizr, Grafana, Filestash...
```

---

## 5. Учебный маршрут

### 5.1 Этап 1: Нормальный OIDC flow в ZITADEL

Подключить одно простое приложение, проверить: discovery, JWKS, Code+PKCE,
state/nonce, claims, короткие токены, logout, refresh-rotation, key rotation.

### 5.2 Этап 2: Passkeys и recovery

Passwordless в ZITADEL + две passkey на независимых устройствах.

### 5.3 Этап 3: Proxy pattern

Прокси для тестового `whoami` через OAuth2 Proxy + Identity Headers; показать,
что direct access закрыт.

### 5.4 Этап 4: Back-Channel Logout

Правильно сейчас — контролировать deactivation программно и читать event
stream из ZITADEL (§4.5).

### 5.5 Этап 5: SCIM и lifecycle

SCIM — только через Rauthy или proxy-ы (§2.5); задокументировать, как
deprovisioning выглядит в текущей траектории (JIT не делает), связать с §4.5.

### 5.6 Этап 6: Аудит

Собирать открытые сессии, менять пароль админа ZITADEL изнутри, restart-ить
ZITADEL с [секретными паролями](../secrets/secret-management-providers.md).

---

## 6. Чего НЕ нужно в homelab

- **LDAP server** — только для legacy (NAS, старые web UI).
- **SAML** — ценна только в enterprise SaaS.
- **Kerberos** — desktop SSO, не нужен для web.
- **RADIUS** — только при WiFi 802.1X.
- **Cerbos/PDP** — для собственного API.
- **Teleport** — SSH/K8s, не web SSO.
- **Identity Governance** — «у нас нет человека, у нас есть админ».

---

## 7. Как ставить задачи и заполнять эту матрицу

- Топик — папка темы; файл — автономно по себе.
- Первая строка после заголовка: «Дата проверки: YYYY-MM-DD».
- Состояние стенда переверяется по рефам в коде и манифестах, которые можно
  открыть: список приложений ZITADEL — `infra/casa/terraform/zitadel/applications.tf` (§0),
  конфигурация OAuth2 Proxy — `apps/casa/oauth2-proxy/manifests/`,
  шлюз forwardAuth — `platform/casa/traefik/manifests/oauth2-proxy.middleware.yaml`.
- Спорные факты по провайдерам — на первичных источниках (ссылки в таблицах);
  если они изменились, обновите дату провайдеров в шапке.
- Список сервисов и описание фактов — [per-service-auth-strategies.md](per-service-auth-strategies.md).
