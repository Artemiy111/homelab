# Единый пользователь для всех сервисов: управление жизненным циклом учётных записей

Дата исследования: 2026-08-18.

## Короткий вывод

Единый пользователь для всех сервисов — это не один протокол, а **стек из трёх
слоёв**: OIDC/SAML для аутентификации («кто вошёл?»), SCIM для provisioning
(«существует ли учётная запись?»), и Back-Channel Logout для инвалидации сессий
(«вышел — и везде вышел»). Полное отключение пользователя одним кликом возможно,
но требует осознанных компромиссов: короткие lifetime токенов (5 минут) как
страховочная сеть, SCIM для deprovisioning приложений без back-channel logout,
и OAuth2 Proxy с Redis для приложений без собственного OIDC.

В текущем homelab: **ZITADEL** как IdP + **OAuth2 Proxy** для proxy-pattern
приложений — правильная архитектура. Для приложений без native OIDC стоит
рассмотреть Authentik proxy outpost как альтернативу OAuth2 Proxy, если нужен
более тесный контроль lifecycle.

---

## 1. Архитектура enterprise Identity Management

### Типовая схема

```
┌─────────────┐    SCIM/Push    ┌──────────────────┐
│  HR System  │───────────────>│  Identity Provider│
│ (source of  │                │  (ZITADEL/Okta/   │
│  truth)     │                │   Entra ID)       │
└─────────────┘                └────────┬─────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    │ OIDC/SAML         │ SCIM              │ Back-Channel
                    ▼                   ▼                   ▼
            ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
            │  Application │  │  Application │  │  Application │
            │  (Gitea)     │  │  (Immich)    │  │  (Nextcloud) │
            │  native OIDC │  │  native OIDC │  │  OIDC+SCIM   │
            └──────────────┘  └──────────────┘  └──────────────┘
```

**Источники:**
- https://guptadeepak.com/sso-deep-dive-saml-oauth-and-scim-in-enterprise-identity-management/
- https://www.stitchflow.com/blog/saml-oidc-scim-guide-it-leaders

### Три функциональных слоя

