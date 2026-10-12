# DB exporters: эксплуатация

## Проверка экспортеров

Проверка, что все экспортеры живы:

```sh
kubectl get pods -l 'app in (seafile-mariadb-exporter,uptime-kuma-mariadb-exporter,seafile-redis-exporter)'
```

Состояние целей в VictoriaMetrics (ожидаем `1` для всех инстансов):

```sh
kubectl exec deploy/victoriametrics -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=up{job=~"redis|mysql"}'
```

Экспортер, вернувший `mysql_up 0` при `up 1`, означает, что сам экспортер жив, но не может подключиться к базе — смотреть его логи:

```sh
kubectl logs deploy/seafile-mariadb-exporter
```
