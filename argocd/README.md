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
| Маршрут | `platform/argocd/route.yaml` — применяется вручную, Argo его не синхронизирует (#858) |

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

helm template platform/homelab | kubectl apply -f -
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
   кластеров вместо ручного создания каждого Application. Возможность рабочая,
   но у нас не используется: генератор собирает `Application` в рантайме, и
   спека не лежит в git. Свойства проверены на стенде, решение — в разделе
   «Приложения из `apps/`».

## Бутстрап: спеки Application'ов живут в git

Application'ы применяет корневой `Application` — `bootstrap/root-application.yaml`.
Он рендерит каталог `argocd/` через kustomize и получает `AppProject` `upstream`
плюс 31 `Application` из `applications/` и `applications/apps/`. Раньше app-of-apps
не было, и спеки лежали только в git: Argo читал желаемое состояние из объекта в
кластере, и пока файл не применён руками, правка values в git ничего не меняла.

Публичный ключ deploy key добавляется в Forgejo (Настройки репозитория → Deploy
keys, только чтение), а приватный ключ отдаётся команде с машины, где он лежит:

Ключ лежит в `~/.ssh/id_homelab-argocd_homelab-repo`, комментарий
`homelab-argocd/homelab-repo` — по нему видно, для чего он:

```sh
argocd repo add ssh://git@forgejo.biplane.casa:2222/artemiy/homelab.git \
  --type git --name homelab \
  --ssh-private-key-path ~/.ssh/id_homelab-argocd_homelab-repo
```

Deploy key сделан без пароля: Argo тянет репозиторий без человека на месте и
зашифрованный ключ не откроет. Личный ключ аккаунта тоже сработал бы, но он шире
нужного — deploy key ограничен одним репозиторием.

Два подводных камня:

- **Без `--ssh-private-key-path` команда не создаст рабочее подключение.** Argo
  не получает ключа и пытается обратиться к SSH-агенту, которого в поде нет:
  `error creating SSH agent: "SSH agent requested but SSH_AUTH_SOCK not-specified"`.
- **URL должен совпасть с `root-application.yaml` посимвольно** — секрет
  сопоставляется с `repoURL` точным сравнением строки.

Хост-ключ Forgejo уже прописан в `configs.ssh.knownHosts` в `install/values.yaml`,
поэтому проверка хоста проходит. Ключ добавлен из `known_hosts` macOS, где
`origin` уже работает, — то есть проверен существующим соединением; `ssh-keyscan`
для этого не годится, он опрашивает сервер и ничего не проверяет. Тип только
`ssh-rsa`: ed25519-хостового ключа Forgejo в `known_hosts` нет.

После изменения `knownHosts` нужен `helm upgrade` с тем же values и перезапуск
`repo-server` — этот блок монтируется в под, а не читается на лету:

```sh
helm upgrade argocd argo/argo-cd --version 10.9.1 \
  --namespace argocd -f argocd/install/values.yaml \
  --set global.domain=argocd.example.com
kubectl -n argocd rollout restart deploy/argocd-repo-server
```

Значение `global.domain` в `--set` нужно только чтобы не переписать его: в
values оно живёт как есть, а передача `--set` поверх `-f` — не ошибка, а
дублирование. Проще переустановить релиз той же командой, что и при установке.

Сам root применяется руками — ровно как и сам Argo ставится `helm install`:
контроллер не может применить Application, который сам его и создаёт.

```sh
kubectl apply -f argocd/bootstrap/root-application.yaml
argocd app sync root
```

Проверка, что переход состоялся и ничего не сломалось:

```sh
argocd proj get upstream              # проект создан
argocd app list --project upstream               # 18 компонентов
argocd app list --project homelab                # 8 сервисов
argocd app list --project homelab-cluster-readers # 5 сервисов, alloy-profiler OutOfSync
argocd app diff traefik               # пусто
```

Дальше спеки меняются только коммитом: правка в git доезжает сама, `kubectl apply`
по одному файлу не нужен.

Что root делает и чего не делает:

| | Зачем |
|---|---|
| `automated.prune: true` | удалённый из git `Application` исчезает из кластера |
| `selfHeal` не включён | отладочные правки Application в кластере не откатываются |
| finalizer не задан | удаление root не сносит компоненты каскадом |
| `retry` с backoff | компенсирует «упавший sync не повторяется сам» для самого root |
| `ignoreDifferences` на `/spec/syncPolicy/automated` | ручное отключение автосинка не считается дрейфом |

Ограничения, которые надо знать до того, как что-то сломается:

- **`destinations` в `projects/upstream.yaml` — белый список из 16 namespace.**
  Компонент в новом namespace не задеплоится, пока его не впишут руками. Сделано
  намеренно: `clusterResourceWhitelist` у всех 18 компонентов одинаковый и
  включает `*`, ограничивать по kind бессмысленно — операторы законно создают
  CRD, ClusterRole, PriorityClass и webhook-конфигурации. Единственное, что
  осталось сузить, — куда им можно.
- **`namespaceResourceWhitelist` не задан намеренно.** Он не только разрешает,
  но и фильтрует resource tree в UI: не внесённые в него `Pod`/`ReplicaSet`
  перестают быть видны под `Deployment`. Плюс namespaced-ресурсы Argo
  ограничивает deny-list'ом, а не allow-list'ом, так что ограничивать их
  whitelist'ом — не то самое.
- **Root живёт в проекте `default`.** Если `default` когда-нибудь ужесточат
  (Argo документирует, как убрать из него все права), root откажется работать —
  тогда ему нужен собственный проект.
- **`prune: true` у root, а finalizer у `Application` в манифестах не задан.**
  Это осознанно: на одном узле ошибка в prune — простой. Но есть исключение,
  о котором надо знать: Argo добавляет `pre-delete-finalizer.argocd.argoproj.io`
  сам, когда в рендере чарта появляется `PreDelete`-хук. На 2026-10-04 это
  произошло с `longhorn` и `vault-secrets-operator`, и удаление спеки из git у
  этих двух снесёт ресурсы каскадом, а у остальных оставит сиротами.
  `resources-finalizer.argocd.argoproj.io` при этом есть не у всех: на 2026-10-05
  его носили три `Application`, созданных `ApplicationSet`, и ни один из 18
  написанных рукой в `applications/`, хотя `automated`-синк включён у обоих
  наборов. Проверять надо всегда, а не по списку:
  ```sh
  kubectl -n argocd get application -o \
    custom-columns='NAME:.metadata.name,FINALIZERS:.metadata.finalizers'
  ```

### Внутренние значения (домен, externalIPs)

Часть values — environment-specific: адрес узла в `traefik` и `forgejo`, issuer и
redirect URL в `radar` и `headlamp`, домен в `dns01-webhook`. Секретов среди них
нет: реальные credentials приходят из Vault через VSO, в Application лежат
ссылки `existingSecret` и `secretKeyRef`.

Значения лежат в публичном репозитории: у `traefik` — в
`platform/traefik/values.yaml`, у остальных компонентов пока инлайн в
`valuesObject` Application. Отдельный приватный слой был отменён
(`docs/adr/0009`): домен и так публичен — wildcard-сертификат Let's Encrypt
попадает в Certificate Transparency, где виден базовый домен, — а приватный
репозиторий стоил второго источника в каждом Application, SSH-подключения Argo,
хост-ключа Forgejo и роли в Vault. Плата: `terraform plan` в этих модулях
больше нельзя прогонять из публичного репозитория, пока `terraform.tfvars`
не на месте, а CI их не проверяет.

Список `gitea.oauth` задаётся целиком: merge-patch заменяет массивы целиком, и
частично перекрыть список нельзя, поэтому в Application перечислены все поля
элемента, а не только `autoDiscoverUrl`.

- **Упавший sync не повторяется сам.** После ошибки контроллер логирует
  `failed previous sync attempt ... will not retry` и ждёт новый revision или ручной sync,
  даже при включённом `automated`. У `root` это компенсировано полем `retry`; у 18
  платформенных `Application` — пока нет, там выкручивается вручную. Форсировать
  из кластера (без CLI):
  ```sh
  kubectl -n argocd patch application local-path-provisioner --type merge \
    -p '{"operation":{"sync":{"prune":true}}}'
  ```
  (`operation` — поле верхнего уровня Application, не в `spec`.)
- **Immutable-поля Kubernetes не дают Argo починить дрейф** — типовая история: StorageClass
  (`reclaimPolicy`, `volumeBindingMode`, `provisioner`, `parameters`) или Service (`clusterIP`).
  Argo будет вечно `OutOfSync` с `field is immutable`; лечится удалением объекта, после чего
  Argo создаёт его заново.

## Приложения из `apps/`

По одному `Application` на сервис, лежат в `argocd/applications/apps/` и
применяются тем же корневым `Application`, что и платформенные компоненты.
Способ тот же, что у 18 компонентов в `applications/`, — в репозитории один
стандарт на все 31 приложение.

Цена — повтор `repoURL` и `targetRevision` в каждом файле. Экономия на нём не
стоит: генератор собирает `Application` в рантайме, спека не лежит в git, и
PR, добавляющий сервис, не показывает ни `prune`, ни `selfHeal`, ни
`syncOptions` — то есть ровно то, что Argo сделает с кластером.

Что было вместо этого: `ApplicationSet` с git-генератором файлов, который читал
`apps/<сервис>/app.yaml` — реестр из четырёх полей (`name`, `dir`, `namespace`,
`project`). От него отказались, и вот почему:

| Проблема реестра | Что вместо |
|---|---|
| `Application` собирается в рантайме, в git не лежит | спека в файле, видна в диффе PR |
| `app.yaml` не проверялся ни одним гейтом: `kubeconform` сканирует `apps/*/k8s`, `platform`, `argocd`, а `apps/<сервис>/app.yaml` не попадает ни в одну дорожку | файл в `argocd/` проверяется kubeconform как `Application` |
| `prune` задан литералом в `spec.template` и достаётся всем без исключения — сервисы с данными защищены только тем, что их не добавили | `prune` виден в файле сервиса |
| поля реестра — подмножество `spec.Application`: чарты (`3x-ui`, `element`) и multi-source values (`traefik`) не выражались | выражаются, отдельный `Application` на каждый случай |
| `path` в реестре перекрывается служебным параметром генератора — пришлось переименовать в `dir` | таких коллизий нет |
| добавление сервиса — одна строка в git, но сервис появляется в кластере сам и незаметно | добавление сервиса — новый файл плюс строка в `argocd/kustomization.yaml`, и в ревью видно, что сервис добавлен под Argo |

Обходной путь для boolean-полей (`templatePatch`, где `prune: {{ .prune }}`
рендерится как YAML, а не как строка) существует и был бы пригоден — но он не
решает ни одну из проблем выше, только последнюю.

### Перевод сервиса на Argo

Один сервис — один файл в `argocd/applications/apps/` плюс строка в
`argocd/kustomization.yaml`. Ниже — порядок для сервиса, который уже применён
руками; AGE подов при этом не должен сброситься.

```sh
# 1. Снять finalizer с Application, если он есть. Иначе удаление спеки
#    снесёт управляемые ресурсы каскадом, а вместе с ними Namespace.
#    Пока сервис обслуживает ApplicationSet — см. «Снятие ApplicationSet».
kubectl -n argocd get application <svc> -o \
  custom-columns='NAME:.metadata.name,FINALIZERS:.metadata.finalizers'
kubectl -n argocd patch application <svc> --type json \
  -p '[{"op":"remove","path":"/metadata/finalizers"}]'

# 2. Проверить рендер до синка: Argo покажет расхождение, если что-то не так.
argocd app diff <svc>

# 3. Синк и проверка, что поды те же.
argocd app sync <svc>
kubectl -n <ns> get pods
```

`server-side apply` обязателен (`ServerSideApply=true`): часть сервисов
применялась Helm'ом, и client-side apply полез бы чинить
`last-applied-configuration`, которого после Helm нет.

### Проект сервиса

`homelab` либо `homelab-cluster-readers`. Второй нужен шести сервисам, читающим
кластер целиком, — `alloy`, `alloy-profiler`, `beyla`, `homepage`,
`victoria-metrics`, `elk`. Список имён и причина — в разделе
«Проект `homelab-cluster-readers`».

### Отключённый сервис

Поле `suspend` у `Application` нет — это механизм Flux. В Argo эквивалент
отсутствие блока `syncPolicy.automated`: приложение существует, но никогда не
синкается само, поэтому Argo не создаст удалённые ресурсы обратно.

Так выключен `alloy-profiler`: `DaemonSet` удалён из кластера вручную
2026-10-06, входящих профилей в `pyroscope` нет. Файл Application оставлен с
манифестами, но без `automated`; включение — убрать блок из файла. Приложение
при этом постоянно `OutOfSync`, и это служит индикатором выключенного
состояния.

Список выключенного, чтобы не выводить его археологией:

| Сервис | Как выключен | Включение |
|---|---|---|
| `authentik`, `gitlab`, `alloy-profiler` | Application без `syncPolicy.automated` | вернуть блок `automated` |
| `local-ai` | манифесты в git, Application нет | завести Application, вернуть namespace в `platform/homelab/values.yaml` |
| `netdata` | удалён из репозитория 2026-10-10 | поставить заново, `netdata` ставится из образа |
| `vmagent` | `replicas: 0` в `apps/victoria-metrics` (#888) | снять `replicas: 0`, снять `enabled: false` в Gatus |

Проверки выключенного в `apps/gatus/config/config.yaml` помечены
`enabled: false`, а не удалены: так видно, что сервис есть и почему молчит.
Красная доска постоянного состояния хуже отсутствия доски — замечают
настоящую тревогу по тем, кто молчит, а не по тем, кто всегда красный.

### Про `prune`

`prune: true` означает: ресурс, удалённый из git, удаляется и из кластера. Для
stateless-сервисов это и нужно — иначе удалённый из репозитория Deployment
продолжит жить.

Для сервиса с данными prune опасен: удаление PVC в тех Application
(`seafile`, `nextcloud`, `forgejo`) равно потере данных. У них будет
`prune: false`, и удаление каталога из git оставит осиротевшие ресурсы, которые
надо снести руками.

Обратная сторона `prune: true` — удаление спеки сервиса из git удаляет и его
ресурсы, если у `Application` есть `resources-finalizer.argocd.argoproj.io`:
finalizer заставляет Argo снести управляемые ресурсы перед тем, как объект
исчезнет. Проверять надо всегда, а не по списку.

Три таких `Application` нашлись 2026-10-06 — их создал `ApplicationSet`, и
finalizer добавлял именно он, а не Argo при `automated`-синке: наши 25
`Application`, написанные рукой, ни одного не имеют, хотя `automated` включён
у всех. Отсюда и порядок ниже.

### Снятие `ApplicationSet`

Удаление `ApplicationSet` каскадом удаляет созданные им `Application` — у них
`ownerReferences` с `blockOwnerDeletion`. Если у них же есть
`resources-finalizer`, каскад продолжается в managed-ресурсы и `Namespace`.
На 2026-10-06 с этим столкнулись при снятии `ApplicationSet apps`:
`code-server` и `mermaid-live-editor` потеряли бы поды.

Просто снять finalizer руками нельзя: `applicationset-controller` в пределах
цикла реконсиляции возвращает его и логирует `updated Application`. Сначала
запрещаем контроллеру трогать эти `Application`, потом снимаем finalizer, потом
удаляем сет:

```sh
# 1. create-only запрещает и изменять, и удалять существующие Application.
kubectl -n argocd patch applicationset apps --type merge \
  -p '{"spec":{"syncPolicy":{"applicationsSync":"create-only"}}}'

# 2. Теперь finalizer держится снятым (проверять после реконсиляции, не сразу).
for a in code-server mermaid-live-editor node-exporter; do
  kubectl -n argocd patch application "$a" --type json \
    -p '[{"op":"remove","path":"/metadata/finalizers"}]'
done
kubectl -n argocd get application \
  -o custom-columns='NAME:.metadata.name,FINALIZERS:.metadata.finalizers' \
  | grep -v '<none>'

# 3. Удалить сет — теперь из git коммитом или руками.
```

Без шага 1 шаг 2 не имеет эффекта, а без шага 2 шаг 3 роняет сервисы. После
перехода финализаторов нет ни у одного `Application`, поэтому будущее удаление
спеки оставит ресурсы сиротами — сносить их руками.

### Проект `homelab`

Единственное кластерное право — свой `Namespace`. Приложение обязано уметь
создать свой, но не может трогать `CRD`, `ClusterRole`, `StorageClass` и прочее
на уровне кластера. Это структурная защита от эскалации: нельзя случайно
выдать сервису кластерные права, как это делал чарт headlamp
(`clusterRoleBinding.create: true`).

`namespaceResourceWhitelist` не задан намеренно. Он не только разрешает, но и
фильтрует resource tree в UI: не внесённые в него `Pod`/`ReplicaSet`
перестают быть видны под `Deployment`. Плюс namespaced-ресурсы Argo
ограничивает deny-list'ом, а не allow-list'ом — ограничивать их whitelist'ом
не то самое.

`destinations` — `namespace: '*'`, в отличие от проекта `upstream`: перечислять
40+ namespace'ов сервисов означало бы править проект при каждом новом
сервисе. Границы сервиса держат его манифесты.

### Проект `homelab-cluster-readers`

Шесть приложений читают кластер целиком — `alloy`, `alloy-profiler`, `beyla`,
`victoria-metrics`, `homepage`, `elk`. Первым пяти и `elk` нужен
`ClusterRole`, а проект `homelab` разрешает только `Namespace`, поэтому они
живут в отдельном проекте `homelab-cluster-readers`.

Отдельно про `Namespace`: сервис, который приносит `namespace.yaml` в своих
манифестах, требует и права создать `Namespace`. В этом проекте такой один —
`homepage`; остальные четыре живут в уже существующем `monitoring`. Поэтому
whitelist содержит `Namespace` с именем `homepage`, а не вид целиком. Без этой
записи синк падает с «`Namespace` is not permitted in project».

Почему отдельный, а не расширить `homelab`: добавление `ClusterRole` в его
whitelist дало бы право всем ~45 сервисам проекта, включая те, которые его не
запрашивали. Здесь право есть ровно у шести.

Whitelist перечисляет не вид целиком, а конкретные имена — двенадцать записей
по шесть пар `ClusterRole`/`ClusterRoleBinding`. Схема
`ClusterResourceRestrictionItem` допускает `name` с glob-паттернами, а без
`name` совпадает всё в группе и виде. Поэтому сервис не сможет создать
посторонний `ClusterRole`, даже если тот появится в манифесте по ошибке.

`clusterResourceWhitelist` — единственный рычаг на кластерные объекты:
namespaced-ресурсы Argo ограничивает deny-list'ом, cluster-scoped —
allow-list'ом. Нет записи → нельзя ни создать, ни удалить. Отсюда свойство,
которого нет у `upstream` с его `*`/`*`: `prune: true` у приложения в
`homelab` или `homelab-cluster-readers` физически не может задеть чужой
кластерный объект.

Почему ограничение нужно. Argo применяет манифесты от имени одной учётки
`system:serviceaccount:argocd:argocd-application-controller`, и у неё есть
права на `create`/`delete` любых кластерных объектов — иначе не поставились бы
операторы Longhorn, Gateway API и cert-manager. `AppProject` вторая линия
поверх этого. Без неё ошибка в манифесте (убрали `ClusterRole` из `k8s/`)
привела бы не к отказу Argo, а к удалению `ClusterRole` из кластера: сборщик
логов или метрик молча теряет права и перестаёт работать.

### Про `kustomization.yaml`

Манифесты лежат в `apps/<сервис>/k8s/`, и Argo в режиме plain-каталога **не
рекурсирует в подкаталоги**: каталог без `kustomization.yaml` считается пустым
и приложение отвечает «app path does not exist». Проверено на стенде — в том
числе пробным `Application` с новым именем, у которого тот же путь работал.

Поэтому каждому сервису под Argo нужен `kustomization.yaml` в корне каталога.
Это заодно делает тип приложения детерминированным: не приходится полагаться
на то, как именно Argo определит каталог.

### Про HTTPRoute и дефолты CRD

Apiserver подставляет в `HTTPRoute` шесть полей, которых нет в манифесте:

| Поле | Значение |
|---|---|
| `spec.parentRefs[].group` | `gateway.networking.k8s.io` |
| `spec.parentRefs[].kind` | `Gateway` |
| `spec.rules[].backendRefs[].group` | `""` |
| `spec.rules[].backendRefs[].kind` | `Service` |
| `spec.rules[].backendRefs[].weight` | `1` |
| `spec.rules[].matches` | `[{path: {type: PathPrefix, value: /}}]` |

Argo о таких дефолтах не знает — он знает только про встроенные типы Kubernetes.
Итог выглядит противоречиво: `argocd app diff` пуст, `argocd app sync` отрабатывает
успешно, но приложение навсегда остаётся `OutOfSync`. Расходится ровно один ресурс
на приложение, и auto-sync не помогает — он же и не срабатывает, потому что
состояние не меняется.

Решение — `resource.customizations.ignoreDifferences` в `install/values.yaml`.
Синтаксис `jqPathExpressions` требует **путь к полю**, а не операцию над ним:
`.spec.parentRefs[]?.group` верно, `.spec.parentRefs[] | del(.group, .kind)` — нет,
`del()` удаляет из результата запроса, и правило молча ничего не игнорирует. На
этом ушла часть времени: ошибка выглядит как «настройка не действует», хотя
настройка как раз неверная.

Дефолты взяты из схемы самого CRD, а не из документации:

```sh
kubectl get crd httproutes.gateway.networking.k8s.io \
  -o jsonpath='{..rules.items.properties}' | jq
```

Правкой всех 41 `apps/*/k8s/route.yaml` вопрос не решается: дефолты появились бы
снова при обновлении CRD, и manifests-файлы начали бы повторять то, что и так
знает apiserver.

## Про кэш ошибок рендера

`controller.default.cache.expiration` по умолчанию **24 часа**, и ошибка
рендера кэшируется на весь этот срок. Практическое следствие: если приложение
упало с ошибкой, то исправление манифестов в git не будет замечено до конца
срока. Не помогают ни `argocd app get --refresh`, ни
`argocd.argoproj.io/refresh=hard`, ни перезапуск `repo-server`.

Обходной путь, которым пришлось воспользоваться при переводе первых трёх
сервисов: изменить ключ кэша. Он складывается из namespace, имени приложения,
URL и пути — но **не** из ревизии, так что фиксация `targetRevision` не
помогает. Сработало удаление и пересоздание `Application` под другим именем.

Понижено до `10m` в `argocd/install/values.yaml`, в `configs.params` — отдельного
значения `controller.default.*` в чарте 10.9.1 нет, ключ попадает в
`argocd-cmd-params-cm` через эту свободную карту. Компонент читает cm при
старте, поэтому после `helm upgrade` нужен рестарт `application-controller`.

Пока `helm upgrade` не выполнен, действует дефолт: об ошибке рендера стоит
думать как о «залипшей на сутки».

## Задержка применения

Webhook не работает: Argo поддерживает его только для GitHub и GitLab, origin
здесь Forgejo. Поэтому root ждёт следующей сверки ревизии, и спека
`Application` доезжает в кластер с задержкой — это нормально и специально не
ускорено.

`kube-state-metrics.yaml` — Application, который ставит официальный чарт
`prometheus-community/kube-state-metrics` в namespace `monitoring`. Он отдаёт
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
(`platform/headlamp/route.yaml`) — вне Application.

### Traefik

`traefik.yaml` — тот же приём для боевого ingress (единственный вход на
`<node1-ip>`, поэтому проверять `argocd app diff` особенно внимательно).
Отличия от headlamp:

- `skipCrds: true` — CRD `*.traefik.io` кластерные; под управлением Argo они
  при удалении приложения снесли бы все `IngressRoute`/`Middleware` кластера.
- values лежат в `platform/traefik/values.yaml` и подключены через `$values` —
  второй источник в `spec.sources`, ссылающийся на этот же репозиторий по SSH.
  Раньше те же 32 значения были продублированы инлайн в `valuesObject`, и правка
  файла молча расходилась с кластером. Теперь файл — единственный источник.
- `service.spec.externalIPs` — адрес узла, и это нагрузочное значение: без него
  Traefik не принимает трафик на адрес узла. Живёт в values-файле.
  Домен здесь не нужен — он в маршрутах `platform/homelab`, а не в values Traefik.
- Значения из приватного репозитория сюда не возвращаются (`docs/adr/0009`):
  домен и адрес узла публичны по решению.
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
# Сначала root: иначе он успеет восстановить то, что удаляется ниже
kubectl delete application root -n argocd

# Сначала приложения и их ресурсы, иначе финалайзеры подвесят удаление namespace
argocd app list -A
argocd app delete guestbook --cascade

helm uninstall argocd -n argocd
helm template platform/homelab | kubectl delete -f -
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
