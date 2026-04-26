import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:app_links/app_links.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Localisation timeago en français
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
    _initDeepLinks();
  }

  /// Initialise l'écoute des deep links (telephoniecap://invite/{token})
  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Lien d'entrée initial (app démarrée via le lien)
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      _handleDeepLink(initialUri);
    }

    // Liens reçus pendant que l'app tourne
    _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    }, onError: (_) {});
  }

  void _handleDeepLink(Uri uri) {
    // telephoniecap://invite/{token}  →  /invite/{token}
    if (uri.scheme == 'telephoniecap' && uri.host == 'invite') {
      final token = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      if (token != null && token.isNotEmpty) {
        // Le router est déjà initialisé — on navigue via GoRouter
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
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        );
      },
    );
  }
}