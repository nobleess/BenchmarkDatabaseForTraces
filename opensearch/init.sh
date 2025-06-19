#!/bin/sh

policy_exists() {
  local status=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://opensearch:9200/_plugins/_ism/policies/jaeger-ism-policy")
  [ "$status" -eq 200 ]
}

extract_version() {
  local response="$1"
  local field="$2"
  echo "$response" | grep -o "\"_$field\":[0-9]*" | cut -d':' -f2
}

update_policy() {
  echo "Попытка обновления ISM-политики..."
  local response=$(curl -s -XGET "http://opensearch:9200/_plugins/_ism/policies/jaeger-ism-policy")
  
  local seq_no=$(extract_version "$response" "seq_no")
  local primary_term=$(extract_version "$response" "primary_term")

  if [ -z "$seq_no" ] || [ -z "$primary_term" ]; then
    echo "Ошибка: не удалось извлечь версии политики"
    return 1
  fi

  echo "Обновление политики с seq_no=$seq_no, primary_term=$primary_term"
  curl -v -XPUT \
    "http://opensearch:9200/_plugins/_ism/policies/jaeger-ism-policy?if_seq_no=$seq_no&if_primary_term=$primary_term" \
    -H "Content-Type: application/json" \
    --data-binary "@/init/opensearch/jaeger-ism-policy.json"
}

apply_policy_to_indices() {
  echo "Применение политики ко всем индексам jaeger-*..."
  curl -X POST "http://opensearch:9200/_plugins/_ism/change_policy/jaeger-*" \
    -H "Content-Type: application/json" \
    -d '{
      "policy_id": "jaeger-ism-policy",
      "state": "hot"
    }'
}

echo "=== Начало инициализации OpenSearch ==="

if policy_exists; then
  echo "ISM-политика уже существует, выполняем обновление..."
  update_policy || {
    echo "Не удалось обновить политику, попытка создания заново..."
    curl -v -XPUT "http://opensearch:9200/_plugins/_ism/policies/jaeger-ism-policy" \
      -H "Content-Type: application/json" \
      --data-binary "@/init/opensearch/jaeger-ism-policy.json"
  }
else
  echo "Создание новой ISM-политики..."
  curl -v -XPUT "http://opensearch:9200/_plugins/_ism/policies/jaeger-ism-policy" \
    -H "Content-Type: application/json" \
    --data-binary "@/init/opensearch/jaeger-ism-policy.json"
fi
sleep 5

apply_policy_to_indices

echo "Установка шаблона для сервисов Jaeger..."
curl -v -XPUT "http://opensearch:9200/_index_template/jaeger-service-template" \
  -H "Content-Type: application/json" \
  --data-binary "@/init/opensearch/jaeger-service-template.json"

echo "Установка шаблона для спанов Jaeger..."
curl -v -XPUT "http://opensearch:9200/_index_template/jaeger-span-template" \
  -H "Content-Type: application/json" \
  --data-binary "@/init/opensearch/jaeger-span-template.json"

echo "Проверка существующих индексов Jaeger..."
count=$(curl -s "http://opensearch:9200/jaeger-*/_count" | grep -o '"count":[0-9]*' | cut -d':' -f2)

if [ "$count" -gt 0 ]; then
  echo "Индексы jaeger-* уже существуют! Все действия выполнены."
  exit 0
fi

echo "Создание начального индекса для спанов..."
curl -v -XPUT "http://opensearch:9200/jaeger-span-000001" \
  -H "Content-Type: application/json" \
  --data-binary "@/init/opensearch/jaeger-span-start-index.json"

echo "Создание начального индекса для сервисов..."
curl -v -XPUT "http://opensearch:9200/jaeger-service-000001" \
  -H "Content-Type: application/json" \
  --data-binary "@/init/opensearch/jaeger-service-start-index.json"

echo "=== Инициализация OpenSearch завершена ==="