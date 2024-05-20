
// Subscriber
const subscriber = redis.createClient();
subscriber.subscribe(channel);
console.log('Waiting for messages...');
subscriber.on('message', (channel, message) => {
  console.log(`Received: ${message}`);
});
