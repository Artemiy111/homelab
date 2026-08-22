#!/usr/bin/env bash

docker run --rm \
  --cap-drop ALL \
  --cap-add CHOWN \
  --security-opt no-new-privileges:true \
  -v ${APPS_STORAGE_PATH:-/storage/apps}/home-assistant:/config:Z \
  alpine:3.23 \
  sh -ec 'chown 0:0 /config; chmod 0700 /config;
    test -e /config/automations.yaml || printf "[]\n" > /config/automations.yaml;
    test -e /config/scripts.yaml || printf "{}\n" > /config/scripts.yaml;
    test -e /config/scenes.yaml || printf "[]\n" > /config/scenes.yaml'