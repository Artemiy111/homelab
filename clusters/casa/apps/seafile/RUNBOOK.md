# Seafile: эксплуатация

## Метрики

```sh
kubectl -n monitoring exec deploy/victoriametrics -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=up%7Bjob%3D%22seafile%22%7D'
```

## Бэкап и восстановление

Дамп (на сервере):

```sh
kubectl -n seafile exec -i seafile-mariadb-0 -- sh -c \
  'mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" --single-transaction \
   --routines --events --triggers --databases ccnet_db seafile_db seahub_db' \
  > /storage/apps/seafile/backups/seafile-$(date +%F).sql
```

Восстановление в уже существующие БД (root-пароль доступен в поде через env):

```sh
kubectl -n seafile exec -i seafile-mariadb-0 -- sh -c \
  'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD"' < <dump>.sql
```
