# Open WebUI

URL: `https://ai.example.com`

Чат-интерфейс для LLM. Пока запущен **без движка инференса**: ни Ollama, ни
OpenAI-совместимый API не подключены (`ENABLE_OLLAMA_API=false`,
`ENABLE_OPENAI_API=false`), поэтому чат не отвечает на сообщения, пока бэкенд
не добавлен. Первый зарегистрированный пользователь становится администратором.

## Первый запуск

Разворачивается манифестами в apps/open-webui/k8s/.

## Подключение движка (позже)

- LocalAI: `ENABLE_OPENAI_API=true`, `OPENAI_API_BASE_URL=http://local-ai-api:8080/v1`
  и `OPENAI_API_KEY` со значением из `local-ai/secrets.enc.env`;
- свой Ollama: добавить сервис в манифесты с
  `OLLAMA_MODELS=/storage/media/ai/models`, тогда веса будут в общей папке.

Значения задаются в манифестах в `apps/open-webui/k8s/`.

## Безопасность

Корневая файловая система контейнера read-only: запись возможна только в
`/app/backend/data` (том), кэш Hugging Face внутри него и memory-backed `/tmp`.
Контейнер работает от непривилегированного пользователя (1000:1000), сбрасывает
все Linux capabilities, не может получать новые привилегии и ограничен по
памяти (4g), CPU (4.0) и PIDs (512).

## Проверка

```sh
curl --resolve ai.example.com:443:<node1-ip> \
  https://ai.example.com/health
```

Ожидаемый ответ: `{"status":true}`.
