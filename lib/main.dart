import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/supabase_client.dart';
import 'providers/providers.dart';
import 'services/localization.dart';
import 'theme.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/task_detail_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/message_detail_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/users_screen.dart';
import 'screens/permissions_screen.dart';
import 'screens/trash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.configured) {
    runApp(
      const ProviderScope(
        child: _ErrorApp(
          'Missing SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY',
        ),
      ),
    );
    return;
  }

  try {
    await Supabase.initialize(
      url: AppConfig.url.trim(),
      publishableKey: AppConfig.publishableKey.trim(),
      // Keep the authenticated session across browser refreshes/restarts.
      // The password itself is never stored by HF Team.
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: true,
      ),
    );
  } catch (e) {
    runApp(
      ProviderScope(
        child: _ErrorApp('Supabase initialization failed: $e'),
      ),
    );
    return;
  }

  AppI18n.setLocale(const Locale('ar'));
  runApp(const ProviderScope(child: HamaWorkApp()));
}

class _ErrorApp extends StatelessWidget {
  final String text;
  const _ErrorApp(this.text);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(text, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

class HamaWorkApp extends ConsumerStatefulWidget {
  const HamaWorkApp({super.key});

  @override
  ConsumerState<HamaWorkApp> createState() => _HamaWorkAppState();
}

class _HamaWorkAppState extends ConsumerState<HamaWorkApp> {
  late final GoRouter router;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();

    router = GoRouter(
      refreshListenable: GoRouterRefreshStream(
        Supabase.instance.client.auth.onAuthStateChange,
      ),
      redirect: (context, state) {
        final logged =
            Supabase.instance.client.auth.currentSession != null;
        final login = state.matchedLocation == '/login';
        if (!logged && !login) return '/login';
        if (logged && login) return '/';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const AuthScreen()),
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
        GoRoute(
          path: '/my-tasks',
          builder: (_, __) => const TasksScreen(scope: 'my'),
        ),
        GoRoute(
          path: '/team-tasks',
          builder: (_, __) => const TasksScreen(scope: 'team'),
        ),
        GoRoute(
          path: '/tasks/:id',
          builder: (_, s) => TaskDetailScreen(
            taskId: s.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: '/messages',
          builder: (_, __) => const MessagesScreen(),
        ),
        GoRoute(
          path: '/messages/:id',
          builder: (_, s) => MessageDetailScreen(
            messageId: s.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/users',
          builder: (_, __) => const UsersScreen(),
        ),
        GoRoute(
          path: '/permissions',
          builder: (_, __) => const PermissionsScreen(),
        ),
        GoRoute(
          path: '/trash',
          builder: (_, __) => const TrashScreen(),
        ),
      ],
    );

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      ref.invalidate(profileProvider);
      ref.invalidate(usersProvider);
      ref.invalidate(tasksProvider('my'));
      ref.invalidate(tasksProvider('team'));
      ref.invalidate(messagesProvider);
      ref.invalidate(notificationsProvider);
      ref.invalidate(dashboardProvider);
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final locale = ref.watch(languageProvider);

    if (profileState.hasValue && profileState.value != null) {
      final desired = profileState.value!.preferredLanguage == 'en'
          ? const Locale('en')
          : const Locale('ar');

      if (desired.languageCode != locale.languageCode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          AppI18n.setLocale(desired);
          ref.read(languageProvider.notifier).state = desired;
        });
      }
    }

    return MaterialApp.router(
      title: 'HF Team',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: HamaTheme.light(),
      routerConfig: router,
    );
  }
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
