import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:app_links/app_links.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  if (!kIsWeb) {
    try {
      await Firebase.initializeApp(
        // options: DefaultFirebaseOptions.currentPlatform, // décommenter après flutterfire configure
      );
      await NotificationService().init();
    } catch (e) {
      debugPrint('[Firebase] Init error (ignored in dev): $e');
    }
  }

  timeago.setLocaleMessages('fr', timeago.FrMessages());

  runApp(
    const ProviderScope(
      child: TelephonieCAPApp(),
    ),
  );
}

class TelephonieCAPApp extends ConsumerStatefulWidget {
  const TelephonieCAPApp({super.key});

  @override
  ConsumerState<TelephonieCAPApp> createState() => _TelephonieCAPAppState();
}

class _TelephonieCAPAppState extends ConsumerState<TelephonieCAPApp> {
  late final AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    // BUG FIX: app_links ne fonctionne pas sur le web, on skip
    if (!kIsWeb) {
      _initDeepLinks();
    }
    _setupNotificationCallbacks();
  }

  void _setupNotificationCallbacks() {
    // Les notifications ne fonctionnent pas sur le web
    if (kIsWeb) return;
    NotificationService().onMessageTap = (data) {
      final convId = data['conversation_id'];
      if (convId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(appRouterProvider).push('/conversations/$convId');
        });
      }
    };
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) _handleDeepLink(initialUri);
    _appLinks.uriLinkStream.listen(_handleDeepLink, onError: (_) {});
  }

  void _handleDeepLink(Uri uri) {
    if (uri.scheme == 'telephoniecap' && uri.host == 'invite') {
      final token = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      if (token != null && token.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(appRouterProvider).go('/invite/$token');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Téléphonie CAP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        );
      },
    );
  }
}