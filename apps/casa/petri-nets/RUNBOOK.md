# petri-nets: эксплуатация

## Проверка

```sh
curl -sS --resolve petri-nets.biplane.casa:443:<node1-ip> \
  -o /dev/null -w '%{http_code}\n' https://petri-nets.biplane.casa/
```

Ожидается `200` и HTML на `curl` без `-o /dev/null`.

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n petri-nets get pods,httproute
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n argocd get application petri-nets
```

Ожидается: один под `Running` и `Ready`, у маршрута `Accepted=True` и
`ResolvedRefs=True`, у приложения `Synced`/`Healthy`.

## Логи и Web Vitals

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n petri-nets logs deploy/petri-nets \
  --since=5m | grep web-vital
```

Ожидается JSON-строка на каждую метрику страницы (`LCP`, `CLS`, …). Метрики
видны и в Loki: в Grafana искать по `{namespace="petri-nets"}` и тексту
`web-vital`.

## Проверка, что ошибки доходят до GlitchTip

Блокировщик рекламы режет запрос к `glitchtip.<домен>`: для страницы это чужой
домен, а списки фильтров включают Sentry-подобные пути. Поэтому проверять нужно
браузером без блокировщика (или с отключённым для этого сайта): иначе события не
будет при любом состоянии кластера.

1. Открыть `https://petri-nets.biplane.casa/` с открытыми DevTools, блокировщик
   для сайта выключен.
2. В консоли выполнить:
   ```js
   setTimeout(() => { throw new Error("glitchtip smoke test") })
   ```
3. В GlitchTip в проекте приложения появляется событие с этим текстом.

Если события нет, проверять по порядку:

1. **Блокировщик.** В uBlock Origin: иконка → список заблокированных запросов,
   искать `glitchtip.<домен>`. Отключить для сайта и повторить.
2. **DSN в странице.** `view-source:` → поиск `glitchtip.`. Пусто — переменная не
   доехала до пода.
3. **Серверная часть без браузера.** Тот же путь, но `curl`:
   ```sh
   curl -sS -X POST 'https://glitchtip.<домен>/api/<проект>/store/?sentry_key=<публичный-ключ>' \
     -H 'content-type: application/json' \
     -d '{"event_id":"'"$(uuidgen | tr 'A-Z' 'a-z' | tr -d '-')"'","message":"store smoke test","level":"error"}'
   ```
   `200` и `event_id` в ответе означают, что ingest и ключ рабочие и дело в
   клиенте.
4. **Сеть в DevTools.** Запрос к `glitchtip.<домен>` либо отсутствует (SDK не
   инициализировался), либо падает (блокировка, CORS, сертификат, DNS).

## Задать или сменить DSN

1. В GlitchTip создать проект (организация — по вкусу), платформа — Browser
   JavaScript. DSN лежит в **Project settings → Client Keys (DSN)**.
2. Добавить в `apps/casa/petri-nets/manifests/deployment.yaml` переменную
   `SENTRY_DSN` со значением DSN, PR, merge.
3. Argo перекатит под: DSN читается на каждый запрос, рестарт нужен только
   потому, что меняется шаблон пода.

DSN — публичное значение, в Vault его не кладут: он всё равно уезжает в HTML.

## Source maps

Карты загружает Job `petri-nets-sourcemaps` при каждом синке приложения (хук
`PostSync`). Политика `BeforeHookCreation` удаляет его перед следующим синком,
поэтому «Job'а нет» — нормальное состояние: смотреть надо логи сразу после синка
и сам release в GlitchTip.

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n petri-nets logs job/petri-nets-sourcemaps
```

Ожидается `uploading source maps for release <sha>` и итог `sentry-cli` с числом
загруженных файлов. Строка `SENTRY_AUTH_TOKEN is empty` означает, что токен не
пришёл из Vault — порядок включения ниже.

### Первое включение и ротация токена

1. GlitchTip → **User settings → Auth Tokens** → создать токен со scope
   `project:write`.
2. `vault kv put kv/petri-nets/glitchtip SENTRY_AUTH_TOKEN=<токен>`.
3. В `infra/casa/terraform/` выполнить `terraform apply` — политика
   `app/petri-nets` и роль для ServiceAccount `vso-petri-nets`.
4. `argocd app sync petri-nets`, чтобы Job запустился (или дождаться следующего
   синка).
5. Проверить логи Job и release в GlitchTip.

Ротация — тот же путь: новое значение в Vault, VSO подхватит его за `refreshAfter`,
карты перезальёт следующий синк.

## Обновление версии

Обычный путь — PR от Renovate с новым digest: проверить, что сборка в
upstream-репозитории зелёная, и смержить.

Вручную:

```sh
crane digest ghcr.io/artemiy111/timed-petri-nets:latest
```

Полученный digest подставить в `image` (тег `latest` оставить перед `@`), PR,
merge, дождаться переката пода.

## Диагностика

- **`CrashLoopBackOff`, в логах `EROFS` или `EACCES`.** Корневая файловая
  система только для чтения; приложению нужна запись в `/tmp` и в
  `/app/.next/cache`, оба каталога — `emptyDir`. Новая точка записи добавляется
  монтированием, а не снятием `readOnlyRootFilesystem`.
- **`503` от Traefik, под `Running`.** Смотреть `kubectl -n petri-nets get
  endpoints petri-nets`: пустой список означает, что под не прошёл readiness
  probe (проба ходит на `/`); отказ при живых эндпоинтах — NetworkPolicy
  (разрешён только namespace `traefik` на порт приложения).
- **Страница открывается без стилей.** В образе нет `.next/static` — ошибка
  сборки образа, а не кластера. Проверяется локально:
  `docker run --rm --entrypoint sh <image> -c 'ls /app/.next/static'`.
- **`404` на `/api/vitals`.** Образ собран без маршрута Web Vitals. В GHCR
  arm64-вариант `latest` отставал от amd64: если образ тянули на маке, а не в
  кластере, это он.
- **Под убит по памяти (`OOMKilled`).** Next.js на SSR держит несколько сотен
  мегабайт; лимит памяти — первый подозреваемый, но раньше смотреть, не выросло
  ли потребление после смены digest.
- **GlitchTip стал медленным, растёт его база.** Единственный поставщик событий
  в него — это приложение с полным сэмплированием. Снижение
  `SENTRY_TRACES_SAMPLE_RATE` режет объём транзакций; ошибки продолжают идти при
  любой доле.

## Удаление

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n argocd delete application petri-nets
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl delete namespace petri-nets
```

Namespace помечен `Prune=false`, поэтому сам он не удаляется: без второй
команды останется сирота с подом и маршрутом.
