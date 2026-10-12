# Grafana: эксплуатация

## Проверка после смены образа

Проверять после смены версии образа и после любой смены образа вообще:

```sh
kubectl -n monitoring exec deploy/grafana-deployment -c grafana -- sh -c \
  'curl -s -u "admin:$GF_SECURITY_ADMIN_PASSWORD" \
     "http://127.0.0.1:3000/api/datasources/uid/victoriametrics/health"'
```

Ожидается `{"status":"OK",...}`. Ответ `plugin.notRegistered` означает, что
плагины выпали из реестра, и алертинг молча слепой.

Drilldown проверяется отдельно — наличием приложений в реестре:

```sh
kubectl -n monitoring exec deploy/grafana-deployment -c grafana -- sh -c \
  'curl -s -u "admin:$GF_SECURITY_ADMIN_PASSWORD" \
     "http://127.0.0.1:3000/api/plugins?embedded=0"' | jq -r '.[].id' | grep app
```

Ожидаются все пять `*-app`. Пусто — меню Drilldown будет пустым, и алертинг
при этом выглядит исправным.

## Проверка datasource

Проверка после правки CR:

```sh
kubectl -n monitoring get grafanadatasource
kubectl -n monitoring exec deploy/grafana-deployment -c grafana -- sh -c \
  'curl -s -u "admin:$GF_SECURITY_ADMIN_PASSWORD" \
     "http://127.0.0.1:3000/api/datasources/uid/victoriametrics/health"'
```

## Проверка дашбордов

Проверка после правки JSON:

```sh
kubectl -n monitoring get grafanadashboard
kubectl -n monitoring logs deploy/grafana-operator --since=30s | grep -c DashboardReconciler
```

Второй счётчик обязан быть больше нуля: без лейбла
`app.kubernetes.io/managed-by` на ConfigMap'е watch не срабатывает и правка
молча не применяется.

## Проверка лейбла managed-by

```sh
kubectl -n monitoring get cm grafana-alerting \
  -o jsonpath='{.metadata.labels}' | grep managed-by
kubectl -n grafana-operator logs deploy/grafana-operator --since=30s | grep -c GrafanaReconciler
```

Второй счётчик обязан быть больше нуля.

## Обновление вендоренного дашборда

Обновление: перекачать JSON, повторить те же три правки, обновить ревизию в
таблице в `README.md`.

```sh
curl -s -o clusters/casa/apps/grafana/config/dashboards/traefik-official.json \
  https://grafana.com/api/dashboards/17346/revisions/latest/download
```

После применения **проверять логи**, а не только состояние Grafana:

```sh
kubectl logs deploy/grafana-deployment -n monitoring --tail=200 | grep provisioning.dashboard
```

Ожидается `finished to provision dashboards` без записей `level=error`.

## Проверка алертинга

Оператор доставил правила — по статусам CR, а не по логам Grafana:

```sh
kubectl -n monitoring get grafanacontactpoints,\
grafananotificationpolicies,\
grafanaalertrulegroups -o json |
  jq -r '.items[] | "\(.kind)/\(.metadata.name)\t\(.status.conditions[0].status)\t\(.status.conditions[0].message // "")"'
```

Все условия должны быть `True` / `ApplySuccessful`. `grafanacontactpoints` в
списке пуст — contact point остался в провижининге, и это ожидаемо.

Правила загружены — по логам провижининга:

```sh
kubectl logs deploy/grafana-deployment -n monitoring --tail=200 | grep -i provisioning.alerting
```

Ожидается `finished to provision alerting` без записей `level=error`. Две
записи `file has invalid suffix '..data'` — это норма: ConfigMap-проекция
кладёт рядом служебные каталоги, Grafana их пропускает.

При первом вычислении после старта пода отдельное правило может один раз
упасть с `plugin.notRegistered` (`attempt=1`): планировщик успевает
добраться до правила раньше, чем реестр плагинов datasource'а. Повтор
проходит успешно, в устойчивом режиме ошибок нет. Если ошибка повторяется на
каждом цикле — это уже не гонка старта, а отсутствие вложенного `datasource`
в `model` (см. «Правила и пороги» в `README.md`).

**Правила вычисляются** — по таблице состояний в БД Grafana, а не по UI.
Это единственная проверка, которая ловит правило, которое применилось, но
не считается: в интерфейсе оно при этом выглядит как рабочее.

```sh
kubectl exec -i shared-1 -n databases -c postgres -- \
  psql -U postgres -d grafana -c \
  "SELECT count(*) AS evaluated,
          count(*) FILTER (WHERE position('\x416c657274696e67' in data) > 0) AS firing
     FROM alert_rule_state;"
```

Ожидается `evaluated` = 14, `firing` — сколько правил сейчас в состоянии
Alerting. Состояние лежит protobuf-блобом, поэтому читается поиском подстроки
`Alerting` в hex; читаемой колонки нет. Расхождение с числом правил в
наборе правил означает, что в Grafana попало лишнее (или потерялось нужное) —
сверять надо с `SELECT count(*) FROM alert_rule`.

**Ноль в `evaluated` означает, что ни одно правило не вычислилось** — при этом
`alert_rule` в базе будет полной, а UI покажет созданные правила. Так выглядел
баг с отсутствующим вложенным `datasource` в `model`.

Таблица `alert_instance` в Grafana 13 пустая и **не является признаком поломки**:
состояние правил переехало в `alert_rule_state`. Проверять `alert_instance` нельзя
— на ней самой alerts сломаны выглядят исправными.

Ошибки оценки видны и в логах:

```sh
kubectl logs deploy/grafana-deployment -n monitoring --since=10m | grep "Failed to evaluate rule"
```

Правила внутри одной группы вычисляются последовательно, поэтому одно сломанное
правило блокирует остальные: в логах будет только его uid. Это сбивает с
толку — кажется, что сломалось одно, а на деле не считается вся группа.

Проверка доставки без правки правил — временно поставить одному правилу
`for: 0s` и заведомо истинное условие, затем вернуть как было. Быстрее и без
риска оставить заведомо ложное правило-«canary», но оно не должно попасть в main.

## Проверка

```sh
curl --resolve grafana.${DOMAIN}:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://grafana.${DOMAIN}/
```

Ожидаемый ответ: `302` (redirect на oauth2-proxy). Health API напрямую:

```sh
kubectl exec deploy/grafana-deployment -- curl -fsS http://127.0.0.1:3000/api/health
```

Что Grafana подключена к Postgres, видно по логу старта (`database: postgres`)
и по отсутствию `grafana.db` в поде.

Ротация секрета проверяется так: сменить значение в Vault, дождаться синка VSO и
убедиться, что под перезапустился сам —

```sh
kubectl -n monitoring get pod -l app=grafana \
  -o jsonpath='{.items[0].metadata.annotations.checksum/secrets}'
```

Пока значение не меняли, аннотация содержит SHA ресурсов; после ротации она
меняется, и это признак рестарта без `rollout restart`.

## Удаление

Откат: убрать CR и вернуть Deployment и Service Grafana из истории git. Данные
в Postgres не теряются — они переживают оба Deployment.
