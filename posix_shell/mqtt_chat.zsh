# mqtt_chat.zsh

# Connect to the MQTT broker
mosquitto_sub -h broker.example.com -t chat &
sub_pid=$!

# Publish messages to the chat topic
publish_message() {
    message="$1"
    mosquitto_pub -h broker.example.com -t chat -m "$message"
}

# Prompt for user input and publish messages
while true; do
    read -r "message?Enter your message: "
    if [ -n "$message" ]; then
        publish_message "$message"
    fi
done

# Clean up the mosquitto_sub process
kill $sub_pid
