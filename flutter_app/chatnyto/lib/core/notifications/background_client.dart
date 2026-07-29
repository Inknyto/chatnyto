import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../brokers/broker_service.dart';
import '../crypto/crypto_service.dart';
import '../crypto/password_vault.dart';
import '../../revamp/chat_service.dart';
import 'notification_service.dart';

/// Keeps a phone reachable when ChatNyto is not running.
///
/// A foreground service holds the app's own process open, and while that
/// process lives the app's normal code keeps the broker connections and
/// everything arrives as usual. But once the app is closed and the system
/// takes the process away, the service comes back on its own, in a fresh
/// isolate where none of the app's state exists — and a ring that arrives
/// then has nobody listening for it. That is the gap this fills: enough of a
/// client to notice a call and make the phone ring.
///
/// Deliberately less than the app:
///
///  * It **connects and listens**, and raises notifications. That is all.
///  * It **writes nothing**. Two isolates writing the same preferences file
///    is how message history gets lost, and the price of not writing is
///    small: when the app is opened, its sync protocol asks the other side
///    to replay whatever was missed, which is what that protocol is for.
///  * It **does not answer calls**. Answering needs a microphone, a screen
///    and the whole call machinery. Instead it rings with a full-screen
///    notification, which brings the app up — and the caller repeats its
///    offer while it rings, so the app finds the call still waiting.
///
/// Only one of the two isolates may be the client at a time, or every
/// message would notify twice. The app stamps [uiHeartbeatKey] while it is
/// alive; this one takes over when that stamp goes stale and stands down
/// when it is fresh again.
class BackgroundClient {
  BackgroundClient._();

  static final BackgroundClient instance = BackgroundClient._();

  /// Written by the running app, read here. Its age is the only thing that
  /// tells a separate isolate whether the app is still there.
  static const uiHeartbeatKey = 'runtime.uiAlive';

  /// How stale the app's stamp has to be before this takes over. Comfortably
  /// more than the app's stamping interval, so a slow moment is not mistaken
  /// for the app being gone.
  static const _uiConsideredGone = Duration(seconds: 40);

  bool _active = false;
  bool _starting = false;

  /// Fingerprints whose ring is already showing, so a caller repeating its
  /// offer does not start the ringtone over and over.
  final Set<String> _ringing = {};
  Timer? _ringClear;

  bool get active => _active;

  /// Whether the app has stopped stamping for long enough that this isolate
  /// should take over listening.
  ///
  /// Pulled out on its own because getting it wrong is silent: too eager and
  /// both isolates connect and every message notifies twice; too reluctant
  /// and calls are missed for exactly as long as it hesitates. A stamp of
  /// zero is the app saying it is on its way out, and counts as gone
  /// straight away. A stamp in the future — a clock that moved — is treated
  /// as fresh rather than as an enormous age.
  static bool appLooksGone(int stampMillis, DateTime now) {
    if (stampMillis <= 0) return true;
    final age = now.millisecondsSinceEpoch - stampMillis;
    if (age < 0) return false;
    return age > _uiConsideredGone.inMilliseconds;
  }

  /// Decides, on each tick of the service, whether to be the client.
  Future<void> tick() async {
    final prefs = await SharedPreferences.getInstance();
    // The stamp is written by another isolate, so the cached copy this one
    // holds is worthless without this.
    await prefs.reload();
    final appIsGone =
        appLooksGone(prefs.getInt(uiHeartbeatKey) ?? 0, DateTime.now());

    if (appIsGone && !_active) {
      await _start();
    } else if (!appIsGone && _active) {
      await _stop();
    }
  }

  Future<void> _start() async {
    if (_starting || _active) return;
    _starting = true;
    try {
      await NotificationService.instance.init();
      // Nothing is on screen in this isolate, so nothing may be suppressed
      // for being the chat the user is looking at.
      NotificationService.instance.appInForeground = false;
      NotificationService.instance.activeChatId = null;
      // Without the remembered password there are no keys, so nothing on any
      // topic can be read. Nothing useful to do but wait for the app.
      final unlocked = await PasswordVault.instance.tryAutoUnlock();
      if (!unlocked) {
        debugPrint('[background] no remembered password; staying idle');
        return;
      }
      await BrokerService.instance.load();
      BrokerService.instance.onChatMessage = _onChatMessage;
      await BrokerService.instance.autoConnectAll();
      BrokerService.instance.startHeartbeat();
      _active = true;
      debugPrint('[background] listening for calls and messages');
    } catch (error) {
      debugPrint('[background] could not start: $error');
    } finally {
      _starting = false;
    }
  }

