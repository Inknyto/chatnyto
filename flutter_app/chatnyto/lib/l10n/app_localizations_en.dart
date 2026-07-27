// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'ChatNyto';

  @override
  String get tabChats => 'Chats';

  @override
  String get call => 'Call';

  @override
  String get tabCalls => 'Calls';

  @override
  String get tabPeople => 'People';

  @override
  String get tabUpdates => 'Updates';

  @override
  String get tabCommunities => 'Communities';

  @override
  String get menuSettings => 'Settings';

  @override
  String get menuSecurity => 'Security & identity';

  @override
  String get menuNetworks => 'Networks';

  @override
  String get toggleTheme => 'Toggle dark/light mode';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get add => 'Add';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get rename => 'Rename';

  @override
  String get create => 'Create';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Retry';

  @override
  String get ok => 'OK';

  @override
  String get welcomeTitle => 'Welcome to ChatNyto';

  @override
  String get welcomeTagline =>
      'Easy, secure connections between people, AI agents and IoT devices — with or without internet. Everything is end-to-end encrypted.';

  @override
  String get welcomeContinue => 'Agree and continue';

  @override
  String get setupTitle => 'Set up your profile';

  @override
  String get setupName => 'Your name';

  @override
  String get setupNameHelp => 'Visible to people you chat with';

  @override
  String get setupPassword => 'Password';

  @override
  String get setupPasswordHelp =>
      'Protects your encryption keys on this device';

  @override
  String get setupStart => 'Start chatting';

  @override
  String get setupNameMissing => 'Please enter your name.';

  @override
  String get setupPasswordShort => 'Password must be at least 8 characters.';

  @override
  String get setupFootnote =>
      'A secure identity (encryption keys) is created for you automatically. No account, no phone number, no servers to configure.';

  @override
  String get unlockTitle => 'Welcome back';

  @override
  String get unlockButton => 'Unlock';

  @override
  String get unlockWrong => 'Wrong password, try again.';

  @override
  String get rememberMe => 'Remember me';

  @override
  String get rememberMeHelp =>
      'Keeps your password in this device\'s keystore so ChatNyto opens straight into your chats.';

  @override
  String get chatsEmpty =>
      'No chats yet.\n\nFind someone in the People tab, or create a group with the button below.';

  @override
  String get sayHello => 'Say hello 👋';

  @override
  String get groupSubtitle => 'Group · anyone with the name can join';

  @override
  String get newGroup => 'New group';

  @override
  String get groupName => 'Group name';

  @override
  String get groupPassphrase => 'Passphrase (optional)';

  @override
  String get groupPassphraseHelp => 'Only people with the passphrase can read';

  @override
  String get renameChat => 'Rename chat';

  @override
  String get renameGroup => 'Rename group';

  @override
  String get renameGroupHelp =>
      'The name is the group\'s address on the network — everyone follows it automatically.';

  @override
  String get wallpaperForChat => 'Wallpaper for this chat';

  @override
  String get useGlobalWallpaper => 'Use global wallpaper';

  @override
  String get deleteChat => 'Delete chat';

  @override
  String get leaveGroup => 'Leave group';

  @override
  String get deleteGroupForEveryone => 'Delete group for everyone';

  @override
  String get deleteLocalWarning =>
      'Removes the chat and its messages on this device.';

  @override
  String get groupAdmins => 'Group admins';

  @override
  String get groupAdminsHelp =>
      'Admins can rename this group and delete it for everyone. Only you can change this list.';

  @override
  String get viewIdentity => 'View identity';

  @override
  String get messageHint => 'Message';

  @override
  String get sendPicture => 'Send a picture';

  @override
  String get choosePicture => 'Choose a picture';

  @override
  String get takePhoto => 'Take a photo';

  @override
  String get formatting => 'Formatting';

  @override
  String get photo => '📷 Photo';

  @override
  String get cannotSendLocked => 'Cannot send: unlock your identity first.';

  @override
  String get searchPeople => 'Search people by name';

  @override
  String get connectedPeopleAppear => 'Connected — people appear automatically';

  @override
  String get searchingNetwork => 'Searching for a network…';

  @override
  String networksReachable(int count) {
    return '$count network(s) reachable';
  }

  @override
  String get turnOnLoraHint =>
      'Turn on the LoRa box or join the same WiFi, then people around you show up here.';

  @override
  String get publicGroupsOnMesh => 'Public groups on the mesh';

  @override
  String get publicGroupTapToJoin => 'Public group · tap to join';

  @override
  String verifiedKey(String fingerprint) {
    return 'Verified · $fingerprint';
  }

  @override
  String get identityChecked =>
      'The signature of this identity was checked against its public key. Compare the fingerprint with your contact through another channel for full certainty.';

  @override
  String get message => 'Message';

  @override
  String get onlineNow => 'Online now';

  @override
  String get nobodyYet => 'Nobody on the network yet';

  @override
  String get networks => 'Networks';

  @override
  String get connected => 'connected';

  @override
  String get disconnected => 'disconnected';

  @override
  String get unreachable => 'Unreachable';

  @override
  String get communityPeople => 'People';

  @override
  String get communityPeopleSub => 'Classic rooms with rich-text messages';

  @override
  String get communityIot => 'IoT devices';

  @override
  String get communityIotSub => 'Securely talk to your connected devices';

  @override
  String get communityAi => 'AI agents';

  @override
  String get communityAiSub =>
      'Claude, GPT, Gemini, a local model — with your own key';

  @override
  String get addBroker => 'Add broker';

  @override
  String get editBroker => 'Edit broker';

  @override
  String get brokerName => 'Name';

  @override
  String get brokerHost => 'Address';

  @override
  String get brokerPort => 'Port';

  @override
  String get brokerUsername => 'Username (optional)';

  @override
  String get brokerUsernameHelp => 'Only for password-protected brokers';

  @override
  String get brokerPassword => 'Password (optional)';

  @override
  String get forgotPassword => 'Forgot your password?';

  @override
  String get otherAccounts => 'Other accounts on this device';

  @override
  String get undo => 'Undo';

  @override
  String get replace => 'Replace';

  @override
  String get signInWillBeRemoved => 'The saved sign-in will be removed';

  @override
  String get signInSaved => 'A sign-in is saved for this network';

  @override
  String get needsSignIn => 'This network needs a sign-in';

  @override
  String get brokerPortOptional => 'Port (only if it is not the standard one)';

  @override
  String get brokerNameHelp =>
      'Optional. Left empty, the network names itself.';

  @override
  String get brokerHostHelp =>
      'Just the address of the network — the server fills in the rest. A broker on your own network can be given as an IP.';

  @override
  String get searchNetworks => 'Search networks and people';

  @override
  String get connectAutomatically => 'Connect automatically';

  @override
  String get findBrokers => 'Find brokers on this network';

  @override
  String get findBrokersHelp =>
      'Looks for public MQTT brokers around you, including the LoRa box.';

  @override
  String get scanning => 'Scanning this network…';

  @override
  String get foundOnNetwork => 'Found on this network';

  @override
  String get noBrokersFound => 'No brokers found on this network.';

  @override
  String get shareByQr => 'Share by QR code';

  @override
  String get scanNetworkCode => 'Scan a network code';

  @override
  String get networkMap => 'Network map';

  @override
  String couldNotConnect(String name) {
    return 'Could not connect to $name';
  }

  @override
  String get settingsProfile => 'Profile';

  @override
  String get profilePicture => 'Profile picture';

  @override
  String get displayName => 'Display name';

  @override
  String get settingsSecurity => 'Security';

  @override
  String get askPasswordEveryOpen => 'Ask password at every app open';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get messageNotifications => 'Message notifications';

  @override
  String get messageNotificationsHelp =>
      'Alerts you when a message arrives and the chat is not open.';

  @override
  String get notificationSound => 'Notification sound';

  @override
  String get soundChime => 'ChatNyto chime';

  @override
  String get soundSystem => 'Your default tone';

  @override
  String get soundSilent => 'Silent';

  @override
  String get stayConnected => 'Stay connected in the background';

  @override
  String get stayConnectedHelp =>
      'Keeps receiving messages while the app is closed, and starts again after a reboot. Shows a quiet permanent notification.';

  @override
  String get settingsPreferences => 'Preferences';

  @override
  String get languageSystem => 'System language';

  @override
  String get language => 'Language';

  @override
  String get darkMode => 'Dark mode';

  @override
  String get chatWallpaper => 'Chat wallpaper';

  @override
  String get appWallpaper => 'App wallpaper';

  @override
  String get glassOpacity => 'Glass opacity';

  @override
  String get glassOpacityHelp =>
      'How much the panels, bubbles and bars show through. Applies everywhere and is remembered.';

  @override
  String get opacityVeryTransparent => 'Very transparent';

  @override
  String get opacityTransparent => 'Transparent';

  @override
  String get opacityBalanced => 'Balanced';

  @override
  String get opacitySolid => 'Solid';

  @override
  String get opacityVerySolid => 'Very solid';

  @override
  String get aiAgents => 'AI agents';

  @override
  String get aiNoAgents => 'No agents yet';

  @override
  String get aiNoAgentsHelp =>
      'Add an agent to chat with Claude, GPT, Gemini, Mistral, a local Ollama model and more. You bring your own key; it stays in this device\'s keystore.';

  @override
  String get aiAddAgent => 'Add an agent';

  @override
  String get aiEditAgent => 'Edit agent';

  @override
  String get aiNewAgent => 'New agent';

  @override
  String get aiDeleteAgent => 'Delete agent';

  @override
  String get aiAgentName => 'Agent name';

  @override
  String get aiProvider => 'Provider';

  @override
  String get aiModel => 'Model';

  @override
  String get aiModelHelp => 'Any model name the provider accepts';

  @override
  String get aiServerAddress => 'Server address (optional)';

  @override
  String get aiInstructions => 'Instructions (system prompt)';

  @override
  String get aiCreativity => 'Creativity';

  @override
  String get aiToolsAllowed => 'Tools this agent may use';

  @override
  String get aiProvidersAndTools => 'AI providers & tools';

  @override
  String get aiByokIntro =>
      'Bring your own key: ChatNyto talks to each provider straight from your device, and the keys never leave its keystore.';

  @override
  String get aiApiKey => 'API key';

  @override
  String get aiApiKeyHelp => 'Stored in this device\'s keystore only';

  @override
  String get aiKeySaved => 'Key saved';

  @override
  String get aiNoKeyYet => 'No key yet';

  @override
  String get aiToolsMcp => 'Tools (MCP)';

  @override
  String get aiToolsMcpHelp =>
      'Model Context Protocol servers give your agents skills — reading files, querying a database, driving your IoT devices. Enable them per agent.';

  @override
  String get aiAddToolServer => 'Add a tool server';

  @override
  String get aiMcpEndpoint => 'MCP endpoint URL';

  @override
  String get aiClearConversation => 'Clear conversation';

  @override
  String get aiThinking => 'thinking…';
}
