# sure

sure — self-hosted учёт личных финансов.
URL: `https://sure.example.com/`

Разворачивается манифестами в apps/sure/k8s/. `web` (Rails) обслуживает
HTTP, `worker` (Sidekiq) — фоновые задачи; оба пишут вложения в один том.

## Хранилище

База — PostgreSQL в общем кластере CNPG `shared` (namespace `databases`,
эндпоинт `shared-rw.databases.svc.cluster.local:5432`). Роль `sure`, база `sure`
и NetworkPolicy объявлены в `platform/cnpg/`. Пароль берётся из запечатанного
`sure-db-auth`: копия в `databases` — для роли, копия в `sure` — для пода
(Secret читается только из своего namespace, а потребитель ходит
cross-namespace). На источнике база называлась `sure_production`, а работа шла
под зарезервированной в CNPG ролью `postgres` — при переносе переименованы.
Данные перенесены логическим дампом (`pg_dump`/`pg_restore`), старый Deployment
`sure-db` снят.

Вложения (Active Storage) лежат на Longhorn-PVC `sure-storage`, общем для `web` и
`worker`; Redis — брокер Sidekiq (PVC `sure-redis`, потеря очереди допустима).

## Проверка

```sh
curl -sk --resolve sure.example.com:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' https://sure.example.com/
```

Ожидаемый ответ: `302` на `/sessions/new` (форма входа).
