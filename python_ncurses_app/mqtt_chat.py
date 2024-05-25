import paho.mqtt.client as mqtt
import curses

def on_connect(client, userdata, flags, rc):
    print("Connected with result code " + str(rc))
    client.subscribe("chat")

def on_message(client, userdata, msg):
    payload = msg.payload.decode("utf-8")
    stdscr.addstr(f"\n{payload}")
    stdscr.refresh()

client = mqtt.Client()
client.on_connect = on_connect
client.on_message = on_message

client.connect("broker.example.com", 1883, 60)

stdscr = curses.initscr()
curses.noecho()
curses.cbreak()

try:
    client.loop_start()

    while True:
        message = stdscr.getstr(curses.LINES - 1, 0).decode("utf-8")
        if message:
            client.publish("chat", message)
            stdscr.addstr(curses.LINES - 1, 0, " " * len(message))
            stdscr.refresh()

except KeyboardInterrupt:
    pass

finally:
    curses.echo()
    curses.nocbreak()
    curses.endwin()
    client.loop_stop()
    client.disconnect()
