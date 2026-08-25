# Open WebUI

URL: `https://ai.example.com`

Чат-интерфейс для LLM. Пока запущен **без движка инференса**: ни Ollama, ни
OpenAI-совместимый API не подключены (`ENABLE_OLLAMA_API=false`,
`ENABLE_OPENAI_API=false`), поэтому чат не отвечает на сообщения, пока бэкенд
не добавлен. Первый зарегистрированный пользователь становится администратором.

## Первый запуск

```sh
bash scripts/bootstrap-platform.sh open-webui
```
> Любые последующие команды `docker compose` этого сервиса требуют того же окружения:
> выполняйте их через `bash scripts/compose-secrets.sh open-webui …` или повторным
> `bash scripts/bootstrap-platform.sh open-webui`.


## Подключение движка (позже)

- LocalAI: `ENABLE_OPENAI_API=true`, `OPENAI_API_BASE_URL=http://local-ai-api:8080/v1`
  и `OPENAI_API_KEY` со значением из `local-ai/secrets.enc.env`;
- свой Ollama: добавить сервис в этот же compose-файл с
  `OLLAMA_MODELS=/storage/media/ai/models`, тогда веса будут в общей папке.

Значения меняются в `compose.yaml`; после правки — commit → push →
`git pull --ff-only` на сервере и повторный запуск через
`scripts/compose-secrets.sh`.

## Безопасность

Корневая файловая система контейнера read-only: запись возможна только в
`/app/backend/data` (том), кэш Hugging Face внутри него и memory-backed `/tmp`.
Контейнер работает от непривилегированного пользователя (1000:1000), сбрасывает
все Linux capabilities, не может получать новые привилегии и ограничен по
памяти (4g), CPU (4.0) и PIDs (512).

## Проверка

```sh
docker compose ps
curl --resolve ai.example.com:443:192.0.2.10 \
  https://ai.example.com/health
```

Ожидаемый ответ: `{"status":true}`.
