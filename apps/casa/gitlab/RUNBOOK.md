# GitLab CE: эксплуатация

## Вход

Пароль root генерируется на первом запуске в файл в PVC:

```sh
kubectl -n gitlab exec deploy/gitlab -- cat /etc/gitlab/initial_root_password
```

Файл удаляется при рестарте пода после первых 24 часов, так что пароль надо
сохранить. Хранить постоянный пароль в секрете здесь намеренно не заведено:
для теста достаточно сгенерированного. Если нужен фиксированный — добавить в
`gitlab.rb` `gitlab_rails['initial_root_password'] = File.read('/run/secrets/...')`
и смонтировать Secret из Vault.

## Ресурсы

При проблемах с памятью — посмотреть `kubectl -n gitlab top pod` и
ужать `sidekiq['max_concurrency']` / лимиты. Первый старт (initdb, миграции,
reconfigure) идёт 5–15 минут; `startupProbe` это учитывает.

## Проверка

```sh
kubectl -n gitlab get pods,pvc,svc,ingress
kubectl -n gitlab logs deploy/gitlab -f

curl -fsS --resolve gitlab.example.com:443:<node1-ip> \
  https://gitlab.example.com/-/health

kubectl -n gitlab exec deploy/gitlab -- gitlab-rake gitlab:check
```

Ожидаемо `/-/health` отдаёт `GitLab OK`. `5xx` и transport error — ошибка.

## Удаление

`local-path` держит reclaimPolicy `Retain`, поэтому PV и каталоги на диске
останутся (`/storage/apps/k8s/local-path/`). Чтобы вычистить полностью —
сначала удалить PVC, затем PV, затем данные на диске.
