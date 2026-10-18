# Zot: эксплуатация

## Проверка

Проверка, что API жив (конфиг anonymous-only, поэтому `/v2/` отдаёт 403 — это
нормально, а pull при этом работает):

```sh
kubectl -n zot logs deploy/zot --tail=20
```

## Добавление upstream-реестра

Дописать запись в `extensions.sync.registries` (`config/config.json`) и применить:

```json
{
  "urls": ["https://quay.io"],
  "onDemand": true,
  "tlsVerify": true,
  "preserveDigest": true,
  "content": [{ "prefix": "**", "destination": "/quay.io" }]
}
```

Для приватных upstream'ов нужен `credentialsFile` из Secret'а, а не из ConfigMap.
