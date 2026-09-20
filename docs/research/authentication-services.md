# Сервисы аутентификации и авторизации для homelab

Дата проверки: 2026-08-16.

## Короткий вывод

Для этого homelab оптимальный основной сервис — **ZITADEL**. Он закрывает
enterprise-набор (OIDC-certified, SAML 2.0, SCIM 2.0, LDAP, RBAC, multi-tenancy/
organizations, passkeys), но при этом это один Go-бинарь поверх одного
PostgreSQL: по официальной документации достаточно 1 CPU и 512 MB. Актуальный
интерфейс Login V2 и консоль заметно чище и современнее authentik, а памяти и
движущихся частей меньше (нет Redis, Celery worker и outposts). authentik
оставить как вторичный стенд ради proxy outposts и flows/stages — это его
реальное преимущество. **Pocket ID** полезен как очень простой passkey-only
OIDC Provider, но он покрывает только узкий и современный сценарий; держать два
независимых источника пользователей и два набора OIDC clients как постоянную
архитектуру не стоит.

Практическое решение:

1. Новые интеграции делать через **native OIDC** с ZITADEL. Начать с Beszel,
   Gitea, Dawarich, Gatus и Immich по уже составленной
   [матрице поддержки](./oidc-support.md).
2. Passkey оставить способом входа **в ZITADEL**, а OIDC — способом передачи
   результата входа приложениям. Это не взаимоисключающие варианты.
3. Для приложений без OIDC использовать **OAuth2 Proxy перед ZITADEL** (нативных
   proxy outposts у ZITADEL нет), когда приложению достаточно внешнего барьера
   либо оно явно умеет доверять заголовку пользователя. authentik outposts —
   только если потребуется именно его proxy-модель.
4. Pocket ID оставить на время миграции и как сравнительный стенд. После переноса
   клиентов и проверки аварийного доступа выбрать один основной IdP.
5. Keycloak изучить отдельным временным стендом, а не постоянным IdP: для
   рабочего кругозора он особенно ценен, но это Java-приложение с заметно
   большим потреблением памяти (≥ 750 MB–2 GB).

## Сначала разложим термины

### Authentication, authorization и provisioning

- **Аутентификация (AuthN)** отвечает на вопрос «кто это?»: пароль, passkey,
  сертификат, TOTP и другие доказательства личности.
- **Авторизация (AuthZ)** отвечает на вопрос «что этому субъекту можно?». IdP
  может передать группы, роли и claims, но конечное решение обычно принимает
  само приложение или отдельный policy decision point наподобие Cerbos.
