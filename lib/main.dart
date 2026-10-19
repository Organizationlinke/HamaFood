import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/supabase_client.dart';
import 'core/resilient_local_storage.dart';
import 'providers/providers.dart';
import 'services/localization.dart';
import 'services/push_notification_service.dart';
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
    final supabaseUrl = AppConfig.url.trim();
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: AppConfig.publishableKey.trim(),
      // Keep the authenticated session across browser refreshes/restarts.
      // If mobile browser localStorage becomes unavailable, the resilient
      // storage falls back to memory instead of crashing the whole app.
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: true,
        localStorage: ResilientLocalStorage(
          persistSessionKey:
              'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token',
        ),
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

class _HamaWorkAppState extends ConsumerState<HamaWorkApp>
    with WidgetsBindingObserver {
  late final GoRouter router;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSub;
  bool _homeEntryAuditDone = false;
  bool _auditWriteInFlight = false;
  bool _pushStartupCheckDone = false;
  bool _pushStartupCheckInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    router = GoRouter(
      navigatorKey: _navigatorKey,
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
          builder: (_, s) => TasksScreen(
            scope: 'my',
            initialStatus: s.uri.queryParameters['status'] ?? 'not_started',
          ),
        ),
        GoRoute(
          path: '/team-tasks',
          builder: (_, s) => TasksScreen(
            scope: 'team',
            initialStatus: s.uri.queryParameters['status'] ?? 'not_started',
          ),
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

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (!mounted) return;
      if (event.event == AuthChangeEvent.signedOut) {
        _homeEntryAuditDone = false;
        _pushStartupCheckDone = false;
      }
      ref.invalidate(profileProvider);
      ref.invalidate(usersProvider);
      ref.invalidate(tasksProvider('my'));
      ref.invalidate(tasksProvider('team'));
      ref.invalidate(messagesProvider);
      ref.invalidate(notificationsProvider);
      ref.invalidate(dashboardProvider);
    });
  }

  /// Updates the user's last-login/session timestamp whenever the app becomes
  /// active again. This covers opening HF Team and returning to it after the
  /// user switched to another application/tab, without requiring sign-out.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recordAppResume();
    }
  }

  Future<void> _recordAppResume() async {
    await _writeLoginAudit(reason: 'app resume');
  }

  Future<void> _recordHomeEntryOnce() async {
    if (_homeEntryAuditDone) return;
    if (Supabase.instance.client.auth.currentSession == null) return;

    _homeEntryAuditDone = true;
    await _writeLoginAudit(reason: 'home entry');
    await _checkPushNotificationsAtStartup();
  }

  Future<void> _checkPushNotificationsAtStartup() async {
    if (_pushStartupCheckDone || _pushStartupCheckInFlight) return;
    if (Supabase.instance.client.auth.currentSession == null) return;

    _pushStartupCheckInFlight = true;
    try {
      final service = HamaPushNotificationService();
      final status = await service.checkAtAppStart();

      if (!mounted) return;
      if (status.enabled) {
        _pushStartupCheckDone = true;
        return;
      }

      // Show the HF Team explanation immediately after the authenticated home
      // shell is ready. The browser's native permission prompt itself is
      // requested only after the user taps the action button, which keeps the
      // flow compatible with browsers that require user activation.
      await _showPushStartupDialog(status);
      _pushStartupCheckDone = true;
    } finally {
      _pushStartupCheckInFlight = false;
    }
  }

  Future<void> _showPushStartupDialog(PushNotificationStatus status) async {
    final denied = status.permissionDenied;

    final materialContext = _navigatorKey.currentState?.overlay?.context;
    if (materialContext == null) return;

    final action = await showDialog<bool>(
      context: materialContext,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          tr(denied
              ? 'Notifications are blocked'
              : 'Allow HF Team notifications'),
        ),
        content: Text(
          tr(denied
              ? 'You previously denied notifications. HF Team cannot show browser notifications until you allow them from your browser/site notification settings.'
              : 'HF Team needs notification permission to alert you about new tasks, messages, replies, and other important activity. Please allow notifications.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr('Later')),
          ),
          if (!denied)
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.notifications_active_rounded),
              label: Text(tr('Allow notifications')),
            ),
        ],
      ),
    );

    if (!mounted || action != true || denied) return;

    final result = await HamaPushNotificationService().enable();
    if (!mounted) return;

    if (result.enabled) {
      final snackContext = _navigatorKey.currentState?.overlay?.context;
      if (snackContext != null) {
        ScaffoldMessenger.of(snackContext).showSnackBar(
          SnackBar(content: Text(tr('Browser notifications enabled.'))),
        );
      }
      return;
    }

    if (result.permissionDenied) {
      final dialogContext = _navigatorKey.currentState?.overlay?.context;
      if (dialogContext == null) return;
      await showDialog<void>(
        context: dialogContext,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr('Notifications are blocked')),
          content: Text(
            tr('You denied notification permission. Open your browser/site notification settings and allow HF Team notifications, then reopen HF Team.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(tr('OK')),
            ),
          ],
        ),
      );
    } else {
      final snackContext = _navigatorKey.currentState?.overlay?.context;
      if (snackContext != null) {
        ScaffoldMessenger.of(snackContext).showSnackBar(
          SnackBar(content: Text(tr(result.message))),
        );
      }
    }
  }

  Future<void> _writeLoginAudit({required String reason}) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null || _auditWriteInFlight) return;

    _auditWriteInFlight = true;
    try {
      await client.rpc('record_my_login');
      // The first app-resume can happen just before the authenticated Home
      // shell finishes building. Mark it as handled so Home entry does not
      // create a duplicate history row.
      if (reason == 'app resume') {
        _homeEntryAuditDone = true;
      }
      // If an administrator is already on the Users screen, refresh the
      // displayed last-login value after entering/returning to the app.
      if (mounted) {
        ref.invalidate(profileProvider);
        ref.invalidate(myLoginHistoryProvider);
        ref.invalidate(usersProvider);
      }
    } catch (e, st) {
      // Login/session usage must never be blocked by an audit-write failure.
      debugPrint('record_my_login ($reason) failed: $e');
      debugPrintStack(stackTrace: st);
    } finally {
      _auditWriteInFlight = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final locale = ref.watch(languageProvider);

    if (profileState.hasValue && profileState.value != null) {
      // The user can enter HF Team without performing a fresh password login
      // because Supabase restores the saved session. Record that app entry
      // once when the authenticated home shell is actually ready.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _recordHomeEntryOnce();
      });

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
