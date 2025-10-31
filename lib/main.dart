// ===================== main.dart — Chat-MVP (ULTRA FINAL) [Part 1/12] =====================
// يشمل خطة 1→9 كاملة: طبقة اجتماعية (ستوري/متابعة/بروفايل/بحث/DMs) + دردشة كاملة (تحرير/حذف/معاينة روابط…)
// + اقتصاد (Coins/VIP/Store/Subscriptions/Rewards/Gifts) + خصوصية وأمان + إشعارات Functions + أداء وكاش
// + لوحات إدارة + i18n + ثيمات VIP + دعم وسائط (صورة/فيديو/صوت/ملفات) + روابط عميقة.
// ملاحظة: هذا الملف يُرسل على 12 جزء. انسخ كل جزء في موضعه بالتتابع.

// ---------- Imports أساسية ----------
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cloud_firestore/cloud_firestore.dart' as cf;

// CODEX-BEGIN:BOOT_AUTH_PING
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Ensures Firebase is initialized, the user is signed in (anonymous if needed),
/// and Firestore is reachable. Also upserts a tiny boot config doc so the app
/// doesn't hang waiting for a missing document.
Future<void> ensureBootAuthAndPing() async {
  // Initialize Firebase once
  try {
    // If already initialized, this is a no-op in recent SDKs.
    await Firebase.initializeApp();
  } catch (_) {
    // Some environments may already be initialized; ignore.
  }

  // Ensure we have an authenticated user (anonymous is fine for boot).
  final auth = FirebaseAuth.instance;
  if (auth.currentUser == null) {
    await auth.signInAnonymously();
  }

  // Tiny ping to a known config doc to prevent "missing doc" hangs.
  final fs = FirebaseFirestore.instance;
  final cfgRef = fs.collection('store_config').doc('app');

  // Merge so we never overwrite real settings if they already exist.
  await cfgRef.set(<String, dynamic>{
    'bootPing': FieldValue.serverTimestamp(),
    // Safe defaults if the doc was missing
    'signupsEnabled': FieldValue.delete(), // keep minimal; do not force values
    'messagingEnabled': FieldValue.delete(),
  }, SetOptions(merge: true));

  // Read once to ensure permissions/connectivity are OK; fail fast if not.
  await cfgRef.get();
  // If we reached here, Firestore is reachable and auth is valid.
  // (We rely on existing app UI for navigation; no UI changes here.)
}
// CODEX-END:BOOT_AUTH_PING
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';

import 'package:flutter/services.dart'; // للروابط العميقة/الحافظة/الاذونات
// (للمعاينة لاحقًا قد نستخدم url_launcher/file_picker/cached_network_image إن أضفتها في pubspec)
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import 'coins_purchase.dart';
import 'services/coins_service.dart';
import 'services/payments_service.dart';
import 'services/invites_service.dart';
// CODEX-BEGIN:TRANSLATOR_IMPORT
import 'modules/translator/translator_service.dart';
// CODEX-END:TRANSLATOR_IMPORT
// CODEX-BEGIN:STORE_IMPORTS
import 'services/cache_service.dart';
import 'services/firestore_service.dart';
// CODEX-END:STORE_IMPORTS
// CODEX-BEGIN:WALLET_IMPORT
import 'modules/wallet/wallet_controller.dart';
// CODEX-END:WALLET_IMPORT
// CODEX-BEGIN:PRIVACY_IMPORTS
import 'modules/privacy/privacy_controller.dart';
import 'modules/privacy/privacy_settings_page.dart';
// CODEX-BEGIN:ADMIN_IMPORT
import 'modules/admin/admin_dashboard_page.dart';
// CODEX-END:ADMIN_IMPORT
import 'services/user_settings_service.dart';
// CODEX-END:PRIVACY_IMPORTS

// ---------- ألوان وهوية ----------
const kTeal = Color(0xFF00796B);      // الأساسي: أخضر مُزرّق
const kGold = Color(0xFFC8A951);      // VIP
const kGray = Color(0xFF6B7280);      // رمادي
const kVipGray = Color(0xFF9CA3AF);   // رمادي VIP
const kBgSoft = Color(0xFFF5F7F8);    // خلفية ناعمة

ThemeData buildLight(Color seed) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
  fontFamily: 'OpenSans',
);
ThemeData buildDark(Color seed) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
  fontFamily: 'OpenSans',
);

// ---------- Utils ----------
String shortTime(cf.Timestamp? ts) {
  if (ts == null) return '';
  final dt = ts.toDate();
  final now = DateTime.now();
  if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
    return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }
  return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2,'0')}';
}

cf.Timestamp normalizeTimestamp(dynamic raw, {DateTime? fallback}) {
  if (raw is cf.Timestamp) return raw;
  if (raw is DateTime) return cf.Timestamp.fromDate(raw);
  if (raw is num) return cf.Timestamp.fromMillisecondsSinceEpoch(raw.toInt());
  return cf.Timestamp.fromDate(fallback ?? DateTime.now());
}
String compactNumber(int n) {
  if (n >= 1000000) return '${(n/1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n/1000).toStringAsFixed(1)}K';
  return '$n';
}
String nowKeyDayUTC() => DateTime.now().toUtc().toIso8601String().substring(0,10); // YYYY-MM-DD

// ---------- Flags/Config ----------
class AppConfig {
  static const enableStories = true;
  static const enableDMs = true;
  static const enableFollow = true;
  static const enableSearch = true;
  static const enableLinkPreview = true;
  static const enableStickers = true;
  static const enableVipSubscriptions = true; // للـ IAP/Stripe لاحقًا
  static const enableCalls = false; // placeholder لويبRTC/مزود خارجي
}

// ---------- Theme State ----------
class AppTheme extends ChangeNotifier {
  bool dark = false;
  Color seed = kTeal;
  double textScale = 1.0;
  bool highContrast = false;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> load() async {
    try {
      final sp = await _prefs;
      dark = sp.getBool('theme.dark') ?? false;
      seed = Color(sp.getInt('theme.seed') ?? kTeal.value);
      textScale = sp.getDouble('theme.textScale') ?? 1.0;
      highContrast = sp.getBool('theme.contrast') ?? false;
      notifyListeners();
    } catch (err, stack) {
      debugPrint('AppTheme.load error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    }
  }
  Future<void> save() async {
    try {
      final sp = await _prefs;
      await sp.setBool('theme.dark', dark);
      await sp.setInt('theme.seed', seed.value);
      await sp.setDouble('theme.textScale', textScale);
      await sp.setBool('theme.contrast', highContrast);
    } catch (err, stack) {
      debugPrint('AppTheme.save error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    }
  }
  void toggleDark(bool v){ dark=v; unawaited(save()); notifyListeners(); }
  void setSeed(Color c){ seed=c; unawaited(save()); notifyListeners(); }
  void setTextScale(double v){ textScale=v; unawaited(save()); notifyListeners(); }
  void setContrast(bool v){ highContrast=v; unawaited(save()); notifyListeners(); }
}

// ---------- Auth/User State ----------
class AppUser extends ChangeNotifier {
  User? firebaseUser;
  Map<String, dynamic> profile = {};
  StreamSubscription? _sub;
  StreamSubscription<User?>? _authStream;

  Future<void> init() async {
    _authStream?.cancel();
    _authStream = FirebaseAuth.instance.userChanges().listen((u) async {
      try {
        firebaseUser = u;
        await _sub?.cancel();
        if (u != null) {
          _sub = cf.FirebaseFirestore.instance.collection('users').doc(u.uid)
              .snapshots().listen((doc) {
            profile = doc.data() ?? {};
            notifyListeners();
          });
          await _ensureDoc(u.uid);
        } else {
          profile = {};
        }
        notifyListeners();
      } catch (err, stack) {
        debugPrint('AppUser.init stream error: $err');
        FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      }
    }, onError: (Object err, StackTrace stack) {
      debugPrint('AppUser.init listen error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    });
  }

  Future<User> autoLogin() async {
    try {
      final cur = FirebaseAuth.instance.currentUser;
      if (cur != null) return cur;
      final cred = await FirebaseAuth.instance.signInAnonymously();
      final user = cred.user;
      if (user == null) {
        throw StateError('Anonymous sign-in returned null user');
      }
      await _ensureDoc(user.uid);
      return user;
    } catch (err, stack) {
      debugPrint('AppUser.autoLogin error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (err, stack) {
      debugPrint('AppUser.signOut error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      rethrow;
    }
  }

  Future<void> _ensureDoc(String uid) async {
    try {
      final ref = cf.FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await ref.get();
      if (!snap.exists) {
        final locales = WidgetsBinding.instance.platformDispatcher.locales;
        final deviceLang = locales.isNotEmpty ? locales.first.languageCode : 'en';
        await ref.set({
          'createdAt': cf.FieldValue.serverTimestamp(),
          'displayName': 'Guest',
          'bio': '',
          'link': '',
          'avatar': null,
          'cover': null,
          'vipLevel': 'Bronze',
          'coins': 0,
          'spentLifetime': 0,
          'followers': 0,
          'following': 0,
          'i18n': {'target': deviceLang, 'auto': true},
          'privacy': {
            'whoCanMessage': 'everyone',
            'whoCanInvite': 'everyone',
            'whoCanMention': 'everyone',
            'showLastSeen': true,
            'showOnline': true,
            'showProfilePic': true,
          'storyVisibility': 'everyone', // everyone/contacts/custom
        },
        'notify': {'dnd': false, 'mentionsOnly': true},
      }, cf.SetOptions(merge: true));
      // CODEX-BEGIN:PRIVACY_DEFAULTS
      await cf.FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('privacy')
          .set(PrivacySettings.defaults.toMap(), cf.SetOptions(merge: true));
      // CODEX-END:PRIVACY_DEFAULTS
      }
    } catch (err, stack) {
      debugPrint('AppUser._ensureDoc error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      rethrow;
    }
  }

  Future<void> updateProfile(Map<String, dynamic> patch) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Cannot update profile without authenticated user');
    }
    try {
      await cf.FirebaseFirestore.instance.collection('users').doc(user.uid).set(patch, cf.SetOptions(merge: true));
    } catch (err, stack) {
      debugPrint('AppUser.updateProfile error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      rethrow;
    }
  }

  @override
  void dispose() {
    _authStream?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

// ---------- Presence ----------
class PresenceService {
  final _rtdb = rtdb.FirebaseDatabase.instance.ref();
  StreamSubscription? _lc;
  Future<void> start(String uid) async {
    try {
      final pres = _rtdb.child('presence/$uid');
      final now = DateTime.now().millisecondsSinceEpoch;
      await pres.update({'online': true, 'lastActive': now});
      pres.onDisconnect().update({'online': false, 'lastActive': rtdb.ServerValue.timestamp});
      await _lc?.cancel();
      _lc = Stream.periodic(const Duration(minutes: 2)).listen((_) {
        cf.FirebaseFirestore.instance.collection('users').doc(uid)
            .set({'lastSeen': cf.FieldValue.serverTimestamp()}, cf.SetOptions(merge: true));
      });
    } catch (err, stack) {
      debugPrint('PresenceService.start error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    }
  }
  Future<void> stop(String uid) async {
    try {
      await _rtdb.child('presence/$uid').update({'online': false, 'lastActive': rtdb.ServerValue.timestamp});
      await cf.FirebaseFirestore.instance.collection('users').doc(uid)
          .set({'lastSeen': cf.FieldValue.serverTimestamp()}, cf.SetOptions(merge: true));
    } catch (err, stack) {
      debugPrint('PresenceService.stop error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    } finally {
      await _lc?.cancel();
      _lc = null;
    }
  }
}

// ---------- FCM (client) ----------
class NotificationsService {
  Future<void> init(String uid) async {
    try {
      final fm = FirebaseMessaging.instance;
      final settings = await fm.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Notifications permission denied');
      }
      final token = await fm.getToken();
      if (token != null && token.isNotEmpty) {
        await cf.FirebaseFirestore.instance.collection('users').doc(uid).set(
          {'fcmToken': token, 'fcmUpdatedAt': cf.FieldValue.serverTimestamp()},
          cf.SetOptions(merge: true),
        );
      }
      fm.onTokenRefresh.listen((t) {
        cf.FirebaseFirestore.instance.collection('users').doc(uid).set(
          {'fcmToken': t, 'fcmUpdatedAt': cf.FieldValue.serverTimestamp()},
          cf.SetOptions(merge: true),
        );
      }, onError: (Object err, StackTrace stack) {
        debugPrint('NotificationsService.onTokenRefresh error: $err');
        FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      });
      FirebaseMessaging.onMessage.listen((m) {
        debugPrint('FCM: ${m.notification?.title} - ${m.notification?.body}');
      }, onError: (Object err, StackTrace stack) {
        debugPrint('NotificationsService.onMessage error: $err');
        FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final roomId = m.data['roomId'];
        final dmId = m.data['dmId'];
        final storyUid = m.data['storyUid'];
        if (roomId != null) navigatorKey.currentState?.pushNamed('/room', arguments: roomId);
        if (dmId != null) navigatorKey.currentState?.pushNamed('/dm', arguments: dmId);
        if (storyUid != null) navigatorKey.currentState?.pushNamed('/stories', arguments: storyUid);
      }, onError: (Object err, StackTrace stack) {
        debugPrint('NotificationsService.onMessageOpenedApp error: $err');
        FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      });
    } catch (err, stack) {
      debugPrint('NotificationsService.init error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    }
  }
}

extension NotificationsDeepLinks on NotificationsService {
  void handleDeepLink(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final roomId = data['roomId'] as String?;
    final postId = data['postId'] as String?;

    switch (type) {
      case 'room':
        if (roomId != null) {
          navigatorKey.currentState?.pushNamed('/room', arguments: roomId);
        }
        break;
      case 'post':
        if (roomId != null && postId != null) {
          navigatorKey.currentState
              ?.pushNamed('/post', arguments: {'roomId': roomId, 'postId': postId});
        }
        break;
      default:
        navigatorKey.currentState?.pushNamed('/notifications');
    }
  }
}

// ---------- Navigator ----------
final navigatorKey = GlobalKey<NavigatorState>();

// ---------- Entry ----------
// CODEX-BEGIN:BOOT_AUTH_CALL
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ensureBootAuthAndPing(); // ensure auth + config before UI
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  await runZonedGuarded(() async {
    // تفعيل كاش Firestore للأداء (يمكن تخصيصه أكثر):
    cf.FirebaseFirestore.instance.settings = const cf.Settings(persistenceEnabled: true);
    runApp(const ChatUltraApp());
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error');
    FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
  });
}
// CODEX-END:BOOT_AUTH_CALL

class ChatUltraApp extends StatefulWidget {
  const ChatUltraApp({super.key});
  @override
  State<ChatUltraApp> createState() => _ChatUltraAppState();
}

class _ChatUltraAppState extends State<ChatUltraApp> with WidgetsBindingObserver {
  final presence = PresenceService();
  final fcm = NotificationsService();
  // CODEX-BEGIN:PRIVACY_PRESENCE_STATE
  bool? _lastPresenceVisible;
  // CODEX-END:PRIVACY_PRESENCE_STATE

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (state == AppLifecycleState.resumed) {
      // CODEX-BEGIN:PRIVACY_PRESENCE_RESUME
      if (_lastPresenceVisible == false) {
        unawaited(presence.stop(uid));
      } else {
        unawaited(presence.start(uid));
      }
      // CODEX-END:PRIVACY_PRESENCE_RESUME
    } else if (state == AppLifecycleState.paused) {
      unawaited(presence.stop(uid));
    }
  }

  // CODEX-BEGIN:PRIVACY_PRESENCE_HELPER
  void _handlePresenceVisibility(String uid, bool showOnline) {
    if (_lastPresenceVisible == showOnline) {
      return;
    }
    _lastPresenceVisible = showOnline;
    if (showOnline) {
      unawaited(presence.start(uid));
    } else {
      unawaited(presence.stop(uid));
    }
  }
  // CODEX-END:PRIVACY_PRESENCE_HELPER

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppTheme()..load()),
        ChangeNotifierProvider(create: (_) => AppUser()..init()),
        ChangeNotifierProvider(create: (_) => TranslatorService()..load()),
        // CODEX-BEGIN:PRIVACY_PROVIDER
        ChangeNotifierProxyProvider2<AppUser, AppTheme, PrivacySettingsController>(
          create: (_) => PrivacySettingsController(UserSettingsService()),
          update: (context, appUser, theme, controller) {
            final current = controller ?? PrivacySettingsController(UserSettingsService());
            current.onError = (error, stack) {
              debugPrint('PrivacySettingsController error: $error');
              FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
            };
            unawaited(current.attach(
              uid: appUser.firebaseUser?.uid,
              highContrastGetter: () => theme.highContrast,
              highContrastSetter: (value) {
                if (theme.highContrast != value) {
                  theme.setContrast(value);
                }
              },
            ));
            return current;
          },
        ),
        // CODEX-END:PRIVACY_PROVIDER
      ],
      child: Consumer3<AppTheme, AppUser, PrivacySettingsController>(
        builder: (_, theme, appUser, privacy, __) {
          final td = theme.dark ? buildDark(theme.seed) : buildLight(theme.seed);
          // CODEX-BEGIN:PRIVACY_PRESENCE_OBSERVER
          final uid = appUser.firebaseUser?.uid;
          if (uid == null) {
            _lastPresenceVisible = null;
          } else {
            final showOnline = privacy.settings?.showOnline ?? true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handlePresenceVisibility(uid, showOnline);
            });
          }
          // CODEX-END:PRIVACY_PRESENCE_OBSERVER
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaleFactor: theme.textScale),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,
              title: 'Chat Ultra',
              theme: theme.highContrast
                  ? td.copyWith(colorScheme: td.colorScheme.copyWith(
                    primary: kTeal, onPrimary: Colors.white,
                    secondary: td.colorScheme.secondary,
                    onSurface: Colors.black, surface: Colors.white))
                  : td,
              initialRoute: '/',
              routes: {
                '/': (_) => SplashPage(onReady: (u) async {
                      final user = await _.read<AppUser>().autoLogin();
                      // CODEX-BEGIN:PRIVACY_BOOTSTRAP
                      final settingsService = UserSettingsService();
                      final privacySettings = await settingsService.fetchPrivacy(user.uid);
                      _lastPresenceVisible = privacySettings.showOnline;
                      if (privacySettings.showOnline) {
                        await presence.start(user.uid);
                      } else {
                        await presence.stop(user.uid);
                      }
                      // CODEX-END:PRIVACY_BOOTSTRAP
                      await fcm.init(user.uid);
                      // تطبيق إعدادات الترجمة من الوثيقة
                      final tr = _.read<TranslatorService>();
                      // CODEX-BEGIN:TRANSLATOR_SETTINGS_BOOT
                      final settingsSnap = await cf.FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .collection('settings')
                          .doc('app')
                          .get();
                      final settingsData = settingsSnap.data();
                      if (settingsData != null) {
                        tr.applyRemoteSettings(settingsData);
                      }
                      // CODEX-END:TRANSLATOR_SETTINGS_BOOT
                      navigatorKey.currentState?.pushReplacementNamed('/home');
                    }),
                '/home': (_) => const HomePage(),
                '/login': (_) => const LoginPage(),
                '/appearance': (_) => const AppearancePage(),
                '/translator': (_) => const TranslatorSettingsPage(),
                '/buy-coins': (_) => const CoinsPurchasePage(),

                // غرف ومجتمعات + دردشة
                '/rooms': (_) => const RoomsTab(),
                '/room': (_) => const RoomPage(),
                '/rooms/create': (_) => const CreateRoomPage(),

                // DMs
                '/dm': (_) => const DMPage(),
                '/inbox': (_) => const InboxPage(),

                // ستوري
                '/stories': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  String? uidArg;
                  int initialIndex = 0;
                  if (args is String) {
                    uidArg = args;
                  } else if (args is Map) {
                    final dynamicUid = args['uid'];
                    final dynamicIndex = args['index'] ?? args['initialIndex'];
                    if (dynamicUid is String) {
                      uidArg = dynamicUid;
                    }
                    if (dynamicIndex is int) {
                      initialIndex = dynamicIndex;
                    }
                  }
                  if (uidArg != null && uidArg.isNotEmpty) {
                    return StoryViewerPage(uid: uidArg!, initialIndex: initialIndex);
                  }
                  return const StoriesHubPage();
                },
                '/story_create': (_) => const StoryCreatePage(),

                // متجر/محفظة/VIP
                '/store': (_) => const StorePage(),
                '/wallet': (_) => const WalletPage(),
                '/vip': (_) => const VIPHubPage(),

                // متابعة وبروفايل
                '/profile': (_) => const ProfilePage(),
                '/profile_edit': (_) => const ProfileEditPage(),
                '/people': (_) => const PeopleDiscoverPage(),

                // بحث شامل
                '/search': (_) => GlobalSearchPage(),

                // خصوصية/إعدادات
                '/privacy': (_) => const PrivacySettingsPage(),
                '/settings': (_) => const SettingsHubPage(),
                '/notifications': (_) => const NotificationCenterPage(),
                '/notify/prefs': (_) => const NotificationPrefsPage(),

                // إدارة
                '/admin': (_) => const AdminPortalPage(),
                '/admin/room': (_) => const AdminRoomPanelPage(),

                // منشورات وغرف
                '/post': (_) => const PostDetailPage(),
                '/room/settings': (_) => const RoomSettingsPage(),
                '/room/board': (_) => const RoomBoardPage(),
              },
            ),
          );
        },
      ),
    );
  }
}

// ---------- صفحات أساس ----------
class SplashPage extends StatelessWidget {
  final Future<void> Function(User?) onReady;
  const SplashPage({super.key, required this.onReady});
  Future<void> _boot() async {
    final u = FirebaseAuth.instance.currentUser;
    await Future.delayed(const Duration(milliseconds: 200));
    await onReady(u);
  }
  @override
  Widget build(BuildContext context) {
    _boot();
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});
  @override
  Widget build(BuildContext context) {
    final appUser = context.read<AppUser>();
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: FilledButton.icon(
          icon: const Icon(Icons.login_rounded),
          onPressed: () async {
            await appUser.autoLogin();
            navigatorKey.currentState?.pushReplacementNamed('/home');
          },
          label: const Text('Continue as Guest'),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).pushNamed('/buy-coins'),
        child: const Icon(Icons.monetization_on),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  int idx = 0;
  @override
  Widget build(BuildContext context) {
    // CODEX-BEGIN:ADMIN_BLOCK_HOME
    final appUser = context.watch<AppUser>();
    final bool blocked = appUser.profile['blocked'] == true;
    void showBlockedSnack() {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تقييد نشر القصص مؤقتاً من قبل الإدارة.')),
      );
    }
    // CODEX-END:ADMIN_BLOCK_HOME
    final tabs = const [
      RoomsTab(),        // مجتمع وغرف
      StorePage(),       // اقتصاد
      ProfilePage(),     // بروفايل
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Ultra'),
        actions: [
          IconButton(onPressed: ()=> navigatorKey.currentState?.pushNamed('/search'),
              icon: const Icon(Icons.search_rounded)),
          IconButton(onPressed: ()=> navigatorKey.currentState?.pushNamed('/appearance'),
              icon: const Icon(Icons.palette_rounded)),
          IconButton(onPressed: ()=> navigatorKey.currentState?.pushNamed('/translator'),
              icon: const Icon(Icons.translate_rounded)),
          IconButton(onPressed: ()=> navigatorKey.currentState?.pushNamed('/admin'),
              icon: const Icon(Icons.admin_panel_settings_rounded)),
        ],
      ),
      body: tabs[idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (v)=> setState(()=> idx=v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum), label: 'Rooms'),
          NavigationDestination(icon: Icon(Icons.store_outlined), selectedIcon: Icon(Icons.store), label: 'Store'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // CODEX-BEGIN:ADMIN_BLOCK_HOME_FAB
        onPressed: blocked
            ? showBlockedSnack
            : () => navigatorKey.currentState?.pushNamed('/story_create'),
        // CODEX-END:ADMIN_BLOCK_HOME_FAB
        icon: const Icon(Icons.brightness_5_rounded),
        label: const Text('Add Story'),
      ),
    );
  }
}

// إعدادات مظهر
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(value: theme.dark, onChanged: theme.toggleDark, title: const Text('Dark mode')),
          ListTile(
            title: const Text('Primary color (Teal)'),
            trailing: const CircleAvatar(backgroundColor: kTeal, radius: 12),
            onTap: () => theme.setSeed(kTeal),
          ),
          ListTile(
            title: const Text('Text size'),
            subtitle: Slider(
              value: theme.textScale, min: 0.9, max: 1.4, divisions: 5,
              label: theme.textScale.toStringAsFixed(1),
              onChanged: (v)=> theme.setTextScale(v),
            ),
          ),
          SwitchListTile(
            value: theme.highContrast,
            onChanged: (v) {
              theme.setContrast(v);
              // CODEX-BEGIN:PRIVACY_THEME_SYNC
              unawaited(context.read<PrivacySettingsController>().setHighContrastFromTheme(v));
              // CODEX-END:PRIVACY_THEME_SYNC
            },
            title: const Text('High contrast'),
          ),
        ],
      ),
    );
  }
}

// مترجم
class TranslatorSettingsPage extends StatelessWidget {
  const TranslatorSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final t = context.watch<TranslatorService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Translator')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Auto translate messages'),
            value: t.autoTranslateEnabled,
            // CODEX-BEGIN:TRANSLATOR_TOGGLE_HANDLER
            onChanged: (v) {
              t.setAuto(v);
            },
            // CODEX-END:TRANSLATOR_TOGGLE_HANDLER
          ),
          const SizedBox(height: 8),
          const Text('Target language'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _LangChip(code: 'ar', label: 'العربية', selected: t.targetLang=='ar', onTap: ()=> t.setLang('ar')),
              _LangChip(code: 'en', label: 'English', selected: t.targetLang=='en', onTap: ()=> t.setLang('en')),
              _LangChip(code: 'fr', label: 'Français', selected: t.targetLang=='fr', onTap: ()=> t.setLang('fr')),
              _LangChip(code: 'es', label: 'Español', selected: t.targetLang=='es', onTap: ()=> t.setLang('es')),
              _LangChip(code: 'de', label: 'Deutsch', selected: t.targetLang=='de', onTap: ()=> t.setLang('de')),
            ],
          ),
        ],
      ),
    );
  }
}
class _LangChip extends StatelessWidget {
  final String code, label; final bool selected; final VoidCallback onTap;
  const _LangChip({required this.code, required this.label, required this.selected, required this.onTap, super.key});
  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(label), selected: selected, onSelected: (_)=> onTap());
  }
}

class StorePage extends StatefulWidget {
  const StorePage({super.key});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  _StorePageState();

  final CoinsService _coinsService = CoinsService();
  final PaymentsService _paymentsService = PaymentsService();
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;

  // CODEX-BEGIN:STORE_STATE
  final FirestoreService _firestoreService = FirestoreService();
  final CacheService _cacheService = CacheService.instance;
  late final ScrollController _storeScrollController;
  final Set<String> _storeSeenIds = <String>{};
  List<StoreItem> _storeItems = <StoreItem>[];
  cf.DocumentSnapshot<Map<String, dynamic>>? _storeCursor;
  bool _loadingStore = false;
  bool _loadingMoreStore = false;
  bool _hasMoreStore = true;
  // CODEX-END:STORE_STATE

