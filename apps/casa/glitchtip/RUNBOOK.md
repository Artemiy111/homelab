# GlitchTip: эксплуатация

## Проверка

```sh
curl --resolve glitchtip.example.com:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://glitchtip.example.com/
```

Ожидается `200`.

```sh
curl --resolve glitchtip.example.com:443:<node1-ip> -sS \
  https://glitchtip.example.com/api/settings/ | jq -r '.socialApps[] | [.provider, .name] | @tsv'
```

Ожидается строка `zitadel` — `Zitadel`: `SocialApp` на месте, и форма входа
предлагает провайдера.

```sh
kubectl -n glitchtip get pods
kubectl -n glitchtip logs deploy/glitchtip -c migrate --tail=5
```

Ожидается `Ready` у web, worker и valkey; в логах init-контейнера —
`Partition maintenance complete` и `OIDC: Zitadel application is up to date`.

## Первый вход и администратор

Вход через Zitadel администратора не создаёт: `/admin/` требует superuser'а.

```sh
kubectl -n glitchtip exec deploy/glitchtip -c glitchtip -- ./manage.py createsuperuser
```

Дальше — обычный вход кнопкой Zitadel на странице входа; первый такой вход
создаёт пользователя. Пока в базе нет ни одного пользователя, GlitchTip
открывает и регистрацию по паролю (`enableUserRegistration` в
`/api/settings/`), после первого — закрывает.

## Пересоздание базы с нуля

Данные не нужны — база удаляется без дампа. Схема, `SocialApp` и всё остальное,
что объявлено кодом, вернутся сами; пропадут учётные записи, проекты и события.

Порядок важен. `Database` не следит за дрейфом: если базу удалить из PostgreSQL,
объект останется `applied: true` и база не появится. И `databaseReclaimPolicy:
retain` означает, что удаление объекта базу не уносит. Поэтому сначала `DROP`,
потом пересоздание объекта:

```sh
kubectl -n databases exec shared-1 -c postgres -- \
  psql -U postgres -d postgres -c 'DROP DATABASE glitchtip WITH (FORCE);'
kubectl -n databases delete databases.postgresql.cnpg.io/glitchtip
kubectl apply -f platform/casa/cnpg/manifests/shared.databases.yaml
kubectl -n databases get databases.postgresql.cnpg.io/glitchtip
```

Ожидается `APPLIED true`. Имя ресурса пишется с группой: короткое `database`
резолвится в CRD MariaDB.

Схему накатывает init-контейнер при старте пода, поэтому запущенные поды надо
пересоздать — до этого web отвечает `5xx`:

```sh
kubectl -n glitchtip delete pod -l app=glitchtip
kubectl -n glitchtip delete pod -l app=glitchtip-worker
kubectl -n glitchtip wait --for=condition=Ready pod -l 'app in (glitchtip,glitchtip-worker)' --timeout=300s
```

Сессии и очередь Valkey ссылаются на удалённые строки, поэтому чистится и он:

```sh
kubectl -n glitchtip exec deploy/glitchtip-valkey -- redis-cli FLUSHALL
```

Проверка, что база пустая и живая:

```sh
kubectl -n databases exec shared-1 -c postgres -- \
  psql -U postgres -d glitchtip -Atc \
  'select (select count(*) from users_user), (select count(*) from django_migrations)'
```

Ожидается `0|169` (число миграций растёт с версией образа). После первого входа
первое число — `1`. Дальше — раздел «Проверка».
