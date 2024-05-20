const client = mqtt.connect('mqtt://localhost:1883');

// Publish data every 5 seconds
setInterval(() => {
  const deviceId = 'device1';
  const data = { value: Math.random() };
  const topic = `devices/${deviceId}/data`;

  client.publish(topic, JSON.stringify(data));
  console.log(`Published data to ${topic}: ${JSON.stringify(data)}`);
}, 5000);
