# LocalAI

URL: `https://localai.example.com`

Используется закреплённый CPU-образ `linux/amd64`. На сервере AMD Ryzen 7 6800H
с восемью физическими ядрами и AVX2. LocalAI сам выбирает число потоков, а
Docker ограничивает весь контейнер 14 единицами CPU, так что два из 16
логических ядер сервера остаются вне его квоты. GPU-устройства намеренно не
пробрасываются.

## Первый запуск


```sh
bash ./init.sh
install -d -m 0750 -o 1000 -g 1000 \
  ${APPS_STORAGE_PATH:-/storage/apps}/local-ai/backends \
  ${APPS_STORAGE_PATH:-/storage/apps}/local-ai/configuration \
  ${APPS_STORAGE_PATH:-/storage/apps}/local-ai/data
docker compose up -d
docker compose ps
```

Существующие модели в `$APPS_STORAGE_PATH/local-ai/models` сохраняются.

Корневая файловая система контейнера read-only. Запись возможна только в
`/models`, `/backends`, `/configuration`, `/data` и memory-backed `/tmp`.
Контейнер работает от непривилегированного пользователя, сбрасывает все Linux
capabilities, не может получать новые привилегии, использовать swap и ограничен
по памяти, CPU, PIDs и логам.

## Проверка

```sh
docker compose ps
docker compose exec api curl --fail http://127.0.0.1:8080/readyz
curl --resolve localai.example.com:443:192.0.2.10 \
  https://localai.example.com/readyz
curl --resolve localai.example.com:443:192.0.2.10 \
  -H "Authorization: Bearer $LOCALAI_API_KEY" \
  https://localai.example.com/v1/models
```

Первый переход в состояние ready может занять время, пока LocalAI сканирует
модели или устанавливает backend. Неудачные пробы игнорируются первые десять
минут, чтобы обычный старт не помечался как unhealthy; успешная проба сразу
делает контейнер healthy.
