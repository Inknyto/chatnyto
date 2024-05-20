const mqtt = require('mqtt');

// Create an MQTT client instance
const client = mqtt.connect('mqtt://localhost');

// Handle client connections
client.on('connect', () => {
  console.log('Connected to MQTT broker');

  // Subscribe to the chat topic
  client.subscribe('chat');
});

// Handle incoming messages
client.on('message', (topic, message) => {
  console.log(`Received message on topic ${topic}: ${message.toString()}`);

  // Broadcast the message to all connected clients
  // (You'll need to implement this logic)
});

// Handle errors
client.on('error', (error) => {
  console.error('Error:', error);
});
