# LocalAI: запуск и проверка

Юнит выключен: `Application` создан, но синка нет (см. «Состояние» в
`README.md`). Перед первым запуском его надо включить и синкнуть.

## Первый запуск

Существующие модели в персистентном каталоге данных сервиса (`models`)
сохраняются.

Первый переход в состояние ready занимает время: LocalAI сканирует модели и при
необходимости устанавливает backend. Неудачные пробы игнорируются первые десять
минут, чтобы обычный старт не помечался как unhealthy; первая успешная проба
сразу делает контейнер healthy — ждать её не нужно, но и считать десятиминутную
задержку сбоем тоже.

## Проверка

```sh
curl --resolve localai.example.com:443:<node1-ip> \
  https://localai.example.com/readyz
curl --resolve localai.example.com:443:<node1-ip> \
  -H "Authorization: Bearer $LOCALAI_API_KEY" \
  https://localai.example.com/v1/models
```