  static const List<int> _fallbackPackages = [100, 250, 600, 1500];

  late final TextEditingController _manualController;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  Stream<int>? _completedTodayStream;

  CoinsConfig? _config;
  PaymentProvider? _provider;
  Map<String, ProductDetails> _productDetails = {};
  bool _initializing = true;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _manualController = TextEditingController();
    _manualController.addListener(() => setState(() {}));
    // CODEX-BEGIN:STORE_INIT
    _storeScrollController = ScrollController();
    _storeScrollController.addListener(_handleStoreScroll);
    // CODEX-END:STORE_INIT
    _initialize();
    // CODEX-BEGIN:STORE_LOAD_INIT
    unawaited(_loadInitialStore());
    // CODEX-END:STORE_LOAD_INIT
  }

  Future<void> _initialize() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _completedTodayStream = _paymentsService.completedCoinsTodayStream(uid);
    }
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = null;
      });
    }

    final configResult = await safeRequest(
      () => _paymentsService.fetchConfig(),
      debugLabel: 'payments.fetchConfig',
    );

    if (!mounted) {
      return;
    }

    if (configResult is SafeFailure<CoinsConfig>) {
      setState(() {
        _initializing = false;
        _error = 'Failed to load the store. Please try again later.';
      });
      return;
    }

    final config = (configResult as SafeSuccess<CoinsConfig>).value;

    try {
      bool playAvailable = false;
      if (!kIsWeb && Platform.isAndroid) {
        playAvailable = await _inAppPurchase.isAvailable();
      }
      final provider =
          await PaymentsService.resolveProvider(playAvailable: playAvailable);
      final products = <String, ProductDetails>{};
      StreamSubscription<List<PurchaseDetails>>? sub;
      if (provider == PaymentProvider.play && playAvailable) {
        final productResult = await safeRequest(
          () => _inAppPurchase.queryProductDetails(config.playSkus.toSet()),
          debugLabel: 'iap.queryProductDetails',
        );
        if (productResult is SafeSuccess<ProductDetailsResponse>) {
          final response = productResult.value;
          if (response.error != null) {
            debugPrint('Play Billing query error: ${response.error}');
          }
          for (final detail in response.productDetails) {
            products[detail.id] = detail;
          }
          sub = _inAppPurchase.purchaseStream.listen(
            _onPurchasesUpdated,
            onError: (Object error, StackTrace stack) {
              debugPrint('Purchase stream error: $error');
              FlutterError.reportError(
                FlutterErrorDetails(exception: error, stack: stack),
              );
            },
          );
        } else if (productResult is SafeFailure<ProductDetailsResponse>) {
          debugPrint('Play Billing query failed: ${productResult.message}');
        }
      }

      if (!mounted) {
        await sub?.cancel();
        return;
      }

      await _purchaseSub?.cancel();
      _purchaseSub = sub;
      setState(() {
        _config = config;
        _provider = provider;
        _productDetails = products;
        _initializing = false;
        _error = null;
      });
    } catch (err, stack) {
      debugPrint('Store init failed: $err');
      FlutterError.reportError(
        FlutterErrorDetails(exception: err, stack: stack),
      );
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Failed to load the store. Please try again later.';
      });
    }
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    _manualController.dispose();
    // CODEX-BEGIN:STORE_DISPOSE
    _storeScrollController.removeListener(_handleStoreScroll);
    _storeScrollController.dispose();
    // CODEX-END:STORE_DISPOSE
    super.dispose();
  }

  int get _manualCoins => int.tryParse(_manualController.text.trim()) ?? 0;

  List<_CoinPackage> _packages(CoinsConfig config) {
    final items = <_CoinPackage>[];
    final seenIds = <String>{};

    // CODEX-BEGIN:STORE_PACKAGES
    if (_storeItems.isNotEmpty) {
      for (final storeItem in _storeItems) {
        final sku = (storeItem.sku ?? '').trim();
        final id = sku.isNotEmpty ? sku : storeItem.id;
        if (id.isEmpty || seenIds.contains(id)) continue;
        final coinsFromItem = storeItem.coins;
        final packMatch = config.packById(id);
        final coins = coinsFromItem > 0
            ? coinsFromItem
            : packMatch?.coins ?? config.coinsForSku(id);
        if (coins <= 0) continue;
        final label = (storeItem.label?.isNotEmpty == true)
            ? storeItem.label
            : packMatch?.label;
        final price = storeItem.price ?? packMatch?.price;
        items.add(
          _CoinPackage(
            id: id,
            coins: coins,
            label: label,
            price: price,
          ),
        );
        seenIds.add(id);
      }
    }
    // CODEX-END:STORE_PACKAGES

    for (final pack in config.packs) {
      if (pack.coins <= 0) continue;
      final id = pack.id.isNotEmpty ? pack.id : 'coins_${pack.coins}';
      items.add(
        _CoinPackage(
          id: id,
          coins: pack.coins,
          label: pack.label.isNotEmpty ? pack.label : null,
          price: pack.hasValidPrice ? pack.price : null,
        ),
      );
      seenIds.add(id);
    }

    for (final sku in config.playSkus) {
      if (seenIds.contains(sku)) continue;
      final pack = config.packById(sku);
      final coins = pack?.coins ?? config.coinsForSku(sku);
      if (coins > 0) {
        final price = pack?.hasValidPrice == true
            ? pack!.price
            : config.packForCoins(coins)?.price;
        items.add(
          _CoinPackage(
            id: sku,
            coins: coins,
            label: pack?.label.isNotEmpty == true ? pack!.label : null,
            price: price != null && price > 0 ? price : null,
          ),
        );
        seenIds.add(sku);
      }
    }

    if (items.isEmpty) {
      for (final amount in _fallbackPackages) {
        items.add(_CoinPackage(id: 'coins_$amount', coins: amount));
      }
    }
    return items;
  }

  // CODEX-BEGIN:STORE_LOADERS
  Future<void> _loadInitialStore() async {
    if (_loadingStore) return;
    if (mounted) {
      setState(() {
        _loadingStore = true;
      });
    }
    final cached = await _cacheService.getStoreFirstPage();
    if (!mounted) {
      return;
    }
    if (cached != null && cached.isNotEmpty) {
      final cachedItems = List<StoreItem>.from(cached);
      setState(() {
        _storeItems = cachedItems;
        _storeSeenIds
          ..clear()
          ..addAll(cachedItems.map((e) => e.id));
        if (_storeItems.isNotEmpty) {
          _error = null;
        }
      });
    }
    var success = true;
    try {
      success = await _retryFetchStore(reset: true);
    } finally {
      if (mounted) {
        setState(() {
          _loadingStore = false;
        });
      }
    }
    if (!mounted) {
      return;
    }
    if (!success && _storeItems.isEmpty) {
      setState(() {
        _error ??= 'Failed to load the store. Please try again later.';
      });
    }
  }

  Future<bool> _retryFetchStore({required bool reset}) async {
    if (reset) {
      _storeCursor = null;
      _hasMoreStore = true;
    }
    const maxAttempts = 3;
    Duration delay = const Duration(milliseconds: 500);
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final success = await _fetchStorePage(
        cursor: reset ? null : _storeCursor,
        replace: reset && attempt == 0,
      );
      if (success) {
        return true;
      }
      if (attempt < maxAttempts - 1) {
        await Future.delayed(delay);
        delay *= 2;
      }
    }
    return false;
  }

  Future<bool> _fetchStorePage({
    required cf.DocumentSnapshot<Map<String, dynamic>>? cursor,
    required bool replace,
  }) async {
    final result = await safeRequest(
      () => _firestoreService.fetchStorePage(
        startAfter: cursor,
        limit: 20,
      ),
      debugLabel: 'store.fetchPage',
    );

    if (!mounted) {
      return false;
    }

    if (result is SafeSuccess<StorePagePayload>) {
      final payload = result.value;
      final updatedItems =
          replace ? <StoreItem>[] : List<StoreItem>.from(_storeItems);
      final updatedIds =
          replace ? <String>{} : Set<String>.from(_storeSeenIds);

      for (final item in payload.items) {
        if (updatedIds.add(item.id)) {
          updatedItems.add(item);
        } else {
          final index =
              updatedItems.indexWhere((existing) => existing.id == item.id);
          if (index != -1) {
            updatedItems[index] = item;
          }
        }
      }

      setState(() {
        _storeItems = updatedItems;
        _storeSeenIds
          ..clear()
          ..addAll(updatedIds);
        _storeCursor = payload.lastDocument ?? cursor;
        _hasMoreStore = payload.hasMore;
        if (_storeItems.isNotEmpty) {
          _error = null;
        }
      });
      if (replace && payload.items.isNotEmpty) {
        unawaited(_cacheService.saveStoreFirstPage(payload.items));
      }
      return true;
    }

    if (result is SafeFailure<StorePagePayload>) {
      debugPrint('Store page fetch failed: ${result.message}');
      if (_storeItems.isEmpty) {
        setState(() {
          _error = 'Failed to load the store. Please try again later.';
        });
      }
    }
    return false;
  }

  void _handleStoreScroll() {
    if (!_storeScrollController.hasClients || _loadingMoreStore || !_hasMoreStore) {
      return;
    }
    final position = _storeScrollController.position;
    if (position.pixels >= position.maxScrollExtent - 120) {
      unawaited(_loadMoreStore());
    }
  }

  Future<void> _loadMoreStore() async {
    if (_loadingMoreStore || !_hasMoreStore) {
      return;
    }
    if (mounted) {
      setState(() {
        _loadingMoreStore = true;
      });
    }
    final success = await _retryFetchStore(reset: false);
    if (!mounted) {
      return;
    }
    if (!success && _storeItems.isEmpty) {
      setState(() {
        _error ??= 'Failed to load the store. Please try again later.';
      });
    }
    setState(() {
      _loadingMoreStore = false;
    });
  }

  Future<void> _onRetryPressed() async {
    if (_initializing || _loadingStore) {
      return;
    }
    setState(() {
      _error = null;
      _loadingStore = true;
    });
    try {
      await Future.wait([
        _initialize(),
        _retryFetchStore(reset: true),
      ]);
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingStore = false;
      });
    }
  }
  // CODEX-END:STORE_LOADERS

  String _estimatedPrice(CoinsConfig config, int coins) {
    final pack = config.packForCoins(coins);
    if (pack != null && pack.hasValidPrice) {
      return '${pack.price.toStringAsFixed(2)} ${config.currency}';
    }
    final estimate = config.estimateFiat(coins);
    if (estimate <= 0) return '--';
    return '≈ ${estimate.toStringAsFixed(2)} ${config.currency}';
  }

  String _providerLabel(PaymentProvider provider) {
    switch (provider) {
      case PaymentProvider.play:
        return 'Google Play Billing';
      case PaymentProvider.stripe:
        return 'Stripe Checkout';
    }
  }

  Uri _successUrl() {
    final projectId = Firebase.app().options.projectId;
    if (projectId == null || projectId.isEmpty) {
      return Uri.parse('https://example.com/payments/success');
    }
    return Uri.parse('https://$projectId.web.app/payments/success');
  }

  Uri _cancelUrl() {
    final projectId = Firebase.app().options.projectId;
    if (projectId == null || projectId.isEmpty) {
      return Uri.parse('https://example.com/payments/cancel');
    }
    return Uri.parse('https://$projectId.web.app/payments/cancel');
  }

  Future<void> _startPlayPurchase(_CoinPackage pkg) async {
    final details = _productDetails[pkg.id];
    if (details == null) {
      _showSnack('Product unavailable. Please refresh.', error: true);
      return;
    }
    if (!mounted) return;
    setState(() => _processing = true);
    final success = await _inAppPurchase.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: details),
      autoConsume: false,
    );
    if (!success && mounted) {
      setState(() => _processing = false);
      _showSnack('Unable to start Google Play checkout.', error: true);
    }
  }

  Future<void> _startStripeCheckout(int coins, {String? packageId}) async {
    if (coins <= 0) {
      _showSnack('Enter a valid amount of coins.', error: true);
      return;
    }
    if (!mounted) return;
    setState(() => _processing = true);
    try {
      final url = await _paymentsService.createStripeCheckout(
        coins: coins,
        successUrl: _successUrl(),
        cancelUrl: _cancelUrl(),
        packageId: packageId,
      );
      final launched =
          await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched) {
        _showSnack('Could not launch checkout URL.', error: true);
      }
    } on PaymentsLimitException {
      _showSnack('Daily limit reached. Try again tomorrow.', error: true);
    } catch (err, stack) {
      debugPrint('Stripe checkout error: $err');
      FlutterError.reportError(
        FlutterErrorDetails(exception: err, stack: stack),
      );
      _showSnack('Failed to start Stripe checkout.', error: true);
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _handlePlayPurchase(PurchaseDetails purchase) async {
    if (!mounted) return;
    setState(() => _processing = true);
    try {
      final token = purchase.verificationData.serverVerificationData;
      final productId = purchase.productID;
      final orderId = purchase.purchaseID;
      if (token.isEmpty) {
        throw StateError('Missing purchase token');
      }
      await _paymentsService.verifyPlayPurchase(
        purchaseToken: token,
        productId: productId,
        orderId: orderId,
      );
      _showSnack('Purchase received. Coins will appear shortly.');
    } on PaymentsLimitException {
      _showSnack('Daily limit reached. Try again tomorrow.', error: true);
    } catch (err, stack) {
      debugPrint('Play verification failed: $err');
      FlutterError.reportError(
        FlutterErrorDetails(exception: err, stack: stack),
      );
      _showSnack('Unable to verify Google Play purchase.', error: true);
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _onPurchasesUpdated(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          if (mounted) {
            setState(() => _processing = true);
          }
          break;
        case PurchaseStatus.error:
          if (mounted) {
            setState(() => _processing = false);
          }
          _showSnack(
            purchase.error?.message ?? 'Purchase failed.',
            error: true,
          );
          break;
        case PurchaseStatus.canceled:
          if (mounted) {
            setState(() => _processing = false);
          }
          _showSnack('Purchase cancelled.');
          break;
        case PurchaseStatus.purchased:
          await _handlePlayPurchase(purchase);
          break;
        case PurchaseStatus.restored:
          break;
      }
      if (purchase.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchase);
      }
    }
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            error ? theme.colorScheme.errorContainer : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(
          child: const Text('Please login to access the store.'),
        ),
      );
    }

    final config = _config;
    final provider = _provider;

    if (_initializing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Store')),
        body: Center(
          child: const CircularProgressIndicator(),
        ),
      );
    }

    if (config == null || provider == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Store')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? 'Unable to load store.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                // CODEX-BEGIN:STORE_RETRY_BUTTON
                onPressed:
                    (_initializing || _loadingStore) ? null : _onRetryPressed,
                // CODEX-END:STORE_RETRY_BUTTON
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final packages = _packages(config);
    return Scaffold(
      appBar: AppBar(title: const Text('Store')),
      body: StreamBuilder<int>(
        stream: _completedTodayStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Failed to load store status. Please retry.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    // CODEX-BEGIN:STORE_STATUS_RETRY
                    onPressed: (_initializing || _loadingStore)
                        ? null
                        : _onRetryPressed,
                    // CODEX-END:STORE_STATUS_RETRY
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final purchasedToday = snapshot.data ?? 0;
          final bool hasLimit = config.dailyLimitCoins > 0;
          final int? remaining = hasLimit
              ? math.max(0, config.dailyLimitCoins - purchasedToday)
              : null;
          final manualCoins = _manualCoins;
          final manualValid =
              manualCoins > 0 && (remaining == null || manualCoins <= remaining);
          final manualEstimate = _estimatedPrice(config, manualCoins);

          return ListView(
            // CODEX-BEGIN:STORE_SCROLL_CONTROLLER
            controller: _storeScrollController,
            // CODEX-END:STORE_SCROLL_CONTROLLER
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StreamBuilder<int>(
                    stream: _coinsService.coinsStream(uid),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Row(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(width: 16),
                            Text('Loading balance...'),
                          ],
                        );
                      }
                      final coins = snapshot.data ?? 0;
                      return Row(
                        children: [
                          const Icon(Icons.monetization_on_rounded,
                              color: kTeal),
                          const SizedBox(width: 12),
                          Text('Current balance: $coins coins'),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Conversion',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('1 ${config.currency} = ${config.rate} coins'),
                      const SizedBox(height: 4),
                      Text(
                        hasLimit
                            ? 'Remaining today: ${remaining ?? 0} / ${config.dailyLimitCoins} coins'
                            : 'Remaining today: Unlimited',
                      ),
                      const SizedBox(height: 4),
                      Text('Payment provider: ${_providerLabel(provider)}'),
                      if (hasLimit && (remaining ?? 0) <= 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Daily purchase limit reached. Please come back tomorrow.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .error,
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add coins manually',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _manualController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Coins',
                          helperText: manualCoins > 0
                              ? 'Estimated charge $manualEstimate'
                              : remaining == null
                                  ? 'Enter amount'
                                  : 'Enter amount (max $remaining)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: !_processing && manualValid
                            ? () => _startStripeCheckout(
                                  manualCoins,
                                  packageId: 'manual',
                                )
                            : null,
                        icon: _processing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.open_in_new),
                        label: const Text('Checkout with Stripe'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Manual top-ups are processed via Stripe Checkout.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Packages', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (packages.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No packages available at the moment.'),
                  ),
                )
              else
                ...packages.map(
                  (pkg) {
                    final product = _productDetails[pkg.id];
                    final subtitleLines = <String>[
                      'Coins: ${pkg.coins}',
                      if (pkg.price != null)
                        'Server price: ${pkg.price!.toStringAsFixed(2)} ${config.currency}',
                      if (provider == PaymentProvider.play) 'SKU: ${pkg.id}',
                      if (provider == PaymentProvider.play && product != null)
                        'Google Play price: ${product.price}',
                      'Estimated: ${_estimatedPrice(config, pkg.coins)}',
                    ];
                    return Card(
                      child: ListTile(
                        title: Text(pkg.displayLabel),
                        subtitle: Text(subtitleLines.join('\n')),
                        trailing: ElevatedButton(
                          onPressed: _processing || (remaining != null && remaining < pkg.coins)
                              ? null
                              : provider == PaymentProvider.play
                                  ? () => _startPlayPurchase(pkg)
                                  : () => _startStripeCheckout(
                                        pkg.coins,
                                        packageId: pkg.id,
                                      ),
                          child: _processing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  provider == PaymentProvider.play
                                      ? 'Buy'
                                      : 'Checkout',
                                ),
                        ),
                      ),
                    );
                  },
                ),
              // CODEX-BEGIN:STORE_PAGINATION_INDICATOR
              if (_loadingMoreStore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              // CODEX-END:STORE_PAGINATION_INDICATOR
            ],
          );
        },
      ),
    );
  }
}

class _CoinPackage {
  const _CoinPackage({
    required this.id,
    required this.coins,
    this.label,
    this.price,
  });

  final String id;
  final int coins;
  final String? label;
  final double? price;

  String get displayLabel =>
      (label != null && label!.isNotEmpty) ? label! : '${coins} coins';
}

// CODEX-BEGIN:WALLET_PAGE
class WalletPage extends StatelessWidget {
  const WalletPage({super.key});

  IconData _iconForType(String? type) {
    switch (type) {
      case 'purchase':
        return Icons.arrow_downward_rounded;
      case 'grant':
        return Icons.card_giftcard_rounded;
      case 'spend':
        return Icons.arrow_upward_rounded;
      default:
        return Icons.monetization_on_rounded;
    }
  }

  Future<void> _showAddBalanceSheet(
    BuildContext context,
    WalletController controller,
  ) async {
    if (controller.addingBalance) return;
    const packages = <_CoinPackage>[
      _CoinPackage(id: 'pack_100', coins: 100, label: '100 coins'),
      _CoinPackage(id: 'pack_500', coins: 500, label: '500 coins'),
      _CoinPackage(id: 'pack_1000', coins: 1000, label: '1000 coins'),
    ];

    final selected = await showModalBottomSheet<_CoinPackage>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final pack in packages)
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text(pack.displayLabel),
                  subtitle: Text('${pack.coins} coins'),
                  onTap: controller.addingBalance
                      ? null
                      : () => Navigator.of(sheetContext).pop(pack),
                ),
            ],
          ),
        );
      },
    );

    if (selected == null) {
      return;
    }

    final success = await controller.addBalance(
      packId: selected.id,
      amount: selected.coins,
    );

    if (!context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    if (success) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Balance updated successfully')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(controller.errorMessage ?? 'Failed to add balance')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Please login to view wallet.')),
      );
    }

    return ChangeNotifierProvider<WalletController>(
      create: (_) {
        final controller = WalletController(
          firestoreService: FirestoreService(),
          cacheService: CacheService.instance,
        );
        unawaited(controller.init(uid));
        return controller;
      },
      child: Builder(
        builder: (context) {
          final controller = context.watch<WalletController>();
          final summary = controller.summary;
          final balance = summary?.balance ?? 0;
          final vipTier = summary?.vipTier ?? 'Bronze';
          final transactions = controller.transactions;
          final dateFormat = DateFormat.yMMMd().add_jm();

          return Scaffold(
            appBar: AppBar(title: const Text('Wallet')),
            body: Column(
              children: [
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.account_balance_wallet_rounded, color: kTeal),
                            const SizedBox(width: 12),
                            if (summary == null && controller.loading)
                              const Expanded(
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Loading balance...'),
                                  ],
                                ),
                              )
                            else
                              Expanded(
                                child: Text('Balance: $balance coins'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('VIP Tier: $vipTier'),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: controller.addingBalance
                                ? null
                                : () => _showAddBalanceSheet(context, controller),
                            child: controller.addingBalance
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Add Balance'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (controller.errorMessage != null && transactions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      controller.errorMessage!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: controller.loading && transactions.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : transactions.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 160),
                                  Center(child: Text('No transactions yet')),
                                ],
                              )
                            : NotificationListener<ScrollNotification>(
                                onNotification: (notification) {
                                  if (notification.metrics.pixels >=
                                          notification.metrics.maxScrollExtent - 120 &&
                                      controller.hasMore &&
                                      !controller.loadingMore) {
                                    controller.loadMore();
                                  }
                                  return false;
                                },
                                child: ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  itemCount: transactions.length +
                                      (controller.loadingMore ? 1 : 0),
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    if (index >= transactions.length) {
                                      return const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 16),
                                        child: Center(
                                            child: CircularProgressIndicator()),
                                      );
                                    }
                                    final tx = transactions[index];
                                    final sign = tx.amount > 0 ? '+' : '';
                                    final dateStr = dateFormat.format(tx.createdAt.toLocal());
                                    return Card(
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .primaryContainer,
                                          child: Icon(
                                            _iconForType(tx.type),
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                        ),
                                        title: Text('$sign${tx.amount}'),
                                        subtitle: Text('${tx.type} • $dateStr'),
                                      ),
                                    );
                                  },
                                ),
                              ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
// CODEX-END:WALLET_PAGE

class VIPHubPage extends StatelessWidget {
  const VIPHubPage({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('VIP Hub (part 8)')));
}
class ProfileEditPage extends StatelessWidget { const ProfileEditPage({super.key}); @override Widget build(BuildContext c)=> const Scaffold(body: Center(child: Text('Profile Edit (part 7)'))); }
class SettingsHubPage extends StatelessWidget { const SettingsHubPage({super.key}); @override Widget build(BuildContext c)=> const Scaffold(body: Center(child: Text('Settings (part 9)'))); }
class AdminPanelPage extends StatelessWidget { const AdminPanelPage({super.key}); @override Widget build(BuildContext c)=> const Scaffold(body: Center(child: Text('Admin (part 9)'))); }
// ===================== main.dart — Chat-MVP (ULTRA FINAL) [Part 2/12] =====================
// Rooms & Communities: list/join/leave/create + basic metadata

class Room {
  final String id;
  final String name;
  final String about;
  final bool isPublic;
  final List<String> members;
  final int membersCount;
  final int messagesCount;
  final cf.Timestamp? lastMsgAt;
  final String? photo;

  Room({
    required this.id,
    required this.name,
    required this.about,
    required this.isPublic,
    required this.members,
    required this.membersCount,
    required this.messagesCount,
    required this.lastMsgAt,
    required this.photo,
  });

  factory Room.fromDoc(cf.DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final members = List<String>.from((d['members'] ?? []).cast<String>());
    final meta = (d['meta'] as Map?) ?? {};
    return Room(
      id: doc.id,
      name: d['name'] ?? doc.id,
      about: d['about'] ?? '',
      isPublic: d['public'] ?? true,
      members: members,
      membersCount: members.isNotEmpty ? members.length : (meta['members'] ?? 0),
      messagesCount: meta['messages'] ?? 0,
      lastMsgAt: meta['lastMsgAt'],
      photo: d['photo'],
    );
  }
}

Future<void> showRoomCreationDialog(BuildContext context) async {
  final name = TextEditingController();
  final about = TextEditingController();
  bool isPublic = true;
  final rootContext = context;
  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('إنشاء غرفة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الغرفة')),
            const SizedBox(height: 8),
            TextField(controller: about, decoration: const InputDecoration(labelText: 'نبذة'), maxLines: 2),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: isPublic,
              onChanged: (v) => setS(() => isPublic = v),
              title: const Text('عامّة (يمكن لأي شخص الانضمام)'),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) {
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  const SnackBar(content: Text('سجّل الدخول أولاً')),
                );
                return;
              }
              final r = cf.FirebaseFirestore.instance.collection('rooms').doc();
              await r.set({
                'name': name.text.trim().isEmpty ? 'Untitled Room' : name.text.trim(),
                'about': about.text.trim(),
                'public': isPublic,
                'photo': null,
                'members': [user.uid],
                'createdBy': user.uid,
                'createdAt': cf.FieldValue.serverTimestamp(),
                'meta': {'members': 1, 'messages': 0, 'lastMsgAt': cf.FieldValue.serverTimestamp()},
                'moderation': {'announcements': []},
              }, cf.SetOptions(merge: true));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('إنشاء'),
          ),
        ],
      ),
    ),
  );
}

class RoomsTab extends StatelessWidget {
  const RoomsTab({super.key});

  Future<void> _createRoomDialog(BuildContext context) async {
    await showRoomCreationDialog(context);
  }

