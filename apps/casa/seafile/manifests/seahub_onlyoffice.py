# Настройки интеграции OnlyOffice для Seahub.
#
# Файл примонтирован в контейнер seafile (см. seafile.deployment.yaml) и подключается
# из seahub_settings.py строкой exec(open(...)). Значения берутся из
# окружения контейнера — их источник — Vault через VSO.
#
# Seahub читает настройки один раз при старте воркера: после изменения этого
# файла или переменных ONLYOFFICE_* перезапустите под:
# `kubectl -n seafile rollout restart deploy/seafile`.

import os

ENABLE_ONLYOFFICE = True
ONLYOFFICE_APIJS_URL = os.environ["ONLYOFFICE_APIJS_URL"]
ONLYOFFICE_JWT_HEADER = os.environ.get("ONLYOFFICE_JWT_HEADER", "Authorization")
ONLYOFFICE_JWT_SECRET = os.environ["ONLYOFFICE_JWT_SECRET"]
