#!/usr/bin/env bash
# Sends sample order messages to the SQS queue in LocalStack
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"

ENDPOINT="${SQS_ENDPOINT:-http://localhost:4566}"
QUEUE_URL="${SQS_QUEUE_URL:-$ENDPOINT/000000000000/orders}"
REGION="${AWS_REGION:-us-east-1}"

messages=(
  '{"orderNumber":"ORD-1001","status":"pending"}'
  '{"orderNumber":"ORD-1002","status":"confirmed"}'
  '{"orderNumber":"ORD-1003","status":"shipped"}'
  '{"orderNumber":"ORD-1004","status":"delivered"}'
  '{"orderNumber":"ORD-1005","status":"pending"}'
)

for msg in "${messages[@]}"; do
  aws --endpoint-url="$ENDPOINT" sqs send-message \
    --queue-url "$QUEUE_URL" \
    --message-body "$msg" \
    --region "$REGION" \
    --output text --query 'MessageId'
  echo "  → sent: $msg"
done
