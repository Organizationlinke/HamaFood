// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:hama_work/widgets/common.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';
// import '../core/supabase_client.dart';
// import '../providers/providers.dart';
// import '../services/localization.dart';
// import '../services/realtime_service.dart';
// import '../theme.dart';

// class AppScaffold extends ConsumerStatefulWidget {
//   final String title;
//   final Widget body;
//   final List<Widget>? actions;
//   final Widget? floatingActionButton;
//   final bool showBack;
//   final String? backRoute;

//   const AppScaffold({super.key, required this.title, required this.body, this.actions, this.floatingActionButton, this.showBack = false, this.backRoute});

//   @override
//   ConsumerState<AppScaffold> createState() => _AppScaffoldState();
// }

// class _AppScaffoldState extends ConsumerState<AppScaffold> {
//   RealtimeChannel? _notificationChannel;

//   @override
//   void initState() {
//     super.initState();
//   }

//   void _startNotificationRealtime() {
//     if (_notificationChannel != null) return;
//     final userId = supabase.auth.currentUser?.id;
//     if (userId == null) return;

//     _notificationChannel = HamaRealtime.notificationsForUser(
//       userId: userId,
//       onChange: () {
//         if (!mounted) return;
//         ref.invalidate(notificationsProvider);
//         ref.invalidate(dashboardProvider);
//       },
//     );
//   }

//   @override
//   void dispose() {
//     final channel = _notificationChannel;
//     if (channel != null) {
//       supabase.removeChannel(channel);
//     }
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     _startNotificationRealtime();
//     final widget = this.widget;
//     final ref = this.ref;
//     final profile = ref.watch(profileProvider).valueOrNull;
//     final unread = ref.watch(notificationsProvider).maybeWhen(
//       data: (items) => items.where((n) => !n.isRead).length,
//       orElse: () => 0,
//     );
//     return Scaffold(
//       appBar: AppBar(
//         titleSpacing: 14,
//         flexibleSpace: Container(
//           decoration: const BoxDecoration(
//             gradient: LinearGradient(
//               colors: [HamaColors.navy, HamaColors.navy2],
//               begin: AlignmentDirectional.centerStart,
//               end: AlignmentDirectional.centerEnd,
//             ),
//           ),
//         ),
//         leading: showBack
//             ? IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () { if (context.canPop()) { context.pop(); } else if (backRoute != null) { context.go(backRoute!); } else { context.go('/'); } })
//             : Builder(builder: (c) => IconButton(icon: const Icon(Icons.menu_rounded), onPressed: () => Scaffold.of(c).openDrawer())),
//         title: Row(
//           children: [
//             const HamaMark(size: 34, compact: true),
//             const SizedBox(width: 10),
//             Flexible(child: T(title, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2))),
//           ],
//         ),
//         actions: [
//           Stack(
//             children: [
//               IconButton(onPressed: () => context.go('/notifications'), icon: const Icon(Icons.notifications_none_rounded)),
//               if (unread > 0)
//                 Positioned(
//                   right: 8,
//                   top: 8,
//                   child: Container(
//                     width: 9,
//                     height: 9,
//                     decoration: const BoxDecoration(color: HamaColors.orange, shape: BoxShape.circle),
//                   ),
//                 ),
//             ],
//           ),
//           ...?actions,
//           const SizedBox(width: 4),
//         ],
//       ),
//       drawer: Drawer(
//         child: SafeArea(
//           child: Column(
//             children: [
//               Container(
//                 width: double.infinity,
//                 padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
//                 decoration: const BoxDecoration(
//                   gradient: LinearGradient(
//                     colors: [HamaColors.navy, HamaColors.navy2],
//                     begin: Alignment.topLeft,
//                     end: Alignment.bottomRight,
//                   ),
//                 ),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Row(children: [
//                       profile == null ? const HamaMark(size: 52) : UserAvatar(user: profile, radius: 26),
//                       const SizedBox(width: 12),
//                       const Text('Hama Work', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
//                     ]),
//                     const SizedBox(height: 4),
//                     Text(
//                       profile?.fullName ?? 'User',
//                       style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
//                     ),
//                     const SizedBox(height: 2),
//                     Text(
//                       '@${profile?.username ?? ''} • ${AppI18n.roleLabel(profile?.role ?? '')}',
//                       style: TextStyle(color: Colors.white.withOpacity(.70), fontSize: 12),
//                     ),
//                   ],
//                 ),
//               ),
//               Expanded(
//                 child: ListView(
//                   padding: const EdgeInsets.symmetric(vertical: 10),
//                   children: [
//                     _nav(context, 'Dashboard', Icons.dashboard_rounded, '/'),
//                     _nav(context, 'My Tasks', Icons.task_alt_rounded, '/my-tasks'),
//                     _nav(context, 'Team Tasks', Icons.groups_rounded, '/team-tasks'),
//                     _nav(context, 'Messages', Icons.forum_rounded, '/messages'),
//                     _nav(context, 'Notifications', Icons.notifications_active_rounded, '/notifications'),
//                     _nav(context, 'Users', Icons.people_alt_rounded, '/users'),
//                     if (profile?.isGm == true) ...[
//                       _nav(context, 'Permissions', Icons.admin_panel_settings_rounded, '/permissions'),
//                       _nav(context, 'Trash', Icons.delete_sweep_rounded, '/trash'),
//                     ],
//                     _nav(context, 'Settings', Icons.tune_rounded, '/settings'),
//                   ],
//                 ),
//               ),
//               const Divider(height: 1),
//               ListTile(
//                 leading: const Icon(Icons.logout_rounded, color: HamaColors.red),
//                 title: const T('Logout'),
//                 onTap: () async {
//                   Navigator.pop(context);
//                   await supabase.auth.signOut();
//                   ref.invalidate(profileProvider);
//                 },
//               ),
//             ],
//           ),
//         ),
//       ),
//       body: body,
//       floatingActionButton: floatingActionButton,
//     );
//   }

