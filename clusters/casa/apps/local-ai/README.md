# LocalAI

URL: `https://localai.example.com`

Используется закреплённый CPU-образ `linux/amd64`. На сервере AMD Ryzen 7 6800H
с восемью физическими ядрами и AVX2. LocalAI сам выбирает число потоков, а
контейнер ограничен 14 единицами CPU, так что два из 16
логических ядер сервера остаются вне его квоты. GPU-устройства намеренно не
пробрасываются.

## Состояние

Манифесты лежат в `clusters/casa/apps/local-ai/manifests/`, `Application` —
`clusters/casa/apps/local-ai/app.yaml`. Блок `syncPolicy.automated` там убран
намеренно: Argo создаёт `Application`, но сервис не разворачивает, поэтому
namespace `local-ai` и поды появятся только после ручного синка. Приложение
при этом постоянно `OutOfSync`, и это индикатор выключенного состояния — тот же
приём, что у `alloy-profiler` (`docs/runbooks/argocd.md`). Включение — вернуть
блок `automated` в `app.yaml` и синкнуть приложение.

## Первый запуск

Существующие модели в персистентном каталоге данных сервиса (`models`)
сохраняются.

Корневая файловая система контейнера read-only. Запись возможна только в
`/models`, `/backends`, `/configuration`, `/data` и memory-backed `/tmp`.
Контейнер работает от непривилегированного пользователя, сбрасывает все Linux
capabilities, не может получать новые привилегии, использовать swap и ограничен
по памяти, CPU, PIDs и логам.

## Проверка

```sh
curl --resolve localai.example.com:443:<node1-ip> \
  https://localai.example.com/readyz
curl --resolve localai.example.com:443:<node1-ip> \
  -H "Authorization: Bearer $LOCALAI_API_KEY" \
  https://localai.example.com/v1/models
```

Первый переход в состояние ready может занять время, пока LocalAI сканирует
модели или устанавливает backend. Неудачные пробы игнорируются первые десять
минут, чтобы обычный старт не помечался как unhealthy; успешная проба сразу
делает контейнер healthy.
