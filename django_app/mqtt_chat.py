# mqtt_chat/settings.py
# ...

INSTALLED_APPS = [
    # ...
    'mqtt_chat.apps.MqttChatConfig',
]

# mqtt_chat/apps.py
from django.apps import AppConfig
from .mqtt_client import MQTTClient

class MqttChatConfig(AppConfig):
    name = 'mqtt_chat'

    def ready(self):
        MQTTClient.start()

# mqtt_chat/mqtt_client.py
import paho.mqtt.client as mqtt

class MQTTClient:
    def __init__(self):
        self.client = mqtt.Client()
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message
        self.client.connect("broker.example.com", 1883, 60)

    def start(self):
        self.client.loop_start()

    def on_connect(self, client, userdata, flags, rc):
        print("Connected with result code " + str(rc))
        client.subscribe("chat")

    def on_message(self, client, userdata, msg):
        payload = msg.payload.decode("utf-8")
        print(f"Received message: {payload}")

    def send_message(self, message):
        self.client.publish("chat", message)

# mqtt_chat/views.py
from django.shortcuts import render
from .mqtt_client import MQTTClient

client = MQTTClient()

def chat_view(request):
    if request.method == 'POST':
        message = request.POST.get('message')
        client.send_message(message)

    return render(request, 'chat.html')