  Future<void> _toggleMembership(String roomId, bool joined) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = cf.FirebaseFirestore.instance.collection('rooms').doc(roomId);
    await cf.FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = (snap.data() ?? {});
      final members = List<String>.from((data['members'] ?? []).cast<String>());
      if (joined) {
        members.remove(uid);
      } else {
        if (!members.contains(uid)) members.add(uid);
      }
      tx.update(ref, {'members': members, 'meta.members': members.length});
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final q = cf.FirebaseFirestore.instance
        .collection('rooms')
        .orderBy('meta.lastMsgAt', descending: true)
        .limit(100)
        .snapshots();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createRoomDialog(context),
        icon: const Icon(Icons.add_circle_rounded),
        label: const Text('غرفة جديدة'),
      ),
      body: StreamBuilder<cf.QuerySnapshot<Map<String, dynamic>>>(
        stream: q,
        builder: (context, snap) {
          if (!snap.hasData) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => _createRoomDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('إنشاء غرفة'),
                  ),
                ],
              ),
            );
          }
          final rooms = snap.data!.docs.map((d) => Room.fromDoc(d)).toList();
          if (rooms.isEmpty) {
            return Center(
              child: TextButton.icon(
                onPressed: () => _createRoomDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('أنشئ أول غرفة لك'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: rooms.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final r = rooms[i];
              final joined = r.members.contains(uid);
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: kTeal.withOpacity(0.12),
                    backgroundImage: (r.photo != null) ? NetworkImage(r.photo!) : null,
                    child: (r.photo == null) ? Text(r.name.isNotEmpty ? r.name.characters.first : '?') : null,
                  ),
                  title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${r.about}\n${compactNumber(r.membersCount)} عضو • ${compactNumber(r.messagesCount)} رسالة',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () async => _toggleMembership(r.id, joined),
                        child: Text(joined ? 'مغادرة' : 'انضمام'),
                      ),
                      FilledButton(
                        onPressed: () {
                          if (!joined && !(r.isPublic)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('الغرفة خاصة — انضم أولاً')),
                            );
                            return;
                          }
                          navigatorKey.currentState?.pushNamed('/room', arguments: r.id);
                        },
                        child: const Text('دخول'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
// ===================== main.dart — Chat-MVP (ULTRA FINAL) [Part 3/12] =====================
// Room Chat: text / image / video / audio + reply/pin/reactions + auto-translate + typing + pagination

enum MsgType { text, image, video, audio, file }

class ChatMessage {
  final String id;
  final String from;
  final MsgType type;
  final String? text;
  final String? mediaUrl;
  final String? thumbUrl;
  final int? durationMs; // for audio/video
  final String? replyTo;
  final Map<String, dynamic>? translated;
  final bool autoTranslated;
  final cf.Timestamp createdAt;
  final Map<String, int>? reactions;
  final bool pinned;

  ChatMessage({
    required this.id,
    required this.from,
    required this.type,
    required this.createdAt,
    this.text,
    this.mediaUrl,
    this.thumbUrl,
    this.durationMs,
    this.replyTo,
    this.translated,
    this.autoTranslated = false,
    this.reactions,
    this.pinned = false,
  });

  factory ChatMessage.fromDoc(cf.DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final createdRaw = d['createdAt'] ?? d['createdAtLocal'];
    return ChatMessage(
      id: doc.id,
      from: d['from'] ?? '',
      type: _parseType(d['type']),
      text: d['text'],
      mediaUrl: d['mediaUrl'],
      thumbUrl: d['thumbUrl'],
      durationMs: (d['durationMs'] as num?)?.toInt(),
      replyTo: d['replyTo'],
      translated: (d['translated'] as Map?)?.cast<String, dynamic>(),
      autoTranslated: d['autoTranslated'] == true,
      createdAt: normalizeTimestamp(createdRaw, fallback: DateTime.now()),
      reactions: (d['reactions'] as Map?)?.map((k, v) => MapEntry(k.toString(), (v ?? 0) as int)),
      pinned: d['pinned'] == true,
    );
  }

  static MsgType _parseType(dynamic v) {
    switch (v) {
      case 'image': return MsgType.image;
      case 'video': return MsgType.video;
      case 'audio': return MsgType.audio;
      case 'file':  return MsgType.file;
      default:      return MsgType.text;
    }
  }
}

// ---------------------- Helpers: Storage Upload ----------------------
class _RoomUploader {
  final String roomId;
  _RoomUploader(this.roomId);

  Future<(String url, String? thumb, int? durationMs)> uploadImage(XFile file) async {
    final ref = FirebaseStorage.instance.ref('rooms/$roomId/images/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
    final bytes = await file.readAsBytes();
    await ref.putData(bytes, SettableMetadata(contentType: 'image/${file.path.split('.').last}'));
    final url = await ref.getDownloadURL();
    return (url, null, null);
  }

  Future<(String url, String? thumb, int? durationMs)> uploadVideo(XFile file) async {
    final ref = FirebaseStorage.instance.ref('rooms/$roomId/videos/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
    await ref.putFile(File(file.path), SettableMetadata(contentType: 'video/${file.path.split('.').last}'));
    final url = await ref.getDownloadURL();
    // (اختياري): توليد thumbnail عبر Functions لاحقًا.
    return (url, null, null);
  }

  Future<(String url, String? thumb, int? durationMs)> uploadAudio(File file, {int? durationMs}) async {
    final ref = FirebaseStorage.instance.ref('rooms/$roomId/audios/${DateTime.now().millisecondsSinceEpoch}.m4a');
    await ref.putFile(file, SettableMetadata(contentType: 'audio/m4a'));
    final url = await ref.getDownloadURL();
    return (url, null, durationMs);
  }
}

// ---------------------- Room Page ----------------------
class RoomPage extends StatefulWidget {
  const RoomPage({super.key});
  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  String get roomId {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && args.isNotEmpty) return args;
    if (args is Map && args['roomId'] is String) return args['roomId'] as String;
    return 'room_demo';
  }
  String? _currentRoomId;
  final _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  String? _replyToId;

  // pagination
  cf.DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  final List<ChatMessage> _buffer = [];
  StreamSubscription<cf.QuerySnapshot<Map<String, dynamic>>>? _liveSub;

  // typing
  Timer? _typingTimer;
  void _setTyping(bool typing) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = rtdb.FirebaseDatabase.instance.ref('typing/$roomId/$uid');
    if (typing) {
      ref.set(true);
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 4), ()=> ref.set(false));
    } else {
      ref.set(false);
    }
  }

  // init
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rid = roomId;
    if (_currentRoomId != rid) {
      _currentRoomId = rid;
      // CODEX-BEGIN:ROOM_TRANSLATION_OVERRIDE_SYNC
      unawaited(_loadRoomTranslationOverrides(rid));
      // CODEX-END:ROOM_TRANSLATION_OVERRIDE_SYNC
      _subscribeLive();
    }
  }

  // CODEX-BEGIN:ROOM_TRANSLATION_OVERRIDE_HELPER
  Future<void> _loadRoomTranslationOverrides(String rid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    try {
      final snap = await cf.FirebaseFirestore.instance
          .collection('rooms')
          .doc(rid)
          .collection('members')
          .doc(user.uid)
          .get();
      if (!mounted) {
        return;
      }
      final data = snap.data();
      context.read<TranslatorService>().applyRoomOverride(
            rid,
            auto: data?['autoTranslateOverride'] as bool?,
            targetLang: (data?['targetLangOverride'] as String?),
          );
    } catch (err, stack) {
      debugPrint('RoomPage._loadRoomTranslationOverrides error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    }
  }
  // CODEX-END:ROOM_TRANSLATION_OVERRIDE_HELPER

  void _subscribeLive() {
    _liveSub?.cancel();
    final q = cf.FirebaseFirestore.instance.collection('rooms').doc(roomId)
      .collection('messages').orderBy('createdAt', descending: true).limit(30);
    _liveSub = q.snapshots(includeMetadataChanges: true).listen((snap) {
      final docs = snap.docs.map(ChatMessage.fromDoc).toList();
      docs.sort((a, b) {
        if (a.pinned && !b.pinned) return -1;
        if (!a.pinned && b.pinned) return 1;
        return b.createdAt.compareTo(a.createdAt);
      });
      setState(() {
        _buffer
          ..clear()
          ..addAll(docs);
        _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      });
    });
  }

  Future<void> _loadMore() async {
    if (_lastDoc == null) return;
    final q = await cf.FirebaseFirestore.instance.collection('rooms').doc(roomId)
      .collection('messages').orderBy('createdAt', descending: true).startAfterDocument(_lastDoc!).limit(30).get();
    if (q.docs.isEmpty) return;
    final more = q.docs.map(ChatMessage.fromDoc).toList();
    more.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    setState(() {
      _buffer.addAll(more);
      _lastDoc = q.docs.last;
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _liveSub?.cancel();
    unawaited(() async {
      try {
        await _recorder.dispose();
      } catch (err, stack) {
        debugPrint('RoomPage recorder dispose error: $err');
        FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      }
    }());
    // CODEX-BEGIN:ROOM_TRANSLATION_CLEAR
    final rid = _currentRoomId;
    if (rid != null) {
      context.read<TranslatorService>().clearRoomOverride(rid);
    }
    // CODEX-END:ROOM_TRANSLATION_CLEAR
    super.dispose();
  }

  // ---------------------- Message Actions ----------------------
  Future<bool> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final fs = cf.FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser!;

    final ref = fs.collection('rooms').doc(roomId).collection('messages');

    final memberDoc = await fs
        .collection('rooms')
        .doc(roomId)
        .collection('members')
        .doc(user.uid)
        .get();
    final rawMuted = memberDoc.data()?['mutedUntil'];
    int mutedUntil = 0;
    if (rawMuted is num) {
      mutedUntil = rawMuted.toInt();
    } else if (rawMuted is cf.Timestamp) {
      mutedUntil = rawMuted.millisecondsSinceEpoch;
    }
    if (mutedUntil > DateTime.now().millisecondsSinceEpoch) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أنت مكتوم مؤقتًا ولا يمكنك الإرسال حالياً.')),
      );
      return false;
    }

    final docRef = ref.doc();
    final payload = {
      'id': docRef.id,
      'uid': user.uid,
      'from': user.uid,
      'senderId': user.uid,
      'type': 'text',
      'text': trimmed,
      'replyTo': _replyToId,
      'createdAt': cf.FieldValue.serverTimestamp(),
      'createdAtLocal': DateTime.now().millisecondsSinceEpoch,
      'reactions': {},
      'pinned': false,
      'visibility': 'everyone',
    };

    try {
      await docRef.set(payload);
      await fs.collection('rooms').doc(roomId).set({
        'lastMessage': trimmed,
        'lastAt': cf.FieldValue.serverTimestamp(),
        'lastMessageAt': cf.FieldValue.serverTimestamp(),
        'lastMessageId': docRef.id,
        'meta': {
          'lastMsgAt': cf.FieldValue.serverTimestamp(),
          'messages': cf.FieldValue.increment(1),
        },
      }, cf.SetOptions(merge: true));
      if (mounted) setState(() => _replyToId = null);
      return true;
    } catch (err, stack) {
      debugPrint('RoomPage send error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذّر إرسال الرسالة، حاول مرة أخرى.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _sendMedia(MsgType type, {String? url, String? thumb, int? duration}) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = cf.FirebaseFirestore.instance.collection('rooms').doc(roomId).collection('messages');
    await ref.add({
      'type': switch (type) { MsgType.image=>'image', MsgType.video=>'video', MsgType.audio=>'audio', _=>'file' },
      'from': uid,
      'mediaUrl': url,
      'thumbUrl': thumb,
      'durationMs': duration,
      'replyTo': _replyToId,
      'createdAt': cf.FieldValue.serverTimestamp(),
      'reactions': {},
      'pinned': false,
    });
    await cf.FirebaseFirestore.instance.collection('rooms').doc(roomId)
      .set({'meta': {'lastMsgAt': cf.FieldValue.serverTimestamp(), 'messages': cf.FieldValue.increment(1)}}, cf.SetOptions(merge: true));
    setState(()=> _replyToId = null);
  }

  Future<void> _toggleReaction(String msgId, String emoji) async {
    final msgRef = cf.FirebaseFirestore.instance.collection('rooms').doc(roomId)
        .collection('messages').doc(msgId);
    await cf.FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(msgRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
      reactions[emoji] = ((reactions[emoji] ?? 0) as int) + 1;
      tx.update(msgRef, {'reactions': reactions});
    });
  }

  Future<void> _pin(String msgId, bool pinned) async {
    await cf.FirebaseFirestore.instance.collection('rooms').doc(roomId)
      .collection('messages').doc(msgId).update({'pinned': pinned});
  }

  Future<void> _delete(String msgId) async {
    await cf.FirebaseFirestore.instance.collection('rooms').doc(roomId)
      .collection('messages').doc(msgId).delete();
  }

  // ---------------------- Pickers ----------------------
  Future<void> _pickImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    final up = _RoomUploader(roomId);
    final (url, thumb, _) = await up.uploadImage(x);
    await _sendMedia(MsgType.image, url: url, thumb: thumb);
  }

  Future<void> _pickVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 2));
    if (x == null) return;
    final up = _RoomUploader(roomId);
    final (url, thumb, dur) = await up.uploadVideo(x);
    await _sendMedia(MsgType.video, url: url, thumb: thumb, duration: dur);
  }

  Future<void> _toggleRecord() async {
    if (!_recording) {
      try {
        final hasPermission = await _recorder.hasPermission();
        if (!hasPermission) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('لا يوجد إذن الميكروفون')));
          return;
        }
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: path,
        );
        if (!mounted) return;
        setState(()=> _recording = true);
      } catch (err, stack) {
        debugPrint('RoomPage._toggleRecord start error: $err');
        FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر بدء التسجيل الصوتي')),
        );
      }
    } else {
      String? path;
      try {
        path = await _recorder.stop();
      } catch (err, stack) {
        debugPrint('RoomPage._toggleRecord stop error: $err');
        FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذّر إيقاف التسجيل الصوتي')),
          );
        }
      } finally {
        if (mounted) {
          setState(()=> _recording = false);
        } else {
          _recording = false;
        }
      }
      if (!mounted || path == null) return;
      final f = File(path);
      final up = _RoomUploader(roomId);
      final durMs = await _probeAudioDurationMs(f.path);
      final (url, _, __) = await up.uploadAudio(f, durationMs: durMs);
      await _sendMedia(MsgType.audio, url: url, duration: durMs);
    }
  }

  Future<int?> _probeAudioDurationMs(String p) async {
    try {
      final player = AudioPlayer();
      await player.setSourceDeviceFile(p);
      final dur = await player.getDuration();
      await player.dispose();
      return dur?.inMilliseconds;
    } catch (_) { return null; }
  }

  Future<void> _startVoiceRecording() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تسجيل الصوت سيتم لاحقًا')),
    );
  }

  // ---------------------- UI ----------------------
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final typingRef = rtdb.FirebaseDatabase.instance.ref('typing/$roomId');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Room'),
        actions: [
          IconButton(
            tooltip: 'تثبيت/إلغاء تثبيت آخر رسالة',
            onPressed: () async {
              final last = await cf.FirebaseFirestore.instance.collection('rooms').doc(roomId)
                  .collection('messages').orderBy('createdAt', descending: true).limit(1).get();
              if (last.docs.isNotEmpty) {
                final cur = last.docs.first.data()['pinned'] == true;
                await _pin(last.docs.first.id, !cur);
              }
            },
            icon: const Icon(Icons.push_pin_outlined),
          ),
          IconButton(
            onPressed: () => navigatorKey.currentState?.pushNamed(
              '/room/settings',
              arguments: roomId,
            ),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'إعدادات الغرفة',
          ),
          IconButton(
            onPressed: () => navigatorKey.currentState?.pushNamed(
              '/room/board',
              arguments: roomId,
            ),
            icon: const Icon(Icons.dashboard_rounded),
            tooltip: 'لوحة المنشورات',
          ),
        ],
      ),
      body: Column(
        children: [
          // typing indicator
          StreamBuilder<rtdb.DatabaseEvent>(
            stream: typingRef.onValue,
            builder: (context, snap) {
              if (snap.data?.snapshot.value is Map) {
                final m = Map<String, dynamic>.from(snap.data!.snapshot.value as Map);
                final others = m.keys.where((k) => k != uid && m[k] == true).toList();
                if (others.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 2),
                    child: Text('…يكتب الآن', style: TextStyle(color: Colors.grey[600])),
                  );
                }
              }
              return const SizedBox.shrink();
            },
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadMore,
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _buffer.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == _buffer.length) {
                    return TextButton(
                      onPressed: _loadMore,
                      child: const Text('تحميل المزيد'),
                    );
                  }
                  final m = _buffer[i];
                  final mine = m.from == uid;
                  return _MessageBubble(
                    message: m,
                    mine: mine,
                    onReact: (e)=> _toggleReaction(m.id, e),
                    onReply: ()=> setState(()=> _replyToId = m.id),
                    onPin: ()=> _pin(m.id, !m.pinned),
                    onDelete: ()=> _delete(m.id),
                  );
                },
              ),
            ),
          ),
          if (_replyToId != null)
            _ReplyPreview(onCancel: ()=> setState(()=> _replyToId = null)),
        ],
      ),
      bottomNavigationBar: _ChatInput(
        roomId: roomId,
        onSendText: (txt) => _sendMessage(txt),
        onPickImage: _pickImage,
        onPickVideo: _pickVideo,
        onStartVoice: _startVoiceRecording,
        recording: _recording,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => navigatorKey.currentState?.pushNamed('/rooms/create'),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

// -------- Enhanced MessageBubble (REPLACE old one) ----------
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final void Function(String emoji) onReact;
  final VoidCallback onReply;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  const _MessageBubble({
    required this.message, required this.mine,
    required this.onReact, required this.onReply, required this.onPin, required this.onDelete, super.key});

  bool _hasUrl(String? t) => t != null && t.contains(RegExp(r'https?://', caseSensitive: false));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = mine ? cs.primaryContainer : cs.surfaceVariant;
    final BoxBorder? border = mine ? Border.all(color: kTeal.withOpacity(0.35)) : null;
    // CODEX-BEGIN:COMPILE_FIX::messagebubble-roomId
    final String roomId = (() {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) return args;
      if (args is Map && args['roomId'] is String) return args['roomId'] as String;
      return 'room_demo';
    })();
    // CODEX-END:COMPILE_FIX::messagebubble-roomId
    // CODEX-BEGIN:TRANSLATOR_RENDER
    final tr = context.watch<TranslatorService>();
    final baseText = message.text ?? '';
    final roomLang = tr.effectiveLangForRoom(roomId);
    final autoEnabled = tr.isAutoEnabledForRoom(roomId);
    final showOriginalOnly = tr.isShowingOriginal(message.id);
    String? translated;
    if (!showOriginalOnly && autoEnabled && baseText.isNotEmpty) {
      translated = tr.getCachedTranslation(message.id, roomLang);
      translated ??= message.translated?[roomLang]?.toString();
      if (translated != null && translated.trim().isNotEmpty) {
        if (translated.trim() != baseText.trim()) {
          tr.primeTranslation(message.id, roomLang, translated);
        } else {
          translated = null;
        }
      } else {
        tr.requestTranslation(roomId: roomId, messageId: message.id, text: baseText);
      }
    }
    final bool showTranslatedText =
        !showOriginalOnly && translated != null && translated.trim().isNotEmpty;

    VoidCallback? showOriginalAction;
    VoidCallback? showTranslationAction;
    if (autoEnabled && baseText.isNotEmpty) {
      if (showTranslatedText) {
        showOriginalAction = () {
          tr.showOriginal(message.id);
        };
      } else if (showOriginalOnly) {
        showTranslationAction = () {
          tr.showTranslation(message.id);
        };
      }
    }
    // CODEX-END:TRANSLATOR_RENDER

    Widget content;
    switch (message.type) {
      case MsgType.image:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.mediaUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(message.mediaUrl!, fit: BoxFit.cover),
              ),
            if ((message.text?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 6),
              Text(message.text!),
              if (_hasUrl(message.text)) _LinkPreview(text: message.text!),
            ]
          ],
        );
        break;
      case MsgType.video:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.mediaUrl != null) _VideoThumb(url: message.mediaUrl!),
            if ((message.text?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 6),
              Text(message.text!),
              if (_hasUrl(message.text)) _LinkPreview(text: message.text!),
            ]
          ],
        );
        break;
      case MsgType.audio:
        content = _AudioTile(url: message.mediaUrl ?? '', durMs: message.durationMs);
        break;
      case MsgType.file:
        content = Row(children: [
          const Icon(Icons.insert_drive_file_rounded),
          const SizedBox(width: 8),
          Expanded(child: Text(message.text ?? 'File')),
        ]);
        break;
      default:
        content = (showTranslatedText)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(translated!, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(baseText, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  if (_hasUrl(baseText)) _LinkPreview(text: baseText),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(baseText),
                  if (_hasUrl(baseText)) _LinkPreview(text: baseText),
                ],
              );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          showModalBottomSheet(
            context: context,
            builder: (_) => _MessageActions(
              onReact: onReact,
              onReply: onReply,
              onPin: onPin,
              onDelete: onDelete,
              pinned: message.pinned,
              // CODEX-BEGIN:TRANSLATOR_ACTIONS
              onShowOriginal: showOriginalAction,
              onShowTranslation: showTranslationAction,
              // CODEX-END:TRANSLATOR_ACTIONS
            ),
          );
        },
        onDoubleTap: () async {
          if (mine && message.type == MsgType.text && (message.text?.isNotEmpty ?? false)) {
            await showEditMessageDialog(context,
              roomId: roomId, msgId: message.id, initialText: message.text!);
          }
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: border),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.replyTo != null)
                _QuotedMessageRich(roomId: roomId, msgId: message.replyTo!),
              content,
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(shortTime(message.createdAt), style: TextStyle(color: Colors.grey[600], fontSize: 10)),
                  if (message.pinned) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.push_pin, size: 12, color: kGold),
                  ],
                  if ((message is ChatMessage) && (messageTextEdited(message))) ...[
                    const SizedBox(width: 6),
                    const Text('edited', style: TextStyle(fontSize: 10, color: kGray)),
                  ],
                ],
              ),
              if ((message.reactions ?? {}).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(spacing: 6, children: [
                    for (final e in message.reactions!.entries)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black12, borderRadius: BorderRadius.circular(999)),
                        child: Text('${e.key} ${e.value}'),
                      )
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool messageTextEdited(ChatMessage m) {
    // يعتمد على وجود الحقل 'edited' في الوثيقة
    // بما أن ChatMessage لا يحمل هذا الحقل مباشرة، نعتمد إشارة النص على الأقل:
    // سنقرأه ضمن الواجهة عبر 'edited' عند العرض إن أضفت له لاحقًا في الموديل.
    // هنا سنعرض الوسم عندما لا يكون createdAt == editedAt (يحتاج تعديل الموديل لاحقًا)،
    // مؤقتًا نجعله دائمًا false إلا إذا تم تعديل الحقل في الوثيقة ويُسترجع في واجهة أخرى.
    return false;
  }
}

