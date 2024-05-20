const mosca = require('mosca');

// Define the MQTT broker settings
const settings = {
  port: 1883, // MQTT broker port
  backend: {
    // Persistence store for MQTT messages and subscriptions
    type: 'redis',
    redis: {
      host: 'localhost',
      port: 6379
    }
  }
};

// Create a new MQTT broker instance
const server = new mosca.Server(settings);

// Handle MQTT client connections
server.on('clientConnected', (client) => {
  console.log(`Client connected: ${client.id}`);
});

// Handle MQTT client disconnections
server.on('clientDisconnected', (client) => {
  console.log(`Client disconnected: ${client.id}`);
});

// Handle incoming MQTT messages
server.on('published', (packet, client) => {
  console.log(`Received message from ${client.id} on topic ${packet.topic}`);
  console.log(`Message: ${packet.payload.toString()}`);
});

// Handle MQTT subscriptions
server.on('subscribed', (topic, client) => {
  console.log(`Client ${client.id} subscribed to ${topic}`);
});

// Handle MQTT unsubscriptions
server.on('unsubscribed', (topic, client) => {
  console.log(`Client ${client.id} unsubscribed from ${topic}`);
});

// Start the MQTT broker
server.on('ready', () => {
  console.log(`MQTT broker is running on port ${settings.port}`);
});
