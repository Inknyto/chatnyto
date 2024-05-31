import React, { useState, useEffect } from 'react';
import mqtt from 'mqtt';

const MQTTClient = () => {
  const [client, setClient] = useState(null);
  const [brokerIP, setBrokerIP] = useState('localhost');
  const [brokerPort, setBrokerPort] = useState('1883');
  const [message, setMessage] = useState('');
  const [messages, setMessages] = useState([]);

  useEffect(() => {
    const newClient = mqtt.connect(`ws://${brokerIP}:${brokerPort}`);

    newClient.on('connect', () => {
      newClient.subscribe('chat');
      console.log('Connected to MQTT broker');
    });

    newClient.on('message', (topic, payload) => {
      if (topic === 'chat') {
        setMessages((prevMessages) => [...prevMessages, payload.toString()]);
      }
    });

    setClient(newClient);

    return () => {
      newClient.end();
    };
  }, [brokerIP, brokerPort]);

  const handleBrokerIPChange = (event) => {
    setBrokerIP(event.target.value);
  };

  const handleBrokerPortChange = (event) => {
    setBrokerPort(event.target.value);
  };

  const handleMessageChange = (event) => {
    setMessage(event.target.value);
  };

  const handlePublish = () => {
    if (client && message) {
      client.publish('chat', message);
      setMessage('');
    }
  };

  return (
    <div>
      <div>
        <label>Broker IP:</label>
        <input type="text" value={brokerIP} onChange={handleBrokerIPChange} />
      </div>
      <div>
        <label>Broker Port:</label>
        <input type="text" value={brokerPort} onChange={handleBrokerPortChange} />
      </div>
      <div>
        <label>Message:</label>
        <input type="text" value={message} onChange={handleMessageChange} />
        <button onClick={handlePublish}>Publish</button>
      </div>
      <div>
        <h3>Messages:</h3>
        <ul>
          {messages.map((msg, index) => (
            <li key={index}>{msg}</li>
          ))}
        </ul>
      </div>
    </div>
  );
};

export default MQTTClient;
