# pymongo-api

Целевая схема проекта — шардированный и реплицированный MongoDB-кластер с Redis-кешем
перед `pymongo_api`, собранная в [`sharding-repl-cache`](./sharding-repl-cache).

## Состав сервисов

| Сервис | Тип | Группа репликации | Назначение |
|---|---|---|---|
| `pymongo_api` | приложение (FastAPI) | — | HTTP API, порт `8080` |
| `redis` | redis | — | кеш ответов приложения, порт `6379` |
| `mongos_router` | mongos | — | точка входа в кластер, порт `27017` |
| `configSrv` | configsvr | `config_server` | метаданные кластера и карта чанков |
| `shard1-1` | shardsvr | `shard1` | шард 1, реплика 1 |
| `shard1-2` | shardsvr | `shard1` | шард 1, реплика 2 |
| `shard1-3` | shardsvr | `shard1` | шард 1, реплика 3 |
| `shard2-1` | shardsvr | `shard2` | шард 2, реплика 1 |
| `shard2-2` | shardsvr | `shard2` | шард 2, реплика 2 |
| `shard2-3` | shardsvr | `shard2` | шард 2, реплика 3 |

## Кеширование

Кеширование включается переменной окружения в сервисе `pymongo_api`:

```yaml
environment:
  REDIS_URL: "redis://redis:6379"
```

Если переменная не задана, приложение работает без кеша.
Проверить, что кеш включён, можно в ответе корневого эндпоинта: поле `"cache_enabled": true`.

Кешируется эндпоинт `/<collection_name>/users` с TTL 60 секунд. Ключи складываются
в Redis с префиксом `api:cache`.

## Как запустить

Все команды ниже выполняются из папки `sharding-repl-cache`:

```shell
cd sharding-repl-cache
docker compose up -d
```

Отдельной настройки Redis не требуется — он готов сразу после старта.
Ниже настраивается только кластер MongoDB.

## Настройка репликации и шардирования

Для настройки и наполнения кластера выполните скрипт ниже.

```shell
./scripts/mongo-init.sh
```

Более детальное описание шагов выполняемых скриптом можно найти в [README.md](./sharding-repl-cache/README.md) 

## Как проверить

### Если вы запускаете проект на предоставленной виртуальной машине

Узнать белый ip виртуальной машины

```shell
curl --silent http://ifconfig.me
```

Дальше вместо `localhost` в примерах ниже используйте `http://<ip виртуальной машины>`.

## Доступные эндпоинты

Список доступных эндпоинтов, swagger: http://localhost:8080/docs

### Информация о MongoDB

```shell
curl -s http://localhost:8080/ | jq
```

В ответе должно быть `"mongo_topology_type": "Sharded"`, `"documents_count": 1000`
и список шардов, где у каждого перечислены все три реплики:

```json
"shards": {
  "shard1": "shard1/shard1-1:27017,shard1-2:27017,shard1-3:27017",
  "shard2": "shard2/shard2-1:27017,shard2-2:27017,shard2-3:27017"
}
```
