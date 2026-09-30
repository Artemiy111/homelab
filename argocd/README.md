# Argo CD (пробный стенд)

Argo CD поднимается на кластере как **проверка второго GitOps-инструмента**:
целевое решение — Flux (см. `docs/research/k8s/argo-cd-vs-flux-cd.md`), но
разницу между «Argo рендерит манифесты сам» и «Flux управляет Helm-релизом»
полезно пощупать руками, а не вычитать.

| | |
|---|---|
| Чарт | `argo/argo-cd` 10.9.1 (community-maintained) |
| Argo CD | v3.5.3 |
| Namespace | `argocd` |
| URL | https://argocd.example.com |
| Параметры | `argocd/install/values.yaml` — только отклонения от дефолтов чарта |
| Маршрут | `platform/homelab/templates/routes/argocd.yaml` |

Все команды ниже выполняются **на сервере** (там есть `helm` и kubeconfig),
из корня репозитория.

## Установка

```sh
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Сначала посмотреть, что получится, не трогая кластер:
helm template argocd argo/argo-cd --version 10.9.1 -f argocd/install/values.yaml | less

helm install argocd argo/argo-cd \
  --version 10.9.1 \
  --namespace argocd --create-namespace \
  -f argocd/install/values.yaml \
  --wait

helm template platform/homelab -f platform/homelab/values.private.yaml | kubectl apply -f -
```

## Проверка

```sh
kubectl -n argocd get pods
```

Ожидаемо пять подов: `argocd-application-controller-0`,
`argocd-applicationset-controller`, `argocd-redis`, `argocd-repo-server`,
`argocd-server`. Отдельный под `dex` не появится — он отключён в values.

```sh
curl --resolve argocd.example.com:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' https://argocd.example.com
```

Ожидаемо `200` (страница логина). `5xx` и transport error — ошибка.

## Вход

Пароль admin генерируется один раз при установке:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Дальше https://argocd.example.com, логин `admin`.

CLI — два способа, потому что gRPC через прокси капризен:

```sh
# 1) через ингресс, поверх HTTP/1.1 (grpc-web)
argocd login argocd.example.com --grpc-web

# 2) через port-forward, вообще минуя Traefik
kubectl -n argocd port-forward svc/argocd-server 8080:80 &
argocd login localhost:8080 --plaintext
```

`--plaintext` нужен именно потому, что стоит `server.insecure: true` — Argo
отдаёт чистый HTTP. Если `argocd` CLI ещё не установлен:

```sh
curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/download/v3.5.3/argocd-linux-amd64
sudo install -m 0755 /tmp/argocd /usr/local/bin/argocd
```

Сразу после первого входа:

```sh
argocd account update-password
```

## Что проверять в рамках эксперимента

Задача стенда — сравнить механики, поэтому смотреть стоит именно на них:

1. **Self-heal (главное отличие от Terraform).** Создать приложение, потом
   вручную увести кластер в сторону — Argo вернёт сам:
   ```sh
   argocd app create guestbook \
     --repo https://github.com/argoproj/argocd-example-apps.git \
     --path guestbook --dest-server https://kubernetes.default.svc \
     --dest-namespace argocd-trial \
     --sync-policy automated --self-heal --auto-prune
   kubectl -n argocd-trial scale deploy guestbook-ui --replicas=5
   ```
2. **Отсутствие Helm-релиза.** `helm list -n argocd-trial` пуст: Argo сделал
   `helm template` и применил результат сам. Сравнить с тем, как повёл бы себя
   Flux `HelmRelease`.
3. **Порядок в Helm-чартах.** У Argo его задают sync-waves
   (`argocd.argoproj.io/sync-wave`), а не `dependsOn`, как во Flux.
4. **`lookup` не работает.** Чарты, читающие существующие объекты кластера при
   шаблонизации (генерация паролей), отрендерятся с пустыми значениями.
5. **ApplicationSet** — генератор приложений из git-директорий и списка
   кластеров вместо ручного создания каждого Application.

## Обновление Application: спека живёт в кластере

Application'ы применяются руками (`kubectl apply -f argocd/applications/<name>.yaml`), app-of-apps
здесь нет. Поэтому Argo читает желаемое состояние **из объекта в кластере**, а манифест в git
нужен только чтобы не потерять это состояние: пока файл не применён, правка values в git
ничего не меняет (приложение остаётся `Synced` на старой спеке).

```sh
kubectl apply -f argocd/applications/local-path-provisioner.yaml   # обновить спеку
argocd app sync local-path-provisioner                    # или ручной sync, см. ниже
```

### Приватные values (домен, externalIPs)

Часть values — environment-specific и не должна лежать в публичном git: адрес
узла в `traefik`, домен и `ssh.externalIPs` в `forgejo`, issuer и redirect URL в
`headlamp` и `radar`, хост реестра в `dns01-webhook`. Секретов среди них нет:
реальные credentials приходят из Vault через VSO, в Application лежат ссылки
`existingSecret`.

