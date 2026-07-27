// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'ChatNyto';

  @override
  String get tabChats => 'Discussions';

  @override
  String get call => 'Appeler';

  @override
  String get tabCalls => 'Appels';

  @override
  String get tabPeople => 'Personnes';

  @override
  String get tabUpdates => 'Actus';

  @override
  String get tabCommunities => 'Communautés';

  @override
  String get menuSettings => 'Paramètres';

  @override
  String get menuSecurity => 'Sécurité et identité';

  @override
  String get menuNetworks => 'Réseaux';

  @override
  String get toggleTheme => 'Basculer entre thème clair et sombre';

  @override
  String get cancel => 'Annuler';

  @override
  String get save => 'Enregistrer';

  @override
  String get add => 'Ajouter';

  @override
  String get delete => 'Supprimer';

  @override
  String get edit => 'Modifier';

  @override
  String get rename => 'Renommer';

  @override
  String get create => 'Créer';

  @override
  String get close => 'Fermer';

  @override
  String get retry => 'Réessayer';

  @override
  String get ok => 'OK';

  @override
  String get welcomeTitle => 'Bienvenue sur ChatNyto';

  @override
  String get welcomeTagline =>
      'Des connexions simples et sûres entre les personnes, les agents IA et les objets connectés — avec ou sans internet. Tout est chiffré de bout en bout.';

  @override
  String get welcomeContinue => 'Accepter et continuer';

  @override
  String get setupTitle => 'Configurez votre profil';

  @override
  String get setupName => 'Votre nom';

  @override
  String get setupNameHelp =>
      'Visible par les personnes avec qui vous discutez';

  @override
  String get setupPassword => 'Mot de passe';

  @override
  String get setupPasswordHelp =>
      'Protège vos clés de chiffrement sur cet appareil';

  @override
  String get setupStart => 'Commencer à discuter';

  @override
  String get setupNameMissing => 'Veuillez saisir votre nom.';

  @override
  String get setupPasswordShort =>
      'Le mot de passe doit comporter au moins 8 caractères.';

  @override
  String get setupFootnote =>
      'Une identité sécurisée (vos clés de chiffrement) est créée automatiquement. Aucun compte, aucun numéro de téléphone, aucun serveur à configurer.';

  @override
  String get unlockTitle => 'Content de vous revoir';

  @override
  String get unlockButton => 'Déverrouiller';

  @override
  String get unlockWrong => 'Mot de passe incorrect, réessayez.';

  @override
  String get rememberMe => 'Se souvenir de moi';

  @override
  String get rememberMeHelp =>
      'Conserve votre mot de passe dans le coffre-fort de l\'appareil pour ouvrir ChatNyto directement sur vos discussions.';

  @override
  String get chatsEmpty =>
      'Aucune discussion pour l\'instant.\n\nTrouvez quelqu\'un dans l\'onglet Personnes, ou créez un groupe avec le bouton ci-dessous.';

  @override
  String get sayHello => 'Dites bonjour 👋';

  @override
  String get groupSubtitle => 'Groupe · rejoignable avec son nom';

  @override
  String get newGroup => 'Nouveau groupe';

  @override
  String get groupName => 'Nom du groupe';

  @override
  String get groupPassphrase => 'Phrase secrète (facultatif)';

  @override
  String get groupPassphraseHelp =>
      'Seules les personnes ayant la phrase secrète peuvent lire';

  @override
  String get renameChat => 'Renommer la discussion';

  @override
  String get renameGroup => 'Renommer le groupe';

  @override
  String get renameGroupHelp =>
      'Le nom est l\'adresse du groupe sur le réseau — tout le monde suit automatiquement.';

  @override
  String get wallpaperForChat => 'Fond d\'écran de cette discussion';

  @override
  String get useGlobalWallpaper => 'Utiliser le fond d\'écran général';

  @override
  String get deleteChat => 'Supprimer la discussion';

  @override
  String get leaveGroup => 'Quitter le groupe';

  @override
  String get deleteGroupForEveryone => 'Supprimer le groupe pour tout le monde';

  @override
  String get deleteLocalWarning =>
      'Supprime la discussion et ses messages sur cet appareil.';

  @override
  String get groupAdmins => 'Administrateurs du groupe';

  @override
  String get groupAdminsHelp =>
      'Les administrateurs peuvent renommer ce groupe et le supprimer pour tout le monde. Vous seul pouvez modifier cette liste.';

  @override
  String get viewIdentity => 'Voir l\'identité';

  @override
  String get messageHint => 'Message';

  @override
  String get sendPicture => 'Envoyer une image';

  @override
  String get choosePicture => 'Choisir une image';

  @override
  String get takePhoto => 'Prendre une photo';

  @override
  String get formatting => 'Mise en forme';

  @override
  String get photo => '📷 Photo';

  @override
  String get cannotSendLocked =>
      'Envoi impossible : déverrouillez d\'abord votre identité.';

  @override
  String get searchPeople => 'Rechercher une personne par son nom';

  @override
  String get connectedPeopleAppear =>
      'Connecté — les personnes apparaissent automatiquement';

  @override
  String get searchingNetwork => 'Recherche d\'un réseau…';

  @override
  String networksReachable(int count) {
    return '$count réseau(x) accessible(s)';
  }

  @override
  String get turnOnLoraHint =>
      'Allumez le boîtier LoRa ou rejoignez le même WiFi : les personnes autour de vous apparaîtront ici.';

  @override
  String get publicGroupsOnMesh => 'Groupes publics du réseau';

  @override
  String get publicGroupTapToJoin => 'Groupe public · touchez pour rejoindre';

  @override
  String verifiedKey(String fingerprint) {
    return 'Vérifié · $fingerprint';
  }

  @override
  String get identityChecked =>
      'La signature de cette identité a été vérifiée avec sa clé publique. Comparez l\'empreinte avec votre contact par un autre moyen pour une certitude totale.';

  @override
  String get message => 'Message';

  @override
  String get onlineNow => 'En ligne maintenant';

  @override
  String get nobodyYet => 'Personne sur le réseau pour l\'instant';

  @override
  String get networks => 'Réseaux';

  @override
  String get connected => 'connecté';

  @override
  String get disconnected => 'déconnecté';

  @override
  String get unreachable => 'Injoignable';

  @override
  String get communityPeople => 'Personnes';

  @override
  String get communityPeopleSub => 'Salons classiques avec messages enrichis';

  @override
  String get communityIot => 'Objets connectés';

  @override
  String get communityIotSub =>
      'Dialoguez en toute sécurité avec vos appareils';

  @override
  String get communityAi => 'Agents IA';

  @override
  String get communityAiSub =>
      'Claude, GPT, Gemini, un modèle local — avec votre propre clé';

  @override
  String get addBroker => 'Ajouter un serveur';

  @override
  String get editBroker => 'Modifier le serveur';

  @override
  String get brokerName => 'Nom';

  @override
  String get brokerHost => 'Adresse';

  @override
  String get brokerPort => 'Port';

  @override
  String get brokerUsername => 'Nom d\'utilisateur (facultatif)';

  @override
  String get brokerUsernameHelp =>
      'Uniquement pour les serveurs protégés par mot de passe';

  @override
  String get brokerPassword => 'Mot de passe (facultatif)';

  @override
  String get forgotPassword => 'Mot de passe oublié ?';

  @override
  String get otherAccounts => 'Autres comptes sur cet appareil';

  @override
  String get undo => 'Annuler';

  @override
  String get replace => 'Remplacer';

  @override
  String get signInWillBeRemoved =>
      'L\'identification enregistrée sera supprimée';

  @override
  String get signInSaved => 'Une identification est enregistrée pour ce réseau';

  @override
  String get needsSignIn => 'Ce réseau demande une identification';

  @override
  String get brokerPortOptional => 'Port (seulement s\'il n\'est pas standard)';

  @override
  String get brokerNameHelp =>
      'Facultatif. Laissé vide, le réseau se nomme lui-même.';

  @override
  String get brokerHostHelp =>
      'Juste l\'adresse du réseau — le serveur complète le reste. Un broker sur votre propre réseau peut être indiqué par son IP.';

  @override
  String get searchNetworks => 'Rechercher réseaux et personnes';

  @override
  String get connectAutomatically => 'Se connecter automatiquement';

  @override
  String get findBrokers => 'Trouver les serveurs de ce réseau';

  @override
  String get findBrokersHelp =>
      'Recherche les serveurs MQTT publics autour de vous, y compris le boîtier LoRa.';

  @override
  String get scanning => 'Analyse du réseau…';

  @override
  String get foundOnNetwork => 'Trouvés sur ce réseau';

  @override
  String get noBrokersFound => 'Aucun serveur trouvé sur ce réseau.';

  @override
  String get shareByQr => 'Partager par QR code';

  @override
  String get scanNetworkCode => 'Scanner un QR code de réseau';

  @override
  String get networkMap => 'Carte du réseau';

  @override
  String couldNotConnect(String name) {
    return 'Connexion impossible à $name';
  }

  @override
  String get settingsProfile => 'Profil';

  @override
  String get profilePicture => 'Photo de profil';

  @override
  String get displayName => 'Nom affiché';

  @override
  String get settingsSecurity => 'Sécurité';

  @override
  String get askPasswordEveryOpen =>
      'Demander le mot de passe à chaque ouverture';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get messageNotifications => 'Notifications de messages';

  @override
  String get messageNotificationsHelp =>
      'Vous prévient quand un message arrive et que la discussion n\'est pas ouverte.';

  @override
  String get notificationSound => 'Son de notification';

  @override
  String get soundChime => 'Carillon ChatNyto';

  @override
  String get soundSystem => 'Votre son par défaut';

  @override
  String get soundSilent => 'Silencieux';

  @override
  String get stayConnected => 'Rester connecté en arrière-plan';

  @override
  String get stayConnectedHelp =>
      'Continue de recevoir les messages quand l\'app est fermée, et redémarre après un redémarrage du téléphone. Affiche une notification permanente discrète.';

  @override
  String get settingsPreferences => 'Préférences';

  @override
  String get languageSystem => 'Langue du système';

  @override
  String get language => 'Langue';

  @override
  String get darkMode => 'Thème sombre';

  @override
  String get chatWallpaper => 'Fond d\'écran des discussions';

  @override
  String get appWallpaper => 'Fond d\'écran de l\'application';

  @override
  String get glassOpacity => 'Opacité du verre';

  @override
  String get glassOpacityHelp =>
      'À quel point les panneaux, bulles et barres laissent voir le fond. S\'applique partout et est mémorisé.';

  @override
  String get opacityVeryTransparent => 'Très transparent';

  @override
  String get opacityTransparent => 'Transparent';

  @override
  String get opacityBalanced => 'Équilibré';

  @override
  String get opacitySolid => 'Opaque';

  @override
  String get opacityVerySolid => 'Très opaque';

  @override
  String get aiAgents => 'Agents IA';

  @override
  String get aiNoAgents => 'Aucun agent pour l\'instant';

  @override
  String get aiNoAgentsHelp =>
      'Ajoutez un agent pour discuter avec Claude, GPT, Gemini, Mistral, un modèle Ollama local et d\'autres. Vous apportez votre clé ; elle reste dans le coffre-fort de l\'appareil.';

  @override
  String get aiAddAgent => 'Ajouter un agent';

  @override
  String get aiEditAgent => 'Modifier l\'agent';

  @override
  String get aiNewAgent => 'Nouvel agent';

  @override
  String get aiDeleteAgent => 'Supprimer l\'agent';

  @override
  String get aiAgentName => 'Nom de l\'agent';

  @override
  String get aiProvider => 'Fournisseur';

  @override
  String get aiModel => 'Modèle';

  @override
  String get aiModelHelp =>
      'N\'importe quel nom de modèle accepté par le fournisseur';

  @override
  String get aiServerAddress => 'Adresse du serveur (facultatif)';

  @override
  String get aiInstructions => 'Instructions (invite système)';

  @override
  String get aiCreativity => 'Créativité';

  @override
  String get aiToolsAllowed => 'Outils utilisables par cet agent';

  @override
  String get aiProvidersAndTools => 'Fournisseurs IA et outils';

  @override
  String get aiByokIntro =>
      'Apportez votre clé : ChatNyto s\'adresse à chaque fournisseur directement depuis votre appareil, et les clés ne quittent jamais son coffre-fort.';

  @override
  String get aiApiKey => 'Clé d\'API';

  @override
  String get aiApiKeyHelp =>
      'Conservée uniquement dans le coffre-fort de cet appareil';

  @override
  String get aiKeySaved => 'Clé enregistrée';

  @override
  String get aiNoKeyYet => 'Pas encore de clé';

  @override
  String get aiToolsMcp => 'Outils (MCP)';

  @override
  String get aiToolsMcpHelp =>
      'Les serveurs Model Context Protocol donnent des compétences à vos agents — lire des fichiers, interroger une base, piloter vos objets connectés. Activez-les agent par agent.';

  @override
  String get aiAddToolServer => 'Ajouter un serveur d\'outils';

  @override
  String get aiMcpEndpoint => 'URL du point d\'accès MCP';

  @override
  String get aiClearConversation => 'Effacer la conversation';

  @override
  String get aiThinking => 'réfléchit…';
}