  /// Hands everything back to the app and goes quiet.
  Future<void> _stop() async {
    _active = false;
    _ringing.clear();
    _ringClear?.cancel();
    _ringClear = null;
    try {
      BrokerService.instance.stopHeartbeat();
      BrokerService.instance.onChatMessage = null;
      for (final broker in BrokerService.instance.brokers) {
        await BrokerService.instance.disconnect(broker);
      }
      IdentityService.instance.lock();
    } catch (error) {
      debugPrint('[background] could not stand down cleanly: $error');
    }
    debugPrint('[background] the app is back; standing down');
  }

  /// The one thing this isolate reads off the wire.
  ///
  /// Only enough to tell a ring from a message: the payload is decrypted
  /// with the same channel key the app would use, and then either the phone
  /// rings or a notification goes up. Nothing is stored either way.
  Future<void> _onChatMessage(String topic, String payload) async {
    if (!_active) return;
    try {
      final read = await ChatService.instance.readForBackground(topic, payload);
      if (read == null) return;
      switch (read.kind) {
        case BackgroundReadKind.incomingCall:
          await _ring(read.chatTitle, read.from);
        case BackgroundReadKind.callEnded:
          _ringing.remove(read.from);
          await NotificationService.instance.cancelIncomingCall();
        case BackgroundReadKind.message:
          await NotificationService.instance.showMessage(
            chatId: read.chatId,
            chatTitle: read.chatTitle,
            sender: read.senderName,
            preview: read.preview,
          );
      }
    } catch (error) {
      debugPrint('[background] could not read a message: $error');
    }
  }

  Future<void> _ring(String caller, String from) async {
    if (_ringing.contains(from)) return;
    _ringing.add(from);
    // The caller repeats its offer for as long as it rings; forgetting who
    // is ringing after a while is what lets a second, later call through.
    _ringClear?.cancel();
    _ringClear = Timer(const Duration(seconds: 60), _ringing.clear);
    // No Answer/Decline buttons: this isolate cannot take a call. The
    // full-screen intent puts the app in front, and the app answers.
    await NotificationService.instance
        .showIncomingCall(caller, withActions: false);
  }
}

/// What the background isolate made of something on the wire.
enum BackgroundReadKind { incomingCall, callEnded, message }

/// The little that a listening isolate needs out of a decrypted payload.
class BackgroundRead {
  BackgroundRead({
    required this.kind,
    required this.chatId,
    required this.chatTitle,
    required this.from,
    this.senderName = '',
    this.preview = '',
  });

  final BackgroundReadKind kind;
  final String chatId;
  final String chatTitle;

  /// Fingerprint of whoever sent it.
  final String from;

  final String senderName;
  final String preview;
}

/// Stamps [BackgroundClient.uiHeartbeatKey] while the app is running, so the
/// service's own isolate knows to stay out of the way.
///
/// Cheap on purpose: one integer every ten seconds. The alternative — the two
/// isolates asking each other over a port — needs both of them to be healthy
/// to give the right answer, and "the app has been killed" is exactly the
/// case where it is not.
class UiPresence {
  UiPresence._();

  static final UiPresence instance = UiPresence._();

  Timer? _timer;

  Future<void> start() async {
    await stamp();
    _timer ??= Timer.periodic(
      const Duration(seconds: 10),
      (_) => stamp(),
    );
  }

  /// Called on the way out as well, so the service can take over promptly
  /// rather than waiting for the stamp to go stale.
  Future<void> stamp({bool leaving = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        BackgroundClient.uiHeartbeatKey,
        leaving ? 0 : DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // Preferences unavailable: the service falls back to its own timing.
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Kept for the JSON shapes the reader below needs to recognise.
const _callType = 'call';
const _syncType = 'sync_req';
const _receiptType = 'receipt';

/// Recognises the envelope kinds a listening isolate cares about. Shared
/// with [ChatService] so the two never disagree about what a ring looks
/// like.
bool isCallEnvelope(Map<String, dynamic> data) => data['type'] == _callType;

bool isPlumbingEnvelope(Map<String, dynamic> data) =>
    data['type'] == _syncType ||
    data['type'] == _receiptType ||
    (data['type'] as String? ?? '').startsWith('group_');

/// Decodes a JSON envelope body, or null when it is not JSON at all.
Map<String, dynamic>? decodeBody(String clear) {
  try {
    return jsonDecode(clear) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}
