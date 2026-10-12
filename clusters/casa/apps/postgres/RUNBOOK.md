# PostgreSQL playground: эксплуатация

## Доступ

pgweb доступен по адресу `https://postgres.example.com/` и сразу подключён к
базе `playground`. Логин и пароль HTTP Basic Auth находятся в секретах сервиса
(`PGWEB_AUTH_USER` и `PGWEB_AUTH_PASS`).

## Работа с PostgreSQL

После подключения к базе через `psql` доступны команды:

```text
\l         список баз данных
\dt        список таблиц
\q         выход
```
