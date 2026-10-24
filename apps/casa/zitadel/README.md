# Zitadel

Zitadel — IdP homelab. Доступен по `https://id.biplane.casa/`,
- консоль — `/ui/console`
- вход — `/ui/v2/login`.

## Как устроено

Postgres поднимается кластером CloudNativePG: суперпользователь остаётся у
оператора, а ZITADEL работает под непривилегированной managed-ролью `zitadel` —
владельцем базы. Кластер `zitadel-db` и его объекты объявлены в этом же юните,
в `manifests/`: он принадлежит ZITADEL, и blast radius IdP не должен совпадать
с остальными базами (`docs/adr/0002`).

`ZITADEL_FIRSTINSTANCE_*` применяется только на пустой базе.

## Порядок применения

Порядок задают волны Argo: namespace, затем конфиги, `VaultAuth`, сетевые
политики и кластер БД, затем секреты VSO и объект `Database`, затем ZITADEL,
Login UI и последним — HTTPRoute. На холодном стенде это заменяет ожидание
зависимостей внутри пода: синк не идёт дальше, пока health-check'и CNPG
(`platform/casa/argocd/values.yaml`) не подтвердят готовность кластера и
применение базы.

Init-контейнера `wait-for-db` больше нет. Он проверял `pg_isready` только на
старте пода: при недоступной базе в момент рестарта под висел в `Init` и не
перезапускался, а готовность кластера всё равно не гарантировал. Цена отказа
теперь та же, что у остальных юнитов: если база лежит уже после старта, ZITADEL
завершается и kubelet возвращает его по экспоненциальной задержке
`CrashLoopBackOff`.

## Изоляция

Оба пода работают не от root, с read-only корневой ФС, сброшенными
capabilities и `RuntimeDefault` seccomp; токен ServiceAccount в них не
монтируется. Namespace объявлен `restricted` для Pod Security Admission, поэтому
под, не соответствующий этим требованиям, просто не запустится — это гейт
против регрессии, а не только декларация.

Пользователи взяты из образов (`zitadel` и `nextjs`), а не заданы числом от
себя: каталог приложения принадлежит им, и чужой uid не прочитает файлы.
Записывать приложению некуда и нечего: конфиг и ключ приходят из ConfigMap и
Secret, состояние живёт в базе.

Сеть закрыта в обе стороны. Ingress разрешён Traefik (Login UI и API), vmagent
(метрики ZITADEL и экспортёр CNPG), оператору CloudNativePG и Login UI — ему
нужен API ZITADEL. Egress — DNS, база, OTLP-коллектор и HTTPS наружу: по нему
идут back-channel logout на адреса приложений и федерация с внешними IdP.
Ограничить наружу нечем: адреса клиентов задаёт администратор в консоли, а не
манифест.

## Секреты

Доставляются из Vault через VSO: `VaultAuth` `vso-zitadel` и пять
`VaultStaticSecret`.

| Путь в Vault | Secret | Ключи |
|---|---|---|
| `kv/zitadel/db` | `zitadel-db-auth` | `username`, `password` managed-роли CNPG |
| `kv/zitadel/admin` | `zitadel-admin` | `ADMIN_PASSWORD` |
| `kv/zitadel/masterkey` | `zitadel-masterkey` | `masterkey` |
| `kv/zitadel/session-cookie` | `zitadel-session-cookie` | `secret` |
| `kv/zitadel/login-service-key` | `zitadel-login-service-key` | `tls.crt`, `tls.key` |

## OIDC-клиент для oauth2-proxy

Приложение `Oauth Proxy` уже создано и импортировано в Terraform
(`infra/casa/terraform/zitadel/applications.tf`). client_id и client_secret лежат в Vault:
`kv/oauth2-proxy/oidc`. Новые клиенты заводить через Terraform, а не в консоли.

## Содержимое инстанса

Организация `homelab`, проект, OIDC-приложения, роли, членства, гранты и
политика логина описаны в Terraform — `infra/casa/terraform/zitadel/`. Разворачивается
инстанс здесь, `apps/casa/zitadel/`; Terraform управляет тем, что внутри.

Что осталось в консоли: human users, service account `homelab-service`,
системные объекты инстанса. Список и причины — `infra/casa/terraform/zitadel/README.md`.

Эксплуатация — в `RUNBOOK.md`.
