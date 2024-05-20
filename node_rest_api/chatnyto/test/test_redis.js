// Publisher
const redis = require('redis');
const publisher = redis.createClient();
const channel = 'message_queue';
const message = 'Hello, Redis!';
publisher.publish(channel, message);
console.log(`Sent: ${message}`);
publisher.quit();

// Subscriber
const subscriber = redis.createClient();
subscriber.subscribe(channel);
console.log('Waiting for messages...');
subscriber.on('message', (channel, message) => {
  console.log(`Received: ${message}`);
});
