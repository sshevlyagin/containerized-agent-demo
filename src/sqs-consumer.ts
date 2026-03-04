import {
  SQSClient,
  ReceiveMessageCommand,
  DeleteMessageCommand,
} from "@aws-sdk/client-sqs";
import { config } from "./config.js";
import { prisma } from "./db.js";

const sqs = new SQSClient({
  region: config.awsRegion,
  endpoint: config.sqsEndpoint,
});

export async function startConsumer(): Promise<void> {
  console.log("SQS consumer started");

  while (true) {
    try {
      const response = await sqs.send(
        new ReceiveMessageCommand({
          QueueUrl: config.sqsQueueUrl,
          WaitTimeSeconds: 20,
          MaxNumberOfMessages: 10,
        })
      );

      if (!response.Messages) continue;

      for (const message of response.Messages) {
        try {
          const { orderNumber, status } = JSON.parse(message.Body!);
          console.log(`Processing order ${orderNumber} → ${status}`);

          await prisma.order.upsert({
            where: { orderNumber },
            update: { status },
            create: { orderNumber, status },
          });

          await sqs.send(
            new DeleteMessageCommand({
              QueueUrl: config.sqsQueueUrl,
              ReceiptHandle: message.ReceiptHandle!,
            })
          );
        } catch (err) {
          console.error("Failed to process message:", err);
        }
      }
    } catch (err) {
      console.error("SQS poll error, retrying in 5s:", err);
      await new Promise((resolve) => setTimeout(resolve, 5000));
    }
  }
}
