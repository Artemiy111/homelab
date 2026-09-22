#!/bin/sh
# ATS не раскрывает переменные окружения в конфигах, а purge-плагину нужен
# секрет, которому не место в git. Поэтому на старте подставляем секрет из
# Secret (env ATS_PURGE_TOKEN) в remap.config и собираем каталог конфигов в
# /run/ats, который передаём через --conf_dir. Каталог в tmpfs, PVC не трогаем.
set -eu

CONF=/run/ats
mkdir -p "$CONF"

for f in records.yaml remap.config cache.config storage.config plugin.config; do
  cp "/opt/etc/trafficserver/$f" "$CONF/$f"
done

sed -i "s|\$(ATS_PURGE_TOKEN)|${ATS_PURGE_TOKEN}|g" "$CONF/remap.config"

exec traffic_server --conf_dir "$CONF"
