# Forgejo (Terraform)

Защита ветки `main` репозитория `artemiy/homelab`. Развёртывание самого
инстанса — `apps/forgejo/` (Argo CD + `forgejo-helm`), здесь только его
содержимое.

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
tokens → Generate new token**. Достаточно скоупа `write:repository`; для
управления пользователями и их ресурсами потребовался бы `write:admin`.

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

## Импорт защиты ветки

Импорт идёт по человекочитаемому id `<owner>/<repo>/<branch>` — числовые ID из
базы искать не нужно. Числовой `repository_id`, который требует ресурс,
резолвится через data source `forgejo_repository` по имени и владельцу.

`imports.tf` переносит уже существующую защиту `main` в state декларативно:

```sh macOS
terraform init
terraform plan
```

Первый plan покажет `1 to import, 0 to add, 0 to change, 0 to destroy`.
`terraform apply` выполняет импорт; после него plan — `No changes`. Блок
`import` идемпотентен и остаётся в репозитории: повторный импорт тех же объектов
ничего не меняет.

Альтернатива — импорт из командной строки или генерация конфига из сервера:

```sh macOS
terraform import forgejo_branch_protection.main artemiy/homelab/main
terraform plan -generate-config-out=generated.tf   # черновик конфига по серверу
```

Если plan предлагает правку, сначала сравнить её с `curl`-выводом текущей
защиты, а не нажимать apply:

```sh macOS
curl -fsS -H "Authorization: token $FORGEJO_API_TOKEN" \
  "https://forgejo.$DOMAIN/api/v1/repos/artemiy/homelab/branch_protections"
```

## Почему часть полей не задана

Все настройки защиты, кроме `branch_name` и `repository_id`, в схеме провайдера —
`Optional + Computed`: не объявив их, Terraform берёт серверное значение в state
и не следит за дрейфом. Значения, которые нужно удерживать, выписаны в
`branch-protection.tf` явно.

Whitelist-поля (`*_whitelist_usernames`, `*_whitelist_teams`,
`push_whitelist_deploy_keys`) не заданы сознательно: сейчас все соответствующие
`enable_*_whitelist` выключены, а провайдер на уровне `ValidateConfig` запрещает
whitelist-атрибут при выключенном флаге. Включать их — нечего; когда понадобится
ограничить push/merge/approvals кругом лиц, флаги и списки добавляются вместе.

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
