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

## Алёрты

Правила живут в Grafana (группа `victoria-metrics`), доставляются в ntfy.
Пороги и обоснование — в `clusters/casa/apps/grafana/README.md`, раздел
«Алёрты». Ниже — что делать, когда алерт уже сработал.

### `vm-free-disk-space-low` / `vm-storage-filling-fast`

Свободного места меньше 1.5 ГБ, либо прогноз обнуления меньше чем за 3 суток.
Это предупреждение, а не авария: TSDB ещё пишет.

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
  '{"spec":{"resources":{"requests":{"storage":"16Gi"}}}}'
```

Если расширять некуда, снижать retention (см. «ёмкость не соответствует
retention» в `README.md`): после смены `-retentionPeriod` нужен `kubectl rollout restart
deploy/victoriametrics`, и данные переживут перезапуск, но временный ряд
станет короче.

### `vm-pending-rows-backlog`

Очередь несохранённых строк выше 1 млн дольше 30 минут. Обычно предшествует
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
утёкший токен. Разовые обрывы лечатся увеличением `for` у правила, а не
ослаблением селектора.
