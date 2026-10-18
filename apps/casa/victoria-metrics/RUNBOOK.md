# VictoriaMetrics: эксплуатация

## Проверка

Наличие целей и их состояние:

```sh
kubectl exec deploy/victoriametrics -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=up' | grep -o '"job":"[^"]*"'
```

HTTP-маршрут VMUI (ожидаем 302 на oauth2-proxy):

```sh
curl --resolve vm.${DOMAIN}:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://vm.${DOMAIN}/
```

## Копия в Monium

Порядок шагов не влияет на доступность: том с ключом помечен `optional`, поэтому
под vmagent стартует и без Secret — копия просто не отправляет данные, пока
ключа нет, и это видно по алерту `monium-write-stalled`. Без `optional`
отсутствующий Secret не дал бы поду встать, а `strategy: Recreate` остановил бы
и локальный сбор метрик.

1. Сервисный аккаунт с ролью `monitoring.editor` на каталог (её требует
   инструкция Monium по remote write) и **API-ключ** к нему с областью действия
   `yc.monium.metrics.write` — в консоли Yandex Cloud. Область действия там
   обязательна, значения ключа показываются один раз. Статический ключ доступа и
   авторизованный ключ не подходят: первый — для AWS-совместимых API, второй —
   для обмена на IAM-токен.
2. Ключ в Vault (ключ в теле запроса совпадает с именем файла в поде):

```sh
vault kv put kv/victoria-metrics/monium-api-key MONIUM_API_KEY=<api-ключ>
```

3. Политика `app/vmagent` (приватный слой):

```sh
cd infra/casa/terraform/vault && terraform apply
```

4. Манифесты — обычным путём.

Файл с ключом появляется в поде после того, как `VaultStaticSecret`
синхронизируется с Vault. Если через пару минут файла всё ещё нет, под нужно
перезапустить:

```sh
kubectl -n monitoring rollout restart deploy/vmagent
```

Проверка, что копия идёт:

```sh
kubectl -n monitoring exec deploy/vmagent -- wget -qO- 'http://127.0.0.1:8429/metrics' | \
  grep -E '^vmagent_remotewrite_(blocks_sent_total|rows_pushed_after_relabel_total|relabel_metrics_dropped_total)'
```

Ожидаем: `blocks_sent_total` с облачным URL растёт, а
`relabel_metrics_dropped_total` для него — большая часть потока: подмножество
отсекается, это норма. Первые после включения строки могут появиться через
пять минут работы дедупликации.

```sh
kubectl -n monitoring exec deploy/vmagent -- ls /etc/vmagent-monium
```

Ожидаем: файл `MONIUM_API_KEY`. Значение не печатать.

Ротация ключа: выпустить новый, повторить `vault kv put`. Secret обновляется
раз в час (`refreshAfter`), файл vmagent перечитывает раз в секунду — рестарт
пода не нужен.

Диагностика по коду ответа Monium (в логах vmagent и в
`vmagent_remotewrite_requests_total` по лейблу `status_code`):

| Код | Что значит |
|---|---|
| `401` | Ключ неверный, отозван или его область действия не подходит (ожидается `yc.monium.metrics.write`) |
| `403` | У сервисного аккаунта нет `monitoring.editor` на каталог |
| `404` | Неверный идентификатор воркспейса в URL |
| `400` | Битый формат, в том числе больше 29 лейблов у метрики. Дропается молча — смотреть `vmagent_remotewrite_packets_dropped_total` |
| `413` | Квота: больше 10 000 метрик в запросе или исчерпана квота уникальных рядов. Ретраится бесконечно, растёт очередь |
| `429` | Превышена скорость записи, повторяется автоматически |

Если растёт `vmagent_remotewrite_pending_data_bytes` по облачному URL, копия не
успевает и очередь копится; при достижении `maxDiskUsagePerURL` vmagent начнёт
выбрасывать старые данные копии. Локальная VictoriaMetrics и её данные от этого
не страдают.

## Алёрты

Правила живут в Grafana (группа `victoria-metrics`), доставляются в ntfy.
Пороги и обоснование — в `apps/casa/grafana/README.md`, раздел
«Алёрты». Ниже — что делать, когда алерт уже сработал.

### `pvc-low-free-space` / `pvc-will-fill-in-3-days`

Свободного места на томе мало, либо прогноз говорит, что оно кончится в
ближайшие дни. Это предупреждение, а не авария: TSDB ещё пишет.

```sh
kubectl exec deploy/victoriametrics -n monitoring -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=vm_data_size_bytes'
kubectl get pvc victoriametrics-vmdata -n monitoring
```

Смотреть `vm_data_size_bytes` по `type`: `storage/big` — основной объём,
`storage/small` — ещё не слитый буфер, `indexdb/*` — индексы. Расширение PVC
на месте (Longhorn сохраняет UID и данные):

```sh
kubectl patch pvc victoriametrics-vmdata -n monitoring -p \
  '{"spec":{"resources":{"requests":{"storage":"<новый размер, больше текущего>"}}}}'
```

Если расширять некуда, снижать retention (см. «Ёмкость и retention» в
`README.md`): после смены `-retentionPeriod` нужен `kubectl rollout restart
deploy/victoriametrics`, и данные переживут перезапуск, но временный ряд
станет короче.

### `vm-pending-rows-backlog`

Очередь несохранённых строк не разгружается. Обычно предшествует
`vm-storage-read-only`: сброс на диск сначала замедляется, потом падает.

```sh
kubectl exec deploy/victoriametrics -n monitoring -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=vm_pending_rows'
```

Смотреть, растёт ли `type="storage"` монотонно. Если да — места на диске уже
нет, и это ложное «медленно»; лечится расширением PVC.

### `vm-storage-read-only`

Авария: vmagent получает 503 на remote write, новые метрики теряются, уже
записанные данные целы. Подробный разбор — `docs/incidents/
0003-victoriametrics-pvc-read-only.md`.

```sh
kubectl exec deploy/victoriametrics -n monitoring -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=vm_free_disk_space_bytes'
```

Порядок действий: расширить PVC, дождаться `vm_storage_is_read_only == 0`,
и только после этого `kubectl rollout restart deploy/victoriametrics`.
Рестарт до расширения не поможет — TSDB снова упрётся в тот же предел.

### `scrape-target-down`

Таргет отвечает, но метрики с него не читаются: 401/403 на `/metrics`, битый
токен, сломанный exporter. Значение `job` в алерте — имя таргета из
`config/vmagent/scrape.yml`.

```sh
kubectl exec deploy/victoriametrics -n monitoring -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=up'
```

Если падает сразу много таргетов, ищите общую причину, а не каждый таргот по
отдельности: один и тот же образ экспортера, одна сетевая политика, один
утёкший токен. Разовые обрывы лечатся увеличением окна срабатывания у правила,
а не ослаблением селектора.

### `monium-write-stalled`

Копия метрик в Monium не отправляет пачки. Локальная запись при этом обычно
жива — правило следит только за облачным URL.

```sh
kubectl -n monitoring exec deploy/vmagent -- wget -qO- 'http://127.0.0.1:8429/metrics' | \
  grep -E 'vmagent_remotewrite_(blocks_sent_total|requests_total|pending_data_bytes)'
```

Смотреть `status_code` в `vmagent_remotewrite_requests_total` по облачному URL и
дальше — по таблице кодов в разделе «Копия в Monium». Лейбл `url` содержит
адрес эндпоинта целиком, потому что vmagent запущен с `-remoteWrite.showURL`.
