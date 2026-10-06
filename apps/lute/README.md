# Lute

Lute — веб-приложение для чтения и изучения иностранных языков (Language
Utilities for Tracking Exposure).

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