class _ReplyPreview extends StatelessWidget {
  final VoidCallback onCancel;
  const _ReplyPreview({super.key, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.reply, size: 16),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'الرد على رسالة...',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(onPressed: onCancel, icon: const Icon(Icons.close)),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Chat input with keyboard submit + send button
class _LegacyChatInput extends StatefulWidget {
  const _LegacyChatInput({super.key, required this.onSend});
  final Future<bool> Function(String text) onSend;

  @override
  State<_LegacyChatInput> createState() => _LegacyChatInputState();
}

class _LegacyChatInputState extends State<_LegacyChatInput> {
  final TextEditingController _c = TextEditingController();
  final FocusNode _f = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    if (_sending) return;
    final t = _c.text.trim();
    if (t.isEmpty) return;
    setState(() => _sending = true);
    try {
      final success = await widget.onSend(t);       // calls host _sendMessage
      if (success && mounted) {
        _c.clear();
        _f.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            // مثال: زر مرفقات (اتركه غير موصول لو ماعندك باكر)
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: _sending ? null : () { /* TODO: open picker if exists */ },
            ),
            Expanded(
              child: TextField(
                controller: _c,
                focusNode: _f,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(), // إرسال من الكيبورد
                decoration: InputDecoration(
                  hintText: 'اكتب رسالة...',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // زر الإرسال يشتغل فقط لما يكون النص غير فارغ
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _c,
              builder: (context, v, _) {
                final canSend = v.text.trim().isNotEmpty && !_sending;
                return IconButton.filled(
                  onPressed: canSend ? _handleSend : null,
                  icon: const Icon(Icons.send_rounded),
                  color: cs.onPrimary,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────── Chat Input (drop-in) ─────────────────
class _ChatInput extends StatefulWidget {
  const _ChatInput({
    required this.roomId,
    required this.onSendText,
    required this.onPickImage,
    required this.onPickVideo,
    required this.onStartVoice,
    this.recording = false,
  });

  final String roomId;
  final Future<bool> Function(String text) onSendText;
  final Future<void> Function() onPickImage;
  final Future<void> Function() onPickVideo;
  final Future<void> Function() onStartVoice;
  final bool recording;

  @override
  State<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<_ChatInput> {
  final messageController = TextEditingController();
  final _focus = FocusNode();
  bool _canSend = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    messageController.addListener(_onChanged);
  }

  @override
  void dispose() {
    messageController.removeListener(_onChanged);
    messageController.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    final enable = messageController.text.trim().isNotEmpty;
    if (enable != _canSend) setState(() => _canSend = enable);
  }

  Future<void> sendTextMessage(String roomId) async {
    if (_sending) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in')),
        );
      }
      return;
    }
    final text = messageController.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      await cf.FirebaseFirestore.instance
          .collection('rooms')
          .doc(roomId)
          .collection('messages')
          .add({
        'text': text,
        'senderId': user.uid,
        'createdAt': cf.FieldValue.serverTimestamp(),
        'type': 'text',
      });
      messageController.clear();
      if (mounted) {
        _focus.requestFocus();
        setState(() => _canSend = false);
      }
    } catch (err, stack) {
      debugPrint('sendTextMessage error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر إرسال الرسالة')), // localized message
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      } else {
        _sending = false;
      }
    }
  }

  void _openPlusMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('صورة من المعرض'),
            onTap: () async { Navigator.pop(ctx); await widget.onPickImage(); },
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('فيديو'),
            onTap: () async { Navigator.pop(ctx); await widget.onPickVideo(); },
          ),
          ListTile(
            leading: const Icon(Icons.mic_none_outlined),
            title: const Text('تسجيل صوتي'),
            onTap: () async { Navigator.pop(ctx); await widget.onStartVoice(); },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Material(
          elevation: 1,
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.add), onPressed: _openPlusMenu, tooltip: 'مرفقات'),
            IconButton(icon: const Icon(Icons.image_outlined), onPressed: widget.onPickImage, tooltip: 'صورة'),
            IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: widget.onPickVideo, tooltip: 'فيديو'),
            IconButton(icon: const Icon(Icons.mic_none_outlined), onPressed: widget.onStartVoice, tooltip: 'صوت'),
            Expanded(
              child: TextField(
                controller: messageController,
                focusNode: _focus,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => sendTextMessage(widget.roomId),
                decoration: const InputDecoration(
                  hintText: 'اكتب رسالة...',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                ),
                minLines: 1, maxLines: 5,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: IconButton.filled(
                onPressed: (_canSend && !_sending)
                    ? () async { await sendTextMessage(widget.roomId); }
                    : null,
                icon: const Icon(Icons.send),
                tooltip: 'إرسال',
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _LinkPreview extends StatelessWidget {
  final String text;
  const _LinkPreview({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(decoration: TextDecoration.underline),
    );
  }
}

class _VideoThumb extends StatelessWidget {
  final String url;
  const _VideoThumb({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.play_circle_fill, size: 48),
    );
  }
}

class _AudioTile extends StatelessWidget {
  final String url;
  final int? durMs;
  const _AudioTile({super.key, required this.url, this.durMs});

  @override
  Widget build(BuildContext context) {
    final duration = durMs != null ? Duration(milliseconds: durMs!) : null;
    final durLabel = duration != null
        ? '${duration.inMinutes.remainder(60).toString().padLeft(2, '0')}:${(duration.inSeconds.remainder(60)).toString().padLeft(2, '0')}'
        : null;
    return Row(
      children: [
        const Icon(Icons.audiotrack),
        const SizedBox(width: 8),
        Expanded(child: Text(url, overflow: TextOverflow.ellipsis)),
        if (durLabel != null) Text(durLabel, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _QuotedMessageRich extends StatelessWidget {
  final String roomId;
  final String msgId;
  const _QuotedMessageRich({super.key, required this.roomId, required this.msgId});

  @override
  Widget build(BuildContext context) {
    return Text('↩︎ رد على رسالة ($msgId)', style: const TextStyle(fontSize: 12, color: kGray));
  }
}

class _MessageActions extends StatelessWidget {
  final void Function(String emoji) onReact;
  final VoidCallback onReply;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final bool pinned;
  final VoidCallback? onShowOriginal;
  final VoidCallback? onShowTranslation;
  const _MessageActions({
    super.key,
    required this.onReact,
    required this.onReply,
    required this.onPin,
    required this.onDelete,
    required this.pinned,
    this.onShowOriginal,
    this.onShowTranslation,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Wrap(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(
              spacing: 12,
              children: [
                for (final emoji in const ['👍', '❤️', '😂', '🔥'])
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      onReact(emoji);
                    },
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.reply_rounded),
            title: const Text('رد'),
            onTap: () {
              Navigator.of(context).pop();
              onReply();
            },
          ),
          // CODEX-BEGIN:TRANSLATOR_ACTION_ITEMS
          if (onShowOriginal != null)
            ListTile(
              leading: const Icon(Icons.translate_rounded),
              title: const Text('Show original'),
              onTap: () {
                Navigator.of(context).pop();
                onShowOriginal?.call();
              },
            ),
          if (onShowTranslation != null)
            ListTile(
              leading: const Icon(Icons.translate_rounded),
              title: const Text('Show translation'),
              onTap: () {
                Navigator.of(context).pop();
                onShowTranslation?.call();
              },
            ),
          // CODEX-END:TRANSLATOR_ACTION_ITEMS
          ListTile(
            leading: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
            title: Text(pinned ? 'إلغاء التثبيت' : 'تثبيت'),
            onTap: () {
              Navigator.of(context).pop();
              onPin();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('حذف'),
            onTap: () {
              Navigator.of(context).pop();
              onDelete();
            },
          ),
        ],
      ),
    );
  }
}

Future<void> showEditMessageDialog(
  BuildContext context, {
  required String roomId,
  required String msgId,
  required String initialText,
}) async {
  final controller = TextEditingController(text: initialText);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تعديل الرسالة'),
      content: TextField(
        controller: controller,
        maxLines: null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
  if (result == null || result.isEmpty || result == initialText.trim()) return;
  await cf.FirebaseFirestore.instance
      .collection('rooms')
      .doc(roomId)
      .collection('messages')
      .doc(msgId)
      .update({
    'text': result,
    'edited': true,
    'editedAt': cf.FieldValue.serverTimestamp(),
  });
}
// ===================== main.dart — Chat-MVP (ULTRA FINAL) [Part 5/12] =====================
// Stories 24h: create (image/video/text), list, viewer, views tracking, basic privacy
// الملاحظات:
// - نخزّن القصص تحت: stories/{ownerUid}/{storyId}
// - كل Story: {type: image|video|text, mediaUrl?, text?, bg?, createdAt, visibility, viewsCount}
// - المنتهي يُخفى على العميل إذا مرّ أكثر من 24 ساعة على createdAt.
// - حذف فعلي يفضَّل عبر Cloud Functions (جدولة) لاحقًا.

// ---------------------- Model ----------------------

int? _parseStoryBgColor(String? value) {
  if (value == null) return null;
  final normalized = value.trim();
  if (normalized.isEmpty) return null;
  if (normalized.startsWith('#')) {
    return int.tryParse(normalized.substring(1), radix: 16);
  }
  if (normalized.startsWith('0x')) {
    return int.tryParse(normalized.substring(2), radix: 16);
  }
  final decimal = int.tryParse(normalized);
  if (decimal != null) return decimal;
  return int.tryParse(normalized, radix: 16);
}

String _detectStoryLang(String? existing) {
  if (existing != null && existing.isNotEmpty) return existing;
  try {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    if (dispatcher.locales.isNotEmpty) {
      return dispatcher.locales.first.languageCode;
    }
    final locale = dispatcher.locale;
    if (locale != null) return locale.languageCode;
  } catch (_) {
    // ignore
  }
  return 'en';
}

Future<void> saveStoryDoc({
  required String ownerId,
  required String storyId,
  required String type,
  String? text,
  String? mediaUrl,
  String? mediaPath,
  int? bgColor,
  String audience = 'all',
}) async {
  final fs = cf.FirebaseFirestore.instance;
  final docRef = fs.collection('stories').doc(ownerId).collection('items').doc(storyId);
  final existing = await docRef.get();
  final data = existing.data();
  final existingCreatedAt = data?['createdAt'];
  final existingExpiresAt = data?['expiresAt'];
  final existingBgColorRaw = data?['bgColor'];
  final lang = _detectStoryLang(data?['lang'] as String?);
  final resolvedBgColor = bgColor ?? switch (existingBgColorRaw) {
    int value => value,
    String value => _parseStoryBgColor(value),
    _ => null,
  };
  final legacyVisibility = audience == 'all' ? 'everyone' : audience;

  final payload = <String, dynamic>{
    'storyId': storyId,
    'ownerId': ownerId,
    'type': type,
    'text': text,
    'mediaUrl': mediaUrl,
    'url': mediaUrl,
    'mediaPath': mediaPath,
    'audience': audience,
    'visibility': legacyVisibility,
    'lang': lang,
    'createdAt': existingCreatedAt is cf.Timestamp ? existingCreatedAt : cf.FieldValue.serverTimestamp(),
    'expiresAt': existingExpiresAt is cf.Timestamp
        ? existingExpiresAt
        : cf.Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
  };

  if (!existing.exists) {
    payload['viewsCount'] = 0;
  }

  if (resolvedBgColor != null) {
    payload['bgColor'] = resolvedBgColor;
    payload['bg'] = resolvedBgColor;
  }

  await docRef.set(payload, cf.SetOptions(merge: true));
  debugPrint('saveStoryDoc => uid=$ownerId storyId=$storyId storagePath=$mediaPath docPath=${docRef.path}');
}

enum StoryType { image, video, text }

class StoryItem {
  final String id;
  final String ownerUid;
  final StoryType type;
  final String? mediaUrl;
  final String? mediaPath;
  final String? text;
  final int? bg; // Color value for text stories
  final cf.Timestamp createdAt;
  final String visibility; // everyone | contacts | custom
  final String audience;
  final cf.Timestamp? expiresAt;
  final int viewsCount;

  StoryItem({
    required this.id,
    required this.ownerUid,
    required this.type,
    required this.createdAt,
    this.mediaUrl,
    this.mediaPath,
    this.text,
    this.bg,
    this.visibility = 'everyone',
    this.audience = 'all',
    this.expiresAt,
    this.viewsCount = 0,
  });

  factory StoryItem.fromDoc(String ownerUid, cf.DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    StoryType _t(String? s) {
      switch (s) { case 'video': return StoryType.video; case 'text': return StoryType.text; default: return StoryType.image; }
    }
    int? _resolveBg(dynamic raw) {
      return switch (raw) {
        int value => value,
        String value => _parseStoryBgColor(value),
        _ => null,
      };
    }

    final createdRaw = d['createdAt'];
    final expiresRaw = d['expiresAt'];

    return StoryItem(
      id: doc.id,
      ownerUid: ownerUid,
      type: _t(d['type'] as String?),
      mediaUrl: (d['url'] as String?) ?? (d['mediaUrl'] as String?),
      mediaPath: d['mediaPath'] as String?,
      text: d['text'] as String?,
      bg: _resolveBg(d['bg']) ?? _resolveBg(d['bgColor']),
      createdAt: createdRaw is cf.Timestamp ? createdRaw : cf.Timestamp.now(),
      visibility: (d['visibility'] as String?) ?? 'everyone',
      audience: (d['audience'] as String?) ?? 'all',
      expiresAt: expiresRaw is cf.Timestamp ? expiresRaw : null,
      viewsCount: (d['viewsCount'] as num?)?.toInt() ?? 0,
    );
  }

  bool get expired {
    if (expiresAt != null) {
      return DateTime.now().isAfter(expiresAt!.toDate());
    }
    final dt = createdAt.toDate();
    return DateTime.now().isAfter(dt.add(const Duration(hours: 24)));
  }
}

Future<List<StoryItem>> fetchUserStories(String uid) async {
  if (uid.isEmpty) return [];
  final now = DateTime.now();
  final nowTs = cf.Timestamp.fromDate(now);
  final fs = cf.FirebaseFirestore.instance;
  List<StoryItem> firestoreStories = [];

  try {
    final query = await fs
        .collection('stories')
        .doc(uid)
        .collection('items')
        .where('expiresAt', isGreaterThan: nowTs)
        .orderBy('createdAt')
        .get();
    firestoreStories = query.docs
        .map((d) => StoryItem.fromDoc(uid, d))
        .where((item) => !item.expired)
        .toList();
    if (firestoreStories.isNotEmpty) {
      return firestoreStories;
    }
  } on cf.FirebaseException catch (err, stack) {
    debugPrint('fetchUserStories Firestore error: ${err.message}');
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }

  final storage = FirebaseStorage.instance.ref('stories/$uid');
  final List<StoryItem> storageStories = [];

  Future<void> traverse(Reference ref) async {
    try {
      final result = await ref.listAll();
      for (final item in result.items) {
        try {
          final meta = await item.getMetadata();
          final updated = meta.updated ?? meta.timeCreated ?? now;
          final expires = updated.add(const Duration(hours: 24));
          final url = await item.getDownloadURL();
          final lower = item.name.toLowerCase();
          StoryType type;
          if (lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.mkv') || lower.endsWith('.webm')) {
            type = StoryType.video;
          } else {
            type = StoryType.image;
          }
          storageStories.add(StoryItem(
            id: item.fullPath,
            ownerUid: uid,
            type: type,
            mediaUrl: url,
            mediaPath: item.fullPath,
            text: null,
            bg: null,
            createdAt: cf.Timestamp.fromDate(updated),
            audience: 'all',
            visibility: 'everyone',
            expiresAt: cf.Timestamp.fromDate(expires),
            viewsCount: 0,
          ));
        } catch (err, stack) {
          debugPrint('fetchUserStories storage item error: $err');
          FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
        }
      }
      for (final prefix in result.prefixes) {
        await traverse(prefix);
      }
    } on FirebaseException catch (err, stack) {
      debugPrint('fetchUserStories storage error: ${err.message}');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    }
  }

  await traverse(storage);
  storageStories.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return storageStories.where((item) => !item.expired).toList();
}

class StoryStrip extends StatefulWidget {
  final String uid;
  final String? displayName;
  final String? avatarUrl;
  const StoryStrip({super.key, required this.uid, this.displayName, this.avatarUrl});

  @override
  State<StoryStrip> createState() => _StoryStripState();
}

class _StoryStripState extends State<StoryStrip> {
  late Future<List<StoryItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchUserStories(widget.uid);
  }

  @override
  void didUpdateWidget(covariant StoryStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _future = fetchUserStories(widget.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.uid.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<List<StoryItem>>(
      future: _future,
      builder: (context, snapshot) {
        final stories = snapshot.data ?? const <StoryItem>[];
        final hasStories = stories.isNotEmpty;
        final count = stories.length;
        final theme = Theme.of(context);
        final borderColor = hasStories
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant.withOpacity(0.4);
        final avatarUrl = widget.avatarUrl;
        final trimmed = widget.displayName?.trim() ?? '';
        final initials = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : 'Y';

        Widget avatarContent;
        if (avatarUrl != null && avatarUrl.isNotEmpty) {
          avatarContent = CircleAvatar(
            radius: 30,
            backgroundImage: NetworkImage(avatarUrl),
          );
        } else {
          avatarContent = CircleAvatar(
            radius: 30,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
            child: Text(
              initials,
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          avatarContent = Stack(
            alignment: Alignment.center,
            children: [
              avatarContent,
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          );
        }

        final tile = GestureDetector(
          onTap: () {
            Navigator.of(context).pushNamed('/stories', arguments: {'uid': widget.uid});
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: borderColor, width: 3),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: ClipOval(child: avatarContent),
                  ),
                  if (hasStories)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$count',
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onPrimary),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Your Story',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        );

        return SizedBox(
          height: 104,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            children: [tile],
          ),
        );
      },
    );
  }
}

// ---------------------- Stories Hub Page (list circles) ----------------------
class StoriesHubPage extends StatelessWidget {
  const StoriesHubPage({super.key});

  Stream<List<(String owner, StoryItem item)>> _storiesStream() {
    // (MVP) نعرض كل الستوري العامة غير المنتهية. يمكن لاحقًا فلترتها بمن تتابعهم فقط.
    final fs = cf.FirebaseFirestore.instance;
    // نجلب آخر 20 مستخدم لديهم ستوري اليوم
    return fs.collection('users').limit(50).snapshots().asyncMap((usersSnap) async {
      final List<(String, StoryItem)> all = [];
      final nowTs = cf.Timestamp.fromDate(DateTime.now());
      for (final u in usersSnap.docs) {
        final uid = u.id;
        final stories = await fs.collection('stories').doc(uid)
            .collection('items')
            .where('expiresAt', isGreaterThan: nowTs)
            .orderBy('expiresAt')
            .orderBy('createdAt', descending: true)
            .limit(5)
            .get();
        for (final s in stories.docs) {
          final it = StoryItem.fromDoc(uid, s);
          if (!it.expired && (it.visibility == 'everyone')) {
            all.add((uid, it));
          }
        }
      }
      // ترتيب حسب الأحدث
      all.sort((a, b) => b.$2.createdAt.compareTo(a.$2.createdAt));
      return all.take(40).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stories'),
        actions: [
          IconButton(
            onPressed: ()=> navigatorKey.currentState?.pushNamed('/story_create'),
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'إضافة ستوري',
          )
        ],
      ),
      body: StreamBuilder<List<(String owner, StoryItem item)>>(
        stream: _storiesStream(),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final items = s.data!;
          if (items.isEmpty) {
            return Center(
              child: TextButton.icon(
                onPressed: ()=> navigatorKey.currentState?.pushNamed('/story_create'),
                icon: const Icon(Icons.add),
                label: const Text('أضف أوّل ستوري'),
              ),
            );
          }

          // نبني قائمة حسب المالك (أحدث لكل مالك)
          final Map<String, StoryItem> latestByOwner = {};
          for (final (owner, it) in items) {
            latestByOwner.putIfAbsent(owner, () => it);
          }
          final owners = latestByOwner.keys.toList();

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            children: [
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                    itemBuilder: (_, i) {
                      final owner = i==0 ? uid : owners[i-1];
                      final isMe = i==0;
                      final story = isMe
                        ? latestByOwner[uid ?? ''] // قد لا يكون لديه ستوري
                        : latestByOwner[owner!];

                      return GestureDetector(
                        onTap: () {
                          if (isMe && story == null) {
                            navigatorKey.currentState?.pushNamed('/story_create');
                          } else {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => _StoriesViewer(ownerUid: owner ?? story!.ownerUid),
                            ));
                          }
                        },
                        child: Column(
                          children: [
                            Container(
                              width: 70, height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: story != null
                                  ? const LinearGradient(colors: [kTeal, Color(0xFF0FAFA0)])
                                  : null,
                                border: story == null ? Border.all(color: Colors.black12) : null,
                              ),
                              padding: const EdgeInsets.all(3),
                              child: CircleAvatar(
                                backgroundColor: Colors.white,
                                child: isMe
                                  ? const Icon(Icons.add, color: kTeal)
                                  : const Icon(Icons.person, color: kTeal),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(isMe ? 'قصتي' : (owner ?? '...'),
                                style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemCount: (uid==null ? 0 : 1) + owners.length),
              ),
              const SizedBox(height: 16),
              // تيار مختصر (شبِه Timeline)
              for (final (owner, it) in items.take(12))
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(owner),
                  subtitle: Text(
                    it.type == StoryType.text
                      ? (it.text ?? '')
                      : (it.type == StoryType.image ? '📷 Image story' : '🎞️ Video story'),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: (){
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => _StoriesViewer(ownerUid: owner),
                      ));
                    },
                  ),
                )
            ],
          );
        },
      ),
    );
  }
}

// CODEX-BEGIN:STORY_REPLY_HELPERS
Future<bool> _storyRepliesAllowed(String ownerUid) async {
  final viewerUid = FirebaseAuth.instance.currentUser?.uid;
  if (viewerUid == null || viewerUid == ownerUid) {
    return false;
  }
  try {
    final service = UserSettingsService();
    final settings = await service.fetchPrivacy(ownerUid);
    final mode = settings.allowStoriesReplies;
    switch (mode) {
      case 'no_one':
        return false;
      case 'contacts':
        return await _isMutualStoryContact(ownerUid, viewerUid);
      case 'everyone':
      default:
        return true;
    }
  } catch (err, stack) {
    debugPrint('storyRepliesAllowed error: $err');
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    return false;
  }
}

Future<bool> _isMutualStoryContact(String ownerUid, String viewerUid) async {
  final fs = cf.FirebaseFirestore.instance;
  final followerDoc = await fs
      .collection('follows')
      .doc(ownerUid)
      .collection('followers')
      .doc(viewerUid)
      .get();
  if (!followerDoc.exists) {
    return false;
  }
  final followingDoc = await fs
      .collection('follows')
      .doc(ownerUid)
      .collection('following')
      .doc(viewerUid)
      .get();
  return followingDoc.exists;
}
// CODEX-END:STORY_REPLY_HELPERS

class StoryViewerPage extends StatefulWidget {
  final String uid;
  final int initialIndex;
  const StoryViewerPage({super.key, required this.uid, this.initialIndex = 0});

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage> {
  // CODEX-BEGIN:STORY_PRIVACY_HELPERS
  Future<bool> _canReplyToOwner() {
    return _storyRepliesAllowed(widget.uid);
  }
  // CODEX-END:STORY_PRIVACY_HELPERS
  List<StoryItem> _stories = [];
  int _index = 0;
  bool _loading = true;
  Timer? _timer;
  VideoPlayerController? _videoController;
  bool _videoInitializing = false;
  bool _videoPaused = false;
  bool _canReply = false;
  bool _replyKnown = false;
  bool _replying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.uid.isEmpty) {
      setState(() {
        _stories = [];
        _loading = false;
      });
      return;
    }
    try {
      final list = await fetchUserStories(widget.uid);
      if (!mounted) return;
      final safeIndex = list.isEmpty
          ? 0
          : math.min(math.max(widget.initialIndex, 0), list.length - 1);
      setState(() {
        _stories = list;
        _index = safeIndex;
        _loading = false;
        _replyKnown = false;
        _canReply = false;
      });
      unawaited(_evaluateReplyPermission());
      if (list.isNotEmpty) {
        await _prepareCurrent();
      }
    } catch (err, stack) {
      debugPrint('StoryViewerPage load error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      if (mounted) {
        setState(() {
          _stories = [];
          _loading = false;
        });
      }
    }
  }

  Future<void> _evaluateReplyPermission() async {
    try {
      final allowed = await _canReplyToOwner();
      if (!mounted) return;
      setState(() {
        _canReply = allowed;
        _replyKnown = true;
      });
    } catch (err, stack) {
      debugPrint('StoryViewerPage reply permission error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      if (!mounted) return;
      setState(() {
        _canReply = false;
        _replyKnown = true;
      });
    }
  }

  Future<void> _replyToStory() async {
    if (!_replyKnown || !_canReply || _replying) {
      return;
    }
    setState(() {
      _replying = true;
    });
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) {
      setState(() {
        _replying = false;
      });
      return;
    }
    final result = await FirestoreService().openOrCreateDirectThread(
      currentUid: currentUid,
      otherUid: widget.uid,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _replying = false;
    });
    if (result is SafeSuccess<String>) {
      navigatorKey.currentState?.pushNamed('/dm', arguments: result.value);
    } else if (result is SafeFailure<String>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  Future<void> _prepareCurrent() async {
    _timer?.cancel();
    await _disposeVideo();
    if (!mounted || _stories.isEmpty) return;
    final current = _stories[_index];
    if (current.type == StoryType.video && current.mediaUrl != null) {
      setState(() {
        _videoInitializing = true;
        _videoPaused = false;
      });
      final controller = VideoPlayerController.networkUrl(Uri.parse(current.mediaUrl!));
      _videoController = controller;
      try {
        await controller.initialize();
        if (!mounted) return;
        controller.addListener(_onVideoTick);
        await controller.play();
        if (mounted) {
          setState(() {
            _videoInitializing = false;
            _videoPaused = false;
          });
        }
      } catch (err, stack) {
        debugPrint('StoryViewerPage video init error: $err');
        FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
        if (mounted) {
          setState(() {
            _videoInitializing = false;
            _videoPaused = false;
          });
        }
      }
    } else {
      _timer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          _next();
        }
      });
    }
  }

  Future<void> _disposeVideo() async {
    final controller = _videoController;
    _videoController = null;
    if (controller != null) {
      controller.removeListener(_onVideoTick);
      try {
        await controller.pause();
      } catch (_) {}
      await controller.dispose();
    }
  }

  void _onVideoTick() {
    final controller = _videoController;
    if (controller == null || !mounted) return;
    final value = controller.value;
    if (!value.isInitialized) return;
    if (value.duration > Duration.zero && value.position >= value.duration) {
      controller.removeListener(_onVideoTick);
      if (mounted) {
        _next();
      }
    }
  }

  void _next() {
    if (_stories.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    if (_index < _stories.length - 1) {
      setState(() {
        _index++;
      });
      unawaited(_prepareCurrent());
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    if (_stories.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    if (_index > 0) {
      setState(() {
        _index--;
      });
      unawaited(_prepareCurrent());
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _toggleVideo() {
    final controller = _videoController;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      controller.pause();
      setState(() {
        _videoPaused = true;
      });
    } else {
      controller.play();
      setState(() {
        _videoPaused = false;
      });
    }
  }

  void _handleTap(TapUpDetails details) {
    final width = MediaQuery.of(context).size.width;
    if (details.localPosition.dx < width / 2) {
      _prev();
    } else {
      _next();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_disposeVideo());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_stories.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('No active stories', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Close'),
              )
            ],
          ),
        ),
      );
    }

    final story = _stories[_index];
    final replyButtonBottom = (story.type == StoryType.video && _videoController != null) ? 96.0 : 24.0;
    Widget content;
    switch (story.type) {
      case StoryType.text:
        content = Container(
          color: Color(story.bg ?? Colors.black.value),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            story.text ?? '',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
        );
        break;
      case StoryType.image:
        content = story.mediaUrl != null
            ? Image.network(story.mediaUrl!, fit: BoxFit.cover)
            : const SizedBox.shrink();
        break;
      case StoryType.video:
        if (_videoInitializing) {
          content = const Center(child: CircularProgressIndicator());
        } else if (_videoController?.value.isInitialized == true) {
          content = FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          );
        } else {
          content = const SizedBox.shrink();
        }
        break;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTapUp: _handleTap,
          onVerticalDragEnd: (_) => Navigator.of(context).maybePop(),
          child: Stack(
            children: [
              Positioned.fill(child: content),
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(_stories.length, (i) {
                        final active = i == _index;
                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            height: 3,
                            decoration: BoxDecoration(
                              color: active ? Colors.white : Colors.white24,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Colors.white24,
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            story.ownerUid,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (story.type == StoryType.video && _videoController != null)
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _toggleVideo,
                        icon: Icon(_videoPaused ? Icons.play_arrow : Icons.pause),
                        label: Text(_videoPaused ? 'Play' : 'Pause'),
                      ),
                    ],
                  ),
                ),
              if (_replyKnown && _canReply)
                Positioned(
                  bottom: replyButtonBottom,
                  left: 16,
                  right: 16,
                  child: SafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FilledButton.tonalIcon(
                        onPressed: _replying ? null : _replyToStory,
                        icon: const Icon(Icons.reply_rounded),
                        label: Text(_replying ? 'Opening…' : 'Reply'),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------- Story Viewer (pager per owner) ----------------------
class _StoriesViewer extends StatefulWidget {
  final String ownerUid;
  const _StoriesViewer({required this.ownerUid});
  @override
  State<_StoriesViewer> createState() => _StoriesViewerState();
}

class _StoriesViewerState extends State<_StoriesViewer> {
  List<StoryItem> stories = [];
  int idx = 0;
  bool loading = true;
  bool canReply = false;
  bool replyKnown = false;
  bool replying = false;

  @override
  void initState() {
    super.initState();
    _loadStories();
  }

  Future<void> _loadStories() async {
    final fs = cf.FirebaseFirestore.instance;
    final nowTs = cf.Timestamp.fromDate(DateTime.now());
    final q = await fs.collection('stories').doc(widget.ownerUid)
      .collection('items')
      .where('expiresAt', isGreaterThan: nowTs)
      .orderBy('expiresAt')
      .orderBy('createdAt', descending: false)
      .get();
    final list = q.docs.map((d) => StoryItem.fromDoc(widget.ownerUid, d))
        .where((e) => !e.expired && e.visibility == 'everyone')
        .toList();
    setState(() {
      stories = list;
      loading = false;
      idx = 0;
      canReply = false;
      replyKnown = false;
    });
    if (stories.isNotEmpty) _markViewed(stories.first);
    unawaited(_evaluateReplyPermission());
  }

  Future<void> _evaluateReplyPermission() async {
    try {
      final allowed = await _storyRepliesAllowed(widget.ownerUid);
      if (!mounted) return;
      setState(() {
        canReply = allowed;
        replyKnown = true;
      });
    } catch (err, stack) {
      debugPrint('StoriesViewer reply permission error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      if (!mounted) return;
      setState(() {
        canReply = false;
        replyKnown = true;
      });
    }
  }

  Future<void> _replyToStory() async {
    if (!replyKnown || !canReply || replying) {
      return;
    }
    setState(() {
      replying = true;
    });
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) {
      setState(() {
        replying = false;
      });
      return;
    }
    final result = await FirestoreService().openOrCreateDirectThread(
      currentUid: currentUid,
      otherUid: widget.ownerUid,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      replying = false;
    });
    if (result is SafeSuccess<String>) {
      navigatorKey.currentState?.pushNamed('/dm', arguments: result.value);
    } else if (result is SafeFailure<String>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  Future<void> _markViewed(StoryItem s) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    final fs = cf.FirebaseFirestore.instance;
    final viewRef = fs.collection('stories').doc(s.ownerUid)
      .collection('items').doc(s.id).collection('views').doc(me);
    final exists = await viewRef.get();
    if (!exists.exists) {
      await viewRef.set({'viewedAt': cf.FieldValue.serverTimestamp()});
      await fs.collection('stories').doc(s.ownerUid)
        .collection('items').doc(s.id)
        .update({'viewsCount': cf.FieldValue.increment(1)});
    }
  }

  void _next() {
    if (idx < stories.length - 1) {
      setState(() => idx++);
      _markViewed(stories[idx]);
    } else {
      Navigator.pop(context);
    }
  }

  void _prev() {
    if (idx > 0) {
      setState(() => idx--);
      _markViewed(stories[idx]);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (stories.isEmpty) return const Scaffold(body: Center(child: Text('لا يوجد ستوري')));

    final s = stories[idx];
    final left = Expanded(child: GestureDetector(onTap: _prev));
    final right = Expanded(child: GestureDetector(onTap: _next));
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: s.type == StoryType.text
                ? Container(
                    color: Color(s.bg ?? Colors.black.value),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          s.text ?? '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 24, height: 1.4),
                        ),
                      ),
                    ),
                  )
                : (s.mediaUrl != null
                    ? (s.type == StoryType.image
                        ? Image.network(s.mediaUrl!, fit: BoxFit.cover)
                        : _VideoFull(url: s.mediaUrl!))
                    : const SizedBox.shrink()),
            ),
            // tap zones
            Row(children: [left, right]),
            // top bar
            Positioned(
              top: 8, left: 12, right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // progress bars
                  Row(
                    children: List.generate(stories.length, (i) {
                      final active = i == idx;
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 3,
                          decoration: BoxDecoration(
                            color: active ? Colors.white : Colors.white24,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const CircleAvatar(backgroundColor: Colors.white24, child: Icon(Icons.person, color: Colors.white)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(widget.ownerUid, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                      IconButton(
                        onPressed: ()=> Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // bottom actions
            Positioned(
              bottom: 8,
              left: 12,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (replyKnown && canReply)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: replying ? null : _replyToStory,
                        icon: const Icon(Icons.reply_rounded),
                        label: Text(replying ? 'Opening…' : 'Reply'),
                      ),
                    ),
                  if (replyKnown && canReply) const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(shortTime(s.createdAt), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      const Spacer(),
                      const Icon(Icons.remove_red_eye, color: Colors.white70, size: 16),
                      const SizedBox(width: 4),
                      Text('${s.viewsCount}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// فيديو ملء الشاشة للستوري
class _VideoFull extends StatefulWidget {
  final String url;
  const _VideoFull({required this.url});
  @override
  State<_VideoFull> createState() => _VideoFullState();
}
class _VideoFullState extends State<_VideoFull> {
  VideoPlayerController? _vc;
  @override
  void initState() {
    super.initState();
    _vc = VideoPlayerController.networkUrl(Uri.parse(widget.url))..initialize().then((_) {
      _vc?.setLooping(true);
      _vc?.play();
      if (mounted) setState((){});
    });
  }
  @override
  void dispose() { _vc?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (_vc?.value.isInitialized != true) {
      return const Center(child: CircularProgressIndicator());
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _vc!.value.size.width,
        height: _vc!.value.size.height,
        child: VideoPlayer(_vc!),
      ),
    );
  }
}

// ---------------------- Create Story Page ----------------------
class StoryCreatePage extends StatefulWidget {
  const StoryCreatePage({super.key});
  @override
  State<StoryCreatePage> createState() => _StoryCreatePageState();
}

class _StoryCreatePageState extends State<StoryCreatePage> {
  final _picker = ImagePicker();
  StoryType _type = StoryType.text;
  XFile? _image;
  XFile? _video;
  final _text = TextEditingController();
  Color _bg = const Color(0xFF222831);
  String _visibility = 'everyone'; // TODO: contacts/custom لاحقًا

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(()=> {_type = StoryType.image, _image = x, _video = null});
  }
  Future<void> _pickVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 30));
    if (x != null) setState(()=> {_type = StoryType.video, _video = x, _image = null});
  }

  Future<void> _publish() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    // CODEX-BEGIN:ADMIN_BLOCK_STORY_UI
    final bool blocked = context.read<AppUser>().profile['blocked'] == true;
    if (blocked) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تقييد نشر القصص مؤقتاً من قبل الإدارة.')),
      );
      return;
    }
    // CODEX-END:ADMIN_BLOCK_STORY_UI
    final storiesRef = cf.FirebaseFirestore.instance.collection('stories').doc(me).collection('items');
    late final cf.DocumentReference<Map<String, dynamic>> docRef;
    if (_type == StoryType.text) {
      final storyId = DateTime.now().millisecondsSinceEpoch.toString();
      docRef = storiesRef.doc(storyId);
    } else {
      docRef = storiesRef.doc();
    }
    final storyId = docRef.id;

    String? mediaUrl;
    String? mediaPath;
    if (_type == StoryType.image && _image != null) {
      final storagePath = 'stories/$me/$storyId/${_image!.name}';
      final sref = FirebaseStorage.instance.ref(storagePath);
      await sref.putFile(
        File(_image!.path),
        SettableMetadata(contentType: 'image/${_image!.path.split('.').last}'),
      );
      mediaUrl = await sref.getDownloadURL();
      mediaPath = sref.fullPath;
    } else if (_type == StoryType.video && _video != null) {
      final storagePath = 'stories/$me/$storyId/${_video!.name}';
      final sref = FirebaseStorage.instance.ref(storagePath);
      await sref.putFile(
        File(_video!.path),
        SettableMetadata(contentType: 'video/${_video!.path.split('.').last}'),
      );
      mediaUrl = await sref.getDownloadURL();
      mediaPath = sref.fullPath;
    }

    final rawText = _text.text.trim();
    final storyAudience = _visibility == 'everyone' ? 'all' : _visibility;

    await saveStoryDoc(
      ownerId: me,
      storyId: storyId,
      type: switch (_type) {
        StoryType.image => 'image',
        StoryType.video => 'video',
        StoryType.text => 'text',
      },
      text: _type == StoryType.text ? (rawText.isEmpty ? null : rawText) : null,
      mediaUrl: mediaUrl,
      mediaPath: mediaPath,
      bgColor: _type == StoryType.text ? _bg.value : null,
      audience: storyAudience,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نشر الستوري ✅')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = Container(
      height: 260,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _type == StoryType.text ? _bg : Colors.black12,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: switch (_type) {
          StoryType.text => Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _text.text.isEmpty ? 'اكتب ستوري نصي...' : _text.text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 22),
            ),
          ),
          StoryType.image => _image == null
              ? const Text('اختر صورة…')
              : Image.file(File(_image!.path), fit: BoxFit.cover),
          StoryType.video => _video == null
              ? const Text('اختر فيديو…')
              : const Icon(Icons.videocam_rounded, size: 64, color: Colors.white),
        },
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء ستوري')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          preview,
          SegmentedButton<StoryType>(
            segments: const [
              ButtonSegment(value: StoryType.text, icon: Icon(Icons.title), label: Text('نص')),
              ButtonSegment(value: StoryType.image, icon: Icon(Icons.image_rounded), label: Text('صورة')),
              ButtonSegment(value: StoryType.video, icon: Icon(Icons.videocam_rounded), label: Text('فيديو')),
            ],
            selected: {_type},
            onSelectionChanged: (s)=> setState(()=> _type = s.first),
          ),
          const SizedBox(height: 10),
          if (_type == StoryType.text) ...[
            TextField(
              controller: _text,
              maxLines: 4,
              onChanged: (_) => setState((){}),
              decoration: const InputDecoration(hintText: 'اكتب هنا…'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('لون الخلفية:'),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    Colors.black, const Color(0xFF222831), kTeal, Colors.deepPurple, Colors.indigo, Colors.redAccent
                  ].map((c)=> GestureDetector(
                    onTap: ()=> setState(()=> _bg = c),
                    child: CircleAvatar(backgroundColor: c, radius: 14),
                  )).toList(),
                )
              ],
            )
          ] else ...[
            Row(
              children: [
                ElevatedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.image), label: const Text('صورة')),
                const SizedBox(width: 8),
                ElevatedButton.icon(onPressed: _pickVideo, icon: const Icon(Icons.videocam), label: const Text('فيديو')),
              ],
            )
          ],
          const SizedBox(height: 12),
          const Text('الخصوصية'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: const Text('للجميع'), selected: _visibility=='everyone', onSelected: (_)=> setState(()=> _visibility='everyone')),
              ChoiceChip(label: const Text('جهات الاتصال'), selected: _visibility=='contacts', onSelected: (_)=> setState(()=> _visibility='contacts')),
              ChoiceChip(label: const Text('مخصّص'), selected: _visibility=='custom', onSelected: (_)=> setState(()=> _visibility='custom')),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _publish,
            icon: const Icon(Icons.send_rounded),
            label: const Text('نشر'),
          ),
        ],
      ),
    );
  }
}
// ===================== main.dart — Chat-MVP (ULTRA FINAL) [Part 6/12] =====================
// DMs + Inbox + Discover People + Follow/Unfollow + Global Search (rooms/users)

