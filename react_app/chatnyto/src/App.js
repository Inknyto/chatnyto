import React, { useState, useEffect } from 'react';
import mqtt from 'mqtt';

const MQTTChatApp = () => {
  const [message, setMessage] = useState('');
  const [messages, setMessages] = useState([]);
  const [client, setClient] = useState(null);

  useEffect(() => {
    const mqttClient = mqtt.connect('mqtt://localhost');
    setClient(mqttClient);

    mqttClient.on('connect', () => {
      mqttClient.subscribe('chat');
    });

    mqttClient.on('message', (topic, payload) => {
      setMessages((prevMessages) => [...prevMessages, payload.toString()]);
    });

    return () => {
      mqttClient.end();
    };
  }, []);

  const sendMessage = () => {
    if (message.trim() && client) {
      client.publish('chat', message);
      setMessage('');
    }
  };

  return (
    <div>
      <h1>MQTT Chat App</h1>
      <div>
        {messages.map((msg, index) => (
          <p key={index}>{msg}</p>
        ))}
      </div>
      <input
        type="text"
        value={message}
        onChange={(e) => setMessage(e.target.value)}
      />
      <button onClick={sendMessage}>Send</button>
    </div>
  );
};

export default MQTTChatApp;
