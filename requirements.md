Order Service
Simple express app that has the following functionality - list to an SQS queue that contains a message with an order number and status (New, Processing, Shipped) writes that status to a DB and has a rest endpoint to get status by order number.

Stack
- Node 22
- Typescript 5
- Express 5
- Postgres 18
- Prisma for migrations 
- pnpm


Use nvm to manage environments and docker compose to test everything.

Running in Docker Compose
- postgres in docker
- local stack sqs mock
- order service 
- test executor