// ---------------------- Follow System ----------------------
class FollowService {
  final _fs = cf.FirebaseFirestore.instance;

  Future<bool> isFollowing(String me, String other) async {
    final d = await _fs.collection('follows').doc(me).collection('following').doc(other).get();
    return d.exists;
  }

  Future<void> follow(String me, String other) async {
    if (me == other) return;
    final meRef = _fs.collection('follows').doc(me).collection('following').doc(other);
    final heRef = _fs.collection('follows').doc(other).collection('followers').doc(me);
    final userMe = _fs.collection('users').doc(me);
    final userHe = _fs.collection('users').doc(other);

    await _fs.runTransaction((tx) async {
      tx.set(meRef, {'at': cf.FieldValue.serverTimestamp()});
      tx.set(heRef, {'at': cf.FieldValue.serverTimestamp()});
      final meDoc = await tx.get(userMe);
      final heDoc = await tx.get(userHe);
      final meFollowing = (meDoc.data()?['following'] ?? 0) as int;
      final heFollowers = (heDoc.data()?['followers'] ?? 0) as int;
      tx.update(userMe, {'following': meFollowing + 1});
      tx.update(userHe, {'followers': heFollowers + 1});
    });
  }

  Future<void> unfollow(String me, String other) async {
    if (me == other) return;
    final meRef = _fs.collection('follows').doc(me).collection('following').doc(other);
    final heRef = _fs.collection('follows').doc(other).collection('followers').doc(me);
    final userMe = _fs.collection('users').doc(me);
    final userHe = _fs.collection('users').doc(other);

    await _fs.runTransaction((tx) async {
      tx.delete(meRef);
      tx.delete(heRef);
      final meDoc = await tx.get(userMe);
      final heDoc = await tx.get(userHe);
      final meFollowing = (meDoc.data()?['following'] ?? 0) as int;
      final heFollowers = (heDoc.data()?['followers'] ?? 0) as int;
      tx.update(userMe, {'following': (meFollowing > 0 ? meFollowing - 1 : 0)});
      tx.update(userHe, {'followers': (heFollowers > 0 ? heFollowers - 1 : 0)});
    });
  }
}

// ---------------------- Discover People ----------------------
// CODEX-BEGIN:DISCOVER_PAGE
class PeopleDiscoverPage extends StatefulWidget {
  const PeopleDiscoverPage({super.key});

  @override
  State<PeopleDiscoverPage> createState() => _PeopleDiscoverPageState();
}

class _PeopleDiscoverPageState extends State<PeopleDiscoverPage> {
  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestoreService = FirestoreService();
  final FollowService _followService = FollowService();
  final List<DiscoverUser> _users = <DiscoverUser>[];
  cf.DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;
  late final String _currentUid;

  @override
  void initState() {
    super.initState();
    _currentUid = FirebaseAuth.instance.currentUser!.uid;
    _scrollController.addListener(_onScroll);
    _loadPage(reset: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    if (_scrollController.position.extentAfter < 320) {
      _loadPage(reset: false);
    }
  }

  Future<void> _loadPage({required bool reset}) async {
    if (_loadingMore) return;
    if (reset) {
      setState(() {
        _initialLoading = true;
        _loadingMore = true;
        _errorMessage = null;
        _hasMore = true;
        _lastDoc = null;
        _users.clear();
      });
    } else {
      setState(() {
        _loadingMore = true;
      });
    }

    final result = await _firestoreService.fetchDiscoverUsers(
      currentUid: _currentUid,
      startAfter: reset ? null : _lastDoc,
      limit: 20,
    );
    if (!mounted) return;

    if (result is SafeSuccess<DiscoverUsersPage>) {
      setState(() {
        _users.addAll(result.value.users);
        _lastDoc = result.value.lastDocument;
        _hasMore = result.value.hasMore;
        _errorMessage = null;
        _initialLoading = false;
        _loadingMore = false;
      });
    } else if (result is SafeFailure<DiscoverUsersPage>) {
      setState(() {
        _errorMessage = result.message;
        _initialLoading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    await _loadPage(reset: true);
  }

  Future<void> _openOrCreateDMWith(String otherUid) async {
    final result = await _firestoreService.openOrCreateDirectThread(
      currentUid: _currentUid,
      otherUid: otherUid,
    );
    if (!mounted) return;
    if (result is SafeSuccess<String>) {
      navigatorKey.currentState?.pushNamed('/dm', arguments: result.value);
    } else if (result is SafeFailure<String>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  void _openProfile(BuildContext context, String uid) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfilePage(userId: uid)));
  }

  Widget _buildList() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: TextButton(
          onPressed: () => _loadPage(reset: true),
          child: const Text('حدث خطأ، حاول مرة أخرى'),
        ),
      );
    }
    if (_users.isEmpty) {
      return const Center(child: Text('لا يوجد اقتراحات حالياً'));
    }
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _users.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        if (i >= _users.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final user = _users[i];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(user.displayName, overflow: TextOverflow.ellipsis),
            subtitle: Text('VIP: ${user.vipTier} • ${compactNumber(user.followers)} متابع'),
            trailing: FutureBuilder<bool>(
              future: _followService.isFollowing(_currentUid, user.uid),
              builder: (c2, fsnap) {
                final isF = fsnap.data == true;
                return Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => isF
                          ? _followService.unfollow(_currentUid, user.uid)
                          : _followService.follow(_currentUid, user.uid),
                      child: Text(isF ? 'إلغاء المتابعة' : 'متابعة'),
                    ),
                    FilledButton(
                      onPressed: () => _openOrCreateDMWith(user.uid),
                      child: const Text('رسالة'),
                    ),
                  ],
                );
              },
            ),
            onTap: () => _openProfile(context, user.uid),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildList();
    return Scaffold(
      appBar: AppBar(title: const Text('Discover People')),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: content is ListView
            ? content
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: content,
                  ),
                ],
              ),
      ),
    );
  }
}
// CODEX-END:DISCOVER_PAGE

// ---------------------- Public Profile View ----------------------
class PublicProfilePage extends StatelessWidget {
  final String userId;
  const PublicProfilePage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final doc = cf.FirebaseFirestore.instance.collection('users').doc(userId).snapshots();
    final me = FirebaseAuth.instance.currentUser!.uid;
    final follow = FollowService();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<cf.DocumentSnapshot<Map<String, dynamic>>>(
        stream: doc,
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final d = s.data!;
          if (!d.exists) return const Center(child: Text('المستخدم غير موجود'));
          final data = d.data()!;
          final name = (data['displayName'] ?? 'User') as String;
          final bio = (data['bio'] ?? '') as String;
          final link = (data['link'] ?? '') as String;
          final followers = (data['followers'] ?? 0) as int;
          final following = (data['following'] ?? 0) as int;
          final vip = (data['vipLevel'] ?? 'Bronze') as String;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: const CircleAvatar(radius: 28, child: Icon(Icons.person)),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('VIP: $vip • $followers متابع • $following يتابع'),
              ),
              if (bio.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(bio),
              ),
              if (link.isNotEmpty) Text(link, style: const TextStyle(color: kTeal)),
              const SizedBox(height: 12),
              FutureBuilder<bool>(
                future: follow.isFollowing(me, userId),
                builder: (c2, fsnap) {
                  final isF = fsnap.data == true;
                  return Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => isF ? follow.unfollow(me, userId) : follow.follow(me, userId),
                        icon: Icon(isF ? Icons.remove_circle_outline : Icons.person_add_alt_1_rounded),
                        label: Text(isF ? 'إلغاء المتابعة' : 'متابعة'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        // CODEX-BEGIN:COMPILE_FIX::publicprofile-snackbar
                        onPressed: () => _openDM(c2, userId),
                        // CODEX-END:COMPILE_FIX::publicprofile-snackbar
                        icon: const Icon(Icons.chat_bubble_rounded),
                        label: const Text('رسالة'),
                      ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // CODEX-BEGIN:COMPILE_FIX::publicprofile-snackbar
  Future<void> _openDM(BuildContext ctx, String uid2) async {
    final me = FirebaseAuth.instance.currentUser!.uid;
    // CODEX-BEGIN:PROFILE_DM
    final service = FirestoreService();
    final result = await service.openOrCreateDirectThread(
      currentUid: me,
      otherUid: uid2,
    );
    if (result is SafeSuccess<String>) {
      navigatorKey.currentState?.pushNamed('/dm', arguments: result.value);
    } else if (result is SafeFailure<String>) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
    // CODEX-END:PROFILE_DM
  }
  // CODEX-END:COMPILE_FIX::publicprofile-snackbar
}

// ---------------------- Inbox (Threads list) ----------------------
// CODEX-BEGIN:INBOX_PAGE
class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestoreService = FirestoreService();
  final List<InboxThreadItem> _threads = <InboxThreadItem>[];
  cf.DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;
  late final String _currentUid;

  @override
  void initState() {
    super.initState();
    _currentUid = FirebaseAuth.instance.currentUser!.uid;
    _scrollController.addListener(_onScroll);
    _loadPage(reset: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    if (_scrollController.position.extentAfter < 320) {
      _loadPage(reset: false);
    }
  }

  Future<void> _loadPage({required bool reset}) async {
    if (_loadingMore) return;
    if (reset) {
      setState(() {
        _initialLoading = true;
        _loadingMore = true;
        _errorMessage = null;
        _hasMore = true;
        _lastDoc = null;
        _threads.clear();
      });
    } else {
      setState(() {
        _loadingMore = true;
      });
    }

    final result = await _firestoreService.fetchInboxThreads(
      currentUid: _currentUid,
      startAfter: reset ? null : _lastDoc,
      limit: 30,
    );
    if (!mounted) return;

    if (result is SafeSuccess<InboxThreadsPage>) {
      setState(() {
        _threads.addAll(result.value.threads);
        _lastDoc = result.value.lastDocument;
        _hasMore = result.value.hasMore;
        _errorMessage = null;
        _initialLoading = false;
        _loadingMore = false;
      });
    } else if (result is SafeFailure<InboxThreadsPage>) {
      setState(() {
        _errorMessage = result.message;
        _initialLoading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    await _loadPage(reset: true);
  }

  Widget _buildList() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: TextButton(
          onPressed: () => _loadPage(reset: true),
          child: const Text('حدث خطأ، حاول مرة أخرى'),
        ),
      );
    }
    if (_threads.isEmpty) {
      return Center(
        child: TextButton.icon(
          onPressed: () => navigatorKey.currentState?.pushNamed('/people'),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('ابدأ محادثة'),
        ),
      );
    }
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _threads.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        if (i >= _threads.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final thread = _threads[i];
        final other = thread.members.firstWhere((x) => x != _currentUid, orElse: () => _currentUid);
        final last = thread.lastMessage ?? '';
        final lastAt = thread.updatedAt;
        final unread = thread.unread[_currentUid] ?? 0;

        return Card(
          child: ListTile(
            leading: Stack(
              children: [
                const CircleAvatar(child: Icon(Icons.person)),
                if (unread > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ),
              ],
            ),
            title: Text(other, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(last, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(shortTime(lastAt), style: const TextStyle(fontSize: 11, color: kGray)),
            onTap: () => navigatorKey.currentState?.pushNamed('/dm', arguments: thread.id),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildList();
    // CODEX-BEGIN:ADMIN_BLOCK_INBOX
    final appUser = context.watch<AppUser>();
    final bool blocked = appUser.profile['blocked'] == true;
    void showBlockedSnack() {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تقييد الرسائل الخاصة مؤقتاً من قبل الإدارة.')),
      );
    }
    // CODEX-END:ADMIN_BLOCK_INBOX
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox')),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: content is ListView
            ? content
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: content,
              ),
            ],
          ),
      ),
      floatingActionButton: FloatingActionButton(
        // CODEX-BEGIN:ADMIN_BLOCK_INBOX_FAB
        onPressed: blocked
            ? showBlockedSnack
            : () => navigatorKey.currentState?.pushNamed('/people'),
        // CODEX-END:ADMIN_BLOCK_INBOX_FAB
        child: const Icon(Icons.person_search_rounded),
      ),
    );
  }
}
// CODEX-END:INBOX_PAGE

// ---------------------- DM Thread Page ----------------------
class DMPage extends StatefulWidget {
  const DMPage({super.key});
  @override
  State<DMPage> createState() => _DMPageState();
}

class _DMPageState extends State<DMPage> {
  late String threadId;
  String otherUid = '';
  final c = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    threadId = (ModalRoute.of(context)!.settings.arguments ?? '') as String;
  }

  Stream<cf.QuerySnapshot<Map<String, dynamic>>> _messages() {
    return cf.FirebaseFirestore.instance.collection('dm_threads').doc(threadId)
      .collection('messages').orderBy('createdAt', descending: true).limit(50).snapshots();
  }

  Future<void> _resolveOtherUid() async {
    final th = await cf.FirebaseFirestore.instance.collection('dm_threads').doc(threadId).get();
    final parts = List<String>.from((th.data()?['members'] ?? []).cast<String>());
    final me = FirebaseAuth.instance.currentUser!.uid;
    otherUid = parts.firstWhere((x) => x != me, orElse: ()=> me);
    setState((){});
  }

  Future<void> _send() async {
    final me = FirebaseAuth.instance.currentUser!.uid;
    final txt = c.text.trim();
    if (txt.isEmpty) return;
    final ref = cf.FirebaseFirestore.instance.collection('dm_threads').doc(threadId);
    await ref.collection('messages').add({
      'from': me,
      'text': txt,
      'createdAt': cf.FieldValue.serverTimestamp(),
    });
    await ref.set({
      'lastMessage': txt,
      'updatedAt': cf.FieldValue.serverTimestamp(),
      'unread': { otherUid: cf.FieldValue.increment(1), me: 0 },
    }, cf.SetOptions(merge: true));
    c.clear();
  }

  @override
  void initState() {
    super.initState();
    _resolveOtherUid();
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser!.uid;
    // CODEX-BEGIN:PRIVACY_DM_READ_RECEIPTS
    final readReceiptsEnabled = context.watch<PrivacySettingsController>().settings?.readReceipts ?? true;
    // CODEX-END:PRIVACY_DM_READ_RECEIPTS
    return Scaffold(
      appBar: AppBar(title: Text(otherUid.isEmpty ? 'Loading...' : otherUid)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<cf.QuerySnapshot<Map<String, dynamic>>>(
              stream: _messages(),
              builder: (c, s) {
                if (!s.hasData) return const Center(child: CircularProgressIndicator());
                final docs = s.data!.docs;
                // عند فتح الشاشة اعتبر الرسائل مقروءة
                if (readReceiptsEnabled) {
                  cf.FirebaseFirestore.instance.collection('dm_threads').doc(threadId)
                      .set({'unread': {me: 0}}, cf.SetOptions(merge: true));
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data();
                    final mine = d['from'] == me;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: mine ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(d['text'] ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: c,
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالة خاصة…',
                        filled: true, border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(14))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(onPressed: _send, child: const Icon(Icons.send_rounded)),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

// ===================== main.dart — Chat-MVP (ULTRA FINAL) [Part 7/12] =====================
// Advanced Profile: view + edit + upload avatar/cover to Firebase Storage

class StoryRingAvatar extends StatelessWidget {
  final String uid;
  final String avatarUrl;
  final double radius;
  const StoryRingAvatar({super.key, required this.uid, required this.avatarUrl, this.radius = 40});

  Stream<cf.QuerySnapshot<Map<String, dynamic>>> _storiesStream() {
    if (uid.isEmpty) {
      return Stream<cf.QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    final since = DateTime.now().subtract(const Duration(hours: 24));
    final ref = cf.FirebaseFirestore.instance
        .collection('stories')
        .doc(uid)
        .collection('items')
        .where('createdAt', isGreaterThanOrEqualTo: cf.Timestamp.fromDate(since))
        .orderBy('createdAt', descending: true)
        .limit(25);
    return ref.snapshots(includeMetadataChanges: true);
  }

  Widget _buildAvatar(BuildContext context, {required bool hasActive, required int count}) {
    final theme = Theme.of(context);
    final innerRadius = math.max(0.0, radius - 4);
    final inner = CircleAvatar(
      radius: innerRadius,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
      child: avatarUrl.isEmpty ? const Icon(Icons.person, size: 36, color: kTeal) : null,
    );

    if (!hasActive) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.white,
        child: inner,
      );
    }

    final ring = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: inner,
    );

    final badgeLabel = count > 9 ? '9+' : '$count';
    final badge = Positioned(
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: count > 9 ? 6 : 5, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        child: Center(
          child: Text(
            badgeLabel,
            style: TextStyle(
              color: theme.colorScheme.onPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: Colors.white,
          child: ring,
        ),
        badge,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<cf.QuerySnapshot<Map<String, dynamic>>>(
      stream: _storiesStream(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final now = DateTime.now();
        int activeCount = 0;
        for (final doc in docs) {
          final data = doc.data();
          final expiresRaw = data['expiresAt'];
          if (expiresRaw != null) {
            final expires = normalizeTimestamp(expiresRaw, fallback: now).toDate();
            if (expires.isAfter(now)) activeCount++;
          } else {
            final created = normalizeTimestamp(data['createdAt'], fallback: now).toDate();
            if (created.isAfter(now.subtract(const Duration(hours: 24)))) activeCount++;
          }
        }
        final hasActive = activeCount > 0;
        return SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: _buildAvatar(context, hasActive: hasActive, count: activeCount),
        );
      },
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('غير مسجّل')));
    }
    final doc = cf.FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    final coinsService = CoinsService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'الإعدادات',
            onPressed: ()=> navigatorKey.currentState?.pushNamed('/privacy'),
            icon: const Icon(Icons.lock_person_rounded),
          ),
          IconButton(
            tooltip: 'تحرير',
            onPressed: ()=> Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfilePage())),
            icon: const Icon(Icons.edit_rounded),
          ),
        ],
      ),
      body: StreamBuilder<cf.DocumentSnapshot<Map<String, dynamic>>>(
        stream: doc,
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final d = s.data!;
          final data = d.data() ?? {};
          final name = (data['displayName'] ?? 'Guest') as String;
          final vip = (data['vipLevel'] ?? 'Bronze') as String;
          final coinsInitial = (data['coins'] ?? 0) as int;
          final followers = (data['followers'] ?? 0) as int;
          final following = (data['following'] ?? 0) as int;
          final bio = (data['bio'] ?? '') as String;
          final link = (data['link'] ?? '') as String;
          final avatar = (data['avatarUrl'] ?? '') as String;
          final cover  = (data['coverUrl'] ?? '') as String;

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              // Cover
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16/9,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        image: cover.isNotEmpty ? DecorationImage(image: NetworkImage(cover), fit: BoxFit.cover) : null,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0, left: 16,
                    child: Container(
                      transform: Matrix4.translationValues(0, 24, 0),
                      child: StoryRingAvatar(uid: uid, avatarUrl: avatar, radius: 40),
                    ),
                  ),
                  Positioned(
                    right: 12, bottom: 12,
                    child: FilledButton.icon(
                      onPressed: ()=> Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfilePage())),
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text('تعديل'),
                    ),
                  )
                ],
              ),
              const SizedBox(height: 28),
              // Info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.workspace_premium_rounded, color: kGold, size: 18),
                        const SizedBox(width: 6),
                        Text('VIP: $vip'),
                        const SizedBox(width: 12),
                        const Icon(Icons.monetization_on_rounded, color: kTeal, size: 18),
                        const SizedBox(width: 4),
                        StreamBuilder<int>(
                          stream: coinsService.coinsStream(uid),
                          initialData: coinsInitial,
                          builder: (context, snap) {
                            final coins = snap.data ?? coinsInitial;
                            return Text('$coins Coins');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('${compactNumber(followers)} متابع'),
                        const SizedBox(width: 12),
                        Text('${compactNumber(following)} يتابع'),
                      ],
                    ),
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(bio),
                    ],
                    if (link.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () => Clipboard.setData(ClipboardData(text: link))
                          .then((_) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الرابط')))),
                        child: Text(link, style: const TextStyle(color: kTeal, decoration: TextDecoration.underline)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              StoryStrip(uid: uid, displayName: name, avatarUrl: avatar),
              const SizedBox(height: 16),
              const Divider(),
              // Quick actions
              ListTile(
                leading: const Icon(Icons.mail_rounded),
                title: const Text('Inbox / الرسائل الخاصة'),
                trailing: const Icon(Icons.chevron_right),
                onTap: ()=> navigatorKey.currentState?.pushNamed('/inbox'),
              ),
              ListTile(
                leading: const Icon(Icons.people_alt_rounded),
                title: const Text('اكتشف أشخاص'),
                trailing: const Icon(Icons.chevron_right),
                onTap: ()=> navigatorKey.currentState?.pushNamed('/people'),
              ),
              ListTile(
                leading: const Icon(Icons.verified_user_rounded),
                title: const Text('Privacy & Safety'),
                trailing: const Icon(Icons.chevron_right),
                onTap: ()=> navigatorKey.currentState?.pushNamed('/privacy'),
              ),
              ListTile(
                leading: const Icon(Icons.wallet_rounded),
                title: const Text('Wallet / VIP'),
                trailing: const Icon(Icons.chevron_right),
                onTap: ()=> navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const WalletPage())),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// =============== Edit Profile ===============
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _name   = TextEditingController();
  final _bio    = TextEditingController();
  final _link   = TextEditingController();
  final _location = TextEditingController();
  DateTime? _birthday;

  final _imagePicker = ImagePicker();
  bool _saving = false;

  String _avatarUrl = '';
  String _coverUrl  = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final d = await cf.FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = d.data() ?? {};
    _name.text = (data['displayName'] ?? '') as String;
    _bio.text  = (data['bio'] ?? '') as String;
    _link.text = (data['link'] ?? '') as String;
    _location.text = (data['location'] ?? '') as String;
    _avatarUrl = (data['avatarUrl'] ?? '') as String;
    _coverUrl  = (data['coverUrl'] ?? '') as String;
    final ts = data['birthday'];
    if (ts is cf.Timestamp) _birthday = ts.toDate();
    if (mounted) setState((){});
  }

  Future<void> _pickAvatar() async {
    final x = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (x == null) return;
    setState(()=> _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final ref = FirebaseStorage.instance.ref('users/$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(File(x.path), SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await cf.FirebaseFirestore.instance.collection('users').doc(uid).set({'avatarUrl': url}, cf.SetOptions(merge: true));
      _avatarUrl = url;
    } finally {
      if (mounted) setState(()=> _saving = false);
    }
  }

  Future<void> _pickCover() async {
    final x = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (x == null) return;
    setState(()=> _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final ref = FirebaseStorage.instance.ref('users/$uid/cover_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(File(x.path), SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await cf.FirebaseFirestore.instance.collection('users').doc(uid).set({'coverUrl': url}, cf.SetOptions(merge: true));
      _coverUrl = url;
    } finally {
      if (mounted) setState(()=> _saving = false);
    }
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    setState(()=> _saving = true);
    try {
      await cf.FirebaseFirestore.instance.collection('users').doc(uid).set({
        'displayName': _name.text.trim().isEmpty ? 'User' : _name.text.trim(),
        'bio'        : _bio.text.trim(),
        'link'       : _link.text.trim(),
        'location'   : _location.text.trim(),
        if (_birthday != null) 'birthday': cf.Timestamp.fromDate(_birthday!),
        'updatedAt'  : cf.FieldValue.serverTimestamp(),
      }, cf.SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التغييرات ✅')));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(()=> _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل البروفايل'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('حفظ'),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Cover + Avatar pickers
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16/9,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    image: _coverUrl.isNotEmpty ? DecorationImage(image: NetworkImage(_coverUrl), fit: BoxFit.cover) : null,
                  ),
                ),
              ),
              Positioned(
                right: 12, bottom: 12,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _pickCover,
                  icon: const Icon(Icons.photo_camera_back_outlined),
                  label: const Text('تغيير الغلاف'),
                ),
              ),
              Positioned(
                left: 16, bottom: -22,
                child: GestureDetector(
                  onTap: _saving ? null : _pickAvatar,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(999),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                    ),
                    padding: const EdgeInsets.all(3),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: _avatarUrl.isNotEmpty ? NetworkImage(_avatarUrl) : null,
                      child: _avatarUrl.isEmpty ? const Icon(Icons.person, size: 36, color: kTeal) : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'الاسم المعروض',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bio,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'نبذة',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _link,
            decoration: const InputDecoration(
              labelText: 'رابط (Website / Social)',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: 'الموقع',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.cake_outlined),
            title: Text(_birthday == null ? 'تاريخ الميلاد' : _birthday!.toString().substring(0,10)),
            trailing: const Icon(Icons.edit_calendar_rounded),
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _birthday ?? DateTime(now.year - 18, now.month, now.day),
                firstDate: DateTime(1900),
                lastDate: now,
              );
              if (picked != null) setState(()=> _birthday = picked);
            },
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('حفظ'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: ()=> navigatorKey.currentState?.pushNamed('/privacy'),
            icon: const Icon(Icons.lock_person_rounded),
            label: const Text('إعدادات الخصوصية'),
          ),
        ],
      ),
    );
  }
}
// ===================== main.dart — Chat-MVP (ULTRA FINAL) [Part 8/12] =====================
// Advanced Admin & Moderation: Reports dashboard, actions (ban/mute/kick), filters, action logs, room selector

