#!/usr/bin/env bash
set -euo pipefail

ORDER_SERVICE_URL="${ORDER_SERVICE_URL:-http://order-service:3000}"
SQS_ENDPOINT="${SQS_ENDPOINT:-http://localstack:4566}"
QUEUE_NAME="orders"
QUEUE_URL="${SQS_ENDPOINT}/000000000000/${QUEUE_NAME}"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

# Wait for order-service health
echo "Waiting for order-service..."
for i in $(seq 1 60); do
  if curl -sf "${ORDER_SERVICE_URL}/health" > /dev/null 2>&1; then
    echo "order-service is healthy"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "FATAL: order-service did not become healthy in 60s"
    exit 1
  fi
  sleep 1
done

# Create the SQS queue
echo "Creating SQS queue '${QUEUE_NAME}'..."
aws --endpoint-url="${SQS_ENDPOINT}" sqs create-queue --queue-name "${QUEUE_NAME}" --region us-east-1

# Send messages
echo "Sending messages..."
aws --endpoint-url="${SQS_ENDPOINT}" sqs send-message --queue-url "${QUEUE_URL}" --region us-east-1 \
  --message-body '{"orderNumber":"ORD-001","status":"New"}'

aws --endpoint-url="${SQS_ENDPOINT}" sqs send-message --queue-url "${QUEUE_URL}" --region us-east-1 \
  --message-body '{"orderNumber":"ORD-001","status":"Processing"}'

aws --endpoint-url="${SQS_ENDPOINT}" sqs send-message --queue-url "${QUEUE_URL}" --region us-east-1 \
  --message-body '{"orderNumber":"ORD-002","status":"New"}'

# Wait for processing
echo "Waiting for messages to be processed..."
sleep 10

# Verify ORD-001 is Processing
STATUS=$(curl -sf "${ORDER_SERVICE_URL}/orders/ORD-001" | jq -r '.status')
assert_eq "ORD-001 status is Processing" "Processing" "$STATUS"

# Verify ORD-002 is New
STATUS=$(curl -sf "${ORDER_SERVICE_URL}/orders/ORD-002" | jq -r '.status')
assert_eq "ORD-002 status is New" "New" "$STATUS"

# Verify 404 for unknown order
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${ORDER_SERVICE_URL}/orders/ORD-999")
assert_eq "ORD-999 returns 404" "404" "$HTTP_CODE"

# Send update for ORD-002
aws --endpoint-url="${SQS_ENDPOINT}" sqs send-message --queue-url "${QUEUE_URL}" --region us-east-1 \
  --message-body '{"orderNumber":"ORD-002","status":"Shipped"}'

echo "Waiting for update to be processed..."
sleep 10

# Verify ORD-002 is now Shipped
STATUS=$(curl -sf "${ORDER_SERVICE_URL}/orders/ORD-002" | jq -r '.status')
assert_eq "ORD-002 status updated to Shipped" "Shipped" "$STATUS"

echo ""
echo "================================"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "================================"

if [ "$FAIL" -gt 0 ]; then
  echo "SOME TESTS FAILED"
  exit 1
fi

echo "ALL TESTS PASSED"