| Слой | Протокол | Вопрос | Стандарт |
|------|----------|--------|----------|
| **Аутентификация** | OIDC / SAML | «Кто это?» | [OIDC Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html), [SAML 2.0](https://docs.oasis-open.org/security/saml/v2.0/) |
| **Provisioning** | SCIM 2.0 | «Должна ли существовать учётная запись?» | [RFC 7643](https://datatracker.ietf.org/doc/html/rfc7643), [RFC 7644](https://datatracker.ietf.org/doc/html/rfc7644) |
| **Инвалидация сессий** | Back-Channel Logout | «Вышел — и везде вышел» | [OIDC Back-Channel 1.0](https://openid.net/specs/openid-connect-backchannel-1_0.html) |

Эти три слоя **не заменяют друг друга**. OIDC login не означает, что приложение
отдаст IdP свою модель прав. SCIM не заменяет аутентификацию. Back-channel
logout не работает без правильных lifetime токенов.

---

## 2. SCIM 2.0: автоматический provisioning и deprovisioning

### Что это

SCIM (System for Cross-domain Identity Management) — REST/JSON протокол для
автоматического создания, обновления и удаления учётных записей пользователя
в приложениях. IdP выступает SCIM-клиентом (push), приложение — SCIM-сервером
(accept).

**Источники:**
- RFC 7643 (Core Schema): https://datatracker.ietf.org/doc/html/rfc7643
- RFC 7644 (Protocol): https://datatracker.ietf.org/doc/html/rfc7644
- https://scim.cloud/

### Операции SCIM

| HTTP Method | Операция | Описание |
|---|---|---|
| `GET` | Retrieve | Чтение одного или нескольких ресурсов |
| `POST` | Create / Search / Bulk | Создание, поиск, пакетные операции |
| `PUT` | Replace | Полная замена ресурса |
| `PATCH` | Partial Update | Изменение отдельных атрибутов |
| `DELETE` | Remove | Удаление ресурса |

**Ключевые эндпоинты:**

| Эндпоинт | Назначение |
|---|---|
| `/Users` | Ресурсы пользователей |
| `/Groups` | Ресурсы групп |
| `/Bulk` | Пакетные операции (макс. 100 операций, 1MB payload в ZITADEL) |
| `/Schemas` | Обнаружение поддерживаемых схем |
| `/ServiceProviderConfig` | Обнаружение возможностей сервера |

### JIT vs SCIM: критическое различие

| Сценарий | JIT (Just-In-Time) | SCIM Push |
|----------|-------------------|-----------|
| Создание аккаунта при первом входе | ✅ | ✅ |
| Пред-провизирование (до первого входа) | ❌ | ✅ |
| Deprovisioning (удаление при увольнении) | ❌ **не может** | ✅ |
| Синхронизация атрибутов (смена роли) | ❌ только при входе | ✅ в реальном времени |
| Compliance (аудит) | ❌ | ✅ |

**Ключевой инсайт**: JIT и SCIM не взаимоисключающие. Типичный паттерн:
сначала JIT для удобства, затем добавление SCIM при возникновении потребности
в lifecycle/deprovisioning. Когда оба включены, SCIM должен быть source of truth,
а JIT — отключён для избежания конфликтов.

**Источники:**
- https://workos.com/guide/scim-vs-jit
- https://clerk.com/articles/scim-vs-jit-provisioning-when-to-use-each
- https://skycloak.io/blog/user-provisioning-explained/

### Поддержка SCIM в IdP

| IdP | SCIM | Примечания |
|-----|------|-----------|
| **Authentik** | Да (нативный) | SCIM provider для provisioning users/groups в внешние приложения |
| **ZITADEL** | Да (превью, v2.69+) | Только users (без groups). Будет за лицензией при GA |
| **Keycloak** | Через расширение | Не нативный; community SCIM 2.0 server extension |
| **Okta** | Да (нативный) | Как клиент, так и сервер |
| **Entra ID** | Да (нативный) | Полный provisioning в тысячи приложений |

**Источники:**
- Authentik SCIM: https://docs.goauthentik.io/add-secure-apps/providers/scim/
- ZITADEL SCIM: https://zitadel.com/docs/apis/scim2

---

## 3. Joiner-Mover-Leaver (JML): жизненный цикл пользователя

### Три фазы

| Фаза | Триггер | Действия |
|------|---------|----------|
| **Joiner** (Онбординг) | Новый сотрудник в HR | Создание аккаунта, назначение ролей/групп, day-one access |
| **Mover** (Смена роли) | Перевод, повышение | Обновление прав, удаление старого доступа, назначение нового |
| **Leaver** (Оффбординг) | Увольнение, окончание контракта | Отключение доступа ко всем системам, инвалидация сессий |

### Концепция «один клик — отключён везде»

Когда администратор отключает пользователя в IdP:

1. **IdP** — состояние пользователя → `deactivated`, новые токены не выдаются
2. **SCIM** — push `active: false` во все приложения с поддержкой SCIM
3. **Back-Channel Logout** — уведомления всем зарегистрированным RPs
4. **RPs** — очистка сессий и отзыв refresh токенов
5. **Страховочная сеть** — короткие lifetime токенов (5 минут) ограничивают окно уязвимости

**Реальность (2026)**: только ~34% организаций отключают доступ в день увольнения.
~50% бывших сотрудников сохраняют доступ к какой-то части систем.

**Источники:**
- https://www.miniorange.com/blog/joiners-movers-and-leavers/
- https://docs.evolveum.com/iam/iga/jml/
- https://learn.microsoft.com/en-us/entra/identity/users/users-revoke-access

---

## 4. Back-Channel Logout: инвалидация сессий

### Почему Front-Channel Logout мёртв (2026)

Front-channel logout использует iframe в браузере для уведомления RPs.
В 2026 году это **ненадёжно**:
- Safari (ITP), Chrome, Firefox блокируют third-party cookies в iframe
- Без cookies RPs не могут идентифицировать сессию для завершения
- Нет подтверждения доставки; таймауты при закрытии браузера

**Источник:** https://openid.net/specs/openid-connect-frontchannel-1_0.html

### Как работает Back-Channel Logout

```
1. Пользователь нажимает "Выйти" в приложении A
2. Браузер → end_session_endpoint IdP
3. IdP очищает свою сессию
4. Для каждого RP с активной сессией:
   a. IdP формирует Logout Token (подписанный JWT)
   b. IdP отправляет HTTP POST на backchannel_logout_uri каждого RP
      POST /backchannel_logout HTTP/1.1
      Content-Type: application/x-www-form-urlencoded
      logout_token=eyJhbGci...
5. RP валидирует токен (signature, iss, aud, exp, events claim)
6. RP очищает сессию по sid/sub
7. RP отвечает HTTP 200 OK
```

### Logout Token (структура)

| Claim | Обязателен | Описание |
|-------|-----------|----------|
| `iss` | Да | Issuer (IdP) |
| `aud` | Да | Audience (client_id RP) |
| `iat` | Да | Время создания |
| `exp` | Да | Истечение (рекомендуется ≤2 минуты) |
| `jti` | Да | Уникальный ID (защита от replay) |
| `events` | Да | Должен содержать `http://schemas.openid.net/event/backchannel-logout` |
| `sub` | Опционально | Subject (ID пользователя) |
| `sid` | Опционально | Session ID (конкретная сессия) |

**Источник:** https://openid.net/specs/openid-connect-backchannel-1_0.html

### Поддержка Back-Channel Logout

| Компонент | Поддержка | Примечания |
|-----------|----------|-----------|
| **ZITADEL** | Экспериментальная (feature flag) | С ~v2.69+, включается через `enable_back_channel_logout` |
| **Keycloak** | Да (нативный) | `backchannel.logout.url` в client attributes |
| **Authentik** | Нет | Не реализован |
| **OAuth2 Proxy** | Нет | [Open issue #1224](https://github.com/oauth2-proxy/oauth2-proxy/issues/1224) |
| **Spring Security** | Да (RP-side) | Встроенный endpoint |
| **Home Assistant** | Нет | Указано как missing feature |

---

## 5. Что происходит при отключении пользователя в ZITADEL

### Последовательность событий

1. **Состояние пользователя → `deactivated`**
2. **Новые токены не выдаются** — проверяется на:
   - Выдаче токена (code exchange, device auth)
   - Обновлении токена (refresh)
   - Userinfo endpoint
   - Token introspection
   - Генерации SAML attributes
3. **Существующие сессии НЕ инвалидируются немедленно** (аналогично Keycloak)
4. **Back-channel logout отправляется** если включён feature flag и приложения
   зарегистрировали `backchannel_logout_uri`
5. **Приложения, проверяющие introspection**, увидят `active: false`

### Проблема JWT

Access token — это通常 JWT: самодостаточный, криптографически подписанный,
валиден до `exp`. Если приложение проверяет JWT только локально (подпись +
expiry), оно **не узнает** об отключении пользователя.

**Решения:**
- Короткие lifetime токенов (5 минут) — ограничивают окно уязвимости
- Token introspection (RFC 7662) — единственная проверка server-side revocation
- Back-channel logout — proactive уведомление приложений
- SCIM push `active: false` — для приложений без OIDC logout

**Источники:**
- https://github.com/zitadel/zitadel/pull/8631
- https://zitadel.com/docs/guides/integrate/back-channel-logout

---

## 6. OAuth2 Proxy: слабое звено в цепочке

### Проблема

OAuth2 Proxy **не инвалидирует сессии** при ошибке обновления токена
с «Session not active» ([issue #1945](https://github.com/oauth2-proxy/oauth2-proxy/issues/1945)).
Если `cookie_refresh` не установлен, просроченные access tokens не проверяются —
cookie может жить дольше токена.

### Решения

1. **Redis backend** + `cookie_refresh=30s` + патч для fatal refresh errors
   (PR #3333) — кросс-приложенческий SSO logout работает в пределах 30 секунд
2. **Смена cookie secret** — инвалидирует ВСЕ сессии deployment'а (ядерная опция)
3. **Backend logout URL** — OAuth2 Proxy может вызвать logout URL при очистке сессии

### Фундаментальная проблема

OAuth2 Proxy спроектирован как stateless proxy. Он не поддерживает mapping
«пользователь → все сессии» для server-side revocation. Нельзя легко вылогинить
конкретного пользователя из всех сессий ([issue #1893](https://github.com/oauth2-proxy/oauth2-proxy/issues/1893)).

**Источники:**
- https://github.com/oauth2-proxy/oauth2-proxy/issues/1945
- https://github.com/oauth2-proxy/oauth2-proxy/issues/1893
- https://oauth2-proxy.github.io/oauth2-proxy/configuration/session_storage/

---

## 7. Token Introspection и Revocation

### RFC 7662: Token Introspection

Эндпоинт позволяет resource server проверить state токена у authorization server:

```json
// Активный токен
{
  "active": true,
  "client_id": "l238j323ds-23ij4",
  "username": "jdoe",
  "scope": "read write",
  "sub": "Z5O3upPC88QrAjx00dis",
  "exp": 1419356238
}

// Отозванный/просроченный токен
{
  "active": false
}
```

**ZITADEL:** `{CUSTOM_DOMAIN}/oauth/v2/introspect`

### RFC 7009: Token Revocation

Отзыв refresh token **должен** также инвалидировать все access tokens на том же grant.
Отзыв access token **может** также отозвать соответствующий refresh token.

**ZITADEL:** `{CUSTOM_DOMAIN}/oauth/v2/revoke`

**Источники:**
- https://www.rfc-editor.org/rfc/rfc7662
- https://www.rfc-editor.org/rfc/rfc7009
- https://zitadel.com/docs/apis/openidoauth/endpoints

---

## 8. Практическая архитектура для homelab

### Текущая архитектура (из существующих исследований)

```
Пользователь --passkey/WebAuthn--> ZITADEL --OIDC--> Native OIDC apps
                                       |
                                       +--OIDC--> OAuth2 Proxy --forwardAuth--> Non-OIDC apps
```

Общий cookie domain `.example.com` обеспечивает SSO-эффект.

**Источники:** [authentication-services.md](./authentication-services.md),
[oidc-support.md](./oidc-support.md)

### Рекомендации по «одному клику — отключён везде»

#### Приоритет 1: Короткие lifetime токенов

В ZITADEL установить:
- Access Token Lifetime: **5 минут** (максимум для безопасности)
- Refresh Token Lifetime: **24 часа** (для удобства)
- Источник: https://zitadel.com/docs/guides/manage/user/lifetimes

#### Приоритет 2: Back-Channel Logout в ZITADEL

Включить experimental feature flag:
```
FEATURES_LOGINV2_REQUIRED=true
FEATURES_ENABLE_BACK_CHANNEL_LOGOUT=true
```
Для каждого OIDC-клиента зарегистрировать `backchannel_logout_uri`.

Источник: https://zitadel.com/docs/guides/integrate/back-channel-logout

#### Приоритет 3: OAuth2 Proxy с Redis

Перейти с cookie storage на Redis:
- Добавить Redis container
- Настроить `--session-store=redis`
- Установить `--cookie-refresh=30s`
- Рассмотреть патч для fatal refresh errors (PR #3333)

#### Приоритет 4: SCIM для поддерживаемых приложений

Настроить SCIM provisioning в ZITADEL для приложений, которые его поддерживают.
Пока ZITADEL SCIM в превью — это учебная площадка, а не production solution.

#### Приоритет 5: Аудит доступа

Регулярно (раз в квартал) проверять:
- Все OIDC-сессии пользователя в ZITADEL (event-sourced → полный audit trail)
- Все активные сессии в OAuth2 Proxy (Redis)
- Соответствие между provisioning и реальным использованием

### Сравнение: Authentik vs ZITADEL для "одного клика"

| Критерий | ZITADEL | Authentik |
|----------|---------|-----------|
| Disable → immediate token rejection | Да (при refresh/introspection) | Да |
| Proxy mode (приложения без OIDC) | Нет | **Да** (major advantage) |
| SCIM | Превью (users only) | Нативный |
| Back-Channel Logout | Экспериментальный | Нет |
| LDAP server | Нет | Да |
| Расход ресурсов | **~100 MB** (Go) | ~300 MB (Python) |
| UI | Современный (Login V2) | Интуитивный |

**Вывод для homelab**: ZITADEL оптимален как primary IdP для OIDC/SAML
приложений. Для приложений без native OIDC использовать OAuth2 Proxy (уже
развёрнут) или Authentik proxy outpost (если нужен более тесный lifecycle
контроль и SCIM).

---

## 9. Полная цепочка «отключён везде»

```
1. Администратор отключает пользователя в ZITADEL
   └─ Состояние → deactivated
   └─ Новые токены не выдаются

2. ZITADEL отправляет Back-Channel Logout
   └─ POST /backchannel_logout_uri для каждого RP с активной сессией
   └─ Logout Token (JWT с sid/sub)

3. Приложения с Back-Channel Logout
   └─ Валидируют Logout Token
   └─ Очищают сессии
   └─ Отзывают refresh tokens

4. Приложения с OIDC (без Back-Channel)
   └─ При следующем refresh → ошибка → сессия очищается
   └─ Окно уязвимости = access token lifetime (5 мин)

5. OAuth2 Proxy (Redis + cookie_refresh=30s)
   └─ При следующем refresh (≤30 сек) → ошибка → сессия очищается
   └─ Окно уязвимости = до 30 секунд

6. Приложения без OIDC (proxy-only)
   └─ Authentik outpost: отключение = немедленный отказ в аутентификации
   └─ OAuth2 Proxy: отключение = ошибка при refresh (≤30 сек)

7. Страховочная сеть
   └─ Access token истекает через ≤5 минут
   └─ Refresh token не обновляется для deactivated users
```

### Оставшееся окно уязвимости

| Тип приложения | Максимальное окно | Как минимизировать |
|---------------|-------------------|-------------------|
| OIDC + Back-Channel Logout | **Немедленно** | Включить feature flag в ZITADEL |
| OIDC без Back-Channel | **5 минут** | Access token lifetime = 5 мин |
| OAuth2 Proxy (Redis) | **30 секунд** | cookie_refresh = 30s |
| Authentik Proxy | **Немедленно** | Отключение в Authentik = отказ |
| Приложение без qualquer SSO | **Бессрочно** | Подключить к IdP через OIDC/proxy |

---

## 10. Стандарты и RFC

| Стандарт | RFC/Spec | Назначение |
|----------|----------|-----------|
| OAuth 2.0 | [RFC 6749](https://datatracker.ietf.org/doc/html/rfc6749) | Делегированная авторизация |
| OIDC Core | [OIDC 1.0](https://openid.net/specs/openid-connect-core-1_0.html) | Аутентификация поверх OAuth 2.0 |
| OIDC Back-Channel Logout | [Spec](https://openid.net/specs/openid-connect-backchannel-1_0.html) | Server-to-server инвалидация сессий |
| OIDC Front-Channel Logout | [Spec](https://openid.net/specs/openid-connect-frontchannel-1_0.html) | Browser-based logout (ненадёжный в 2026) |
| SCIM Core | [RFC 7643](https://datatracker.ietf.org/doc/html/rfc7643) | Schema для User/Group ресурсов |
| SCIM Protocol | [RFC 7644](https://datatracker.ietf.org/doc/html/rfc7644) | REST API для provisioning |
| Token Introspection | [RFC 7662](https://datatracker.ietf.org/doc/html/rfc7662) | Проверка state токена |
| Token Revocation | [RFC 7009](https://datatracker.ietf.org/doc/html/rfc7009) | Отзыв токенов |
| WebAuthn | [W3C Spec](https://www.w3.org/TR/webauthn-3/) | Passkeys / биометрическая аутентификация |
| OAuth 2.0 Security BCP | [RFC 9700](https://datatracker.ietf.org/doc/html/rfc9700) | Лучшие практики безопасности |
| TOTP | [RFC 6238](https://datatracker.ietf.org/doc/html/rfc6238) | Временные одноразовые пароли |
| LDAP | [RFC 4511](https://datatracker.ietf.org/doc/html/rfc4511) | Directory Access Protocol |
| SAML 2.0 | [OASIS](https://docs.oasis-open.org/security/saml/v2.0/) | XML-based федерация |

---

## 11. Учебный маршрут

### Этап 1: Понять OIDC flow

Подключить одно приложение (Beszel, Gitea), проверить discovery, JWKS,
Authorization Code + PKCE, claims, logout, key rotation.

### Этап 2: Passkeys и recovery

Настроить passkey-only в ZITADEL, проверить recovery при потере устройства.

### Этап 3: Proxy pattern

Защитить тестовый whoami через OAuth2 Proxy перед ZITADEL, посмотреть headers.

### Этап 4: Back-Channel Logout

Включить feature flag в ZITADEL, зарегистрировать backchannel_logout_uri
на тестовом приложении, проверить инвалидацию сессий.

### Этап 5: SCIM и lifecycle

Настроить SCIM provisioning в ZITADEL, проверить создание/отключение
пользователя и его влияние на downstream приложения.

### Этап 6: Аудит и мониторинг

Настроить логирование OIDC событий, проверить event stream ZITADEL,
проверить активные сессии в OAuth2 Proxy.

---

## 12. Чего НЕ нужно для homelab

- **LDAP server** — нужен только для legacy приложений (NAS, старые web UI)
- **SAML** — избыточен для homelab; ценно только для enterprise SaaS
- **Kerberos** — сетевой/desktop SSO, не нужен для web приложений
- **RADIUS** — только если есть сетевая инфраструктура (WiFi 802.1X)
- **Cerbos/PDP** — для разработки собственного API, а не готовых сервисов
- **Teleport** — infrastructure access (SSH, K8s), а не web SSO
- **Identity Governance (IGA)** —过kill для homelab; аудит вручную