// ---------------------- Admin Portal (rooms picker) ----------------------
class AdminPortalPage extends StatelessWidget {
  const AdminPortalPage({super.key});

  @override
  Widget build(BuildContext context) {
    // CODEX-BEGIN:ADMIN_PORTAL
    final appUser = context.watch<AppUser>();
    final uid = appUser.firebaseUser?.uid;
    final bool isAdmin = appUser.profile['isAdmin'] == true;
    return AdminDashboardPage(uid: uid, isAdmin: isAdmin);
    // CODEX-END:ADMIN_PORTAL
  }
}

// ---------------------- Admin Room Panel (tabs) ----------------------
class AdminRoomPanelPage extends StatefulWidget {
  const AdminRoomPanelPage({super.key});
  @override
  State<AdminRoomPanelPage> createState() => _AdminRoomPanelPageState();
}

class _AdminRoomPanelPageState extends State<AdminRoomPanelPage> with SingleTickerProviderStateMixin {
  late String roomId;
  late TabController tc;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        roomId = args;
      } else if (args is Map && args['roomId'] is String) {
        roomId = args['roomId'] as String;
      } else {
        roomId = 'room_demo';
      }
      tc = TabController(length: 3, vsync: this);
      _initialized = true;
    }
  }

  @override
  void dispose() {
    tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('إدارة الغرفة — $roomId'),
        bottom: TabBar(
          controller: tc,
          tabs: const [
            Tab(text: 'البلاغات', icon: Icon(Icons.report)),
            Tab(text: 'الأعضاء', icon: Icon(Icons.group)),
            Tab(text: 'السجل', icon: Icon(Icons.receipt_long)),
          ],
        ),
      ),
      body: TabBarView(
        controller: tc,
        children: [
          _ReportsTab(roomId: roomId),
          _MembersTab(roomId: roomId),
          _ActionsLogTab(roomId: roomId),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: ()=> _showQuickActions(context, roomId),
        icon: const Icon(Icons.shield_moon_rounded),
        label: const Text('إجراء سريع'),
      ),
    );
  }
}

// ---------------------- Reports Tab ----------------------
class _ReportsTab extends StatefulWidget {
  final String roomId;
  const _ReportsTab({required this.roomId});
  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}
class _ReportsTabState extends State<_ReportsTab> {
  final _status = ValueNotifier<String>('open'); // open | reviewed | actioned | dismissed | all
  final _type   = ValueNotifier<String>('all');  // message | user | room | all
  final _search = TextEditingController();

  cf.Query<Map<String, dynamic>> _buildQuery() {
    var q = cf.FirebaseFirestore.instance.collection('rooms').doc(widget.roomId)
      .collection('reports').orderBy('createdAt', descending: true) as cf.Query<Map<String, dynamic>>;
    if (_status.value != 'all') q = q.where('status', isEqualTo: _status.value);
    if (_type.value != 'all')   q = q.where('targetType', isEqualTo: _type.value);
    return q.limit(100);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // filters
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Wrap(
            spacing: 8, runSpacing: 6,
            children: [
              _ChipPicker<String>(
                title: 'الحالة', valueList: const ['open','reviewed','actioned','dismissed','all'],
                value: _status, labels: const {
                  'open':'مفتوح','reviewed':'مُراجع','actioned':'تم إجراء','dismissed':'مرفوض','all':'الكل'
                },
              ),
              _ChipPicker<String>(
                title: 'النوع', valueList: const ['all','message','user','room'],
                value: _type, labels: const {
                  'all':'الكل','message':'رسالة','user':'مستخدم','room':'غرفة'
                },
              ),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: 'بحث بالـ targetId / السبب…',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_)=> setState((){}),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<cf.QuerySnapshot<Map<String, dynamic>>>(
            stream: _buildQuery().snapshots(),
            builder: (c, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              var docs = s.data!.docs;
              final q = _search.text.trim().toLowerCase();
              if (q.isNotEmpty) {
                docs = docs.where((d) {
                  final m = d.data();
                  final txt = '${m['targetId'] ?? ''} ${m['reason'] ?? ''} ${m['type'] ?? ''}'.toLowerCase();
                  return txt.contains(q);
                }).toList();
              }
              if (docs.isEmpty) return const Center(child: Text('لا توجد بلاغات مطابقة.'));
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final id = docs[i].id;
                  final d  = docs[i].data();
                  final targetType = d['targetType'] ?? d['type'] ?? 'message';
                  final reason = d['reason'] ?? '';
                  final status = d['status'] ?? 'open';
                  final targetId = d['targetId'] ?? '';
                  final createdAt = d['createdAt'] as cf.Timestamp?;
                  final createdBy = d['createdBy'] ?? '';

                  return Card(
                    child: ListTile(
                      leading: Icon(
                        targetType=='user' ? Icons.person :
                        targetType=='room' ? Icons.forum :
                        Icons.message_rounded, color: kTeal),
                      title: Text('$targetType → $targetId'),
                      subtitle: Text('سبب: $reason • حالة: $status'),
                      trailing: Text(shortTime(createdAt), style: const TextStyle(fontSize: 11, color: kGray)),
                      onTap: ()=> _openReportSheet(context, widget.roomId, id, d),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openReportSheet(BuildContext ctx, String roomId, String reportId, Map<String, dynamic> data) async {
    showModalBottomSheet(
      context: ctx, isScrollControlled: true,
      builder: (_) => _ReportActionSheet(roomId: roomId, reportId: reportId, data: data),
    );
  }
}

// ---------------------- Members Tab (ban/mute/kick) ----------------------
class _MembersTab extends StatefulWidget {
  final String roomId;
  const _MembersTab({required this.roomId});
  @override
  State<_MembersTab> createState() => _MembersTabState();
}
class _MembersTabState extends State<_MembersTab> {
  final _q = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final mref = cf.FirebaseFirestore.instance.collection('rooms').doc(widget.roomId)
      .collection('members').orderBy('joinedAt', descending: true).limit(200).snapshots();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _q,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث عن عضو…'),
            onChanged: (_)=> setState((){}),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<cf.QuerySnapshot<Map<String, dynamic>>>(
            stream: mref,
            builder: (c, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              var docs = s.data!.docs;
              final q = _q.text.trim().toLowerCase();
              if (q.isNotEmpty) {
                docs = docs.where((d) {
                  final name = (d.data()['displayName'] ?? d.id).toString().toLowerCase();
                  return name.contains(q) || d.id.toLowerCase().contains(q);
                }).toList();
              }
              if (docs.isEmpty) return const Center(child: Text('لا أعضاء مطابقين.'));
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final uid = docs[i].id;
                  final m = docs[i].data();
                  final name = (m['displayName'] ?? uid) as String;
                  final mutedUntil = m['mutedUntil'] as cf.Timestamp?;
                  final bannedUntil = m['bannedUntil'] as cf.Timestamp?;
                  final role = (m['role'] ?? 'member') as String;

                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(name),
                      subtitle: Text('الدور: $role'
                          '${mutedUntil!=null ? ' • مكتوم حتى ${shortTime(mutedUntil)}' : ''}'
                          '${bannedUntil!=null ? ' • محظور حتى ${shortTime(bannedUntil)}' : ''}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.admin_panel_settings_rounded),
                        onPressed: ()=> _openMemberSheet(context, widget.roomId, uid, name),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openMemberSheet(BuildContext ctx, String roomId, String uid, String name) async {
    showModalBottomSheet(
      context: ctx, isScrollControlled: true,
      builder: (_) => _MemberActionSheet(roomId: roomId, targetUid: uid, targetName: name),
    );
  }
}

// ---------------------- Actions Log Tab ----------------------
class _ActionsLogTab extends StatelessWidget {
  final String roomId;
  const _ActionsLogTab({required this.roomId});

  @override
  Widget build(BuildContext context) {
    final q = cf.FirebaseFirestore.instance.collection('rooms').doc(roomId)
      .collection('moderation').doc('actionsRoot')
      .collection('actions').orderBy('createdAt', descending: true).limit(200).snapshots();

    return StreamBuilder<cf.QuerySnapshot<Map<String, dynamic>>>(
      stream: q,
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final docs = s.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('لا يوجد سجل إجراءات بعد.'));
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final act = (d['action'] ?? 'action') as String;
            final by = (d['createdBy'] ?? '') as String;
            final at = d['createdAt'] as cf.Timestamp?;
            final target = (d['targetUserId'] ?? d['targetId'] ?? '') as String;
            final reason = (d['reason'] ?? '') as String;
            final note = (d['note'] ?? '') as String;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.gavel_rounded, color: kTeal),
                title: Text('$act → $target'),
                subtitle: Text([if (reason.isNotEmpty) 'سبب: $reason', if (note.isNotEmpty) 'ملاحظة: $note'].join(' • ')),
                trailing: Text(shortTime(at), style: const TextStyle(fontSize: 11, color: kGray)),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------- Quick Actions FAB ----------------------
Future<void> _showQuickActions(BuildContext context, String roomId) async {
  final cUid = TextEditingController();
  final cReason = TextEditingController();
  String action = 'mute_1h'; // mute_1h, mute_24h, ban_7d, ban_30d, kick

  await showModalBottomSheet(
    context: context, isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('إجراء سريع', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(controller: cUid, decoration: const InputDecoration(labelText: 'User ID')),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: action,
            decoration: const InputDecoration(labelText: 'الإجراء'),
            items: const [
              DropdownMenuItem(value: 'mute_1h', child: Text('كتم 1 ساعة')),
              DropdownMenuItem(value: 'mute_24h', child: Text('كتم 24 ساعة')),
              DropdownMenuItem(value: 'ban_7d', child: Text('حظر 7 أيام')),
              DropdownMenuItem(value: 'ban_30d', child: Text('حظر 30 يوم')),
              DropdownMenuItem(value: 'kick', child: Text('طرد فوري')),
            ],
            onChanged: (v){ action = v ?? action; },
          ),
          const SizedBox(height: 8),
          TextField(controller: cReason, decoration: const InputDecoration(labelText: 'سبب (اختياري)')),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              final uid = cUid.text.trim();
              if (uid.isEmpty) return;
              await _applyModerationAction(roomId: roomId, targetUid: uid, action: action, reason: cReason.text.trim());
              if (context.mounted) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تنفيذ الإجراء ✅')));
            },
            child: const Text('تنفيذ'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

// ---------------------- Report Action Sheet ----------------------
class _ReportActionSheet extends StatefulWidget {
  final String roomId;
  final String reportId;
  final Map<String, dynamic> data;
  const _ReportActionSheet({required this.roomId, required this.reportId, required this.data});
  @override
  State<_ReportActionSheet> createState() => _ReportActionSheetState();
}
class _ReportActionSheetState extends State<_ReportActionSheet> {
  String _status = 'reviewed';
  String _quick = 'warn';
  final _note = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final targetType = d['targetType'] ?? d['type'];
    final targetId = d['targetId'] ?? '';
    final reason = d['reason'] ?? '';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 16),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Container(height: 4, width: 48, margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(999))),
            Text('بلاغ: $targetType → $targetId', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('السبب: $reason', style: const TextStyle(color: kGray)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('تغيير الحالة:'),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _status,
                  items: const [
                    DropdownMenuItem(value: 'open', child: Text('مفتوح')),
                    DropdownMenuItem(value: 'reviewed', child: Text('مُراجع')),
                    DropdownMenuItem(value: 'actioned', child: Text('تم إجراء')),
                    DropdownMenuItem(value: 'dismissed', child: Text('مرفوض')),
                  ],
                  onChanged: (v)=> setState(()=> _status = v ?? _status),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    await cf.FirebaseFirestore.instance.collection('rooms').doc(widget.roomId)
                      .collection('reports').doc(widget.reportId).update({'status': _status});
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('حفظ الحالة'),
                ),
              ],
            ),
            const Divider(),
            Align(alignment: Alignment.centerLeft, child: Text('إجراء سريع على الهدف:', style: Theme.of(context).textTheme.titleSmall)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text('تحذير'), selected: _quick=='warn', onSelected: (_)=> setState(()=> _quick='warn')),
                ChoiceChip(label: const Text('كتم 24h'), selected: _quick=='mute_24h', onSelected: (_)=> setState(()=> _quick='mute_24h')),
                ChoiceChip(label: const Text('حظر 7d'), selected: _quick=='ban_7d', onSelected: (_)=> setState(()=> _quick='ban_7d')),
                ChoiceChip(label: const Text('طرد'), selected: _quick=='kick', onSelected: (_)=> setState(()=> _quick='kick')),
              ],
            ),
            const SizedBox(height: 8),
            TextField(controller: _note, decoration: const InputDecoration(hintText: 'ملاحظة داخلية…')),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                if (targetType == 'user' && (targetId as String).isNotEmpty) {
                  await _applyModerationAction(roomId: widget.roomId, targetUid: targetId, action: _quick, reason: reason, note: _note.text.trim());
                  await cf.FirebaseFirestore.instance.collection('rooms').doc(widget.roomId)
                    .collection('reports').doc(widget.reportId).update({'status': 'actioned'});
                  if (context.mounted) Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إجراء الإجراء وتحديث الحالة')));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الهدف ليس مستخدمًا أو المعرف فارغ')));
                }
              },
              icon: const Icon(Icons.gavel_rounded),
              label: const Text('تنفيذ الإجراء'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ---------------------- Member Action Sheet ----------------------
class _MemberActionSheet extends StatefulWidget {
  final String roomId;
  final String targetUid;
  final String targetName;
  const _MemberActionSheet({required this.roomId, required this.targetUid, required this.targetName});
  @override
  State<_MemberActionSheet> createState() => _MemberActionSheetState();
}
class _MemberActionSheetState extends State<_MemberActionSheet> {
  String action = 'mute_1h';
  final _reason = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('عضو: ${widget.targetName}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: action,
            decoration: const InputDecoration(labelText: 'الإجراء'),
            items: const [
              DropdownMenuItem(value: 'mute_1h', child: Text('كتم 1 ساعة')),
              DropdownMenuItem(value: 'mute_24h', child: Text('كتم 24 ساعة')),
              DropdownMenuItem(value: 'ban_7d', child: Text('حظر 7 أيام')),
              DropdownMenuItem(value: 'ban_30d', child: Text('حظر 30 يوم')),
              DropdownMenuItem(value: 'kick', child: Text('طرد')),
              DropdownMenuItem(value: 'warn', child: Text('تحذير')),
            ],
            onChanged: (v)=> action = v ?? action,
          ),
          const SizedBox(height: 8),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: 'سبب (اختياري)')),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              await _applyModerationAction(
                roomId: widget.roomId,
                targetUid: widget.targetUid,
                action: action,
                reason: _reason.text.trim(),
              );
              if (context.mounted) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تنفيذ الإجراء ✅')));
            },
            icon: const Icon(Icons.security_rounded),
            label: const Text('تنفيذ'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ---------------------- Helper: Apply Moderation Action ----------------------
Future<void> _applyModerationAction({
  required String roomId,
  required String targetUid,
  required String action,
  String? reason,
  String? note,
}) async {
  final fs = cf.FirebaseFirestore.instance;
  final me = FirebaseAuth.instance.currentUser?.uid ?? 'system';
  final now = DateTime.now();

  // members doc
  final mref = fs.collection('rooms').doc(roomId).collection('members').doc(targetUid);
  final logRef = fs.collection('rooms').doc(roomId)
    .collection('moderation').doc('actionsRoot')
    .collection('actions').doc();

  Duration? muteDur;
  Duration? banDur;
  bool kick = false;

  switch (action) {
    case 'mute_1h':  muteDur = const Duration(hours: 1); break;
    case 'mute_24h': muteDur = const Duration(hours: 24); break;
    case 'ban_7d':   banDur = const Duration(days: 7); break;
    case 'ban_30d':  banDur = const Duration(days: 30); break;
    case 'kick':     kick = true; break;
    case 'warn':     break;
  }

  await fs.runTransaction((tx) async {
    final updates = <String, dynamic>{};
    if (muteDur != null) updates['mutedUntil'] = cf.Timestamp.fromDate(now.add(muteDur));
    if (banDur != null)  updates['bannedUntil'] = cf.Timestamp.fromDate(now.add(banDur));
    if (kick)            updates['kickedAt'] = cf.Timestamp.fromDate(now);

    if (updates.isNotEmpty) {
      tx.set(mref, updates, cf.SetOptions(merge: true));
    }

    tx.set(logRef, {
      'action': action,
      'targetUserId': targetUid,
      'reason': reason,
      'note': note,
      'createdBy': me,
      'createdAt': cf.FieldValue.serverTimestamp(),
    });
  });

  // لو طرد: يمكنك كذلك إزالة العضو من قائمة أعضاء الغرفة إن أردت
  if (kick) {
    try {
      await fs.collection('rooms').doc(roomId).collection('members').doc(targetUid).delete();
    } catch (_) {}
  }
}

// ---------------------- Reusable: Chip Picker ----------------------
class _ChipPicker<T> extends StatelessWidget {
  final String title;
  final List<T> valueList;
  final Map<T, String>? labels;
  final ValueNotifier<T> value;
  const _ChipPicker({required this.title, required this.valueList, required this.value, this.labels, super.key});
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6, crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(title, style: const TextStyle(color: kGray)),
        ...valueList.map((v) => ChoiceChip(
          label: Text(labels?[v] ?? v.toString()),
          selected: value.value == v,
          onSelected: (_)=> value.value = v,
        )),
      ],
    );
  }
}
// ===================== main.dart — Chat-MVP (ULTRA FINAL) [Part 9/12] =====================
// Communities/Rooms Advanced: Create room, Roles, Invites, Rules, Bad-words filter, Auto-welcome

// -------- Data shapes (Firestore suggested) --------
// rooms/{roomId}:
//  { name, about, public: true/false, ownerId, createdAt, meta:{members, messages, lastMsgAt}, rules:[...], config:{badWords:[], autoMuteOnBadWord:true, muteMinutes:10, welcomeText:""} }
// rooms/{roomId}/members/{uid}: { role: owner|admin|mod|member, joinedAt, mutedUntil?, bannedUntil? }
// rooms/{roomId}/invites/{code}: { code, createdBy, createdAt, uses:0, maxUses:null|number, expiresAt:null|ts }
// rooms/{roomId}/messages/{msgId}: { type:'text|image|video|file|system', text, from, createdAt, ... }

// -------- Helpers --------
Future<String> createRoom({
  required String name,
  String? about,
  bool isPublic = true,
}) async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final ref = cf.FirebaseFirestore.instance.collection('rooms').doc();
  await ref.set({
    'name': name.trim(),
    'about': (about ?? '').trim(),
    'public': isPublic,
    'ownerId': uid,
    'createdAt': cf.FieldValue.serverTimestamp(),
    'meta': {'members': 1, 'messages': 0, 'lastMsgAt': cf.FieldValue.serverTimestamp()},
    'rules': [
      'احترام الجميع، لا سباب ولا تحرّش.',
      'ممنوع السبام والإعلانات غير المرخصة.',
    ],
    'config': {
      'badWords': ['سبّة','شتيمة','كلمة_ممنوعة'], // عدّلها من الإعدادات
      'autoMuteOnBadWord': true,
      'muteMinutes': 10,
      'welcomeText': '👋 أهلاً بك في الغرفة!',
    },
  });
  // ضمّ المالك كعضو owner
  await ref.collection('members').doc(uid).set({
    'role': 'owner',
    'joinedAt': cf.FieldValue.serverTimestamp(),
    'displayName': FirebaseAuth.instance.currentUser?.displayName ?? 'Owner',
  });
  // رسالة ترحيب مبدئية
  await postSystemMessage(roomId: ref.id, text: 'تم إنشاء الغرفة ✨');
  return ref.id;
}

Future<void> postSystemMessage({required String roomId, required String text}) async {
  final fs = cf.FirebaseFirestore.instance;
  final mref = fs.collection('rooms').doc(roomId).collection('messages').doc();
  await mref.set({
    'type': 'system',
    'text': text,
    'createdAt': cf.FieldValue.serverTimestamp(),
  });
  await fs.collection('rooms').doc(roomId)
    .set({'meta': {'lastMsgAt': cf.FieldValue.serverTimestamp()}}, cf.SetOptions(merge: true));
}

Future<String> generateInviteCode(String roomId, {int? maxUses, cf.Timestamp? expiresAt}) async {
  try {
    return await InvitesService.createInvite(roomId: roomId, maxUses: maxUses, expiresAt: expiresAt);
  } on FirebaseFunctionsException catch (err, stack) {
    debugPrint('generateInviteCode error: ${err.code} ${err.message}');
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    rethrow;
  } catch (err, stack) {
    debugPrint('generateInviteCode error: $err');
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    rethrow;
  }
}

String _randomCode(int len) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rnd = math.Random.secure();
  return List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join();
}

Future<bool> joinRoomWithCode(String code) async {
  try {
    final me = FirebaseAuth.instance.currentUser;
    final displayName = me?.displayName;
    final result = await InvitesService.redeemInvite(code: code, displayName: displayName);
    return result.joined;
  } on FirebaseFunctionsException catch (err, stack) {
    debugPrint('joinRoomWithCode error: ${err.code} ${err.message}');
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    return false;
  } catch (err, stack) {
    debugPrint('joinRoomWithCode error: $err');
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    return false;
  }
}

