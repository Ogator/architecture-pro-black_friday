#!/bin/bash
set -e

###
# Инициализация шардированного кластера MongoDB с репликацией и наполнение БД данными
###

cd "$(dirname "$0")/.."

# Дождаться, пока в группе репликации появится PRIMARY.
# Проверяем набор целиком, а не конкретный узел: выборы в наборе из трёх реплик
# могут выбрать любого члена, не обязательно того, на котором выполнялся rs.initiate.
wait_primary() {
  local svc="$1" i primary
  printf '    ожидаем PRIMARY в группе репликации через %s' "$svc"
  for i in $(seq 1 60); do
    primary=$(docker compose exec -T "$svc" mongosh --port 27017 --quiet --eval \
      'const m = rs.status().members.find((x) => x.stateStr === "PRIMARY"); print(m ? m.name : "")' \
      2>/dev/null | tr -d '\r')
    if [ -n "$primary" ]; then
      printf ' — PRIMARY: %s\n' "$primary"
      return 0
    fi
    printf '.'
    sleep 2
  done
  printf '\n'
  echo "ОШИБКА: PRIMARY в группе репликации ($svc) не выбран за 120 секунд" >&2
  return 1
}

echo "==> 1. Инициализируем replica set config-сервера (config_server)"
docker compose exec -T configSrv mongosh --port 27017 --quiet <<'EOF'
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv:27017" }
  ]
});
EOF
wait_primary configSrv

echo "==> 2. Инициализируем группу репликации шарда 1 (shard1, 3 реплики)"
docker compose exec -T shard1-1 mongosh --port 27017 --quiet <<'EOF'
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1-1:27017" },
    { _id: 1, host: "shard1-2:27017" },
    { _id: 2, host: "shard1-3:27017" }
  ]
});
EOF
wait_primary shard1-1

echo "==> 3. Инициализируем группу репликации шарда 2 (shard2, 3 реплики)"
docker compose exec -T shard2-1 mongosh --port 27017 --quiet <<'EOF'
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-1:27017" },
    { _id: 1, host: "shard2-2:27017" },
    { _id: 2, host: "shard2-3:27017" }
  ]
});
EOF
wait_primary shard2-1

echo "==> 4. Добавляем шарды в кластер через mongos_router"
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<'EOF'
sh.addShard("shard1/shard1-1:27017,shard1-2:27017,shard1-3:27017");
sh.addShard("shard2/shard2-1:27017,shard2-2:27017,shard2-3:27017");
EOF

echo "==> 5. Включаем шардирование для БД somedb и коллекции helloDoc"
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<'EOF'
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { name: "hashed" });
EOF

echo "==> 6. Наполняем коллекцию данными (1000 документов)"
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<'EOF'
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i });
print("Всего документов: " + db.helloDoc.countDocuments());
EOF

echo "==> 7. Проверяем распределение документов по шардам"
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<'EOF'
use somedb
db.helloDoc.getShardDistribution();
EOF

echo "==> Готово. Кластер с репликацией инициализирован."
