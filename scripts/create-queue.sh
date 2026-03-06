#!/usr/bin/env bash
# Creates the SQS queue in LocalStack (idempotent)
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"

aws --endpoint-url="${SQS_ENDPOINT:-http://localhost:4566}" \
    sqs create-queue \
    --queue-name orders \
    --region "${AWS_REGION:-us-east-1}"

echo "SQS queue 'orders' ready"
