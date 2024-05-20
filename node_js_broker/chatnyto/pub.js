// Publisher
const redis = require('redis');
const publisher = redis.createClient();
const channel = 'message_queue';
const message = 'Hello, Redis!';

publisher.publish(channel, message);
console.log(`Sent: ${message}`);
publisher.quit();
