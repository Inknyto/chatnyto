import { useState, useEffect } from 'react';
import { Text, View } from 'react-native';
import * as mqtt from './mqtt'


const MQTT_BROKER = 'mqtt://localhost'; // Modifiez le protocole et supprimez le port

const App = () => {
  const [_message, set_Message] = useState('');

  useEffect(() => {
    // Connexion au broker MQTT avec nom d'utilisateur et mot de passe
    const client = mqtt.connect(MQTT_BROKER);

    client.on('connect', () => {
      console.log('Connected to MQTT broker');
      client.subscribe(topicTemperature);
      client.subscribe(topicHumidity);
    });

    client.on('message', (topic, message) => {
      // Réception des données MQTT
      const data = message.toString();
      if (topic === 'chat') {
        set_Message(data);
      }
    });

    // Nettoyage de la connexion MQTT lors du démontage du composant
    return () => {
      client.end();
    };
  }, []);

  return (
    <View>
      <Text>Message: {_message}%</Text>
    </View>
  );
};

export default App;