- **Provisioning** создаёт, обновляет и удаляет учётные записи. Для этого в
  организациях используется SCIM; его HTTP-протокол определён в
  [RFC 7644](https://datatracker.ietf.org/doc/html/rfc7644). Сам факт успешного
  SSO не гарантирует своевременного удаления учётной записи из приложения.

Эти функции связаны, но не заменяют друг друга. В частности, OIDC login не
означает, что приложение отдаст IdP всю свою модель прав.

### SSO

**Single Sign-On** — не отдельный протокол, а пользовательский результат: одна
сессия у Identity Provider (IdP) позволяет открыть несколько приложений без
повторного ввода учётных данных. Приложение при этом является OIDC Relying Party
или SAML Service Provider. Централизованный вход улучшает отзыв доступа и MFA,
но делает IdP критической точкой: нужны backup, проверенный recovery и как
минимум две независимые passkey администратора.

### OIDC и OAuth 2.0

**OAuth 2.0** — framework делегированной **авторизации**, а не протокол входа;
это прямо определено в [RFC 6749](https://datatracker.ietf.org/doc/html/rfc6749).
**OpenID Connect (OIDC)** добавляет к OAuth 2.0 слой аутентификации, ID Token и
стандартизованные claims; это определено в
[OIDC Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html).

Для нового web/mobile-клиента следует учить Authorization Code flow, PKCE,
проверку `issuer`, `aud`, `nonce`, подписи по JWKS и короткоживущие tokens.
Актуальные меры безопасности, включая отказ от implicit grant и защиту от
подмены redirect, собраны в
[OAuth 2.0 Security Best Current Practice, RFC 9700](https://datatracker.ietf.org/doc/html/rfc9700).
OIDC — главный практический выбор для современных приложений и основной
стандарт, который имеет смысл внедрять в homelab.

### Passkeys и WebAuthn

**Passkey** — способ аутентифицировать пользователя у конкретного сайта/IdP на
основе пары криптографических ключей. WebAuthn определяет browser API и модель
Relying Party в [спецификации W3C](https://www.w3.org/TR/webauthn-3/), а FIDO
описывает passkeys как замену паролям на базе FIDO/WebAuthn в
[своём обзоре](https://fidoalliance.org/passkeys/).

Passkey не выполняет SSO сама по себе. Типовая цепочка выглядит так:

```text
пользователь --passkey/WebAuthn--> ZITADEL --OIDC/SAML--> приложение
```

Поэтому вопрос «OIDC или passkey?» некорректен: обычно нужны оба слоя. Для дома
passkey-only удобен, но необходимо заранее проверить recovery при потере телефона,
ноутбука или security key.

### SAML, LDAP, SCIM и proxy auth

| Механизм | Что решает | Насколько нужен дома | Насколько полезен на работе |
| --- | --- | --- | --- |
| **OIDC** | Современный web/mobile SSO поверх OAuth 2.0 | **Основной выбор** | **Обязателен** для IAM/backend/platform работы |
| **OAuth 2.0** | Делегированный доступ к API | Нужен как основа OIDC и для API | **Обязателен**, но не следует называть OAuth login полноценным OIDC без ID Token |
| **SAML 2.0** | XML-based федерация браузерного входа | Обычно только для лаборатории или старого приложения | **Очень полезен**: по-прежнему встречается в enterprise SaaS; стандарт опубликован [OASIS](https://docs.oasis-open.org/security/saml/v2.0/) |
| **LDAP/LDAPS** | Доступ к каталогу пользователей и групп | Нужен лишь для legacy-приложений/NAS | **Полезен** для AD/legacy; LDAP — directory protocol из [RFC 4511](https://datatracker.ietf.org/doc/html/rfc4511), а не browser SSO |
| **SCIM 2.0** | Provisioning/deprovisioning пользователей и групп | Почти всегда избыточен | **Очень полезен** для lifecycle/JML (joiner, mover, leaver) |
| **WebAuthn/passkeys** | Phishing-resistant вход пользователя | **Рекомендуется** | Быстро растущая практическая ценность; изучать вместе с recovery и attestation |
| **TOTP** | Второй фактор по общему секрету | Полезный fallback | Распространён, но слабее passkeys против phishing; алгоритм определён в [RFC 6238](https://datatracker.ietf.org/doc/html/rfc6238) |
| **Forward auth** | Reverse proxy спрашивает внешний сервис, пропускать ли HTTP request | Очень удобен для старых web UI | Полезный platform pattern, но это не единый стандарт и не внутренняя сессия приложения |
| **RADIUS/Kerberos** | Сетевой доступ и корпоративный desktop/domain SSO | Только при специальной задаче | Полезны в network/AD-инфраструктуре, но не первый шаг для web SSO |

В выборке selfh.st OIDC в той или иной роли поддерживают почти все полноценные
IAM/CIAM продукты и несколько шлюзов. SAML заметно реже и сосредоточен в
enterprise-ориентированных продуктах; SCIM ещё реже. Это не измерение мирового
рынка, но хорошо показывает, чему отдавать приоритет в учебном homelab.

## Что именно находится на странице selfh.st

Список получен из актуальных данных каталога selfh.st: tag `Authentication`
имеет id `23` в [tags.json](https://selfhst.github.io/cdn/directory/tags.json),
а 21 соответствующая запись находится в
[software.json](https://selfhst.github.io/cdn/directory/software.json). Каталог
использован только для состава списка; возможности ниже проверены по официальной
документации и upstream-репозиториям.

Оценка «работа» означает **переносимость изученных концепций**, а не статистику
вакансий: 5/5 — прямой опыт с типичными enterprise/cloud IAM задачами, 1/5 —
узкий продуктовый сценарий.

### Полноценные workforce IdP/IAM

| Сервис | Возможности и границы | Homelab | Работа |
| --- | --- | --- | ---: |
| [Keycloak](https://www.keycloak.org/docs/latest/server_admin/) | OIDC/OAuth 2.0, SAML, identity brokering, LDAP/AD federation, Kerberos, WebAuthn/passkeys, роли и сложные authentication flows. Наиболее полный учебный стенд, но требует больше настройки и сопровождения. | Хорош, если цель — именно учёба enterprise IAM; для текущего дома избыточен рядом с ZITADEL. | **5/5** |
| [ZITADEL](https://github.com/zitadel/zitadel) | OIDC-certified IAM на Go: OIDC/OAuth 2.0, SAML 2.0, SCIM 2.0, LDAP federation, passkeys/WebAuthn, RBAC, multi-tenancy (instances/organizations), audit event stream и брендинг. Один бинарь + один PostgreSQL, по документации достаточно 1 CPU и 512 MB. UI (Login V2/консоль) современный и опрятный. Нет нативных reverse-proxy outposts — proxy-кейсы через OAuth2 Proxy. Kubernetes: официальный Helm chart, горизонтальное масштабирование и zero-downtime обновления без внешнего session store (для HA рекомендован именно кластер). | **Новый основной выбор**: enterprise-уровень при малом потреблении ресурсов, аккуратном UI и нормальной поддержке K8s. | **5/5** |
| [authentik](https://github.com/goauthentik/authentik) | OIDC/OAuth 2.0, SAML, LDAP, RADIUS и proxy provider; flows/stages позволяют собирать политики входа. Python + PostgreSQL + Redis + Celery worker (и опционально outposts), поэтому тяжелее ZITADEL по памяти; UI менее аккуратный. | Оставить как вторичный стенд ради proxy outposts и сложных flows, но не основным IdP. | **5/5** |
| [Kanidm](https://github.com/kanidm/kanidm) | Identity management, passkeys, OAuth2/OIDC, RADIUS, Unix integration и read-only LDAPS gateway. Это не просто web IdP, а современная попытка объединить каталог и аутентификацию. | Сильный вариант, если хочется изучать ещё Linux/RADIUS/directory; лишний при цели только web SSO. | **4/5** |
| [Rauthy](https://github.com/sebadob/rauthy) | Лёгкий OIDC/OAuth 2.0 IdP с passkey-only accounts, Device Authorization, SCIM v2, forward-auth и PAM/NSS. Уже охватывает удивительно широкий набор протоколов, но экосистема меньше Keycloak. | Один из лучших лёгких альтернативных IdP, особенно на малом железе. | **4/5** |
| [Casdoor](https://github.com/casdoor/casdoor) | UI-first IAM: OIDC/OAuth, SAML, CAS, LDAP, SCIM, WebAuthn/TOTP; authorization опирается на Casbin. Очень широкий набор интеграций повышает и поверхность настройки. | Подходит для эксперимента с большим числом протоколов; не даёт преимуществ перед ZITADEL. | **3/5** |

### CIAM: вход пользователей в собственный продукт

CIAM (Customer Identity and Access Management) ориентирован не столько на вход
сотрудников в готовые внутренние приложения, сколько на signup/login, tenants,
organizations, branded UI и API собственного SaaS. Это хороший выбор для
разработки продукта, но не обязательно лучший центр homelab.

| Сервис | Возможности и границы | Homelab | Работа |
| --- | --- | --- | ---: |
| [FusionAuth](https://fusionauth.io/docs/) | Self-hosted CIAM с OAuth2/OIDC и SAML как IdP/SP, passkeys/passwordless, MFA, RBAC, tenants и глубокой кастомизацией. Нужно отдельно проверять, какие функции входят в выбранную редакцию/лицензию. | Технически подходит, но ценность появляется при разработке собственного приложения, а не при защите десятка готовых сервисов. | **5/5** для product/backend IAM |
| [Logto](https://github.com/logto-io/logto) | Developer-oriented CIAM: OIDC/OAuth, SAML, multi-tenancy, enterprise SSO и RBAC, готовые login/signup flows. | Выбирать для разработки своего web/mobile продукта; как общий homelab IdP естественнее ZITADEL. | **4/5** |
| [Authgear](https://github.com/authgear/authgear-server) | CIAM с OIDC/OAuth/SAML, passkeys, MFA, RBAC, audit logs и enterprise connections к ADFS/LDAP; production deployment ориентирован на Kubernetes. | Богатый, но тяжёлый для малого homelab; полезнее как product-auth лаборатория. | **4/5** |
| [Melody Auth](https://github.com/ValueMelody/melody-auth) | OAuth/auth server с OIDC discovery, social/OIDC и SAML sign-in, MFA, passkey enrollment и policy-based flows. Более молодой и менее типичный стек. | Годится для эксперимента, но нет причины предпочесть зрелым IdP в критической точке. | **2/5** |

> ZITADEL рассмотрен в таблице workforce IdP выше (это основной выбор) и
> одновременно закрывает CIAM-сценарии: organizations/multi-tenancy, tenants,
> branding per organization.

### Homelab-first IdP и auth gateways

| Сервис | Возможности и границы | Homelab | Работа |
| --- | --- | --- | ---: |
| [Pocket ID](https://github.com/pocket-id/pocket-id) | OpenID-certified OIDC/OAuth 2.0 Provider с **только passkey**; есть LDAP user/group sync и client credentials для machine-to-machine, но нет SAML и собственного proxy provider. | **Отличный простой старт** и уже развёрнут; узок для сложных policies и enterprise federation. | **3/5**: хорошо учит OIDC client setup и passkeys, но не весь enterprise lifecycle |
| [Authelia](https://github.com/authelia/authelia) | Proxy companion для Traefik/nginx/Caddy и одновременно OpenID-certified OIDC Provider; file/LDAP users, TOTP/WebAuthn/passkeys, access-control rules. Upstream всё ещё называет OIDC offering beta. SAML IdP нет. | **Очень хороший** выбор для proxy-first homelab; менее универсален, чем ZITADEL. | **3/5** |
| [Tinyauth](https://github.com/tinyauthapp/tinyauth) | Middleware для Traefik/nginx/Caddy с OAuth, LDAP и access controls; с v5.1 также OpenID-certified Basic OP. Upstream предупреждает об active development и возможных изменениях конфигурации. | Сильный простой комбайн, если хочется меньше компонентов; сейчас дублирует ZITADEL. | **3/5** |
| [VoidAuth](https://github.com/voidauth/voidauth) | OIDC Provider, ForwardAuth, LDAP directory server, MFA и passkey-only accounts. Документация по app setup в значительной степени community-driven; upstream также предупреждает, что независимого security audit не было. | Много функций в одном homelab-oriented сервисе, но для корневого trust service зрелость нужно оценивать особенно строго. | **2/5** |
| [OAuth2 Proxy](https://github.com/oauth2-proxy/oauth2-proxy) | Reverse proxy/middleware, который отправляет пользователя во внешний OAuth/OIDC IdP и передаёт upstream username/groups headers. **Не хранит основную identity сам**. Один Go-бинарь без отдельной БД/Redis: десятки МБ памяти (сессии в cookie, Redis опционален). CNCF Sandbox project. | **Рекомендуемый дополнительный инструмент** для приложений без native OIDC; подключать к ZITADEL. | **5/5** для platform/Kubernetes/ingress практики |
| [nforwardauth](https://github.com/nosduco/nforwardauth) | Минимальный ForwardAuth с локальным `passwd`, общей cookie и `X-Forwarded-User`; upstream указывает только username/password и даже держит CSRF improvement в roadmap. | Не выбирать при уже существующем IdP: создаёт ещё один пароль и более слабую отдельную identity silo. | **1/5** |

### Каталог, авторизация и доступ к инфраструктуре

| Сервис | На самом деле решает | Homelab | Работа |
| --- | --- | --- | ---: |
| [GLAuth](https://github.com/glauth/glauth) | Лёгкий LDAP server с file/S3/SQL/LDAP backends. Не предоставляет современный browser SSO без отдельного IdP. | Полезен только если конкретное приложение требует LDAP или хочется отдельная лаборатория directory bind/search/group schema. | **3/5**: базовые LDAP навыки переносятся, но AD/Entra значительно шире |
| [Cerbos](https://github.com/cerbos/cerbos) | Policy Decision Point: приложение передаёт principal/resource/action/context, Cerbos вычисляет решение по YAML policies. Не логинит пользователя и не заменяет IdP. | Не нужен готовым сервисам; очень полезен при разработке собственного API. | **5/5** для backend/platform authorization |
| [Teleport](https://github.com/gravitational/teleport) | Identity-aware access plane для SSH, Kubernetes, databases, RDP и внутренних apps; выдаёт короткоживущие SSH/mTLS credentials, ведёт RBAC/audit/session recording. Это не обычный IdP для всех домашних web apps. В Community внешнее SSO ограничено GitHub; OIDC/SAML connectors находятся в Enterprise согласно [feature matrix](https://goteleport.com/docs/feature-matrix/). | Ставить, если задача — заменить SSH keys/bastion и изучить infrastructure access, а не ради входа в Immich. | **5/5** для DevOps/SRE/security |
| [Defguard](https://github.com/DefGuard/defguard) | Remote-access platform вокруг WireGuard: IAM, connection-level MFA, WebAuthn/TOTP, внутренний OIDC Provider, внешний OIDC и LDAP/AD sync. | Интересен как замена/дополнение VPN с identity; не нужен как ещё один общий IdP при Tailscale + ZITADEL. | **4/5** для network/zero-trust практики |
| [AuthPortal](https://github.com/modom-ofn/auth-portal) | Специализированный gateway для Plex/Jellyfin/Emby: их login, TOTP, собственный OAuth 2.1/OIDC, permissions и экспорт пользователей в LDAP. Upstream прямо предупреждает про vibe-coding/rapid iteration и «use at your own risk». | Только для media-community use case и после security review; не выбирать корнем доверия всего homelab. | **1/5** |

Все 21 позиции со страницы учтены; часть продуктов намеренно встречается только
в одной основной категории, хотя имеет пересекающиеся функции.

## Как читать claims, groups и роли

OIDC решает доставку проверяемого утверждения о пользователе, но не создаёт
универсальную схему прав. Практичная граница ответственности:

```text
IdP: login, MFA/passkeys, user lifecycle, groups, базовые claims
  |
  +-- приложение: свои роли, ownership и object-level permissions
  |
  +-- Cerbos/другой PDP: общие сложные ABAC/RBAC policies для собственного ПО
```

Не следует выдавать административную роль только по редактируемому пользователем
полю вроде display name. Для группового mapping нужны стабильные group IDs/names,
явное allow-list правило и тест отрицательного сценария. ForwardAuth должен
перезаписывать identity headers и приниматься приложением только от доверенной
proxy-сети; иначе клиент сможет подставить `X-Forwarded-User` сам.

## Учебный маршрут с максимальной пользой для работы

### Этап 1. Нормальный OIDC flow в ZITADEL

Подключить одно простое приложение, затем проверить:

- discovery document и JWKS;
- Authorization Code + PKCE;
- `state`, `nonce`, exact redirect URI;
- `sub`, `iss`, `aud`, `exp`, `email`, `groups`;
- logout, session expiry, refresh token rotation и отзыв пользователя;
- key rotation без аварии всех клиентов.

Это самая высокая отдача и для дома, и для backend/platform работы.

### Этап 2. Passkeys и recovery

Настроить passwordless (passkey-only) вход в ZITADEL. В консоли: организация →
Settings → Login Behavior and Security → в блоке Passkey поставить «Passkey
Login» = Allowed (в новых версиях опция называется именно так, раньше —
«Passwordless Login»). Глобального переключателя «отключить пароль» нет:
passkey-only получается у пользователя, у которого есть passkey и нет пароля.
Самый чистый способ онбординга — отдельная **ссылка регистрации passkey** (на
странице пользователя в консоли или через API `POST /v2/users/{id}/passkeys/registration_link`): она регистрирует только passkey, без пароля. Обычный
инвайт/регистрация Login V2 при этом показывают выбор метода (пароль, passkey,
внешний IdP), пока разрешены оба; скрыть пароль на этой странице нельзя
(upstream #8996) — passkey-only задаётся фактом отсутствия пароля, а не
настройкой формы. У существующих пользователей — снять пароль. После этого
форма входа покажет только кнопку passkey: fallback «войти с паролем»
отображается, лишь если пароль у пользователя есть (hosted login).
Самостоятельная регистрация (self-service, без предсозданного пользователя)
passkey-only из коробки не работает: built-in форма требует пароль как
обязательное поле, а при выключенном local auth страница регистрации Login V2
рендерится пустой (upstream #11682) — нужен свой UI поверх API. Чекбокс
«Local authentication allowed» в Login Form при этом не выключать: по tooltip он
отключает и passkey, оставляя только внешних IdP. Порядок важен: сначала
зарегистрировать минимум две passkey на независимых устройствах и проверить
вход, и только потом убирать пароль. Важно: в passkey-only режиме у ZITADEL нет
fallback на пароль/TOTP — при потере passkey восстановление только через
администратора (upstream issue #10717). Passkeys регистрировать на своём custom
domain. Сравнить с passkey-only моделью Pocket ID.

### Этап 3. Proxy pattern

Защитить тестовый `whoami` через OAuth2 Proxy перед ZITADEL (proxy outposts authentik — опциональный сравнительный стенд).
Посмотреть, какие headers получает upstream, затем доказать, что прямой доступ к
upstream закрыт и клиентский identity header не проходит. Это переносимый опыт
для ingress/reverse proxy, но не следует выдавать его за native OIDC приложения.

### Этап 4. Один SAML и один LDAP стенд

В отдельном тестовом клиенте разобрать SAML metadata, Entity ID, ACS URL,
assertion signing/encryption и clock skew.Затем подключить ZITADEL к тестовому GLAuth либо изучить LDAP federation ZITADEL (внешний LDAP/AD как источник): bind DN, base DN, user/group search, TLS и group mapping. Не нужно переводить домашние приложения на эти протоколы —
ценность именно учебная.

### Этап 5. Provisioning и fine-grained authorization

Для собственного маленького приложения попробовать SCIM-capable IdP (например,
ZITADEL или Rauthy) и отдельно Cerbos. Проверить не только создание пользователя,
но disable/delete, group removal и отзыв active sessions. Так становятся видны
различия между authentication, provisioning и authorization.

### Этап 6. Infrastructure identity

Если интерес смещается в DevOps/SRE, временно развернуть Teleport Community и
изучить короткоживущие SSH certificates, roles и audit.Важно не планировать бесплатную OIDC-интеграцию с ZITADEL: по текущей матрице Teleport она относится к Enterprise. Defguard имеет смысл изучать отдельно, если нужен WireGuard VPN с
connection-level MFA.

## Окончательная рекомендация

Для эксплуатации выбрать **ZITADEL как один основной IdP**, passkeys как
основной способ AuthN, а OIDC как основной протокол SSO. Выбор обусловлен тремя
критериями: enterprise-покрытие (OIDC-certified, SAML, SCIM, LDAP, RBAC,
multi-tenancy), аккуратный современный UI (Login V2 и консоль) и низкое
потребление ресурсов (один Go-бинарь + один PostgreSQL; по документации хватает
1 CPU и 512 MB — без Redis, worker и outposts). authentik оставить как
сравнительный стенд только ради proxy outposts и flows/stages, но не как
постоянный IdP. Pocket ID использовать как временный источник до миграции и
учебный эталон минимального OIDC Provider. OAuth2 Proxy подключать к ZITADEL для
приложений без native OIDC. Не вводить LDAP, SAML, SCIM, Cerbos, Teleport или
Defguard без конкретного сценария; изучать их в короткоживущих стендах.

Лицензия ZITADEL — AGPL-3.0 с Apache-2.0/MIT исключениями для SDK и отдельных
директорий; для самостоятельного self-host это некритично, но стоит учитывать,
если планируется перепродавать его как SaaS с модификациями.

Если приоритет изменится:

- **максимум рабочего enterprise IAM опыта** — временный Keycloak lab (Java: ≥ 750 MB–2 GB RAM);
- **минимум домашнего сопровождения** — Pocket ID;
- **минимум потребления памяти** — Rauthy (Rust, один бинарь, очень лёгкий);
- **proxy-first защита web UI** — Authelia или Tinyauth;
- **собственный B2B/SaaS продукт** — Logto, FusionAuth (или CIAM-слой уже развёрнутого ZITADEL);
- **единый современный каталог + Linux/RADIUS** — Kanidm;
- **SSH/Kubernetes/database access** — Teleport;
- **WireGuard + identity/MFA** — Defguard;
- **сложная авторизация собственного API** — Cerbos.
