#!/bin/sh
# ATS читает конфиги из /opt/etc/trafficserver (TS_ROOT=/opt). Опция --conf_dir
# действует только для команд -C (verify_config и т. п.), а не для обычного
# запуска, поэтому каталог с конфигами так не подменить.
#
# Из-за этого конфиги не монтируются в /opt/etc/trafficserver по subPath
# (read-only поверх файлов образа), а копируются туда на старте. Так подстановка
# секрета PURGE в remap.config реально попадает в загружаемый файл, а дефолты
# образа (sni.yaml, strategies.yaml, ssl_multicert.config, body_factory/ и пр.)
# остаются на месте — мы перекрываем только свои шесть файлов.
set -eu

SRC=/run/ats-src
DEST=/opt/etc/trafficserver
# proxy.config.admin.user_id в образе — nobody: traffic_server пишет state-файлы
# PURGE уже после сброса привилегий, поэтому владельцем делаем его.
ATS_UID=65534

for f in records.yaml cache.config storage.config plugin.config ip_allow.yaml; do
  cp "$SRC/$f" "$DEST/$f"
done

# Секрет — hex (openssl rand -hex), в нём нет символов, значимых для sed,
# поэтому подстановка безопасна.
sed "s|\$(ATS_PURGE_TOKEN)|${ATS_PURGE_TOKEN}|g" "$SRC/remap.config" > "$DEST/remap.config"

# Плагин на старте пишет ERROR, если state-файла нет (generation id
# отсутствует). Это штатно для ещё не «пургнутых» origin'ов, но засоряет лог.
# Предсоздаём пустые файлы от имени пользователя ATS — пустой файл читается как
# gen_id 0 без ошибки, а первый PURGE запишет туда новое поколение.
grep -o -- '--state-file=[^ ]*' "$DEST/remap.config" | cut -d= -f2 | while read -r sf; do
  if [ ! -e "$sf" ]; then
    : > "$sf"
    chown "$ATS_UID" "$sf"
  fi
done

exec traffic_server
