# Lute

Lute — веб-приложение для чтения и изучения иностранных языков (Language
Utilities for Tracking Exposure). Контейнер доступен только через Traefik по
адресу `https://lute.example.com/`; порт приложения напрямую на хост не
публикуется. Внутри контейнера приложение слушает порт `5001`. Постоянные данные
находятся в `$APPS_STORAGE_PATH/lute/data`.

## Запуск

`init.sh` создаёт каталоги данных и книг в `$APPS_STORAGE_PATH/lute` и формирует
`config.env` с именем хоста (используется в правиле маршрутизации Traefik). Из
каталога сервиса:

```sh
bash scripts/bootstrap-platform.sh lute
```

Доступ к приложению идёт через `traefiknet`; на хосту должна быть запись DNS
`lute.example.com` -> адрес сервера.

## Понижение привилегий

Образ не умеет работать от не-root через `user: "1000:1000"`: на старте он пишет
во внутренний каталог `/pythainlp-data`, владелец которого в образе root, от uid
1000 туда нет доступа (`PermissionError: '/pythainlp-data'`). Поэтому контейнер
запускается от root.

При этом применяется «точечное» деление привилегий: `cap_drop: ALL` с возвратом
единственной нужной capability — `CAP_DAC_OVERRIDE`. Она требуется, потому что
хостовый каталог данных `$APPS_STORAGE_PATH/lute/data` принадлежит uid 1000, а
контейнер-root без `CAP_DAC_OVERRIDE` не может в него писать
(`sqlite3.OperationalError: attempt to write a readonly database`). Остальные
capability сброшены, понижая поверхность атаки по сравнению с исходным запуском от
root со всеми capability по умолчанию.

Также задействован `security_opt: label:disable` (SELinux-метка) и добавлен
healthcheck по `http://127.0.0.1:5001/`.

## Хранилище в k8s

Первый сервис, переведённый с `hostPath` на PVC, — как пилот перед возможной
миграцией остальных. Данные при этом не переезжают: `apps/lute/k8s/pv-pvc.yaml`
описывает **статические** `local`-тома, которые указывают на те же каталоги
(`/storage/apps/lute/data/data` и `/storage/apps/lute/data/backups`), а
`storageClassName: local-storage-retain` (`k8s/local-storage/`) только связывает их
с PVC. На диске не меняется ничего, кроме способа объявления.

```sh
kubectl apply -f k8s/local-storage/
kubectl apply -f apps/lute/k8s/pv-pvc.yaml
kubectl apply -f apps/lute/k8s/deployment.yaml
```

Два тома вместо одного:

- `lute-data` → `/lute_data` — сама база `lute.db`, картинки, плагины;
- `lute-backup` → `/lute_backup` — каталог бэкапов Lute (`Settings → backup_dir`).
  Отдельный том, чтобы копии переживали порчу каталога данных и чтобы их можно
  было позже увести на другой носитель.

Про бэкапы Lute: приложение умеет их само — `lute/backup/service.py` копирует
SQLite-базу в `lute_backup_<timestamp>.db.gz` (плюс зеркалит `userimages`) и
делает это автоматически, если включены `backup_enabled` и `backup_auto`, не чаще
раза в сутки (`should_run_auto_backup`). Ротацию задаёт `backup_count`, ручные
бэкапы (`manual_`-префикс) не удаляются. Это не отменяет внешний бэкап: копии
лежат на том же диске, что и данные.

Именование: `<сервис>-<назначение>-pv` / PVC `<сервис>-<назначение>`.