**Целевая схема** — отдельный приватный репозиторий (`docs/adr/0008`, #641):
Argo читает values оттуда сам, через `spec.sources` + `repoCreds` +
`helm.valueFiles: $values/<app>.yaml`. Файлов на узле в этой схеме нет, а правка
внутреннего значения идёт через PR приватного репозитория.

Пока перевод не сделан, работает прежняя конвенция: файл в
`argocd/applications/` — это шаблон (плейсхолдеры или опущенные ключи), а
реальные значения — в untracked `<name>.private.yaml` (merge-patch), который
применяется сразу после шаблона:

```sh
kubectl apply -f argocd/applications/forgejo.yaml
kubectl -n argocd patch application forgejo --type=merge \
  --patch-file argocd/applications/forgejo.private.yaml
```

Два свойства этого способа, о которых нужно помнить:

- **Ручной `helm upgrade --set` не подходит**: релизом владеет Argo, и selfHeal
  откатит. Применять один шаблон тоже нельзя — приватные значения затрутся (домен
  станет `example.com`, `externalIPs` пропадут).
- **`--type=merge` заменяет массивы целиком**, поэлементного слияния нет.
  Поэтому приватный файл обязан повторять весь список — так он и повторяет
  `gitea.oauth` в `forgejo.private.yaml` — и любое новое поле внутри этого списка
  патч затирает молча. Это ещё один довод за целевую схему, где values
  приезжают целиком, а не оверлеем.

`.gitignore` исключает `argocd/applications/*.private.yaml`; правило снимается
только после того, как файлов не останется (#641).

#### Доступ Argo к приватному репозиторию (настройка один раз)

Транспорт — SSH по service-DNS, потому что читает repo-server, то есть потребитель
внутри кластера. Наружу ничего открывать не нужно: `forgejo-ssh` — ClusterIP.
Argo узнаёт репозиторий по `url` из Secret с меткой
`argocd.argoproj.io/secret-type: repository`. Ссылаться на этот Secret в
Application не нужно: `repoCreds` существует только у одиночного `spec.source`,
в `spec.sources[]` такого поля нет, и попытка его указать даёт
`strict decoding error`. Поэтому в Vault лежат три ключа с именами, которые
Argo ожидает, — `sshPrivateKey`, `type` и `url`, — и шаблон трансформации не
нужен: VSO переносит ключи в Secret как есть.

```sh
# 1. Пара ключей на узле. Публичная половина становится deploy key'ом в Forgejo
#    (Settings → Deploy keys, без галочки Allow Write access).
ssh-keygen -t ed25519 -N '' -C 'argocd@homelab-values' -f ~/.ssh/argocd_homelab_values

# 2. Значения в Vault. Имена ключей — как их читает Argo: `sshPrivateKey`
#    приватная половина, `type` и `url` для подключения. Значение обязано
#    заканчиваться переводом строки, иначе OpenSSH такой ключ не разбирает.
vault kv put kv/forgejo/@argocd/ssh/homelab-values \
  sshPrivateKey=@$HOME/.ssh/argocd_homelab_values \
  type=git \
  url=ssh://git@forgejo-ssh.forgejo.svc.cluster.local:2222/artemiy/homelab-values

# 3. Роль и политика в Vault — через terraform, иначе ServiceAccount не получит
#    доступ на чтение пути. Сначала plan, потом apply: правило и роль на Argo
#    добавляются рядом с остальными, ограничивать apply не нужно.
terraform -chdir=terraform plan
terraform -chdir=terraform apply

# 4. Манифесты: ServiceAccount, VaultAuth и VaultStaticSecret. Secret
#    `homelab-values-repo` создаст VSO, вручную его не делаем.
kubectl apply -f argocd/vso-argocd.serviceaccount.yaml \
  -f argocd/vso-argocd.vaultauth.yaml \
  -f argocd/homelab-values-repo.vaultstaticsecret.yaml

# 5. Проверить, что Secret собрался, ключи на месте и метка проставлена. Значение
#    приватного ключа не печатаем.
kubectl -n argocd get vaultstaticsecret homelab-values-repo \
  -o json | jq -r '.status.conditions[0].status'
kubectl -n argocd get secret homelab-values-repo \
  -o json | jq -r '[.data | keys, .metadata.labels["argocd.argoproj.io/secret-type"]]'

# 6. Host key Forgejo. С узла service-DNS не резолвится, поэтому сканируем из
#    пода, иначе git не сможет сверить ключ хоста. При нестандартном порте запись
#    имеет вид [host]:2222.
kubectl -n argocd run keyscan --rm -i --restart=Never --image=alpine:3 -- \
  sh -c 'apk add -q openssh-client && ssh-keyscan -p 2222 forgejo-ssh.forgejo.svc.cluster.local'

# 7. Отдать host key Argo. В ConfigMap один ключ `ssh_known_hosts` на все
#    репозитории, так что дописываем запись к существующему содержимому.
kubectl -n argocd patch cm argocd-ssh-known-hosts-cm --type merge \
  -p "$(jq -rn --arg v "$(kubectl -n argocd get cm argocd-ssh-known-hosts-cm \
      -o jsonpath='{.data.ssh_known_hosts}')
<вывод keyscan>" '{data:{"ssh_known_hosts":$v}}')"

# 8. Убрать приватную половину с узла — только после шага 5, когда Secret уже
#    собран из Vault. До этого шага файл единственная копия ключа.
rm ~/.ssh/argocd_homelab_values
```

Шаги 6-7 повторяются при смене host key'а Forgejo. Путь в Vault и
`VaultStaticSecret` — единственное место, где живёт приватная половина: на узле
она остаётся только между шагами 2 и 8, а в кластере появляется исключительно из
Vault.

Host key'ы Argo хранит в ConfigMap `argocd-ssh-known-hosts-cm`, а не в
`argocd-tls-certs-cm`: в последнем лежат TLS-сертификаты для https-репозиториев,
и для SSH он не читается.

Второй источник в Application обязан иметь `ref: values` — именно он
сопоставляется с `$values`. Без него Argo попытается применять манифесты из
приватного репозитория, а не только читать из него values.

Ещё две вещи, которые полезно знать до того, как что-то менять:

- **Упавший sync не повторяется сам.** После ошибки контроллер логирует
  `failed previous sync attempt ... will not retry` и ждёт новый revision или ручной sync,
  даже при включённом `automated`. Форсировать из кластера (без CLI):
  ```sh
  kubectl -n argocd patch application local-path-provisioner --type merge \
    -p '{"operation":{"sync":{"prune":true}}}'
  ```
  (`operation` — поле верхнего уровня Application, не в `spec`.)
- **Immutable-поля Kubernetes не дают Argo починить дрейф** — типовая история: StorageClass
  (`reclaimPolicy`, `volumeBindingMode`, `provisioner`, `parameters`) или Service (`clusterIP`).
  Argo будет вечно `OutOfSync` с `field is immutable`; лечится удалением объекта, после чего
  Argo создаёт его заново.

## kube-state-metrics (боевой компонент под Argo)

`kube-state-metrics.yaml` — Application, который ставит официальный чарт
`prometheus-community/kube-state-metrics` в namespace `default`. Он отдаёт
метрики состояния объектов кластера (`kube_*`), которых нет у node-exporter.
Это уже не пробный стенд, а рабочий компонент, поэтому держать его нужно
**только** под Argo — не дублировать манифестами для будущего Flux.

```sh
kubectl apply -f argocd/applications/kube-state-metrics.yaml
argocd app get kube-state-metrics
argocd app diff kube-state-metrics
```

`syncPolicy` автоматический (prune + selfHeal): Argo сам приводит кластер к
состоянию чарта. Проверка self-heal — увести ресурс в сторону и дождаться
возврата (сравнимо с ручным `helm upgrade`):

```sh
kubectl -n default scale deploy kube-state-metrics --replicas=3
argocd app get kube-state-metrics
```

Метрики скрейпит vmagent (job `kube-state-metrics` в
`apps/victoria-metrics/config/vmagent/scrape.yml`) — после синка нужно
перезапустить vmagent.

## Адопция существующего Helm-релиза (на примере headlamp)

`headlamp.yaml` переводит уже работающий Helm-релиз под Argo **без
пересоздания** ресурсов. Порядок применим и к боевому Traefik.

```sh
kubectl apply -f argocd/applications/headlamp.yaml

argocd app diff headlamp        # желаемое (чарт) vs живое: расхождений быть не должно
argocd app sync headlamp        # server-side apply берёт ownership, Pod не пересоздаётся

kubectl -n headlamp get pods    # AGE не должен сброситься
```

Так как релиз ставился Helm 4 (server-side apply), адопция идёт
`ServerSideApply=true` — иначе client-side apply полез бы чинить
`last-applied-configuration`, которого Helm не оставляет.

Дальше нужно «забыть» Helm-релиз, чтобы `helm upgrade` не конкурировал с Argo.
Опции «удалить релиз, но оставить ресурсы» у Helm нет: `--keep-resources` не
существует ни в 3, ни в 4, а `--cascade orphan` — это лишь propagation policy
при удалении самих объектов. Рабочий способ — удалить release-секреты; ресурсы
при этом не трогаются, а релиз пропадает из `helm list`:

```sh
kubectl -n headlamp delete secret -l owner=helm,name=headlamp
```

Проверка: `helm list -n headlamp` пуст, ресурсы и Pod на месте.

Границы владения: чарт по умолчанию создаёт `ClusterRoleBinding headlamp-admin`
на SA пода `headlamp` — то есть выдаёт cluster-admin самому поду. Здесь это
выключено (`clusterRoleBinding.create: false`): под остаётся бесправным и
бежит под SA `headlamp`. Права приходят из OIDC: Headlamp отдаёт apiserver'у
`id_token`, который тот проверяет по подписи Zitadel и читает из него claim
`role` как группу. `cluster-admin` выдаётся группе `oidc:admin`
(`platform/headlamp/headlamp-admins.clusterrolebinding.yaml`), поэтому он есть
только у пользователей с ролью `admin` в Zitadel. `extraManifests` в этом
Application больше нет. Маршрут
(`platform/homelab/templates/routes/headlamp.yaml`) — вне Application.

### Traefik

`traefik.yaml` — тот же приём для боевого ingress (единственный вход на
`<node1-ip>`, поэтому проверять `argocd app diff` особенно внимательно).
Отличия от headlamp:

- `skipCrds: true` — CRD `*.traefik.io` кластерные; под управлением Argo они
  при удалении приложения снесли бы все `IngressRoute`/`Middleware` кластера.
- values продублированы из `platform/traefik/values.yaml` инлайном. При правке
  values менять оба места, иначе кластер уедет от файла.
- `service.spec.externalIPs` приезжает из `traefik.private.yaml`, и это
  нагрузочное значение: без него   Traefik не принимает трафик на адрес узла. Домен
  здесь не нужен — он живёт в маршрутах `platform/homelab`, а не в values
  Traefik.
- Обе строки выше снимаются вместе с переводом на values из приватного
  репозитория: и дублирование, и файл (`docs/adr/0008`, #641).
- Чарт сам создаёт `ClusterRole`/`ClusterRoleBinding`/`IngressClass` — они под
  управлением Argo (в отличие от RBAC headlamp, который вне чарта).

### sealed-secrets

`sealed-secrets.yaml` — адопция боевого контроллера в `kube-system`. Отличия:

- `skipCrds: true` — CRD `sealedsecrets.bitnami.com` кластерный, обновляется
  вручную (`helm show crds ... | kubectl apply -f -`).
- values — только `fullnameOverride`; без него ресурсы назывались бы
  `sealed-secrets`, а не `sealed-secrets-controller`.
- приватный ключ `sealed-secrets-key*` чартом не управляется, Argo его не
  трогает.
- после адопции забыть Helm-релиз:
  `kubectl -n kube-system delete secret -l owner=helm,name=sealed-secrets`.

## Отклонения от дефолтов чарта

| Параметр | Дефолт | Здесь | Зачем |
|---|---|---|---|
| `global.domain` | `argocd.example.com` | реальный домен | попадает в генерируемые URL |
| `configs.params."server.insecure"` | `false` | `true` | TLS терминирует Traefik |
| `configs.cm."timeout.reconciliation"` | `120s` | `60s` | реактивнее на одном репо |
| `dex.enabled` | `true` | `false` | SSO будет внешний (authentik) |
| `notifications.enabled` | `true` | `false` | контроллер уведомлений пока не нужен |
| `*.resources` | `{}` | заданы | однозный кластер: без limits контроллер может вытеснить приложения |

## Удаление

```sh
# Сначала приложения и их ресурсы, иначе финалайзеры подвесят удаление namespace
argocd app list -A
argocd app delete guestbook --cascade

helm uninstall argocd -n argocd
helm template platform/homelab -f platform/homelab/values.private.yaml | kubectl delete -f -
kubectl delete ns argocd

# CRD чарт намеренно не удаляет (crds.keep: true) — снимаем руками
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io
```

## ⚠️ Argo CD и Flux одновременно

Два GitOps-контроллера, ведущие один и тот же объект к разным желаемым
состояниям, — это гарантированный «пинг-понг» и непонятные случайные откаты.

Пока стенд живёт вместе с будущим Flux:

- держать Argo на **отдельном** наборе ресурсов: тестовые приложения, а не
  боевые манифесты кластера из `platform/`;
- не указывать обоим контроллерам один и тот же git-путь;
- помнить, что Argo ставится Helm'ом, а Flux будет управлять собой сам —
  их собственные манифесты в кластере тоже не должны пересекаться.

## Источники

- [argo-cd Helm chart](https://artifacthub.io/packages/helm/argo/argo-cd)
- [Argo CD Operator Manual](https://argo-cd.readthedocs.io/en/stable/operator-manual/)
- [docs/research/k8s/argo-cd-vs-flux-cd.md](../docs/research/k8s/argo-cd-vs-flux-cd.md)
- [docs/research/k8s/k0s-kubernetes-distribution.md](../docs/research/k8s/k0s-kubernetes-distribution.md)
