import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/localization.dart';
import '../services/repository.dart';

final repoProvider = Provider<AppRepository>((ref) => AppRepository());
final profileProvider = FutureProvider<Profile?>((ref) => ref.watch(repoProvider).myProfile());
final usersProvider = FutureProvider<List<Profile>>((ref) => ref.watch(repoProvider).users());
final dashboardProvider = FutureProvider<DashboardStats>((ref) => ref.watch(repoProvider).dashboardStats());
final tasksProvider = FutureProvider.family<List<Task>, String>((ref, scope) => ref.watch(repoProvider).tasks(scope: scope));
final messagesProvider = FutureProvider<List<MessageItem>>((ref) => ref.watch(repoProvider).messages());
final notificationsProvider = FutureProvider<List<NotificationItem>>((ref) => ref.watch(repoProvider).notifications());
final taskCommentsProvider = FutureProvider.family<List<TaskComment>, String>((ref, id) => ref.watch(repoProvider).taskComments(id));
final messageCommentsProvider = FutureProvider.family<List<MessageComment>, String>((ref, id) => ref.watch(repoProvider).messageComments(id));
final messageRecipientsProvider = FutureProvider.family<List<Profile>, String>((ref, id) => ref.watch(repoProvider).messageRecipients(id));
final languageProvider = StateProvider<Locale>((ref) => AppI18n.locale);
