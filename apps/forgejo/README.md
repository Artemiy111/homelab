# Forgejo

Forgejo — лёгкая self-hosted Git-платформа (форк Gitea), которая задумана как
основной дом для этого репозитория.

| | |
|---|---|
| URL | `https://forgejo.example.com/` |
| Git over SSH | `ssh://git@forgejo.example.com:2222/OWNER/REPO.git` |
| Namespace | `forgejo` |
| Развёртывание | Argo CD: `k8s/argocd/forgejo.yaml`, чарт `forgejo-helm` |
| Данные | PVC `forgejo-data` на `longhorn-retain` (Longhorn) |
| База | CNPG-кластер `shared` в namespace `databases`, роль и база `forgejo` |

Самостоятельная регистрация выключена, новые репозитории и профили приватны,
Forgejo Actions выключены до появления отдельного runner.

## Как развёрнуто

Официального Helm-чарта у Forgejo нет; де-факто стандарт — **forgejo-helm** из
организации `forgejo-contrib` на Codeberg (форк чарта Gitea под Forgejo:
внешняя база, rootless-образ, admin-пользователь и метрики из коробки).
Application ставит его как git-источник с `path: .`, как local-path-provisioner.

Две вещи, которые важно знать про этот чарт:

- **`appVersion` в git-дереве неверный.** В `Chart.yaml` на теге `v16.0.1`
  лежит `appVersion: 14.0.1` — настоящий appVersion подставляется только в
  OCI-артефакт при релизе. Поэтому `image.tag` и `image.digest` заданы явно,
  иначе Argo развернул бы Forgejo 14. Тег/дайджест — те же, что были в
  манифестах до переезда на чарт.
- **Веб-мастера установки нет.** Чарт всегда ставит `INSTALL_LOCK=true`, вся
  конфигурация приезжает из values, а админ создаётся init-контейнером.

## Хранилище

`persistence.claimName: forgejo-data`, класс `longhorn-retain`, 5Gi. Стратегия
деплоймента — `Recreate` (дефолт чарта): том RWO, два пода одновременно его не
смонтируют. Менять имя PVC после установки нельзя — это будет новый том.

Что лежит в томе: `git/repositories` (сами репозитории), LFS-объекты,
вложения, аватары, `custom/` и сгенерированный `gitea/conf/app.ini`. **База — не
здесь**: она в CNPG. Для полного восстановления нужны обе половины.

## База

Кластер `shared` (namespace `databases`), роль `forgejo`, база `forgejo`.
Подключение идёт на `shared-rw.databases.svc.cluster.local:5432`, доступ
разрешён в `k8s/cnpg/networkpolicy.yaml` (`allow-shared-from-consumers`).

Пароль роли лежит в `databases/forgejo-db-auth` и он же — в
`forgejo/forgejo-secrets` (один плейнтекст, два запечатанных SealedSecret'а —
принятая в репозитории схема, см. `k8s/cnpg/README.md`). Подставляется в
app.ini через `FORGEJO__database__PASSWD` из `gitea.additionalConfigFromEnvs`,
поэтому секрет чарту не нужен.

## Секреты

| SealedSecret | Что внутри | Кто читает |
|---|---|---|
| `apps/forgejo/k8s/secrets.sealedsecret.yaml` | `POSTGRES_PASSWORD`, `FORGEJO_METRICS_TOKEN` | чарт (env → app.ini) |
| `apps/forgejo/k8s/admin.sealedsecret.yaml` | `username` (`forgejo-admin`), `password` админа | чарт (init-контейнер) |

Перезапечатать можно только на сервере: `kubeseal` привязан к namespace и
имени, а приватный ключ контроллера доступен лишь там
(`docs/agents/server-access.md`).

**Про админа:** это служебная учётка (`forgejo-admin`, почта
`admin@example.com`), а не личный аккаунт человека: роль в сервисе и
человек — разные сущности, у них разные пароли и разные последствия утечки.
Логин `admin` использовать нельзя — Forgejo резервирует это имя («name is
reserved»), поэтому имя с суффиксом сервиса; почта при этом короткая.

Режим `initialOnlyNoReset`: чарт выставляет пароль при создании пользователя и
больше его не трогает (режим `keepUpdated` перетирал бы пароль при каждом
рестарте пода). Важно: чарт создаёт админа только если такого пользователя ещё
нет — на живом стенде он его не создал, потому что в базе уже был другой админ;
после пересоздания базы учётки заведены руками (`forgejo admin user create`).

Пользователи: `forgejo-admin` (служебный админ) и `user` (личный, без прав
админа).

Осторожно с именами: чарт создаёт Secret с именем релиза (`forgejo`) для своих
init-скриптов, поэтому секреты сервиса названы `forgejo-secrets` и
`forgejo-admin`. Совпадение имён означало бы двух владельцев одного объекта
(SealedSecret-контроллер и Argo), и они затирали бы ключи друг друга.

## Проверка

```sh
kubectl -n argocd get application forgejo
kubectl -n forgejo get pods,pvc,svc,ingress

curl -fsS --resolve forgejo.example.com:443:192.0.2.10 \
  https://forgejo.example.com/api/healthz   # status: pass, database:ping: pass

kubectl -n forgejo exec deploy/forgejo -- forgejo admin user list --admin

# SSH: порт открыт и отдаёт баннер Forgejo
ssh -T -p 2222 -o StrictHostKeyChecking=no git@192.0.2.10
```

## Резервное копирование

Пока **не настроено**, и это главный незакрытый пункт: под `shared` задуман
ObjectStore + ScheduledBackup в rustfs (Barman Cloud Plugin), см.
`k8s/cnpg/README.md`. До этого репозитории (PVC) и база (CNPG) живут без
резервных копий, а `longhorn-retain` защищает только от удаления PVC, не от
отказа диска или логической порчи.

Когда база будет покрыта бэкапами, для репозиториев останется второй путь:
push-зеркало в GitHub — git распределённый, и код переживёт потерю сервера даже
без бэкапов. Планируемый порядок: сначала зеркало, потом перенос `origin`.

## Обновление

1. Посмотреть release notes Forgejo и тег чарта (`forgejo-helm` на Codeberg).
2. В `k8s/argocd/forgejo.yaml` поднять `targetRevision` (тег чарта) и
   `image.tag`/`image.digest` (образ Forgejo) — это две независимые вещи.
3. `kubectl apply -f k8s/argocd/forgejo.yaml`, дождаться sync.
4. Миграции схемы выполняет init-контейнер чарта (`forgejo migrate`); если он
   циклится, смотреть его логи: обычно это недоступная база.

Откат: вернуть прежние теги в values и снова `kubectl apply`. Образ и чарт
пинятся по версии/дайджесту, поэтому откат детерминированный.

## Грабли, проверенные на живом стенде

- **`lookup` в чарте ломается под Argo.** Чарт умеет генерировать пароль админа
  и хранить его в своём Secret'е, читая существующий объект через `lookup`. Argo
  рендерит чарт без доступа к кластеру, поэтому пароль менялся бы при каждом
  sync. Лечится `gitea.admin.existingSecret` — что и сделано.
- **Ingress под Argo вечно `Progressing`.** Traefik не пишет
  `status.loadBalancer.ingress`, а Argo считает такой Ingress нездоровым.
  Сейчас на Ingress стоит аннотация `argocd.argoproj.io/ignore-healthcheck`;
  когда Ingress'ов под Argo станет больше, чище завести
  `resource.customizations.health.networking.k8s.io_Ingress` в `argocd-cm`.
- **`image.pullPolicy` и digest.** Образ пинится дайджестом, тег остаётся
  человекочитаемым маркером версии.
