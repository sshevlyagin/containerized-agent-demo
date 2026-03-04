import "dotenv/config";

export const config = {
  databaseUrl: process.env.DATABASE_URL!,
  sqsEndpoint: process.env.SQS_ENDPOINT!,
  sqsQueueUrl: process.env.SQS_QUEUE_URL!,
  awsRegion: process.env.AWS_REGION ?? "us-east-1",
  port: parseInt(process.env.PORT ?? "3000", 10),
};
