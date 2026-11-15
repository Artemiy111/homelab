# Linkwarden: эксплуатация

## Первый запуск

Юнит не поднимется, пока в Vault нет двух путей: приложение читает их оба, а
CNPG — пароль роли из того же `kv/linkwarden/db`.

1. Завести значения (пароль без спецсимволов, чтобы не ломать `DATABASE_URL`):

   ```sh
   vault kv put kv/linkwarden/db \
     username=linkwarden \
     password="$(openssl rand -hex 24)"

   vault kv put kv/linkwarden/secrets \
     NEXTAUTH_SECRET="$(openssl rand -base64 32)" \
     MEILI_MASTER_KEY="$(openssl rand -hex 32)"
   ```

2. Применить роли и политики Vault:

   ```sh
   cd infra/casa/terraform/vault && terraform plan && terraform apply
   ```

3. Дождаться синхронизации Argo:

   ```sh
   kubectl -n argocd get application linkwarden
   kubectl -n linkwarden get pods
   ```

Ожидаемо: приложение в `Synced`/`Healthy`, два пода в `Running`/`Ready`, а
`VaultStaticSecret` юнита — в `True` (два в `linkwarden` и `linkwarden-db-auth`
в `databases`).

## Регистрация и вход

Форма регистрации открыта по умолчанию. Зарегистрировать первую учётку сразу
после запуска: пока форма открыта, её может открыть любой, кто дошёл до сервиса.
Закрыть регистрацию переменной окружения нельзя — это `NEXT_PUBLIC_*`,
запечённый в образ при сборке.

## Проверка на стенде

```sh
curl -sk --resolve linkwarden.<домен>:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' https://linkwarden.<домен>/
```

Ожидаемый ответ: `200` (страница входа) или `307` на неё.

В интерфейсе: зарегистрироваться, добавить закладку и дождаться, пока у неё
появятся скриншот, PDF и текст. Затем найти её поиском по слову из сохранённой
страницы — так проверяются сразу архиватор и Meilisearch.

Связь с базой и индексом:

```sh
kubectl -n linkwarden logs deploy/linkwarden --since=5m | grep -iE 'prisma|error'
kubectl -n linkwarden logs deploy/linkwarden-meilisearch --since=5m
```

Ошибок подключения к `shared-rw.databases.svc.cluster.local:5432` и к
`linkwarden-meilisearch.linkwarden.svc.cluster.local:7700` быть не должно.

## Обновление версии

Renovate присылает PR с новым тегом и дайджестом. Миграции базы выполняет сам
образ при старте (`prisma migrate deploy`), отката миграций нет — перед мажорным
обновлением сделать дамп базы.

```sh
kubectl -n linkwarden rollout status deploy/linkwarden
kubectl -n linkwarden rollout status deploy/linkwarden-meilisearch
```

Том архива и том индекса не пересоздаются, но под приложения перекатывается с
простоем: стратегия `Recreate` из-за `ReadWriteOnce`.

## Дамп базы

Дамп пишется в файл внутри пода: поток через `kubectl exec` на этом канале
рвётся, а оборванный `pg_dump` продолжает держать блокировки в базе.

```sh
kubectl -n databases exec shared-1 -c postgres -- sh -c \
  'pg_dump -U linkwarden -d linkwarden -Fc -f /var/lib/postgresql/data/linkwarden.dump &&
   pg_restore -l /var/lib/postgresql/data/linkwarden.dump | wc -l'

kubectl cp databases/shared-1:/var/lib/postgresql/data/linkwarden.dump \
  -c postgres ./linkwarden-$(date +%F).dump
```

Файл остаётся в томе базы до удаления руками, поэтому копию на macOS можно снять
и позже. Дамп содержит закладки, пользователей и теги, но не архив: скриншоты,
PDF и текст лежат на томе приложения.

## Диагностика

| Симптом | Что смотреть |
|---|---|
| Под `CreateContainerConfigError` | Secret'ы не созданы: `kubectl -n linkwarden get vaultstaticsecret` |
| Под стартует и падает | `kubectl -n linkwarden logs deploy/linkwarden --previous` |
| Закладка создаётся, архива нет | логи воркера в том же поде: `grep -i playwright` |
| Поиск пустой, закладки есть | `/health` у Meilisearch и его логи; переиндексация |
| `role "linkwarden" does not exist` | не применилась `Database`/роль в `databases` |

## Удаление

Убрать `clusters/casa/argocd/apps/linkwarden.yaml` и каталог юнита — Argo удалит
всё, кроме namespace и PVC: у них `Prune=false`. Затем руками, осознанно:

```sh
kubectl -n databases delete database linkwarden
kubectl -n linkwarden delete pvc linkwarden-data linkwarden-meilisearch
kubectl delete namespace linkwarden
```

Том `longhorn-retain` после удаления PVC остаётся сиротой; как его удалить или
восстановить — в RUNBOOK юнита `longhorn`.
