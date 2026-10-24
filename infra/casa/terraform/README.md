# Terraform

Один каталог на root-модуль, у каждого свой state. State локальный на macOS,
в git не попадает.

## Модули

| Модуль | Что описывает | Документация |
| --- | --- | --- |
| `forgejo/` | Защита ветки `main` репозитория `homelab` | `infra/casa/terraform/forgejo/README.md` |
| `vault/` | Политики, роли и kubernetes-auth в HashiCorp Vault | `infra/casa/terraform/vault/README.md` |
| `uptime-kuma/` | Мониторы, теги, status page и настройки Uptime Kuma | `infra/casa/terraform/uptime-kuma/README.md` |
| `zitadel/` | Организация, проект, OIDC-приложения, роли, членства, гранты и политика логина Zitadel | `infra/casa/terraform/zitadel/README.md` |
| `tailscale/` | DNS tailnet: MagicDNS и split DNS на домашний домен | `infra/casa/terraform/tailscale/README.md` |
| `technitium/` | DNS-записи зоны стенда и bootstrap-зоны `cloudflare-dns.com` | `infra/casa/terraform/technitium/README.md` |
| `rustfs/` | Бакет `mirror` и его policy | `infra/casa/terraform/rustfs/README.md` |

## Запуск

Набор доступов у каждого модуля свой, он описан в README модуля — ссылки в
таблице выше. Общего «залогиниться один раз» нет: Vault, Technitium, Zitadel и
Uptime Kuma проверяют разные креды.

## Доступ к Zitadel

Провайдер получает путь к JSON-ключу service account (private key JWT), а не сам
ключ и не токен, поэтому приватный ключ не попадает ни в репозиторий, ни в
state. Ключ готовится один раз в консоли Zitadel, путь и роли описаны в
`infra/casa/terraform/zitadel/README.md`.

## Параметры

Параметры конкретного модуля лежат в неотслеживаемом `infra/casa/terraform/<модуль>/terraform.tfvars`
и в git не попадают. В репозитории только пример в README модуля.

## Секреты в state

Реквизиты доступа к API сервиса передаются провайдерам через окружение, а не
через блок `provider`: аргументы блока в state не сохраняются. Ресурсы, чьи
атрибуты содержат секреты, в этом репозитории не заводятся — пароль
администратора Vault в state не лежит, и по той же причине уведомления
Uptime Kuma остались за пределами Terraform. В `infra/casa/terraform/zitadel` секрет
`client_secret` приложений намеренно не импортируется: он остаётся в Vault,
а в state его нет.