Future<bool> joinRoom(String roomId) async {
  final fs = cf.FirebaseFirestore.instance;
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final memRef = fs.collection('rooms').doc(roomId).collection('members').doc(uid);
  final exist = await memRef.get();
  if (!exist.exists) {
    await memRef.set({
      'role': 'member',
      'joinedAt': cf.FieldValue.serverTimestamp(),
      'displayName': FirebaseAuth.instance.currentUser?.displayName ?? 'Member',
    });
    await fs.collection('rooms').doc(roomId).set({
      'meta': {'members': cf.FieldValue.increment(1), 'lastMsgAt': cf.FieldValue.serverTimestamp()}
    }, cf.SetOptions(merge: true));
    // رسالة ترحيب
    final doc = await fs.collection('rooms').doc(roomId).get();
    final welcome = ((doc.data()?['config'] ?? {}) as Map)['welcomeText'] ?? '👋 أهلاً بك!';
    await postSystemMessage(roomId: roomId, text: '$welcome');
  }
  return true;
}
// ---------------------- Create Room Page ----------------------
class CreateRoomPage extends StatefulWidget {
  const CreateRoomPage({super.key});
  @override
  State<CreateRoomPage> createState() => _CreateRoomPageState();
}

class _CreateRoomPageState extends State<CreateRoomPage> {
  final _name = TextEditingController();
  final _about = TextEditingController();
  bool _public = true;
  bool _loading = false;

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب اسم الغرفة')));
      return;
    }
    setState(()=> _loading = true);
    try {
      final id = await createRoom(name: _name.text, about: _about.text, isPublic: _public);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إنشاء الغرفة ✅')));
        navigatorKey.currentState?.pushReplacementNamed('/room', arguments: id);
      }
    } finally { if (mounted) setState(()=> _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء غرفة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم الغرفة *')),
          const SizedBox(height: 8),
          TextField(controller: _about, maxLines: 3, decoration: const InputDecoration(labelText: 'وصف مختصر')),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _public, onChanged: (v)=> setState(()=> _public=v),
            title: const Text('غرفة عامة (مرئية للجميع)'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _create,
            icon: _loading ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.add_circle_outline),
            label: const Text('إنشاء'),
          ),
        ],
      ),
    );
  }
}
// ---------------------- Room Settings Page ----------------------
class RoomSettingsPage extends StatefulWidget {
  const RoomSettingsPage({super.key});
  @override
  State<RoomSettingsPage> createState() => _RoomSettingsPageState();
}

class _RoomSettingsPageState extends State<RoomSettingsPage> with SingleTickerProviderStateMixin {
  late String roomId;
  late TabController tc;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        roomId = args;
      } else if (args is Map && args['roomId'] is String) {
        roomId = args['roomId'] as String;
      } else {
        roomId = 'room_demo';
      }
      tc = TabController(length: 4, vsync: this);
      _initialized = true;
    }
  }

  @override
  void dispose() { tc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final roomDoc = cf.FirebaseFirestore.instance.collection('rooms').doc(roomId).snapshots();
    return Scaffold(
      appBar: AppBar(
        title: Text('إعدادات الغرفة — $roomId'),
        bottom: TabBar(
          controller: tc,
          tabs: const [
            Tab(text: 'الأساسيات', icon: Icon(Icons.tune_rounded)),
            Tab(text: 'القواعد', icon: Icon(Icons.rule_rounded)),
            Tab(text: 'الأدوار', icon: Icon(Icons.group_work_rounded)),
            Tab(text: 'دعوات', icon: Icon(Icons.link_rounded)),
          ],
        ),
      ),
      body: StreamBuilder<cf.DocumentSnapshot<Map<String, dynamic>>>(
        stream: roomDoc,
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final data = s.data!.data() ?? {};
          return TabBarView(
            controller: tc,
            children: [
              _RoomBasicsTab(roomId: roomId, data: data),
              _RoomRulesTab(roomId: roomId, data: data),
              _RoomRolesTab(roomId: roomId),
              _RoomInvitesTab(roomId: roomId),
            ],
          );
        },
      ),
    );
  }
}

class _RoomBasicsTab extends StatefulWidget {
  final String roomId; final Map<String, dynamic> data;
  const _RoomBasicsTab({required this.roomId, required this.data});
  @override
  State<_RoomBasicsTab> createState() => _RoomBasicsTabState();
}
class _RoomBasicsTabState extends State<_RoomBasicsTab> {
  late final nameC = TextEditingController(text: widget.data['name'] ?? '');
  late final aboutC = TextEditingController(text: widget.data['about'] ?? '');
  bool public = true;

  @override
  void initState() {
    super.initState();
    public = (widget.data['public'] == true);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(controller: nameC, decoration: const InputDecoration(labelText: 'الاسم')),
        const SizedBox(height: 8),
        TextField(controller: aboutC, maxLines: 3, decoration: const InputDecoration(labelText: 'الوصف')),
        const SizedBox(height: 8),
        SwitchListTile(value: public, onChanged: (v)=> setState(()=> public=v), title: const Text('غرفة عامة')),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            await cf.FirebaseFirestore.instance.collection('rooms').doc(widget.roomId).set({
              'name': nameC.text.trim(),
              'about': aboutC.text.trim(),
              'public': public,
              'updatedAt': cf.FieldValue.serverTimestamp(),
            }, cf.SetOptions(merge: true));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ ✅')));
          },
          child: const Text('حفظ'),
        )
      ],
    );
  }
}

class _RoomRulesTab extends StatefulWidget {
  final String roomId; final Map<String, dynamic> data;
  const _RoomRulesTab({required this.roomId, required this.data});
  @override
  State<_RoomRulesTab> createState() => _RoomRulesTabState();
}
class _RoomRulesTabState extends State<_RoomRulesTab> {
  late List<String> rules;
  late List<String> badWords;
  bool autoMute = true;
  int muteMinutes = 10;
  final ruleC = TextEditingController();
  final badC  = TextEditingController();
  final welcomeC = TextEditingController();

  @override
  void initState() {
    super.initState();
    rules = List<String>.from((widget.data['rules'] ?? const []).cast<String>());
    final cfg = (widget.data['config'] ?? {}) as Map;
    badWords = List<String>.from((cfg['badWords'] ?? const <String>[]).cast<String>());
    autoMute = cfg['autoMuteOnBadWord'] == true;
    muteMinutes = (cfg['muteMinutes'] ?? 10) as int;
    welcomeC.text = (cfg['welcomeText'] ?? '👋 أهلاً بك!') as String;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('قواعد الغرفة', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (int i=0;i<rules.length;i++)
          ListTile(
            leading: const Icon(Icons.rule_rounded),
            title: Text(rules[i]),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(()=> rules.removeAt(i)),
            ),
          ),
        Row(
          children: [
            Expanded(child: TextField(controller: ruleC, decoration: const InputDecoration(hintText: 'أضف قاعدة...'))),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () { if (ruleC.text.trim().isNotEmpty) setState(()=> rules.add(ruleC.text.trim())); ruleC.clear(); },
            )
          ],
        ),
        const Divider(height: 24),
        const Text('الكلمات الممنوعة', style: TextStyle(fontWeight: FontWeight.w700)),
        Wrap(
          spacing: 6,
          children: [
            for (int i=0;i<badWords.length;i++)
              Chip(label: Text(badWords[i]), onDeleted: ()=> setState(()=> badWords.removeAt(i))),
          ],
        ),
        Row(
          children: [
            Expanded(child: TextField(controller: badC, decoration: const InputDecoration(hintText: 'أضف كلمة ممنوعة...'))),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () { if (badC.text.trim().isNotEmpty) setState(()=> badWords.add(badC.text.trim())); badC.clear(); },
            )
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(value: autoMute, onChanged: (v)=> setState(()=> autoMute=v), title: const Text('كتم تلقائي عند استخدام كلمة ممنوعة')),
        ListTile(
          leading: const Icon(Icons.timer_rounded),
          title: const Text('مدة الكتم (بالدقائق)'),
          trailing: SizedBox(
            width: 90,
            child: TextFormField(
              initialValue: '$muteMinutes',
              keyboardType: TextInputType.number,
              onChanged: (v)=> muteMinutes = int.tryParse(v) ?? 10,
            ),
          ),
        ),
        const Divider(height: 24),
        TextField(controller: welcomeC, maxLines: 2, decoration: const InputDecoration(labelText: 'رسالة الترحيب التلقائي')),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            await cf.FirebaseFirestore.instance.collection('rooms').doc(widget.roomId).set({
              'rules': rules,
              'config': {
                'badWords': badWords,
                'autoMuteOnBadWord': autoMute,
                'muteMinutes': muteMinutes,
                'welcomeText': welcomeC.text.trim(),
              }
            }, cf.SetOptions(merge: true));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ ✅')));
          },
          child: const Text('حفظ'),
        )
      ],
    );
  }
}

class _RoomRolesTab extends StatelessWidget {
  final String roomId;
  const _RoomRolesTab({required this.roomId});
  @override
  Widget build(BuildContext context) {
    final q = cf.FirebaseFirestore.instance.collection('rooms').doc(roomId).collection('members')
      .orderBy('joinedAt', descending: true).limit(200).snapshots();
    return StreamBuilder<cf.QuerySnapshot<Map<String, dynamic>>>(
      stream: q,
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final docs = s.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('لا أعضاء.'));
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) {
            final d = docs[i];
            final m = d.data();
            final name = (m['displayName'] ?? d.id) as String;
            final role = (m['role'] ?? 'member') as String;
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(name),
                subtitle: Text('الدور: $role'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => _setRole(roomId, d.id, v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'owner', child: Text('Owner')),
                    PopupMenuItem(value: 'admin', child: Text('Admin')),
                    PopupMenuItem(value: 'mod', child: Text('Moderator')),
                    PopupMenuItem(value: 'member', child: Text('Member')),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _setRole(String room, String uid, String role) async {
    await cf.FirebaseFirestore.instance.collection('rooms').doc(room).collection('members').doc(uid)
      .set({'role': role}, cf.SetOptions(merge: true));
  }
}

class _RoomInvitesTab extends StatefulWidget {
  final String roomId;
  const _RoomInvitesTab({required this.roomId});
  @override
  State<_RoomInvitesTab> createState() => _RoomInvitesTabState();
}
class _RoomInvitesTabState extends State<_RoomInvitesTab> {
  final usesC = TextEditingController();
  cf.Timestamp? _exp;
  bool _loading = false;
  bool _creating = false;
  String? _error;
  List<InviteCodeInfo> _invites = const [];

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  @override
  void dispose() {
    usesC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: usesC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'الحد الأقصى للاستخدامات (اختياري)'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _creating ? null : _handleCreateInvite,
                icon: _creating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.link_rounded),
                label: Text(_creating ? 'جارٍ الإنشاء...' : 'إنشاء كود'),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() {
                      _exp = cf.Timestamp.fromDate(DateTime(picked.year, picked.month, picked.day, 23, 59));
                    });
                  }
                },
                icon: const Icon(Icons.event),
                tooltip: 'تعيين تاريخ انتهاء',
              ),
              if (_exp != null)
                IconButton(
                  onPressed: () => setState(() => _exp = null),
                  icon: const Icon(Icons.close),
                  tooltip: 'إزالة تاريخ الانتهاء',
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildInvitesBody()),
      ],
    );
  }

  Widget _buildInvitesBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _loadInvites(showSpinner: true),
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (_invites.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadInvites(showSpinner: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('لا أكواد دعوة بعد.')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadInvites(showSpinner: false),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _invites.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final invite = _invites[i];
          final max = invite.maxUses;
          final exp = invite.expiresAt;
          final subtitle = StringBuffer('استخدامات: ${invite.uses}${max != null ? '/$max' : ''}');
          if (exp != null) {
            subtitle.write(' • ينتهي: ${shortTime(exp)}');
          }
          return Card(
            child: ListTile(
              leading: const Icon(Icons.key_rounded, color: kTeal),
              title: Text(invite.code),
              subtitle: Text(subtitle.toString()),
              trailing: IconButton(
                icon: const Icon(Icons.copy_rounded),
                onPressed: () => Clipboard.setData(ClipboardData(text: invite.code))
                    .then((_) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم النسخ')))),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleCreateInvite() async {
    setState(() {
      _creating = true;
    });
    try {
      final maxUses = int.tryParse(usesC.text.trim());
      final code = await generateInviteCode(widget.roomId, maxUses: maxUses, expiresAt: _exp);
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: code));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تم إنشاء الكود ونسخه: $code')));
      await _loadInvites(showSpinner: false);
    } on FirebaseFunctionsException catch (err) {
      if (!mounted) return;
      final message = _friendlyError(err.code);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل إنشاء الكود: $err')));
    } finally {
      if (mounted) {
        setState(() {
          _creating = false;
        });
      }
    }
  }

  Future<void> _loadInvites({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() {
        _error = null;
      });
    }
    try {
      final invites = await InvitesService.listInvites(roomId: widget.roomId);
      if (!mounted) return;
      setState(() {
        _invites = invites;
        _loading = false;
      });
    } on FirebaseFunctionsException catch (err, stack) {
      debugPrint('listInvites error: ${err.code} ${err.message}');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(err.code);
      });
    } catch (err, stack) {
      debugPrint('listInvites error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'حدث خطأ أثناء تحميل الدعوات. حاول مجددًا لاحقًا.';
      });
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'permission-denied':
        return 'ليس لديك صلاحية لإدارة الدعوات في هذه الغرفة.';
      case 'failed-precondition':
        return 'لا يمكن معالجة الطلب بسبب حالة الغرفة أو الدعوة.';
      case 'not-found':
        return 'الدعوة غير موجودة أو انتهت صلاحيتها.';
      case 'deadline-exceeded':
        return 'انتهت مهلة الطلب، تحقق من الاتصال وحاول مرة أخرى.';
      default:
        return 'تعذر تنفيذ الطلب. (${code.isEmpty ? 'خطأ غير معروف' : code})';
    }
  }
}
// ===================== main.dart — Chat-MVP (ULTRA FINAL) [Part 10/12] =====================
// Room Board: posts (text/image/poll) + likes + comments + pin-as-announcement

// ---------------------- Data model (Firestore suggested) ----------------------
// rooms/{roomId}/posts/{postId}:
// { type:'text|image|poll', text, imageUrl, authorId, createdAt, likes:0, comments:0, pinned:false,
//   poll:{options:[{text:'',votes:0}], voters:{uid:true}} }
// rooms/{roomId}/posts/{postId}/comments/{commentId}:
// { text, authorId, createdAt }

// ---------------------- Helpers ----------------------
String shortUid(String uid) => uid.length <= 6 ? uid : uid.substring(0,6);

Future<void> toggleLike(String roomId, String postId) async {
  final fs = cf.FirebaseFirestore.instance;
  final me = FirebaseAuth.instance.currentUser!.uid;
  final likeRef = fs.collection('rooms').doc(roomId).collection('posts').doc(postId)
      .collection('likes').doc(me);
  final postRef = fs.collection('rooms').doc(roomId).collection('posts').doc(postId);

  await fs.runTransaction((tx) async {
    final liked = await tx.get(likeRef);
    final post = await tx.get(postRef);
    int cur = (post.data()?['likes'] ?? 0) as int;
    if (liked.exists) {
      tx.delete(likeRef);
      tx.update(postRef, {'likes': (cur > 0 ? cur - 1 : 0)});
    } else {
      tx.set(likeRef, {'at': cf.FieldValue.serverTimestamp()});
      tx.update(postRef, {'likes': cur + 1});
    }
  });
}

Future<void> addComment({
  required String roomId,
  required String postId,
  required String text,
}) async {
  final fs = cf.FirebaseFirestore.instance;
  final me = FirebaseAuth.instance.currentUser!.uid;
  final cref = fs.collection('rooms').doc(roomId).collection('posts').doc(postId).collection('comments').doc();
  final pref = fs.collection('rooms').doc(roomId).collection('posts').doc(postId);
  await fs.runTransaction((tx) async {
    tx.set(cref, {'text': text, 'authorId': me, 'createdAt': cf.FieldValue.serverTimestamp()});
    final p = await tx.get(pref);
    final cur = (p.data()?['comments'] ?? 0) as int;
    tx.update(pref, {'comments': cur + 1});
  });
}

Future<void> pinPost(String roomId, String postId, bool value) async {
  final ref = cf.FirebaseFirestore.instance.collection('rooms').doc(roomId).collection('posts').doc(postId);
  await ref.update({'pinned': value});
  if (value) {
    await postSystemMessage(roomId: roomId, text: '📌 تم تثبيت منشور ($postId) بواسطة المشرف.');
  }
}

// ---------------------- Composer (sheet) ----------------------
class PostComposerSheet extends StatefulWidget {
  final String roomId;
  const PostComposerSheet({super.key, required this.roomId});
  @override
  State<PostComposerSheet> createState() => _PostComposerSheetState();
}

class _PostComposerSheetState extends State<PostComposerSheet> {
  String kind = 'text'; // text | image | poll
  final txt = TextEditingController();

  // image
  final _picker = ImagePicker();
  Uint8List? _imageBytes;
  String? _imageName;

  // poll
  final opt1 = TextEditingController();
  final opt2 = TextEditingController();
  final opt3 = TextEditingController();

  bool _saving = false;

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (x == null) return;
    _imageBytes = await x.readAsBytes();
    _imageName = x.name;
    if (mounted) setState((){});
  }

  Future<void> _publish() async {
    if (_saving) return;
    setState(()=> _saving = true);
    try {
      final fs = cf.FirebaseFirestore.instance;
      final me = FirebaseAuth.instance.currentUser!.uid;
      final posts = fs.collection('rooms').doc(widget.roomId).collection('posts');

      if (kind == 'text') {
        if (txt.text.trim().isEmpty) return;
        await posts.add({
          'type': 'text',
          'text': txt.text.trim(),
          'authorId': me,
          'createdAt': cf.FieldValue.serverTimestamp(),
          'likes': 0, 'comments': 0, 'pinned': false,
        });
      } else if (kind == 'image') {
        if (_imageBytes == null) return;
        final ref = FirebaseStorage.instance.ref('rooms/${widget.roomId}/posts/${DateTime.now().millisecondsSinceEpoch}_${_imageName ?? 'img'}.jpg');
        await ref.putData(_imageBytes!, SettableMetadata(contentType: 'image/jpeg'));
        final url = await ref.getDownloadURL();
        await posts.add({
          'type': 'image',
          'imageUrl': url,
          'text': txt.text.trim(),
          'authorId': me,
          'createdAt': cf.FieldValue.serverTimestamp(),
          'likes': 0, 'comments': 0, 'pinned': false,
        });
      } else if (kind == 'poll') {
        final opts = [opt1.text.trim(), opt2.text.trim(), opt3.text.trim()].where((e) => e.isNotEmpty).toList();
        if (opts.length < 2) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل خيارين على الأقل')));
          return;
        }
        await posts.add({
          'type': 'poll',
          'text': txt.text.trim(),
          'authorId': me,
          'createdAt': cf.FieldValue.serverTimestamp(),
          'likes': 0, 'comments': 0, 'pinned': false,
          'poll': {
            'options': opts.map((t) => {'text': t, 'votes': 0}).toList(),
            'voters': {},
          }
        });
      }

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(()=> _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          top: 12,
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(height: 4, width: 48, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(999))),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'text', icon: Icon(Icons.notes_rounded), label: Text('نص')),
                  ButtonSegment(value: 'image', icon: Icon(Icons.image_rounded), label: Text('صورة')),
                  ButtonSegment(value: 'poll', icon: Icon(Icons.how_to_vote_rounded), label: Text('تصويت')),
                ],
                selected: {kind},
                onSelectionChanged: (s)=> setState(()=> kind = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: txt,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'اكتب شيئًا…'),
              ),
              if (kind == 'image') ...[
                const SizedBox(height: 8),
                if (_imageBytes != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_imageBytes!, height: 160, fit: BoxFit.cover),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text('اختيار صورة'),
                ),
              ],
              if (kind == 'poll') ...[
                const SizedBox(height: 8),
                TextField(decoration: const InputDecoration(labelText: 'الخيار 1'), controller: opt1),
                TextField(decoration: const InputDecoration(labelText: 'الخيار 2'), controller: opt2),
                TextField(decoration: const InputDecoration(labelText: 'الخيار 3 (اختياري)'), controller: opt3),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _publish,
                icon: _saving ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.send_rounded),
                label: const Text('نشر'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------- Board (list of posts) ----------------------
class RoomBoardPage extends StatelessWidget {
  const RoomBoardPage({super.key});
  @override
  Widget build(BuildContext context) {
    final roomId = (ModalRoute.of(context)!.settings.arguments ?? 'room_demo') as String;
    final q = cf.FirebaseFirestore.instance.collection('rooms').doc(roomId)
      .collection('posts').orderBy('pinned', descending: true).orderBy('createdAt', descending: true).limit(100).snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة المنشورات'),
        actions: [
          IconButton(
            onPressed: ()=> showModalBottomSheet(
              context: context, isScrollControlled: true,
              builder: (_) => PostComposerSheet(roomId: roomId),
            ),
            icon: const Icon(Icons.add_box_rounded),
            tooltip: 'منشور جديد',
          ),
          IconButton(
            onPressed: ()=> navigatorKey.currentState?.pushNamed('/room/settings', arguments: roomId),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'إعدادات الغرفة',
          ),
        ],
      ),
      body: StreamBuilder<cf.QuerySnapshot<Map<String, dynamic>>>(
        stream: q,
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final docs = s.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: TextButton.icon(
                onPressed: ()=> showModalBottomSheet(
                  context: context, isScrollControlled: true,
                  builder: (_) => PostComposerSheet(roomId: roomId),
                ),
                icon: const Icon(Icons.add),
                label: const Text('أنشئ أول منشور'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final id = docs[i].id;
              final d = docs[i].data();
              return _PostCard(roomId: roomId, postId: id, data: d);
            },
          );
        },
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final String roomId, postId; final Map<String, dynamic> data;
  const _PostCard({required this.roomId, required this.postId, required this.data, super.key});
  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser!.uid;
    final type = (data['type'] ?? 'text') as String;
    final text = (data['text'] ?? '') as String;
    final img  = (data['imageUrl'] ?? '') as String;
    final author = (data['authorId'] ?? '') as String;
    final likes = (data['likes'] ?? 0) as int;
    final comments = (data['comments'] ?? 0) as int;
    final pinned = data['pinned'] == true;
    final at = data['createdAt'] as cf.Timestamp?;

    Widget content;
    if (type == 'image') {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (text.isNotEmpty) Padding(
            padding: const EdgeInsets.only(bottom: 8), child: Text(text)),
          if (img.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(img, fit: BoxFit.cover),
            ),
        ],
      );
    } else if (type == 'poll') {
      final poll = (data['poll'] ?? {}) as Map;
      final List opts = (poll['options'] ?? const []);
      content = _PollWidget(roomId: roomId, postId: postId, options: opts.cast<Map>());
    } else {
      content = Text(text);
    }

    return Card(
      child: InkWell(
        onTap: ()=> navigatorKey.currentState?.pushNamed('/post', arguments: {'roomId': roomId, 'postId': postId}),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(child: Icon(Icons.person, size: 18)),
                  const SizedBox(width: 8),
                  Text(shortUid(author), style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (pinned) const Icon(Icons.push_pin, color: kGold),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'pin') pinPost(roomId, postId, true);
                      if (v == 'unpin') pinPost(roomId, postId, false);
                      if (v == 'report') _reportPost(roomId, postId);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'pin', child: Text('تثبيت')),
                      const PopupMenuItem(value: 'unpin', child: Text('إلغاء التثبيت')),
                      const PopupMenuItem(value: 'report', child: Text('إبلاغ')),
                    ],
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              content,
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: ()=> toggleLike(roomId, postId),
                    icon: const Icon(Icons.favorite_border_rounded),
                  ),
                  Text(compactNumber(likes)),
                  const SizedBox(width: 12),
                  const Icon(Icons.mode_comment_outlined, size: 20, color: kGray),
                  const SizedBox(width: 4),
                  Text(compactNumber(comments)),
                  const Spacer(),
                  Text(shortTime(at), style: const TextStyle(fontSize: 11, color: kGray)),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reportPost(String roomId, String postId) async {
    await cf.FirebaseFirestore.instance.collection('rooms').doc(roomId).collection('reports').add({
      'type': 'content',
      'targetType': 'post',
      'targetId': postId,
      'reason': 'inappropriate',
      'status': 'open',
      'createdBy': FirebaseAuth.instance.currentUser!.uid,
      'createdAt': cf.FieldValue.serverTimestamp(),
    });
  }
}

// ---------------------- Poll Widget ----------------------
class _PollWidget extends StatefulWidget {
  final String roomId, postId;
  final List<Map> options;
  const _PollWidget({super.key, required this.roomId, required this.postId, required this.options});
  @override
  State<_PollWidget> createState() => _PollWidgetState();
}
class _PollWidgetState extends State<_PollWidget> {
  bool _voting = false;

  Future<void> _vote(int idx) async {
    if (_voting) return;
    setState(()=> _voting = true);
    try {
      final fs = cf.FirebaseFirestore.instance;
      final me = FirebaseAuth.instance.currentUser!.uid;
      final pref = fs.collection('rooms').doc(widget.roomId).collection('posts').doc(widget.postId);
      await fs.runTransaction((tx) async {
        final p = await tx.get(pref);
        final poll = Map<String, dynamic>.from((p.data()?['poll'] ?? {}) as Map);
        final voters = Map<String, dynamic>.from((poll['voters'] ?? {}) as Map);
        if (voters.containsKey(me)) return; // already voted
        final List opts = List.from(poll['options'] ?? const []);
        if (idx < 0 || idx >= opts.length) return;
        final item = Map<String, dynamic>.from(opts[idx] as Map);
        item['votes'] = (item['votes'] ?? 0) + 1;
        opts[idx] = item;
        voters[me] = true;
        poll['options'] = opts;
        poll['voters'] = voters;
        tx.update(pref, {'poll': poll});
      });
    } finally {
      if (mounted) setState(()=> _voting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.options.fold<int>(0, (acc, m) => acc + ((m['votes'] ?? 0) as int));
    return Column(
      children: [
        for (int i=0; i<widget.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _PollOptionTile(
              text: (widget.options[i]['text'] ?? '') as String,
              votes: (widget.options[i]['votes'] ?? 0) as int,
              total: total,
              onVote: ()=> _vote(i),
              busy: _voting,
            ),
          ),
      ],
    );
  }
}

class _PollOptionTile extends StatelessWidget {
  final String text; final int votes; final int total;
  final VoidCallback onVote; final bool busy;
  const _PollOptionTile({super.key, required this.text, required this.votes, required this.total, required this.onVote, required this.busy});
  @override
  Widget build(BuildContext context) {
    final p = total == 0 ? 0.0 : votes / total;
    return InkWell(
      onTap: busy ? null : onVote,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(child: Text(text)),
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: p, minHeight: 8),
              ),
            ),
            const SizedBox(width: 6),
            Text('${(p*100).toStringAsFixed(0)}%'),
          ],
        ),
      ),
    );
  }
}

