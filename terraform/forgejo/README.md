# Forgejo (Terraform)

Управляет содержимым инстанса Forgejo: репозиторием `artemiy/homelab`, защитой
его ветки `main` и организацией `actions` (зеркала экшенов). Развёртывание самого
инстанса — `apps/forgejo/` (Argo CD + `forgejo-helm`), здесь только его
содержимое.

## Что управляется

| Ресурс | Объект | Что фиксирует |
| --- | --- | --- |
| `forgejo_organization.actions` | организация `actions` | `visibility = public`, `repo_admin_change_team_access` |
| `forgejo_repository.homelab` | репозиторий `artemiy/homelab` | squash — единственный стиль merge, набор unit'ов, wiki, трекер |
| `forgejo_branch_protection.main` | ветка `main` | запрет прямого push, обязательные status checks |

## Запуск

С macOS: провайдер ходит в `https://forgejo.<домен>` напрямую.

```sh macOS
cd terraform/forgejo
export FORGEJO_API_TOKEN="<токен>"
terraform init
terraform plan
```

## Доступ провайдера

Токен читается из переменной окружения `FORGEJO_API_TOKEN`. В блок `provider`
он не пишется: аргументы блока в state не сохраняются, а ресурсов с секретами
здесь вообще нет (см. «Чего модуль не делает»).

Токен заводится один раз в веб-интерфейсе: **Settings → Applications → Access
tokens → Generate new token**. Нужны скоупы `write:repository` (репозиторий и
защита ветки) и `write:organization` (организация).

Самоподписанный сертификат Forgejo-клиент игнорировать не умеет — хост должен
отдавать сертификат, которому доверяет macOS. Публичный домен стенда этому
условию удовлетворяет; для тестового самоподписи в README провайдера есть
`openssl s_client`.

## Значения

```hcl
domain = "example.com"
```

`domain` — корневой домен стенда, а не адрес инстанса: в провайдер
подставляется `forgejo.${var.domain}`, как в `apps/forgejo`. Реальное значение —
в `terraform.tfvars`, который не коммитится.

## Импорт

`imports.tf` переносит в state три уже существующих объекта. Id импорта —
человекочитаемые, числовые ID из базы не нужны:

| Ресурс | Id |
| --- | --- |
| `forgejo_organization.actions` | `actions` |
| `forgejo_repository.homelab` | `artemiy/homelab` |
| `forgejo_branch_protection.main` | `artemiy/homelab/main` |

```sh macOS
terraform init
terraform plan     # 3 to import, 0 to add, 0 to change, 0 to destroy
terraform apply    # выполняет только импорт
terraform plan     # No changes
```

Блоки `import` идемпотентны и остаются в репозитории: повторный импорт тех же
объектов ничего не меняет.

Если plan предлагает правку, сначала сравнить её с `curl`-выводом текущего
состояния, а не нажимать apply:

```sh macOS
curl -fsS -H "Authorization: token $FORGEJO_API_TOKEN" \
  "https://forgejo.$DOMAIN/api/v1/repos/artemiy/homelab"
curl -fsS -H "Authorization: token $FORGEJO_API_TOKEN" \
  "https://forgejo.$DOMAIN/api/v1/orgs/actions"
```

## Осторожно: репозиторий и организация

У `forgejo_repository` есть create-only поля — `auto_init`, `gitignores`,
`license`, `readme`, `issue_labels`, `template`, `clone_addr`, `mirror`, `mirror_interval`.
Изменение любого из них **пересоздаёт репозиторий с потерей данных**, поэтому они
не заданы (они `Optional + Computed`) и добавлять их нельзя. Поле `auth_token`
содержит секрет и тоже не задаётся.

На `forgejo_repository.homelab` и `forgejo_organization.actions` стоит
`lifecycle.prevent_destroy`: удаление репозитория — потеря кода, удаление
организации `actions` — потеря зеркал экшенов.

## Почему часть полей не задана

Все настройки, кроме обязательных, в схеме провайдера — `Optional + Computed`:
не объявив их, Terraform берёт серверное значение в state и не следит за дрейфом.
Значения, которые нужно удерживать (стиль merge, набор unit'ов, видимость
организации), выписаны явно. Пустые строки (`description`, `website`, `location`)
не заданы: пустое значение и отсутствие значения неотличимы на сервере.

Whitelist-поля защиты ветки (`*_whitelist_usernames`, `*_whitelist_teams`,
`push_whitelist_deploy_keys`) не заданы сознательно: сейчас все соответствующие
`enable_*_whitelist` выключены, а провайдер на уровне `ValidateConfig` запрещает
whitelist-атрибут при выключенном флаге. Когда понадобится ограничить
push/merge/approvals кругом лиц, флаги и списки добавляются вместе.

Два поля защиты провайдер не умеет: `apply_to_admins` и `ignore_stale_approvals`.
Они остаются как есть и вне Terraform.

## Чего модуль не делает

Ресурсы провайдера, чьи атрибуты содержат секреты, сюда сознательно не
заводятся — иначе секрет попадёт в локальный state (правило «Секреты в state» в
`terraform/README.md`):

- `forgejo_personal_access_token`, `forgejo_repository_action_secret` —
  токены (`PACKAGES_TOKEN` и подобные);
- `forgejo_user` — пароль пользователя;
- `forgejo_repository_webhook` — секрет вебхука;
- `forgejo_deploy_key`, `forgejo_ssh_key`, `forgejo_gpg_key` — ключи.

То же решение, что `client_secret` приложений Zitadel и уведомления Uptime Kuma.
Push-зеркало в GitHub тоже вне модуля: URL зеркала содержит токен.

Провайдер также не умеет OAuth2-приложения, защиту тегов, instance-настройки
(`app.ini`) и регистрацию раннера — последняя делается через
`forgejo-cli actions register` (`apps/forgejo/README.md`).
