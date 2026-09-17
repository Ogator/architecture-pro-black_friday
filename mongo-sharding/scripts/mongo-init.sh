#!/bin/bash
set -e

###
# Инициализация шардированного кластера MongoDB и наполнение БД данными
###

cd "$(dirname "$0")/.."

echo "==> 1. Инициализируем replica set config-сервера (config_server)"
docker compose exec -T configSrv mongosh --port 27017 --quiet <<'EOF'
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27017" }]
});
EOF

echo "==> 2. Инициализируем replica set шарда 1 (shard1)"
docker compose exec -T shard1-1 mongosh --port 27017 --quiet <<'EOF'
rs.initiate({
  _id: "shard1",
  members: [{ _id: 0, host: "shard1-1:27017" }]
});
EOF

echo "==> 3. Инициализируем replica set шарда 2 (shard2)"
docker compose exec -T shard2-1 mongosh --port 27017 --quiet <<'EOF'
rs.initiate({
  _id: "shard2",
  members: [{ _id: 0, host: "shard2-1:27017" }]
});
EOF

echo "==> Ждём, пока реплики выберут PRIMARY..."
sleep 15

echo "==> 4. Добавляем шарды в кластер через mongos_router"
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<'EOF'
sh.addShard("shard1/shard1-1:27017");
sh.addShard("shard2/shard2-1:27017");
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

echo "==> Готово. Кластер инициализирован."