// ---------------------- Post Detail (comments) ----------------------
class PostDetailPage extends StatelessWidget {
  const PostDetailPage({super.key});
  @override
  Widget build(BuildContext context) {
    final args = (ModalRoute.of(context)!.settings.arguments as Map?) ?? {};
    final roomId = (args['roomId'] ?? 'room_demo') as String;
    final postId = (args['postId'] ?? '') as String;

    final pref = cf.FirebaseFirestore.instance.collection('rooms').doc(roomId).collection('posts').doc(postId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل المنشور'),
        actions: [
          IconButton(
            onPressed: () => navigatorKey.currentState?.pushNamed('/search'),
            icon: const Icon(Icons.search_rounded),
            tooltip: 'بحث',
          ),
        ],
      ),
      body: StreamBuilder<cf.DocumentSnapshot<Map<String, dynamic>>>(
        stream: pref.snapshots(),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          if (!s.data!.exists) return const Center(child: Text('المنشور محذوف'));
          final d = s.data!.data()!;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _PostCard(roomId: roomId, postId: postId, data: d),
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text('التعليقات', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    _CommentsList(roomId: roomId, postId: postId),
                  ],
                ),
              ),
              _CommentBar(roomId: roomId, postId: postId),
            ],
          );
        },
      ),
    );
  }
}

class _CommentsList extends StatelessWidget {
  final String roomId, postId;
  const _CommentsList({super.key, required this.roomId, required this.postId});
  @override
  Widget build(BuildContext context) {
    final q = cf.FirebaseFirestore.instance.collection('rooms').doc(roomId)
      .collection('posts').doc(postId).collection('comments')
      .orderBy('createdAt', descending: true).limit(100).snapshots();
    return StreamBuilder<cf.QuerySnapshot<Map<String, dynamic>>>(
      stream: q,
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final docs = s.data!.docs;
        if (docs.isEmpty) return const Padding(
          padding: EdgeInsets.all(12),
          child: Text('لا يوجد تعليقات بعد.'),
        );
        return Column(
          children: [
            for (final doc in docs)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person, size: 18)),
                title: Text(doc.data()['text'] ?? ''),
                subtitle: Text(shortUid(doc.data()['authorId'] ?? '')),
                trailing: Text(shortTime(doc.data()['createdAt'] as cf.Timestamp?), style: const TextStyle(fontSize: 11, color: kGray)),
              )
          ],
        );
      },
    );
  }
}

class _CommentBar extends StatefulWidget {
  final String roomId, postId;
  const _CommentBar({super.key, required this.roomId, required this.postId});
  @override
  State<_CommentBar> createState() => _CommentBarState();
}
class _CommentBarState extends State<_CommentBar> {
  final c = TextEditingController();
  bool _busy = false;

  Future<void> _send() async {
    final t = c.text.trim();
    if (t.isEmpty || _busy) return;
    setState(()=> _busy = true);
    try {
      await addComment(roomId: widget.roomId, postId: widget.postId, text: t);
      c.clear();
    } finally { if (mounted) setState(()=> _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: c,
                decoration: const InputDecoration(
                  hintText: 'أضف تعليقًا…',
                  filled: true, border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(14))),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton.small(
              onPressed: _send,
              child: _busy ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.send_rounded),
            )
          ],
        ),
      ),
    );
  }
}
// ===================== main.dart — Chat-MVP (ULTRA FINAL) [Part 11/12] =====================
// Global Advanced Search: people, rooms, posts, messages with filters & quick suggestions

// ---------------------- Search Page ----------------------
class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({super.key});
  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> with SingleTickerProviderStateMixin {
  final q = TextEditingController();
  late TabController tc;
  String sort = 'relevance'; // relevance | newest | popular
  bool onlyVerified = false; // للأشخاص والغرف
  bool inMyRooms   = false;  // الرسائل/المنشورات داخل غرفي فقط

  // حفظ تاريخ البحث محليًا
  List<String> history = [];

  @override
  void initState() {
    super.initState();
    tc = TabController(length: 4, vsync: this);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final sp = await SharedPreferences.getInstance();
    history = sp.getStringList('search.history') ?? [];
    setState((){});
  }

  Future<void> _pushHistory(String term) async {
    term = term.trim();
    if (term.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    history.remove(term);
    history.insert(0, term);
    if (history.length > 15) history = history.sublist(0, 15);
    await sp.setStringList('search.history', history);
  }

  void _doSearch() { setState((){}); _pushHistory(q.text); }

  @override
  void dispose() {
    tc.dispose();
    q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: q,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_)=> _doSearch(),
          decoration: const InputDecoration(
            hintText: 'ابحث عن أشخاص / غرف / منشورات / رسائل…',
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(onPressed: _doSearch, icon: const Icon(Icons.search_rounded)),
        ],
        bottom: TabBar(
          controller: tc,
          tabs: const [
            Tab(icon: Icon(Icons.person_search_rounded), text: 'أشخاص'),
            Tab(icon: Icon(Icons.forum_rounded), text: 'غرف'),
            Tab(icon: Icon(Icons.dashboard_rounded), text: 'منشورات'),
            Tab(icon: Icon(Icons.message_rounded), text: 'رسائل'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Filters row
          _SearchFiltersBar(
            sort: sort,
            onSort: (v)=> setState(()=> sort=v),
            onlyVerified: onlyVerified,
            onOnlyVerified: (v)=> setState(()=> onlyVerified=v),
            inMyRooms: inMyRooms,
            onInMyRooms: (v)=> setState(()=> inMyRooms=v),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: tc,
              children: [
                _PeopleResults(queryCtrl: q, sort: sort, onlyVerified: onlyVerified),
                _RoomsResults(queryCtrl: q, sort: sort, onlyVerified: onlyVerified),
                _PostsResults(queryCtrl: q, sort: sort, inMyRooms: inMyRooms),
                _MessagesResults(queryCtrl: q, sort: sort, inMyRooms: inMyRooms),
              ],
            ),
          ),
          if (q.text.trim().isEmpty && history.isNotEmpty) ...[
            const Divider(height: 1),
            _RecentSearches(history: history, onPick: (t){ q.text = t; _doSearch(); }),
          ],
        ],
      ),
      floatingActionButton: q.text.trim().isEmpty
          ? FloatingActionButton.extended(
              onPressed: ()=> _fillQuickExamples(q, setState),
              icon: const Icon(Icons.lightbulb_rounded),
              label: const Text('اقتراحات'),
            )
          : null,
    );
  }

  void _fillQuickExamples(TextEditingController c, void Function(void Function()) set) {
    final examples = [
      'Flutter DZ',
      'AI بالعربية',
      'مساعدة ترجمة',
      'تصويت',
      'bugs',
      'VIP',
      'announcement',
    ];
    c.text = examples[math.Random().nextInt(examples.length)];
    set((){});
  }
}

class _SearchFiltersBar extends StatelessWidget {
  final String sort;
  final void Function(String) onSort;
  final bool onlyVerified; final void Function(bool) onOnlyVerified;
  final bool inMyRooms; final void Function(bool) onInMyRooms;
  const _SearchFiltersBar({
    super.key,
    required this.sort, required this.onSort,
    required this.onlyVerified, required this.onOnlyVerified,
    required this.inMyRooms, required this.onInMyRooms,
  });
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _FilterChipX(
            label: 'الصلة', selected: sort=='relevance', onTap: ()=> onSort('relevance')),
          _FilterChipX(
            label: 'الأحدث', selected: sort=='newest', onTap: ()=> onSort('newest')),
          _FilterChipX(
            label: 'الأكثر شعبية', selected: sort=='popular', onTap: ()=> onSort('popular')),
          const VerticalDivider(width: 12),
          _FilterChipX(
            label: 'موثّق فقط', icon: Icons.verified_rounded,
            selected: onlyVerified, onTap: ()=> onOnlyVerified(!onlyVerified)),
          _FilterChipX(
            label: 'داخل غرفي', icon: Icons.home_rounded,
            selected: inMyRooms, onTap: ()=> onInMyRooms(!inMyRooms)),
        ],
      ),
    );
  }
}

class _RecentSearches extends StatelessWidget {
  const _RecentSearches({
    super.key,
    required this.history,
    required this.onPick,
  });

  final List<String> history;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in history)
            ActionChip(
              label: Text(t),
              onPressed: () => onPick(t),
            ),
        ],
      ),
    );
  }
}

class _FilterChipX extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap; final IconData? icon;
  const _FilterChipX({required this.label, required this.selected, required this.onTap, this.icon, super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surfaceVariant,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------- People Results ----------------------
Future<void> showGiftDialog(BuildContext context, {required String toUserId}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Send gift'),
      content: Text('Send a gift to $toUserId ?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}

class _PeopleResults extends StatelessWidget {
  final TextEditingController queryCtrl;
  final String sort;
  final bool onlyVerified;
  const _PeopleResults({super.key, required this.queryCtrl, required this.sort, required this.onlyVerified});

  @override
  Widget build(BuildContext context) {
    final term = queryCtrl.text.trim();
    cf.Query<Map<String, dynamic>> base = cf.FirebaseFirestore.instance.collection('users');
    if (term.isNotEmpty) {
      base = base.where('keywords', arrayContainsAny: _keywords(term));
    }
    if (onlyVerified) {
      base = base.where('verified', isEqualTo: true);
    }
    if (sort == 'newest')   base = base.orderBy('createdAt', descending: true);
    else if (sort == 'popular') base = base.orderBy('followers', descending: true);
    else base = base.orderBy('displayName'); // relevance (تقريبية عبر keywords+الاسم)

    return StreamBuilder<cf.QuerySnapshot<Map<String, dynamic>>>(
      stream: base.limit(50).snapshots(),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final docs = s.data!.docs;
        if (docs.isEmpty) return const _EmptyHint(text: 'لا نتائج للأشخاص.');
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final uid = docs[i].id;
            final name = (d['displayName'] ?? uid) as String;
            final vip = (d['vipLevel'] ?? 'Bronze') as String;
            final followers = (d['followers'] ?? 0) as int;
            final avatar = (d['avatarUrl'] ?? '') as String;
            final verified = d['verified'] == true;
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                  child: avatar.isEmpty ? const Icon(Icons.person) : null,
                ),
                title: Row(
                  children: [
                    Text(name),
                    if (verified) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.verified_rounded, color: kGold, size: 16),
                    ],
                  ],
                ),
                subtitle: Text('VIP: $vip • متابعون: ${compactNumber(followers)}'),
                trailing: FilledButton(
                  onPressed: ()=> showGiftDialog(context, toUserId: uid),
                  child: const Text('إهداء'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------- Rooms Results ----------------------
class _RoomsResults extends StatelessWidget {
  final TextEditingController queryCtrl;
  final String sort;
  final bool onlyVerified;
  const _RoomsResults({super.key, required this.queryCtrl, required this.sort, required this.onlyVerified});

  @override
  Widget build(BuildContext context) {
    final term = queryCtrl.text.trim();
    cf.Query<Map<String, dynamic>> base = cf.FirebaseFirestore.instance.collection('rooms').where('public', isEqualTo: true);
    if (term.isNotEmpty) {
      base = base.where('keywords', arrayContainsAny: _keywords(term));
    }
    if (onlyVerified) {
      base = base.where('verified', isEqualTo: true);
    }
    if (sort == 'newest')     base = base.orderBy('createdAt', descending: true);
    else if (sort == 'popular') base = base.orderBy('meta.members', descending: true);
    else base = base.orderBy('name');

    return StreamBuilder<cf.QuerySnapshot<Map<String, dynamic>>>(
      stream: base.limit(50).snapshots(),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final docs = s.data!.docs;
        if (docs.isEmpty) return const _EmptyHint(text: 'لا نتائج للغرف.');
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final id = docs[i].id;
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.forum_rounded)),
                title: Text(d['name'] ?? id),
                subtitle: Text('${d['about'] ?? ''}\nأعضاء: ${compactNumber((d['meta']?['members'] ?? 0) as int)}'),
                isThreeLine: true,
                trailing: FilledButton(
                  onPressed: ()=> navigatorKey.currentState?.pushNamed('/room', arguments: id),
                  child: const Text('دخول'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------- Posts Results (Board) ----------------------
class _PostsResults extends StatelessWidget {
  final TextEditingController queryCtrl;
  final String sort;
  final bool inMyRooms;
  const _PostsResults({super.key, required this.queryCtrl, required this.sort, required this.inMyRooms});

  @override
  Widget build(BuildContext context) {
    final term = queryCtrl.text.trim();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // مبدئيًا: نبحث عبر collectionGroup على posts ونفلتر بالنص/النوع
    cf.Query<Map<String, dynamic>> base = cf.FirebaseFirestore.instance.collectionGroup('posts');
    if (term.isNotEmpty) {
      base = base.where('keywords', arrayContainsAny: _keywords(term));
    }
    if (inMyRooms && uid != null) {
      // نأتي بغرفي أولًا (IDs) ثم نفلتر محليًا
      return FutureBuilder<List<String>>(
        future: _myRoomIds(uid),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final roomIds = s.data!;
          return _postsStream(base, roomFilter: roomIds.contains, sort: sort);
        },
      );
    }
    return _postsStream(base, sort: sort);
  }

  Widget _postsStream(cf.Query<Map<String, dynamic>> base, {bool Function(String)? roomFilter, required String sort}) {
    if (sort == 'newest') base = base.orderBy('createdAt', descending: true);
    else if (sort == 'popular') base = base.orderBy('likes', descending: true);
    else base = base.orderBy('pinned', descending: true).orderBy('createdAt', descending: true);

    return StreamBuilder<cf.QuerySnapshot<Map<String, dynamic>>>(
      stream: base.limit(60).snapshots(),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        var docs = s.data!.docs;
        if (roomFilter != null) {
          docs = docs.where((d) => roomFilter(d.reference.parent.parent!.id)).toList();
        }
        if (docs.isEmpty) return const _EmptyHint(text: 'لا نتائج للمنشورات.');
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final d = docs[i];
            final roomId = d.reference.parent.parent!.id;
            return _PostCard(roomId: roomId, postId: d.id, data: d.data());
          },
        );
      },
    );
  }
}

// ---------------------- Messages Results (Chat) ----------------------
class _MessagesResults extends StatelessWidget {
  final TextEditingController queryCtrl;
  final String sort;
  final bool inMyRooms;
  const _MessagesResults({super.key, required this.queryCtrl, required this.sort, required this.inMyRooms});

  @override
  Widget build(BuildContext context) {
    final term = queryCtrl.text.trim();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    cf.Query<Map<String, dynamic>> base = cf.FirebaseFirestore.instance.collectionGroup('messages').where('type', isEqualTo: 'text');
    if (term.isNotEmpty) {
      base = base.where('keywords', arrayContainsAny: _keywords(term));
    }
    if (sort == 'newest') base = base.orderBy('createdAt', descending: true);
    else base = base.orderBy('pinned', descending: true).orderBy('createdAt', descending: true);

    return FutureBuilder<List<String>>(
      future: inMyRooms && uid != null ? _myRoomIds(uid) : Future.value(null),
      builder: (c, s) {
        return StreamBuilder<cf.QuerySnapshot<Map<String, dynamic>>>(
          stream: base.limit(60).snapshots(),
          builder: (c2, s2) {
            if (!s2.hasData) return const Center(child: CircularProgressIndicator());
            var docs = s2.data!.docs;
            if (s.hasData && s.data != null) {
              final roomIds = s.data!;
              docs = docs.where((d) => roomIds.contains(d.reference.parent.parent!.id)).toList();
            }
            if (term.isNotEmpty) {
              final qlc = term.toLowerCase();
              docs = docs.where((d) => (d.data()['text'] ?? '').toString().toLowerCase().contains(qlc)).toList();
            }
            if (docs.isEmpty) return const _EmptyHint(text: 'لا نتائج للرسائل.');
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final d = docs[i];
                final roomId = d.reference.parent.parent!.id;
                final msg = d.data();
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.message_rounded),
                    title: Text(msg['text'] ?? ''),
                    subtitle: Text('Room: $roomId • by: ${shortUid(msg['from'] ?? '')}'),
                    trailing: Text(shortTime(msg['createdAt'] as cf.Timestamp?), style: const TextStyle(fontSize: 11, color: kGray)),
                    onTap: ()=> navigatorKey.currentState?.pushNamed('/room', arguments: roomId),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(color: kGray);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, style: style, textAlign: TextAlign.center),
      ),
    );
  }
}

// ---------------------- Shared helpers for search ----------------------
List<String> _keywords(String term) {
  // تقسيم مبسّط إلى كلمات مفتاحية (يمكن تحسينه لاحقًا)
  final raw = term.toLowerCase().split(RegExp(r'\s+')).where((e) => e.trim().isNotEmpty).toList();
  final unique = <String>{};
  for (final w in raw) {
    unique.add(w);
    if (w.length > 3) unique.add(w.substring(0, 3));
  }
  return unique.toList();
}

Future<List<String>> _myRoomIds(String uid) async {
  final qs = await cf.FirebaseFirestore.instance.collectionGroup('members')
    .where(cf.FieldPath.documentId, isEqualTo: uid).get();
  final ids = <String>[];
  for (final d in qs.docs) {
    final roomId = d.reference.parent.parent?.id;
    if (roomId != null) ids.add(roomId);
  }
  return ids;
}
// ===================== main.dart — Chat-MVP (ULTRA FINAL) [Part 12/12] =====================
// Notifications Center + Preferences + Badge + Advanced FCM + Deep Links

// ---------------------- Data Model (Firestore) ----------------------
// users/{uid}/inbox/{nid}: {
//   type:'message|mention|invite|post_like|comment|system',
//   title, body, roomId?, postId?, from?, action?:{'type':'open_room'|'open_post'|'open_invite'|'open_inbox','code'?:string},
//   read:false, createdAt
// }
// users/{uid}.notify: { dnd:bool, mentionsOnly:bool, rooms:bool, posts:bool, follows:bool, invites:bool }

// ---------------------- Global FCM background handler ----------------------
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // بإمكانك تسجيل Log أو تحديث badge مخزن محليًا إن رغبت
}

// ---------------------- Notification Badge Provider ----------------------
class NotificationBadge extends ChangeNotifier {
  StreamSubscription? _sub;
  int unread = 0;

  void bind(String uid) {
    _sub?.cancel();
    _sub = cf.FirebaseFirestore.instance
      .collection('users').doc(uid).collection('inbox')
      .where('read', isEqualTo: false)
      .snapshots()
      .listen((snap) { unread = snap.docs.length; notifyListeners(); });
  }

  void disposeBind() => _sub?.cancel();
}

// ---------------------- Helpers: enqueue inbox item ----------------------
Future<void> enqueueInbox({
  required String toUid,
  required String type,
  required String title,
  required String body,
  Map<String, dynamic>? extra,
}) async {
  final ref = cf.FirebaseFirestore.instance.collection('users').doc(toUid).collection('inbox').doc();
  await ref.set({
    'type': type,
    'title': title,
    'body': body,
    'read': false,
    'createdAt': cf.FieldValue.serverTimestamp(),
    ...?extra,
  });
}

// مثال: إعلام أعضاء الغرفة برسالة مُثبّتة/إعلان (مبسّط جداً للـ MVP)
Future<void> notifyRoomMembersOfAnnouncement(String roomId, String text) async {
  final mems = await cf.FirebaseFirestore.instance.collection('rooms').doc(roomId).collection('members').limit(500).get();
  for (final m in mems.docs) {
    final uid = m.id;
    await enqueueInbox(
      toUid: uid,
      type: 'system',
      title: 'إعلان جديد',
      body: text,
      extra: {'roomId': roomId, 'action': 'open_room'},
    );
  }
}

// ---------------------- Inbox Page (Notification Center) ----------------------
class NotificationCenterPage extends StatelessWidget {
  const NotificationCenterPage({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('سجّل الدخول أولاً')));
    final q = cf.FirebaseFirestore.instance.collection('users').doc(uid)
      .collection('inbox').orderBy('createdAt', descending: true).limit(100).snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('مركز الإشعارات'),
        actions: [
          IconButton(
            onPressed: ()=> navigatorKey.currentState?.pushNamed('/notify/prefs'),
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'تفضيلات الإشعارات',
          ),
          IconButton(
            onPressed: () async {
              final batch = cf.FirebaseFirestore.instance.batch();
              final docs = await cf.FirebaseFirestore.instance.collection('users').doc(uid).collection('inbox')
                  .where('read', isEqualTo: false).get();
              for (final d in docs.docs) {
                batch.update(d.reference, {'read': true});
              }
              await batch.commit();
            },
            icon: const Icon(Icons.done_all_rounded),
            tooltip: 'تعيين الكل كمقروء',
          ),
        ],
      ),
      body: StreamBuilder<cf.QuerySnapshot<Map<String, dynamic>>>(
        stream: q,
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final docs = s.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('لا إشعارات حتى الآن.'));
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final id = docs[i].id;
              final d  = docs[i].data();
              final read = d['read'] == true;
              final type = (d['type'] ?? 'system') as String;
              final title = (d['title'] ?? '') as String;
              final body  = (d['body'] ?? '') as String;
              final roomId = d['roomId'];
              final postId = d['postId'];
              return Dismissible(
                key: ValueKey(id),
                background: Container(color: Colors.redAccent, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), child: const Icon(Icons.delete, color: Colors.white)),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => docs[i].reference.delete(),
                child: Card(
                  child: ListTile(
                    leading: Icon(
                      _iconForType(type), color: read ? kGray : kTeal),
                    title: Text(title, style: TextStyle(fontWeight: read ? FontWeight.w400 : FontWeight.w700)),
                    subtitle: Text(body),
                    trailing: IconButton(
                      icon: Icon(read ? Icons.mark_email_read : Icons.mark_email_unread),
                      onPressed: ()=> docs[i].reference.update({'read': !read}),
                      tooltip: read ? 'تعيينه كغير مقروء' : 'تعيينه كمقروء',
                    ),
                    onTap: () {
                      // Deep open
                      if (postId != null && roomId != null) {
                        navigatorKey.currentState?.pushNamed('/post', arguments: {'roomId': roomId, 'postId': postId});
                      } else if (roomId != null) {
                        navigatorKey.currentState?.pushNamed('/room', arguments: roomId);
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _iconForType(String t) {
    return switch (t) {
      'message' => Icons.message_rounded,
      'mention' => Icons.alternate_email_rounded,
      'invite'  => Icons.key_rounded,
      'post_like' => Icons.favorite_rounded,
      'comment' => Icons.mode_comment_rounded,
      _ => Icons.notifications_rounded,
    };
  }
}

// ---------------------- Notification Preferences ----------------------
class NotificationPrefsPage extends StatefulWidget {
  const NotificationPrefsPage({super.key});
  @override
  State<NotificationPrefsPage> createState() => _NotificationPrefsPageState();
}
class _NotificationPrefsPageState extends State<NotificationPrefsPage> {
  bool dnd = false, mentionsOnly = true, rooms = true, posts = true, follows = true, invites = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await cf.FirebaseFirestore.instance.collection('users').doc(uid).get();
    final n = (doc.data()?['notify'] ?? {}) as Map;
    dnd = n['dnd'] == true;
    mentionsOnly = n['mentionsOnly'] == true;
    rooms = n['rooms'] != false;
    posts = n['posts'] != false;
    follows = n['follows'] != false;
    invites = n['invites'] != false;
    setState(()=> _loading = false);
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await cf.FirebaseFirestore.instance.collection('users').doc(uid).set({
      'notify': {'dnd': dnd, 'mentionsOnly': mentionsOnly, 'rooms': rooms, 'posts': posts, 'follows': follows, 'invites': invites}
    }, cf.SetOptions(merge: true));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ ✅')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('تفضيلات الإشعارات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(value: dnd, onChanged: (v)=> setState(()=> dnd=v), title: const Text('عدم الإزعاج (DND)')),
          SwitchListTile(value: mentionsOnly, onChanged: (v)=> setState(()=> mentionsOnly=v), title: const Text('تنبيهات المنشن فقط')),
          const Divider(),
          SwitchListTile(value: rooms, onChanged: (v)=> setState(()=> rooms=v), title: const Text('تنبيهات الرسائل/الغرف')),
          SwitchListTile(value: posts, onChanged: (v)=> setState(()=> posts=v), title: const Text('تنبيهات المنشورات')),
          SwitchListTile(value: invites, onChanged: (v)=> setState(()=> invites=v), title: const Text('تنبيهات الدعوات')),
          SwitchListTile(value: follows, onChanged: (v)=> setState(()=> follows=v), title: const Text('تنبيهات المتابعة (لاحقًا)')),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
        ],
      ),
    );
  }
}

// ---------------------- Show badge in UI (example placements) ----------------------
// 1) في HomePage AppBar: أيقونة Inbox مع شارة
class _HomeInboxIcon extends StatelessWidget {
  const _HomeInboxIcon({super.key});
  @override
  Widget build(BuildContext context) {
    final nb = context.watch<NotificationBadge>();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: ()=> navigatorKey.currentState?.pushNamed('/inbox'),
          icon: const Icon(Icons.notifications_none_rounded),
          tooltip: 'الإشعارات',
        ),
        if (nb.unread > 0)
          Positioned(
            right: 6, top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(999)),
              child: Text('${nb.unread}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }
}

// أضف الأيقونة إلى AppBar في HomePage:
/// في HomePage.build داخل actions:
/// actions: [
///   IconButton(onPressed: () => navigatorKey.currentState?.pushNamed('/appearance'), icon: const Icon(Icons.palette_rounded)),
///   IconButton(onPressed: () => navigatorKey.currentState?.pushNamed('/translator'), icon: const Icon(Icons.translate_rounded)),
///   const _HomeInboxIcon(),
/// ],

// 2) أربط الـ NotificationBadge بمزود (Provider) على مستوى التطبيق
// في ChatMVPApp.build -> داخل MultiProvider أضف:
/// ChangeNotifierProvider(create: (_) => NotificationBadge()),

// ثم فعّل الربط بعد تسجيل الدخول (في Splash/onReady مثلاً):
/// if (u != null) {
///   await presence.start(u.uid);
///   await fcm.init(u.uid);
///   // bind badge
///   (navigatorKey.currentContext as Element).read<NotificationBadge>().bind(u.uid);
///   navigatorKey.currentState?.pushReplacementNamed('/home');
/// }

// ---------------------- Trigger inbox events (examples) ----------------------
// عند تثبيت منشور (سبق وضعها في الجزء 10): يمكنك أيضًا تنبيه الأعضاء:
Future<void> pinPostAndNotify(String roomId, String postId, bool value) async {
  await pinPost(roomId, postId, value);
  if (value) {
    await notifyRoomMembersOfAnnouncement(roomId, 'تم تثبيت منشور جديد');
  }
}

// عند mention داخل رسالة (تطبيق مبسّط: يبحث @uid في النص)
Future<void> notifyMentionsIfAny(String roomId, String text, String fromUid) async {
  final reg = RegExp(r'@([A-Za-z0-9_\-]{6,})'); // صيغة UID مختصرة/اسم مستخدم محتمل
  final hits = reg.allMatches(text).map((m) => m.group(1)!).toSet().toList();
  if (hits.isEmpty) return;
  for (final short in hits) {
    // هنا تحتاج خريطة short->uid حقيقية (اسم المستخدم). في الـ MVP سنفترض short هو uid كامل إذا طوله 28+، وإلا نتجاهله.
    if (short.length < 20) continue;
    await enqueueInbox(
      toUid: short,
      type: 'mention',
      title: 'تم منشنك',
      body: 'لديك منشن في غرفة $roomId',
      extra: {'roomId': roomId, 'action': 'open_room', 'from': fromUid},
    );
  }
}
