import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'ChatNyto'**
  String get appTitle;

  /// No description provided for @tabChats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get tabChats;

  /// No description provided for @call.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

  /// No description provided for @tabCalls.
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get tabCalls;

  /// No description provided for @tabPeople.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get tabPeople;

  /// No description provided for @tabUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get tabUpdates;

  /// No description provided for @tabCommunities.
  ///
  /// In en, this message translates to:
  /// **'Communities'**
  String get tabCommunities;

  /// No description provided for @menuSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get menuSettings;

  /// No description provided for @menuSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security & identity'**
  String get menuSecurity;

  /// No description provided for @menuNetworks.
  ///
  /// In en, this message translates to:
  /// **'Networks'**
  String get menuNetworks;

  /// No description provided for @toggleTheme.
  ///
  /// In en, this message translates to:
  /// **'Toggle dark/light mode'**
  String get toggleTheme;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to ChatNyto'**
  String get welcomeTitle;

  /// No description provided for @welcomeTagline.
  ///
  /// In en, this message translates to:
  /// **'Easy, secure connections between people, AI agents and IoT devices — with or without internet. Everything is end-to-end encrypted.'**
  String get welcomeTagline;

  /// No description provided for @welcomeContinue.
  ///
  /// In en, this message translates to:
  /// **'Agree and continue'**
  String get welcomeContinue;

  /// No description provided for @setupTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your profile'**
  String get setupTitle;

  /// No description provided for @setupName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get setupName;

  /// No description provided for @setupNameHelp.
  ///
  /// In en, this message translates to:
  /// **'Visible to people you chat with'**
  String get setupNameHelp;

  /// No description provided for @setupPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get setupPassword;

  /// No description provided for @setupPasswordHelp.
  ///
  /// In en, this message translates to:
  /// **'Protects your encryption keys on this device'**
  String get setupPasswordHelp;

  /// No description provided for @setupStart.
  ///
  /// In en, this message translates to:
  /// **'Start chatting'**
  String get setupStart;

  /// No description provided for @setupNameMissing.
  ///
  /// In en, this message translates to:
  /// **'Please enter your name.'**
  String get setupNameMissing;

  /// No description provided for @setupPasswordShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters.'**
  String get setupPasswordShort;

  /// No description provided for @setupFootnote.
  ///
  /// In en, this message translates to:
  /// **'A secure identity (encryption keys) is created for you automatically. No account, no phone number, no servers to configure.'**
  String get setupFootnote;

  /// No description provided for @unlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get unlockTitle;

  /// No description provided for @unlockButton.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlockButton;

  /// No description provided for @unlockWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong password, try again.'**
  String get unlockWrong;

  /// No description provided for @rememberMe.
  ///
  /// In en, this message translates to:
  /// **'Remember me'**
  String get rememberMe;

  /// No description provided for @rememberMeHelp.
  ///
  /// In en, this message translates to:
  /// **'Keeps your password in this device\'s keystore so ChatNyto opens straight into your chats.'**
  String get rememberMeHelp;

  /// No description provided for @chatsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No chats yet.\n\nFind someone in the People tab, or create a group with the button below.'**
  String get chatsEmpty;

  /// No description provided for @sayHello.
  ///
  /// In en, this message translates to:
  /// **'Say hello 👋'**
  String get sayHello;

  /// No description provided for @groupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Group · anyone with the name can join'**
  String get groupSubtitle;

  /// No description provided for @newGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroup;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupName;

  /// No description provided for @groupPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase (optional)'**
  String get groupPassphrase;

  /// No description provided for @groupPassphraseHelp.
  ///
  /// In en, this message translates to:
  /// **'Only people with the passphrase can read'**
  String get groupPassphraseHelp;

  /// No description provided for @renameChat.
  ///
  /// In en, this message translates to:
  /// **'Rename chat'**
  String get renameChat;

  /// No description provided for @renameGroup.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get renameGroup;

  /// No description provided for @renameGroupHelp.
  ///
  /// In en, this message translates to:
  /// **'The name is the group\'s address on the network — everyone follows it automatically.'**
  String get renameGroupHelp;

  /// No description provided for @wallpaperForChat.
  ///
  /// In en, this message translates to:
  /// **'Wallpaper for this chat'**
  String get wallpaperForChat;

  /// No description provided for @useGlobalWallpaper.
  ///
  /// In en, this message translates to:
  /// **'Use global wallpaper'**
  String get useGlobalWallpaper;

  /// No description provided for @deleteChat.
  ///
  /// In en, this message translates to:
  /// **'Delete chat'**
  String get deleteChat;

  /// No description provided for @leaveGroup.
  ///
  /// In en, this message translates to:
  /// **'Leave group'**
  String get leaveGroup;

  /// No description provided for @deleteGroupForEveryone.
  ///
  /// In en, this message translates to:
  /// **'Delete group for everyone'**
  String get deleteGroupForEveryone;

  /// No description provided for @deleteLocalWarning.
  ///
  /// In en, this message translates to:
  /// **'Removes the chat and its messages on this device.'**
  String get deleteLocalWarning;

  /// No description provided for @groupAdmins.
  ///
  /// In en, this message translates to:
  /// **'Group admins'**
  String get groupAdmins;

  /// No description provided for @groupAdminsHelp.
  ///
  /// In en, this message translates to:
  /// **'Admins can rename this group and delete it for everyone. Only you can change this list.'**
  String get groupAdminsHelp;

  /// No description provided for @viewIdentity.
  ///
  /// In en, this message translates to:
  /// **'View identity'**
  String get viewIdentity;

  /// No description provided for @messageHint.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get messageHint;

  /// No description provided for @sendPicture.
  ///
  /// In en, this message translates to:
  /// **'Send a picture'**
  String get sendPicture;

  /// No description provided for @choosePicture.
  ///
  /// In en, this message translates to:
  /// **'Choose a picture'**
  String get choosePicture;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get takePhoto;

  /// No description provided for @formatting.
  ///
  /// In en, this message translates to:
  /// **'Formatting'**
  String get formatting;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'📷 Photo'**
  String get photo;

  /// No description provided for @cannotSendLocked.
  ///
  /// In en, this message translates to:
  /// **'Cannot send: unlock your identity first.'**
  String get cannotSendLocked;

  /// No description provided for @searchPeople.
  ///
  /// In en, this message translates to:
  /// **'Search people by name'**
  String get searchPeople;

  /// No description provided for @connectedPeopleAppear.
  ///
  /// In en, this message translates to:
  /// **'Connected — people appear automatically'**
  String get connectedPeopleAppear;

  /// No description provided for @searchingNetwork.
  ///
  /// In en, this message translates to:
  /// **'Searching for a network…'**
  String get searchingNetwork;

  /// No description provided for @networksReachable.
  ///
  /// In en, this message translates to:
  /// **'{count} network(s) reachable'**
  String networksReachable(int count);

  /// No description provided for @turnOnLoraHint.
  ///
  /// In en, this message translates to:
  /// **'Turn on the LoRa box or join the same WiFi, then people around you show up here.'**
  String get turnOnLoraHint;

  /// No description provided for @publicGroupsOnMesh.
  ///
  /// In en, this message translates to:
  /// **'Public groups on the mesh'**
  String get publicGroupsOnMesh;

  /// No description provided for @publicGroupTapToJoin.
  ///
  /// In en, this message translates to:
  /// **'Public group · tap to join'**
  String get publicGroupTapToJoin;

  /// No description provided for @verifiedKey.
  ///
  /// In en, this message translates to:
  /// **'Verified · {fingerprint}'**
  String verifiedKey(String fingerprint);

  /// No description provided for @identityChecked.
  ///
  /// In en, this message translates to:
  /// **'The signature of this identity was checked against its public key. Compare the fingerprint with your contact through another channel for full certainty.'**
  String get identityChecked;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @onlineNow.
  ///
  /// In en, this message translates to:
  /// **'Online now'**
  String get onlineNow;

  /// No description provided for @nobodyYet.
  ///
  /// In en, this message translates to:
  /// **'Nobody on the network yet'**
  String get nobodyYet;

  /// No description provided for @networks.
  ///
  /// In en, this message translates to:
  /// **'Networks'**
  String get networks;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'connected'**
  String get connected;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'disconnected'**
  String get disconnected;

  /// No description provided for @unreachable.
  ///
  /// In en, this message translates to:
  /// **'Unreachable'**
  String get unreachable;

  /// No description provided for @communityPeople.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get communityPeople;

  /// No description provided for @communityPeopleSub.
  ///
  /// In en, this message translates to:
  /// **'Classic rooms with rich-text messages'**
  String get communityPeopleSub;

  /// No description provided for @communityIot.
  ///
  /// In en, this message translates to:
  /// **'IoT devices'**
  String get communityIot;

  /// No description provided for @communityIotSub.
  ///
  /// In en, this message translates to:
  /// **'Securely talk to your connected devices'**
  String get communityIotSub;

  /// No description provided for @communityAi.
  ///
  /// In en, this message translates to:
  /// **'AI agents'**
  String get communityAi;

  /// No description provided for @communityAiSub.
  ///
  /// In en, this message translates to:
  /// **'Claude, GPT, Gemini, a local model — with your own key'**
  String get communityAiSub;

  /// No description provided for @addBroker.
  ///
  /// In en, this message translates to:
  /// **'Add broker'**
  String get addBroker;

  /// No description provided for @editBroker.
  ///
  /// In en, this message translates to:
  /// **'Edit broker'**
  String get editBroker;

  /// No description provided for @brokerName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get brokerName;

  /// No description provided for @brokerHost.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get brokerHost;

  /// No description provided for @brokerPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get brokerPort;

  /// No description provided for @brokerUsername.
  ///
  /// In en, this message translates to:
  /// **'Username (optional)'**
  String get brokerUsername;

  /// No description provided for @brokerUsernameHelp.
  ///
  /// In en, this message translates to:
  /// **'Only for password-protected brokers'**
  String get brokerUsernameHelp;

  /// No description provided for @brokerPassword.
  ///
  /// In en, this message translates to:
  /// **'Password (optional)'**
  String get brokerPassword;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot your password?'**
  String get forgotPassword;

  /// No description provided for @otherAccounts.
  ///
  /// In en, this message translates to:
  /// **'Other accounts on this device'**
  String get otherAccounts;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @replace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replace;

  /// No description provided for @signInWillBeRemoved.
  ///
  /// In en, this message translates to:
  /// **'The saved sign-in will be removed'**
  String get signInWillBeRemoved;

  /// No description provided for @signInSaved.
  ///
  /// In en, this message translates to:
  /// **'A sign-in is saved for this network'**
  String get signInSaved;

  /// No description provided for @needsSignIn.
  ///
  /// In en, this message translates to:
  /// **'This network needs a sign-in'**
  String get needsSignIn;

  /// No description provided for @brokerPortOptional.
  ///
  /// In en, this message translates to:
  /// **'Port (only if it is not the standard one)'**
  String get brokerPortOptional;

  /// No description provided for @brokerNameHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. Left empty, the network names itself.'**
  String get brokerNameHelp;

  /// No description provided for @brokerHostHelp.
  ///
  /// In en, this message translates to:
  /// **'Just the address of the network — the server fills in the rest. A broker on your own network can be given as an IP.'**
  String get brokerHostHelp;

  /// No description provided for @searchNetworks.
  ///
  /// In en, this message translates to:
  /// **'Search networks and people'**
  String get searchNetworks;

  /// No description provided for @connectAutomatically.
  ///
  /// In en, this message translates to:
  /// **'Connect automatically'**
  String get connectAutomatically;

  /// No description provided for @findBrokers.
  ///
  /// In en, this message translates to:
  /// **'Find brokers on this network'**
  String get findBrokers;

  /// No description provided for @findBrokersHelp.
  ///
  /// In en, this message translates to:
  /// **'Looks for public MQTT brokers around you, including the LoRa box.'**
  String get findBrokersHelp;

  /// No description provided for @scanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning this network…'**
  String get scanning;

  /// No description provided for @foundOnNetwork.
  ///
  /// In en, this message translates to:
  /// **'Found on this network'**
  String get foundOnNetwork;

  /// No description provided for @noBrokersFound.
  ///
  /// In en, this message translates to:
  /// **'No brokers found on this network.'**
  String get noBrokersFound;

  /// No description provided for @shareByQr.
  ///
  /// In en, this message translates to:
  /// **'Share by QR code'**
  String get shareByQr;

  /// No description provided for @scanNetworkCode.
  ///
  /// In en, this message translates to:
  /// **'Scan a network code'**
  String get scanNetworkCode;

  /// No description provided for @networkMap.
  ///
  /// In en, this message translates to:
  /// **'Network map'**
  String get networkMap;

  /// No description provided for @couldNotConnect.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to {name}'**
  String couldNotConnect(String name);

  /// No description provided for @settingsProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get settingsProfile;

  /// No description provided for @profilePicture.
  ///
  /// In en, this message translates to:
  /// **'Profile picture'**
  String get profilePicture;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// No description provided for @settingsSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurity;

  /// No description provided for @askPasswordEveryOpen.
  ///
  /// In en, this message translates to:
  /// **'Ask password at every app open'**
  String get askPasswordEveryOpen;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @messageNotifications.
  ///
  /// In en, this message translates to:
  /// **'Message notifications'**
  String get messageNotifications;

  /// No description provided for @messageNotificationsHelp.
  ///
  /// In en, this message translates to:
  /// **'Alerts you when a message arrives and the chat is not open.'**
  String get messageNotificationsHelp;

  /// No description provided for @notificationSound.
  ///
  /// In en, this message translates to:
  /// **'Notification sound'**
  String get notificationSound;

  /// No description provided for @soundChime.
  ///
  /// In en, this message translates to:
  /// **'ChatNyto chime'**
  String get soundChime;

  /// No description provided for @soundSystem.
  ///
  /// In en, this message translates to:
  /// **'Your default tone'**
  String get soundSystem;

  /// No description provided for @soundSilent.
  ///
  /// In en, this message translates to:
  /// **'Silent'**
  String get soundSilent;

  /// No description provided for @stayConnected.
  ///
  /// In en, this message translates to:
  /// **'Stay connected in the background'**
  String get stayConnected;

  /// No description provided for @stayConnectedHelp.
  ///
  /// In en, this message translates to:
  /// **'Keeps receiving messages while the app is closed, and starts again after a reboot. Shows a quiet permanent notification.'**
  String get stayConnectedHelp;

  /// No description provided for @settingsPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get settingsPreferences;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System language'**
  String get languageSystem;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get darkMode;

  /// No description provided for @chatWallpaper.
  ///
  /// In en, this message translates to:
  /// **'Chat wallpaper'**
  String get chatWallpaper;

  /// No description provided for @appWallpaper.
  ///
  /// In en, this message translates to:
  /// **'App wallpaper'**
  String get appWallpaper;

  /// No description provided for @glassOpacity.
  ///
  /// In en, this message translates to:
  /// **'Glass opacity'**
  String get glassOpacity;

  /// No description provided for @glassOpacityHelp.
  ///
  /// In en, this message translates to:
  /// **'How much the panels, bubbles and bars show through. Applies everywhere and is remembered.'**
  String get glassOpacityHelp;

  /// No description provided for @opacityVeryTransparent.
  ///
  /// In en, this message translates to:
  /// **'Very transparent'**
  String get opacityVeryTransparent;

  /// No description provided for @opacityTransparent.
  ///
  /// In en, this message translates to:
  /// **'Transparent'**
  String get opacityTransparent;

  /// No description provided for @opacityBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get opacityBalanced;

  /// No description provided for @opacitySolid.
  ///
  /// In en, this message translates to:
  /// **'Solid'**
  String get opacitySolid;

  /// No description provided for @opacityVerySolid.
  ///
  /// In en, this message translates to:
  /// **'Very solid'**
  String get opacityVerySolid;

  /// No description provided for @aiAgents.
  ///
  /// In en, this message translates to:
  /// **'AI agents'**
  String get aiAgents;

  /// No description provided for @aiNoAgents.
  ///
  /// In en, this message translates to:
  /// **'No agents yet'**
  String get aiNoAgents;

  /// No description provided for @aiNoAgentsHelp.
  ///
  /// In en, this message translates to:
  /// **'Add an agent to chat with Claude, GPT, Gemini, Mistral, a local Ollama model and more. You bring your own key; it stays in this device\'s keystore.'**
  String get aiNoAgentsHelp;

  /// No description provided for @aiAddAgent.
  ///
  /// In en, this message translates to:
  /// **'Add an agent'**
  String get aiAddAgent;

  /// No description provided for @aiEditAgent.
  ///
  /// In en, this message translates to:
  /// **'Edit agent'**
  String get aiEditAgent;

  /// No description provided for @aiNewAgent.
  ///
  /// In en, this message translates to:
  /// **'New agent'**
  String get aiNewAgent;

  /// No description provided for @aiDeleteAgent.
  ///
  /// In en, this message translates to:
  /// **'Delete agent'**
  String get aiDeleteAgent;

  /// No description provided for @aiAgentName.
  ///
  /// In en, this message translates to:
  /// **'Agent name'**
  String get aiAgentName;

  /// No description provided for @aiProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get aiProvider;

  /// No description provided for @aiModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get aiModel;

  /// No description provided for @aiModelHelp.
  ///
  /// In en, this message translates to:
  /// **'Any model name the provider accepts'**
  String get aiModelHelp;

  /// No description provided for @aiServerAddress.
  ///
  /// In en, this message translates to:
  /// **'Server address (optional)'**
  String get aiServerAddress;

  /// No description provided for @aiInstructions.
  ///
  /// In en, this message translates to:
  /// **'Instructions (system prompt)'**
  String get aiInstructions;

  /// No description provided for @aiCreativity.
  ///
  /// In en, this message translates to:
  /// **'Creativity'**
  String get aiCreativity;

  /// No description provided for @aiToolsAllowed.
  ///
  /// In en, this message translates to:
  /// **'Tools this agent may use'**
  String get aiToolsAllowed;

  /// No description provided for @aiProvidersAndTools.
  ///
  /// In en, this message translates to:
  /// **'AI providers & tools'**
  String get aiProvidersAndTools;

  /// No description provided for @aiByokIntro.
  ///
  /// In en, this message translates to:
  /// **'Bring your own key: ChatNyto talks to each provider straight from your device, and the keys never leave its keystore.'**
  String get aiByokIntro;

  /// No description provided for @aiApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get aiApiKey;

  /// No description provided for @aiApiKeyHelp.
  ///
  /// In en, this message translates to:
  /// **'Stored in this device\'s keystore only'**
  String get aiApiKeyHelp;

  /// No description provided for @aiKeySaved.
  ///
  /// In en, this message translates to:
  /// **'Key saved'**
  String get aiKeySaved;

  /// No description provided for @aiNoKeyYet.
  ///
  /// In en, this message translates to:
  /// **'No key yet'**
  String get aiNoKeyYet;

  /// No description provided for @aiToolsMcp.
  ///
  /// In en, this message translates to:
  /// **'Tools (MCP)'**
  String get aiToolsMcp;

  /// No description provided for @aiToolsMcpHelp.
  ///
  /// In en, this message translates to:
  /// **'Model Context Protocol servers give your agents skills — reading files, querying a database, driving your IoT devices. Enable them per agent.'**
  String get aiToolsMcpHelp;

  /// No description provided for @aiAddToolServer.
  ///
  /// In en, this message translates to:
  /// **'Add a tool server'**
  String get aiAddToolServer;

  /// No description provided for @aiMcpEndpoint.
  ///
  /// In en, this message translates to:
  /// **'MCP endpoint URL'**
  String get aiMcpEndpoint;

  /// No description provided for @aiClearConversation.
  ///
  /// In en, this message translates to:
  /// **'Clear conversation'**
  String get aiClearConversation;

  /// No description provided for @aiThinking.
  ///
  /// In en, this message translates to:
  /// **'thinking…'**
  String get aiThinking;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
