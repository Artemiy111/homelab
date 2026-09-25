# GitLab CE (тестовый стенд)

GitLab CE одним подом из образа `gitlab/gitlab-ce` — для проверки, а не
эксплуатации. Внутри пода сразу всё: nginx, puma (Rails), sidekiq, Gitaly,
встроенные PostgreSQL и Redis.

| | |
|---|---|
| URL | `https://gitlab.example.com/` |
| Namespace | `gitlab` |
| Деплой | `apps/gitlab/k8s/`, руками (`kubectl apply`), без Argo |
| Образ | `gitlab/gitlab-ce:19.4.0-ce.0` |
| Данные | PVC `gitlab-data` (10Gi) и `gitlab-config` (1Gi), класс `local-path` |
| Логин | `root` |

## Почему одним подом

Официальная документация GitLab прямо не рекомендует этот образ для
Kubernetes: под один, значит single point of failure, обновление с простоем, нет
горизонтального масштабирования. Для теста это приемлемая цена за то, что не
нужно поднимать десяток подов (webservice, sidekiq, gitaly, minio, redis,
postgres, ...) и ~10 Gi RAM. Если понадобится «как в проде» — брать чарт
`gitlab/gitlab`, но на текущем узле он не влезет.

## Как развёрнуто

```sh
kubectl apply --server-side --field-manager=homelab -f apps/gitlab/k8s/
helm template platform/homelab -f platform/homelab/values.private.yaml | kubectl apply --server-side --field-manager=homelab -f -
```

`platform/homelab-config/configmap.yaml` содержит документ для namespace
`gitlab` (DOMAIN, TZ) — оттуда Deployment берёт env, а `gitlab.rb` подставляет
их как `ENV['DOMAIN']` и `ENV['TZ']`.

### Конфигурация

Весь `gitlab.rb` лежит в ConfigMap `gitlab-omnibus` (ключ `omnibus.rb`) и
передаётся в образ через `GITLAB_OMNIBUS_CONFIG`. Образ оценивает эту
переменную как ruby **до** собственного `/etc/gitlab/gitlab.rb` и не пишет в
файл, поэтому `/etc/gitlab` остаётся чистым PVC под секреты и host keys.

Что задано и зачем:

- `external_url` — https за Traefik; внутренний nginx переведён на plain HTTP
  на 80 (`listen_https=false`, `redirect_http_to_https=false`), иначе
  Traefik → GitLab → Traefik даёт цикл редиректов.
- `gitlab_rails['trusted_proxies']` — pod CIDR k0s, чтобы Rails доверял
  `X-Forwarded-Proto` от Traefik и строил ссылки как https.
- `prometheus_monitoring['enable'] = false` — снимает Prometheus, Grafana,
  Alertmanager и все экспортёры (~1 Gi).
- `gitlab_kas`, `gitlab_pages`, `registry`, `mattermost` — выключены, тестовому
  инстансу не нужны.
- `puma['worker_processes'] = 0`, `sidekiq['max_concurrency'] = 5`,
  `postgresql['shared_buffers'] = "256MB"` — обязательно: omnibus сайзит
  puma/sidekiq/Postgres по ресурсам **хоста** (16 CPU, 27 Gi), а не по лимитам
  пода. Без явных значений Postgres мог бы зарезервировать несколько GiB
  shared_buffers и получить OOM.

## Вход

Пароль root генерируется на первом запуске в файл в PVC:

```sh
kubectl -n gitlab exec deploy/gitlab -- cat /etc/gitlab/initial_root_password
```

Файл удаляется при рестарте пода после первых 24 часов, так что пароль надо
сохранить. Хранить постоянный пароль в секрете здесь намеренно не заведено:
для теста достаточно сгенерированного. Если нужен фиксированный — добавить в
`gitlab.rb` `gitlab_rails['initial_root_password'] = File.read('/run/secrets/...')`
и смонтировать SealedSecret.

## Ресурсы

| | requests | limits |
|---|---|---|
| CPU | 500m | 4 |
| Память | 2Gi | 5Gi |

На узле свободно ~5 Gi, поэтому GitLab с остальными сервисами помещается
впритык. При проблемах с памятью — посмотреть `kubectl -n gitlab top pod` и
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

## Ограничения тестового стенда

- Нет SMTP: приглашения и уведомления не уходят; MTA в образ не входит.
- Нет GitLab Runner: CI-пайплайны настроить можно, но исполнять их некому —
  раннер ставится отдельно (`gitlab/gitlab-runner`).
- HTTPS-порты 22 (git over SSH) наружу не выставлены: работать с репозиториями
  по HTTP. SSH добавляется Service'ом `2222:22` и
  `gitlab_rails['gitlab_shell_ssh_port'] = 2222`.
- NetworkPolicy для namespace не заведена: на kube-router есть риск, что
  default-deny заблокирует http-пробы kubelet (они идут с IP узла, а не пода).
- Резервных копий нет. Для теста — ок; для нужных данных это отдельная задача.

## Удаление

```sh
helm template platform/homelab -f platform/homelab/values.private.yaml | kubectl delete -f -
kubectl delete -f apps/gitlab/k8s/
```

`local-path` держит reclaimPolicy `Retain`, поэтому PV и каталоги на диске
останутся (`/storage/apps/k8s/local-path/`). Чтобы вычистить полностью —
сначала удалить PVC, затем PV, затем данные на диске.
