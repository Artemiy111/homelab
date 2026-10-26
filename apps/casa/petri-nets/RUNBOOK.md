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

1. Открыть `https://petri-nets.biplane.casa/` с открытыми DevTools.
2. В консоли выполнить:
   ```js
   setTimeout(() => { throw new Error("glitchtip smoke test") })
   ```
3. В GlitchTip в проекте приложения должно появиться событие с этим текстом в
   пределах минуты.

Если события нет: в исходнике страницы (`view-source:`) поискать DSN — пустой
DSN означает, что переменная не задана; при заданном DSN проверить, что браузер
не блокирует запрос к `glitchtip.<домен>` (adblock, DNS, сертификат).

## Задать или сменить DSN

1. В GlitchTip создать проект (организация — по вкусу), платформа — Browser
   JavaScript. DSN лежит в **Project settings → Client Keys (DSN)**.
2. Добавить в `apps/casa/petri-nets/manifests/deployment.yaml` переменную
   `SENTRY_DSN` со значением DSN, PR, merge.
3. Argo перекатит под: DSN читается на каждый запрос, рестарт нужен только
   потому, что меняется шаблон пода.

DSN — публичное значение, в Vault его не кладут: он всё равно уезжает в HTML.

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

## Удаление

```sh
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl -n argocd delete application petri-nets
KUBECONFIG=~/.kube/configs/homelab.yaml kubectl delete namespace petri-nets
```

Namespace помечен `Prune=false`, поэтому сам он не удаляется: без второй
команды останется сирота с подом и маршрутом.