//   Widget _nav(BuildContext context, String label, IconData icon, String route) => ListTile(
//     leading: Icon(icon, color: HamaColors.navy2),
//     title: T(label, style: const TextStyle(fontWeight: FontWeight.w600)),
//     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//     onTap: () {
//       Navigator.pop(context);
//       context.go(route);
//     },
//   );
// }
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hama_work/widgets/common.dart';

import '../core/supabase_client.dart';
import '../providers/providers.dart';
import '../services/localization.dart';
import '../services/realtime_service.dart';
import '../theme.dart';

class AppScaffold extends ConsumerStatefulWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showBack;
  final String? backRoute;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.showBack = false,
    this.backRoute,
  });

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  RealtimeChannel? _notificationChannel;

  @override
  void initState() {
    super.initState();
  }

  void _startNotificationRealtime() {
    if (_notificationChannel != null) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _notificationChannel = HamaRealtime.notificationsForUser(
      userId: userId,
      onChange: () {
        if (!mounted) return;

        ref.invalidate(notificationsProvider);
        ref.invalidate(dashboardProvider);
      },
    );
  }

  @override
  void dispose() {
    final channel = _notificationChannel;

    if (channel != null) {
      supabase.removeChannel(channel);
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _startNotificationRealtime();

    final profile = ref.watch(profileProvider).valueOrNull;

    final unread = ref.watch(notificationsProvider).maybeWhen(
          data: (items) => items.where((n) => !n.isRead).length,
          orElse: () => 0,
        );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 14,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                HamaColors.navy,
                HamaColors.navy2,
              ],
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
            ),
          ),
        ),

        leading: widget.showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else if (widget.backRoute != null) {
                    context.go(widget.backRoute!);
                  } else {
                    context.go('/');
                  }
                },
              )
            : Builder(
                builder: (c) => IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => Scaffold.of(c).openDrawer(),
                ),
              ),

        title: Row(
          children: [
            const HamaMark(
              size: 34,
              compact: true,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: T(
                widget.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: .2,
                ),
              ),
            ),
          ],
        ),

        actions: [
          Stack(
            children: [
              IconButton(
                onPressed: () => context.go('/notifications'),
                icon: const Icon(
                  Icons.notifications_none_rounded,
                ),
              ),

              if (unread > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: HamaColors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),

          ...?widget.actions,

          const SizedBox(width: 4),
        ],
      ),

      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  20,
                  22,
                  20,
                  20,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      HamaColors.navy,
                      HamaColors.navy2,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        profile == null
                            ? const HamaMark(size: 52)
                            : UserAvatar(
                                user: profile,
                                radius: 26,
                              ),

                        const SizedBox(width: 12),

                        const Text(
                          'Hama Work',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    Text(
                      profile?.fullName ?? 'User',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      '@${profile?.username ?? ''} • '
                      '${AppI18n.roleLabel(profile?.role ?? '')}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(.70),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                  ),
                  children: [
                    _nav(
                      context,
                      'Dashboard',
                      Icons.dashboard_rounded,
                      '/',
                    ),
                    _nav(
                      context,
                      'My Tasks',
                      Icons.task_alt_rounded,
                      '/my-tasks',
                    ),
                    _nav(
                      context,
                      'Team Tasks',
                      Icons.groups_rounded,
                      '/team-tasks',
                    ),
                    _nav(
                      context,
                      'Messages',
                      Icons.forum_rounded,
                      '/messages',
                    ),
                    _nav(
                      context,
                      'Notifications',
                      Icons.notifications_active_rounded,
                      '/notifications',
                    ),
                    _nav(
                      context,
                      'Users',
                      Icons.people_alt_rounded,
                      '/users',
                    ),

                    if (profile?.isGm == true) ...[
                      _nav(
                        context,
                        'Permissions',
                        Icons.admin_panel_settings_rounded,
                        '/permissions',
                      ),
                      _nav(
                        context,
                        'Trash',
                        Icons.delete_sweep_rounded,
                        '/trash',
                      ),
                    ],

                    _nav(
                      context,
                      'Settings',
                      Icons.tune_rounded,
                      '/settings',
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              ListTile(
                leading: const Icon(
                  Icons.logout_rounded,
                  color: HamaColors.red,
                ),
                title: const T('Logout'),
                onTap: () async {
                  Navigator.pop(context);

                  await supabase.auth.signOut();

                  ref.invalidate(profileProvider);
                },
              ),
            ],
          ),
        ),
      ),

      body: widget.body,

      floatingActionButton: widget.floatingActionButton,
    );
  }

  Widget _nav(
    BuildContext context,
    String label,
    IconData icon,
    String route,
  ) {
    return ListTile(
      leading: Icon(
        icon,
        color: HamaColors.navy2,
      ),
      title: T(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onTap: () {
        Navigator.pop(context);
        context.go(route);
      },
    );
  }
}