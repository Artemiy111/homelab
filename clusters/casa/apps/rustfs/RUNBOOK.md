# RustFS: эксплуатация

## Использование

Пример с AWS CLI (path-style обязателен, регион произвольный):

```sh
aws --endpoint-url https://s3.${DOMAIN} \
    --no-verify-ssl s3 ls
```

Для самоподписанных сценариев вне браузера CA letsencrypt публичный, поэтому
достаточно стандартного доверия; флаг `--no-verify-ssl` нужен только при
обращении по IP.

## Смена root-креденшелов

Смена root-креденшелов: обновить значение в Vault по пути `kv/rustfs/credentials`,
дождаться синка VSO и пересоздать под.
Учтите: креды применяются только при инициализации пустого `/data`; для смены
на существующих данных создать нового пользователя через консоль/API, а не
переопределять env.

## Зеркало артефактов

Форсировать прогон:

```sh
kubectl -n rustfs create job --from=cronjob/mirror-sync mirror-sync-manual
```

Проверка анонимного доступа:

```sh
kubectl -n rustfs exec deploy/rustfs -- \
  curl -fsS -o /dev/null -w '%{http_code}\n' \
  http://rustfs/mirror/kubeconform/0.8.0/kubeconform_0.8.0_linux_amd64.tar.gz
```
