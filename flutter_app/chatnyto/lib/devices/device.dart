import 'dart:convert';

/// The families of device the app knows how to speak to.
///
/// Two quite different things live here, deliberately in one list. An MQTT
/// device is one the user owns and configures: it listens on a topic of
/// their broker and does what the payload says. A television is something
/// bought years ago that speaks its manufacturer's own protocol over the
/// local network and will never speak MQTT. Both are "a thing in the house
/// I want to press a button for", so both belong in one place, however
/// little they have in common underneath.
enum DeviceKind {
  /// Anything on the broker: a relay, a lamp, a sensor, an ESP32.
  mqtt,

  /// Roku, and the many boxes that licensed its protocol.
  roku,

  /// Samsung televisions from 2016 onwards (Tizen).
  samsungTv,

  /// LG televisions from 2012 onwards (webOS).
  lgTv,

  /// Android TV, Google TV, and Nvidia Shield.
  androidTv,
}

extension DeviceKindLabel on DeviceKind {
  String get label => switch (this) {
        DeviceKind.mqtt => 'MQTT device',
        DeviceKind.roku => 'Roku',
        DeviceKind.samsungTv => 'Samsung TV',
        DeviceKind.lgTv => 'LG TV',
        DeviceKind.androidTv => 'Android TV',
      };

  /// What the user has to know to add one.
  String get hint => switch (this) {
        DeviceKind.mqtt =>
          'Talks over your own broker, so it works on a network with no '
              'internet at all.',
        DeviceKind.roku =>
          'Roku, and the streaming sticks built on it. Nothing to set up on '
              'the television.',
        DeviceKind.samsungTv =>
          'Samsung smart TVs, 2016 and later. The television will ask you to '
              'allow this phone, once.',
        DeviceKind.lgTv =>
          'LG smart TVs running webOS. The television will ask you to allow '
              'this phone, once.',
        DeviceKind.androidTv =>
          'Android TV and Google TV boxes with network debugging turned on.',
      };

  bool get isTelevision => this != DeviceKind.mqtt;

  /// The port each protocol lives on when the user gives only an address.
  int get defaultPort => switch (this) {
        DeviceKind.mqtt => 0,
        DeviceKind.roku => 8060,
        DeviceKind.samsungTv => 8002,
        DeviceKind.lgTv => 3000,
        DeviceKind.androidTv => 5555,
      };
}

/// What an MQTT device's control looks like on screen.
enum ControlKind {
  /// On and off, published as two payloads of the user's choosing.
  toggle,

  /// A number in a range: brightness, a setpoint, a speed.
  slider,

  /// One payload, sent when pressed. A door, a reset, a scene.
  button,

  /// Nothing to press: a value arriving on a topic, shown as it changes.
  reading,
}

extension ControlKindLabel on ControlKind {
  String get label => switch (this) {
        ControlKind.toggle => 'Switch',
        ControlKind.slider => 'Dial',
        ControlKind.button => 'Button',
        ControlKind.reading => 'Reading',
      };
}

/// One thing you can do to a device, or one thing it tells you.
///
/// A control is defined by the user rather than discovered, because the
/// devices this has to work with are a relay board someone wired themselves
/// and an ESP32 with a sketch on it — neither announces a schema, and
/// requiring one would rule out exactly the hardware this app exists for.
class DeviceControl {
  DeviceControl({
    required this.name,
    required this.kind,
    required this.topic,
    this.onPayload = 'ON',
    this.offPayload = 'OFF',
    this.pressPayload = 'PRESS',
    this.min = 0,
    this.max = 100,
    this.unit = '',
  });

  final String name;
  final ControlKind kind;

  /// Published to for a control, subscribed to for a reading.
  final String topic;

  final String onPayload;
  final String offPayload;
  final String pressPayload;
  final double min;
  final double max;

  /// Shown after a reading's value: °C, %, ppm.
  final String unit;

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind.name,
        'topic': topic,
        'on': onPayload,
        'off': offPayload,
        'press': pressPayload,
        'min': min,
        'max': max,
        'unit': unit,
      };

  static DeviceControl fromJson(Map<String, dynamic> json) => DeviceControl(
        name: json['name'] as String? ?? '',
        kind: ControlKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => ControlKind.button,
        ),
        topic: json['topic'] as String? ?? '',
        onPayload: json['on'] as String? ?? 'ON',
        offPayload: json['off'] as String? ?? 'OFF',
        pressPayload: json['press'] as String? ?? 'PRESS',
        min: (json['min'] as num?)?.toDouble() ?? 0,
        max: (json['max'] as num?)?.toDouble() ?? 100,
        unit: json['unit'] as String? ?? '',
      );
}

/// A device the user has added.
class Device {
  Device({
    required this.id,
    required this.name,
    required this.kind,
    this.address = '',
    this.port = 0,
    this.room = '',
    this.token = '',
    this.controls = const [],
  });

  final String id;
  final String name;
  final DeviceKind kind;

  /// The address on the local network, for the televisions. Empty for MQTT
  /// devices, which are reached through whichever broker carries them.
  final String address;
  final int port;

  /// Free text, used only to group the list. "Kitchen", "Workshop".
  final String room;

  /// What a television handed back when it was paired. Kept because losing
  /// it means being asked to allow the phone again on the television's own
  /// screen, with its own remote, which is the one thing this replaces.
  final String token;

  final List<DeviceControl> controls;

  Device copyWith({
    String? name,
    DeviceKind? kind,
    String? address,
    int? port,
    String? room,
    String? token,
    List<DeviceControl>? controls,
  }) =>
      Device(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        address: address ?? this.address,
        port: port ?? this.port,
        room: room ?? this.room,
        token: token ?? this.token,
        controls: controls ?? this.controls,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'address': address,
        'port': port,
        'room': room,
        'token': token,
        'controls': controls.map((c) => c.toJson()).toList(),
      };

  static Device? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null) return null;
    return Device(
      id: id,
      name: json['name'] as String? ?? id,
      kind: DeviceKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => DeviceKind.mqtt,
      ),
      address: json['address'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 0,
      room: json['room'] as String? ?? '',
      token: json['token'] as String? ?? '',
      controls: (json['controls'] as List?)
              ?.whereType<Map>()
              .map((c) => DeviceControl.fromJson(Map<String, dynamic>.from(c)))
              .toList() ??
          const [],
    );
  }

  static String encode(List<Device> devices) =>
      jsonEncode(devices.map((d) => d.toJson()).toList());
}

/// The buttons a remote has, named once so every television speaks the same
/// language to the screen and only the protocol layer knows the difference.
enum RemoteKey {
  power,
  home,
  back,
  up,
  down,
  left,
  right,
  ok,
  volumeUp,
  volumeDown,
  mute,
  channelUp,
  channelDown,
  playPause,
  rewind,
  forward,
  info,
  exit,
}
