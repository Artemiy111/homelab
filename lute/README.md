# Lute

Lute — веб-приложение для чтения и изучения иностранных языков (Language
Utilties for Tracking Exposure). Контейнер публикует порт `40070` на хост, а не
только через Traefik. Постоянные данные находятся в `/storage/apps/lute/data`.

## Почему нельзя просто снять привилегии

Прямое понижение прав для этого образа ломает запуск:

- `user: "1000:1000"` — приложение на старте пишет во внутренний каталог
  `/pythainlp-data`, владелец которого в образе root. От uid 1000 туда доступа
  нет, получаем `PermissionError: '/pythainlp-data'` и выход.
- `cap_drop: ALL` при работе от root — хостовый каталог данных
  `/storage/apps/lute/data` принадлежит uid 1000, а контейнер-root без
  `CAP_DAC_OVERRIDE` не может в него писать, откуда `sqlite3.OperationalError:
  attempt to write a readonly database`.

Поэтому оставлена исходная конфигурация: только `security_opt: label:disable`
(SELinux-метка), без `user` и без `cap_drop`.
