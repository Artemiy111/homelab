# Настройки входа по OAuth2 через Zitadel для Seahub.
#
# Файл примонтирован в контейнер seafile (см. compose.yaml) и подключается
# из seahub_settings.py строкой exec(open(...)). Значения берутся из
# окружения контейнера — их источник — secrets.enc.env сервиса.
#
# Seafile CE не поддерживает OIDC напрямую, поэтому используется generic
# OAuth2: Zitadel отдаёт профиль через эндпоинт userinfo. Формат настроек —
# отдельные OAUTH_* переменные, как в официальной доке Seafile 13.
#
# Seahub читает настройки один раз при старте воркера: после изменения этого
# файла или переменных ZITADEL_OAUTH_* выполните
# `docker compose restart seafile`.

import os

ENABLE_OAUTH = True
# JIT-провижининг: неизвестный пользователь из Zitadel создаётся в Seafile
# автоматически при первом SSO-входе. Аккаунт создаётся с реальным email (см.
# патч create_user в init-postinstall.sh), поэтому последующие входы линкуются.
# OAUTH_CREATE_UNKNOWN_USER здесь ВКЛЮЧАЕТ наш патч oauth view: штатно Seafile CE
# эту настройку игнорирует и выдаёт "new user registration is not allowed".
OAUTH_CREATE_UNKNOWN_USER = True
# Первый успешно зашедший через Zitadel пользователь становится админом Seafile,
# если в системе ещё нет ни одного staff-пользователя. Bootstrap-admin
# (admin@${DOMAIN}) удаляется в init-postinstall.sh, чтобы именно цитадель-юзер
# стал админом.
OAUTH_PROMOTE_FIRST_USER_TO_ADMIN = True
OAUTH_ACTIVATE_USER_AFTER_CREATION = False

# id.example.com — внешний домен Zitadel (ZITADEL_EXTERNALDOMAIN).
OAUTH_PROVIDER_DOMAIN = "zitadel"
OAUTH_CLIENT_ID = os.environ["ZITADEL_OAUTH_CLIENT_ID"]
OAUTH_CLIENT_SECRET = os.environ["ZITADEL_OAUTH_CLIENT_SECRET"]
OAUTH_REDIRECT_URL = "https://seafile.%s/oauth/callback/" % os.environ["DOMAIN"]

OAUTH_AUTHORIZATION_URL = "https://id.%s/oauth/v2/authorize" % os.environ["DOMAIN"]
OAUTH_TOKEN_URL = "https://id.%s/oauth/v2/token" % os.environ["DOMAIN"]
OAUTH_USER_INFO_URL = "https://id.%s/oidc/v1/userinfo" % os.environ["DOMAIN"]

OAUTH_SCOPE = ["openid", "profile", "email"]

# Линковка к существующему аккаунту работает в seahub/oauth/views.py через
# oauth_user_info['email'] (ищет User.objects.get_old_user по email-клейму).
# Поэтому email-клейм ОБЯЗАН маппиться в литерал "email", а не в contact_email —
# иначе ветка линковки не срабатывает и создаётся второй аккаунт.
# Внешний уникальный id (sub у Zitadel) идёт в "uid" — это ключ соц-привязки.
OAUTH_ATTRIBUTE_MAP = {
    "sub": (True, "uid"),
    "name": (False, "name"),
    "email": (False, "email"),
}
