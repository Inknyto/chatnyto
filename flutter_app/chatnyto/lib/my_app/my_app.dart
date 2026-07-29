import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../calls/call_banner.dart';
import '../calls/call_page.dart';
import '../calls/call_service.dart';
import '../core/brokers/broker_service.dart';
import '../core/crypto/crypto_service.dart';
import '../core/crypto/password_vault.dart';
import '../core/notifications/background_client.dart';
import '../core/notifications/background_service.dart';
import '../core/notifications/notification_service.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/glass_controller.dart';
import '../core/theme/locale_controller.dart';
import '../core/theme/theme_controller.dart';
import '../l10n/app_localizations.dart';
import '../core/widgets/liquid_glass.dart';
import '../revamp/chat_service.dart';
import '../revamp/home_shell.dart';
import '../revamp/onboarding.dart';
import 'app_drawer.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  /// Needed to put the call screen in front from anywhere in the app.
  static final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();
  bool _callScreenOpen = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CallService.instance.init();
    CallService.instance.addListener(_onCallChanged);
    // Tells the foreground service's own isolate that the app is here, so it
    // does not also connect and notify everything twice.
    UiPresence.instance.start();
    ThemeController.instance.load();
    GlassController.instance.load();
    LocaleController.instance.load();
  }

  @override
  void dispose() {
    CallService.instance.removeListener(_onCallChanged);
    UiPresence.instance.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// An incoming call has to interrupt whatever is on screen, so the call
  /// page is pushed from here rather than from any one screen.
  void _onCallChanged() {
    final calls = CallService.instance;
    if (calls.state == CallState.ringing) _openCall();
  }

  /// Puts the call screen in front, from the ring or from the banner.
  void _openCall() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || _callScreenOpen) return;
    _callScreenOpen = true;
    navigator
        .push(GlassPageRoute(page: const CallPage()))
        .whenComplete(() => _callScreenOpen = false);
  }

  /// The broker connections and their heartbeat are deliberately left
  /// running when the app goes to the background, so messages keep arriving
  /// (and raise notifications). Coming back to the foreground is the moment
  /// to repair whatever the OS tore down while we were away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    NotificationService.instance.appInForeground =
        state == AppLifecycleState.resumed;
    // Being detached is the app going away for good. Clearing the stamp lets
    // the service take over listening on its next tick rather than waiting
    // for it to go stale, so a call arriving seconds later still rings.
    if (state == AppLifecycleState.detached) {
      UiPresence.instance.stamp(leaving: true);
    } else {
      UiPresence.instance.stamp();
    }
    if (state == AppLifecycleState.resumed &&
        IdentityService.instance.isUnlocked) {
      // The service is what holds the process open. If the system took it
      // away while we were gone, now is the moment to put it back, before
      // anything else — otherwise the next trip to the background is the
      // one where messages stop arriving.
      BackgroundService.instance.startIfEnabled();
      // Coming back to the app usually means something changed — a
      // different WiFi, mobile data back on — so the networks that were
      // backed off deserve another go straight away.
      BrokerService.instance.retryNow();
      BrokerService.instance.autoConnectAll().then((_) async {
        await BrokerService.instance.advertiseEverywhere();
        await ChatService.instance.syncAll();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) {
        return ValueListenableBuilder<Locale?>(
          valueListenable: LocaleController.instance,
          builder: (context, locale, _) => MaterialApp(
            title: 'ChatNyto',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: mode,
            // null follows the phone's language.
            locale: locale,
            navigatorKey: _navigatorKey,
            // Wrapped around the navigator rather than around one page, so
            // an ongoing call stays reachable from every screen — including
            // the ones pushed on top.
            builder: (context, child) => CallBanner(
              onTap: _openCall,
              child: child ?? const SizedBox.shrink(),
            ),
            supportedLocales: LocaleController.supported,
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              // Required by the quill editor/toolbar widgets; without it
              // they throw and blank the whole page.
              ...FlutterQuillLocalizations.localizationsDelegates,
            ],
            home: const _Entry(),
          ),
        );
      },
    );
  }
}

/// What the app should show at start-up.
enum _Start { onboarding, unlock, home }

/// Decides the start screen: onboarding on first run, the chats when the
/// identity could be unlocked with the remembered password, otherwise the
/// unlock screen.
class _Entry extends StatefulWidget {
  const _Entry();

  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> {
  // Resolved once: rebuilds (a theme toggle, for instance) must not send
  // the user back through the unlock decision.
  late final Future<_Start> _start = _decide();

  static Future<_Start> _decide() async {
    if (!await IdentityService.instance.exists()) return _Start.onboarding;
    if (!IdentityService.instance.isUnlocked &&
        !await PasswordVault.instance.tryAutoUnlock()) {
      return _Start.unlock;
    }
    // Networks, chat sync and notifications start before the first frame of
    // the home screen, not as a side effect of building it.
    await startRevampServices();
    return _Start.home;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Start>(
      future: _start,
      builder: (context, snapshot) {
        switch (snapshot.data) {
          case null:
            return const GlassBackground(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Center(child: CircularProgressIndicator()),
              ),
            );
          case _Start.onboarding:
            return const WelcomeScreen();
          case _Start.unlock:
            return const UnlockScreen();
          case _Start.home:
            return const HomeShell();
        }
      },
    );
  }
}

class AppPage extends StatelessWidget {
  const AppPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('ChatNyto'),
          actions: [
            IconButton(
              tooltip: 'Toggle dark/light mode',
              icon: Icon(
                Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
              ),
              onPressed: ThemeController.instance.toggle,
            ),
          ],
        ),
        drawer: const AppDrawer(),
        body: const AppContent(),
      ),
    );
  }
}

class AppContent extends StatelessWidget {
  const AppContent({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bienvenue sur ChatNyto!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Cette application de chat permet de discuter avec humains, '
            'robots et intelligences artificielles, avec ou sans internet '
            '(MQTT sur LoRa). Ouvrez le menu pour accéder aux catégories.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            Icons.people_alt_rounded,
            'Humains',
            'Discussions classiques, chiffrées de bout en bout',
          ),
          _buildSection(
            context,
            Icons.smart_toy_rounded,
            'Robots',
            'Discutez avec les objets connectés',
          ),
          _buildSection(
            context,
            Icons.auto_awesome_rounded,
            'IAs',
            'Intelligences artificielles locales et cloud',
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, IconData icon, String title, String description) {
    return LiquidGlass(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        subtitle: Text(description, style: const TextStyle(fontSize: 15)),
      ),
    );
  }
}
