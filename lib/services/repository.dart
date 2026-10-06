import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import '../models/models.dart';

class AppRepository {
  SupabaseClient get _db => supabase;

  String get _uid =>
      _db.auth.currentUser?.id ??
      (throw const AuthException('Not authenticated'));

  String _code(String prefix) {
    final d = DateTime.now();
    final r = Random.secure().nextInt(9000) + 1000;
    return '$prefix-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}-'
        '${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}${d.second.toString().padLeft(2, '0')}-$r';
  }

  Future<Profile?> myProfile() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    final row = await _db.from('profiles').select().eq('id', user.id).maybeSingle();
    return row == null ? null : Profile.fromMap(Map<String, dynamic>.from(row));
  }

  Future<List<Profile>> users({bool activeOnly = true}) async {
    var q = _db.from('profiles').select(
          'id,username,full_name,user_code,role,department,preferred_language,is_active,avatar_url',
        );
    if (activeOnly) q = q.eq('is_active', true);
    final rows = await q.order('full_name');
    return rows
        .map<Profile>((m) => Profile.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<void> loginWithUsername({
    required String username,
    required String password,
  }) async {
    final u = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9._-]{3,40}$').hasMatch(u)) {
      throw const AuthException('Invalid username');
    }

    await _db.auth.signInWithPassword(
      email: '$u@${AppConfig.authDomain}',
      password: password,
    );

    final row = await _db
        .from('profiles')
        .select('username,is_active')
        .eq('id', _uid)
        .maybeSingle();

    if (row == null) {
      await _db.auth.signOut();
      throw const AuthException('Profile is not configured');
    }

    if ((row['username'] ?? '').toString().toLowerCase() != u ||
        row['is_active'] != true) {
      await _db.auth.signOut();
      throw const AuthException('User is inactive or username does not match');
    }

    try {
      await _db
          .from('profiles')
          .update({'last_seen_at': DateTime.now().toIso8601String()})
          .eq('id', _uid);
    } catch (_) {}
  }

  Future<void> createUser({
    required String username,
    required String fullName,
    required String password,
    required String role,
    required String departmentCode,
    String? jobTitle,
  }) async {
    final profile = await myProfile();
    if (profile == null || !profile.isGm) {
      throw const AuthException('Only the General Manager can create users');
    }

    final response = await _db.functions.invoke(
      'create-user',
      body: {
        'username': username.trim().toLowerCase(),
        'full_name': fullName.trim(),
        'password': password,
        'role': role,
        'department_code': departmentCode,
        'job_title': jobTitle?.trim(),
      },
    );

    if (response.status < 200 || response.status >= 300) {
      throw PostgrestException(message: response.data?.toString() ?? 'Could not create user');
    }
  }

  Future<void> changeMyPassword(String newPassword) async {
    if (newPassword.length < 6) throw const AuthException('Password must be at least 6 characters');
    await _db.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> resetUserPassword({required String userId, required String newPassword}) async {
    final p = await myProfile();
    if (p == null || !p.isGm) throw const AuthException('Only the General Manager can reset passwords');
    final response = await _db.functions.invoke('admin-reset-password', body: {
      'user_id': userId,
      'new_password': newPassword,
    });
    if (response.status < 200 || response.status >= 300) {
      throw PostgrestException(message: response.data?.toString() ?? 'Could not reset password');
    }
  }

  Future<void> uploadAvatar(Uint8List bytes, String extension) async {
    final path = '$_uid/avatar_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final contentType = switch (extension.toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    await _db.storage.from('avatars').uploadBinary(
      path, bytes, fileOptions: FileOptions(upsert: true, contentType: contentType),
    );
    final url = _db.storage.from('avatars').getPublicUrl(path);
    await _db.rpc('set_my_avatar_url', params: {'p_url': url});
  }

  Future<List<UserPermission>> userPermissions(String userId) async {
    final p = await myProfile();
    if (p == null || !p.isGm) throw const AuthException('Only the General Manager can manage permissions');
    final rows = await _db.from('user_permissions').select('user_id,permission_key,enabled').eq('user_id', userId);
    return rows.map<UserPermission>((m) => UserPermission.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  Future<void> setUserPermission({required String userId, required String permissionKey, required bool enabled}) async {
    final p = await myProfile();
    if (p == null || !p.isGm) throw const AuthException('Only the General Manager can manage permissions');
    await _db.from('user_permissions').upsert({
      'user_id': userId, 'permission_key': permissionKey, 'enabled': enabled, 'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<bool> hasPermission(String permissionKey) async {
    final p = await myProfile();
    if (p?.isGm == true) return true;
    final row = await _db.from('user_permissions').select('enabled').eq('user_id', _uid).eq('permission_key', permissionKey).maybeSingle();
    return row?['enabled'] == true;
  }

  Future<void> setPreferredLanguage(String code) async {
    if (code != 'ar' && code != 'en') {
      throw const PostgrestException(message: 'Invalid language');
    }
    await _db.rpc(
      'set_preferred_language',
      params: {'p_language': code},
    );
  }

  Future<DashboardStats> dashboardStats() async {
    await _syncDueNotifications();
    final tasks = await this.tasks();
    final my = tasks
        .where((t) => t.responsibleId == _uid || t.followerId == _uid)
        .toList();
    final unreadMessages = await _db.rpc('count_unread_messages');
    final unreadNotifications = await _db
        .from('notifications')
        .select('id')
        .eq('user_id', _uid)
        .eq('is_read', false)
        .count(CountOption.exact);

    return DashboardStats(
      myTasks: my.length,
      teamTasks: tasks.length,
      overdueTasks:
          tasks.where((t) => t.isOverdue).length,
      readyTasks: tasks
          .where((t) => t.effectiveStatus == 'ready_for_completion')
          .length,
      unreadMessages: unreadMessages is int ? unreadMessages : 0,
      unreadNotifications: unreadNotifications.count,
    );
  }

  Future<List<Task>> tasks({String scope = 'team'}) async {
    await _syncDueNotifications();
    final rows = await _db.from('tasks').select().isFilter('deleted_at', null).order('deadline');
    final all = rows
        .map<Task>((m) => Task.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    if (scope == 'my') {
      return all
          .where((t) => t.responsibleId == _uid || t.followerId == _uid)
          .toList();
    }
    return all;
  }

  Future<Task> taskById(String id) async {
    final row = await _db.from('tasks').select().eq('id', id).single();
    return Task.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> updateTask({
    required String id,
    required String title,
    String? description,
    required String priority,
    required DateTime deadline,
    required String responsibleId,
    String? followerId,
    bool? evidenceRequired,
    bool? managerConfirmationRequired,
    double? totalQuantity,
    String? quantityUnit,
  }) async {
    final p = await myProfile();
    if (p == null || !p.isGm) throw const AuthException('Only the General Manager can edit tasks');
    await _db.rpc('admin_update_task', params: {
      'p_task_id': id,
      'p_title': title.trim(),
      'p_description': description?.trim().isEmpty == true ? null : description?.trim(),
      'p_priority': priority,
      'p_deadline': deadline.toIso8601String(),
      'p_responsible_id': responsibleId,
      'p_follower_id': followerId,
      'p_evidence_required': evidenceRequired,
      'p_manager_confirmation_required': managerConfirmationRequired,
      'p_total_quantity': totalQuantity,
      'p_quantity_unit': quantityUnit?.trim().isEmpty == true ? null : quantityUnit?.trim(),
    });
  }

  Future<void> deleteTask(String id) async {
    final p = await myProfile();
    if (p == null || !p.isGm) throw const AuthException('Only the General Manager can delete tasks');
    await _db.rpc('admin_delete_task', params: {'p_task_id': id});
  }

  Future<List<Task>> trashTasks() async {
    final p = await myProfile();
    if (p == null || !p.isGm) throw const AuthException('Only the General Manager can access trash');
    final rows = await _db.from('tasks').select().not('deleted_at', 'is', null).order('deleted_at', ascending: false);
    return rows.map<Task>((m) => Task.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  Future<void> restoreTask(String id) async {
    final p = await myProfile();
    if (p == null || !p.isGm) throw const AuthException('Only the General Manager can restore tasks');
    await _db.rpc('admin_restore_task', params: {'p_task_id': id});
  }

  Future<void> permanentlyDeleteTask(String id) async {
    final p = await myProfile();
    if (p == null || !p.isGm) throw const AuthException('Only the General Manager can permanently delete tasks');
    await _db.rpc('admin_permanently_delete_task', params: {'p_task_id': id});
  }

  Future<Task> createTask({
    required String title,
    String? description,
    required String priority,
    required DateTime deadline,
    required String responsibleId,
    String? followerId,
    bool evidenceRequired = false,
    bool managerConfirmationRequired = true,
    String? messageId,
    double? totalQuantity,
    String? quantityUnit,
  }) async {
    final profile = await myProfile();
    if (profile == null || !profile.isGm) {
      throw const AuthException(
        'Only the General Manager can create tasks',
      );
    }

    if (title.trim().isEmpty) {
      throw const PostgrestException(message: 'Task title is required');
    }

    final row = await _db
        .from('tasks')
        .insert({
          'code': _code('TASK'),
          'title': title.trim(),
          'description': description?.trim().isEmpty == true
              ? null
              : description?.trim(),
          'priority': priority,
          'status': 'not_started',
          'responsible_id': responsibleId,
          'follower_id': followerId,
          'deadline': deadline.toIso8601String(),
          'evidence_required': evidenceRequired,
          'manager_confirmation_required': managerConfirmationRequired,
          'created_by': _uid,
          'message_id': messageId,
          'total_quantity': totalQuantity,
          'quantity_unit': quantityUnit?.trim().isEmpty == true ? null : quantityUnit?.trim(),
        })
        .select()
        .single();

    final task = Task.fromMap(Map<String, dynamic>.from(row));

    // Notification fallback: the DB trigger may already create these.
    // The dedupe key in the DB prevents duplicates.
    try {
      await _db.rpc(
        'notify_task_created',
        params: {'p_task_id': task.id},
      );
    } catch (_) {}

    return task;
  }

  Future<void> updateTaskStatus(String id, String status, {String? proofNote}) async {
    if (![
      'not_started',
      'in_progress',
      'ready_for_completion',
    ].contains(status)) {
      throw const PostgrestException(message: 'Invalid task status');
    }

    await _db.rpc(
      'set_task_status',
      params: {
        'p_task_id': id,
        'p_status': status,
        'p_proof_note': proofNote,
      },
    );

    try {
      await _db.rpc(
        'notify_task_status',
        params: {
          'p_task_id': id,
          'p_status': status,
        },
      );
    } catch (_) {}
  }

  Future<void> reopenTask(String id) async {
    if (!await hasPermission('tasks.reopen')) throw const AuthException('Reopen task permission required');

    await _db.rpc(
      'reopen_task',
      params: {'p_task_id': id},
    );

    try {
      await _db.rpc(
        'notify_task_status',
        params: {
          'p_task_id': id,
          'p_status': 'in_progress',
        },
      );
    } catch (_) {}
  }

  Future<void> cancelTask(String id) async {
    if (!await hasPermission('tasks.cancel')) throw const AuthException('Cancel task permission required');

    await _db.rpc('cancel_task', params: {'p_task_id': id});

    try {
      await _db.rpc(
        'notify_task_status',
        params: {
          'p_task_id': id,
          'p_status': 'cancelled',
        },
      );
    } catch (_) {}
  }

  Future<void> reviewTaskCompletion(String id) async {
    await _db.rpc('review_task_completion', params: {'p_task_id': id});
    try {
      await _db.rpc(
        'notify_task_status',
        params: {
          'p_task_id': id,
          'p_status': 'awaiting_approval',
        },
      );
    } catch (_) {}
  }

  Future<void> confirmTask(String id) async {
    final p = await myProfile();
    if (p == null || !p.isGm) {
      throw const AuthException('Only the General Manager can approve the operation');
    }

    await _db.rpc('approve_task', params: {'p_task_id': id});

    try {
      await _db.rpc(
        'notify_task_status',
        params: {
          'p_task_id': id,
          'p_status': 'completed',
        },
      );
    } catch (_) {}
  }

  Future<void> evaluateTask(
    String id,
    int score,
    String? comment,
  ) async {
    if (!await hasPermission('tasks.evaluate')) throw const AuthException('Evaluate task permission required');
    if (score < 1 || score > 10) {
      throw const PostgrestException(
        message: 'Score must be between 1 and 10',
      );
    }

    await _db.rpc(
      'evaluate_task',
      params: {
        'p_task_id': id,
        'p_score': score,
        'p_comment': comment?.trim().isEmpty == true
            ? null
            : comment?.trim(),
      },
    );
  }

  Future<List<TaskStage>> taskStages(String taskId) async {
    final rows = await _db.from('task_stages')
        .select('id,task_id,title,deadline,target_quantity,quantity_unit,sort_order,created_by,created_at,creator:profiles(full_name,avatar_url)')
        .eq('task_id', taskId)
        .order('sort_order')
        .order('deadline');
    return rows.map<TaskStage>((m) => TaskStage.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  Future<TaskStage> createTaskStage({
    required String taskId,
    required String title,
    required DateTime deadline,
    double? targetQuantity,
    String? quantityUnit,
    int sortOrder = 1,
  }) async {
    final p = await myProfile();
    if (p == null || !p.isGm) {
      throw const AuthException('Only the General Manager can add task stages');
    }
    final row = await _db.from('task_stages').insert({
      'task_id': taskId,
      'title': title.trim(),
      'deadline': deadline.toIso8601String(),
      'target_quantity': targetQuantity,
      'quantity_unit': quantityUnit?.trim().isEmpty == true ? null : quantityUnit?.trim(),
      'sort_order': sortOrder,
      'created_by': _uid,
    }).select().single();
    return TaskStage.fromMap(Map<String, dynamic>.from(row));
  }

  Future<List<TaskDailyUpdate>> taskDailyUpdates(String taskId) async {
    final rows = await _db.from('task_daily_updates')
        .select('id,task_id,stage_id,work_date,quantity_done,work_note,created_by,created_at,creator:profiles(full_name,avatar_url)')
        .eq('task_id', taskId)
        .order('work_date', ascending: false)
        .order('created_at', ascending: false);
    return rows.map<TaskDailyUpdate>((m) => TaskDailyUpdate.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  Future<TaskDailyUpdate> saveDailyUpdate({
    required String taskId,
    String? stageId,
    required DateTime workDate,
    double? quantityDone,
    String? workNote,
  }) async {
    if (quantityDone != null && quantityDone < 0) {
      throw const PostgrestException(message: 'Quantity cannot be negative');
    }
    final data = {
      'task_id': taskId,
      'stage_id': stageId,
      'work_date': workDate.toIso8601String().substring(0, 10),
      'quantity_done': quantityDone,
      'work_note': workNote?.trim().isEmpty == true ? null : workNote?.trim(),
      'created_by': _uid,
    };
    final row = await _db.from('task_daily_updates')
        .insert(data)
        .select('id,task_id,stage_id,work_date,quantity_done,work_note,created_by,created_at,creator:profiles(full_name,avatar_url)')
        .single();
    return TaskDailyUpdate.fromMap(Map<String, dynamic>.from(row));
  }

  Future<List<TaskFollowerNote>> taskFollowerNotes(String taskId) async {
    final rows = await _db
        .from('task_follower_notes')
        .select('id,task_id,created_by,note,created_at,updated_at,creator:profiles(full_name,avatar_url)')
        .eq('task_id', taskId)
        .order('created_at', ascending: false);
    return rows.map<TaskFollowerNote>((m) => TaskFollowerNote.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  Future<TaskFollowerNote> addTaskFollowerNote(String taskId, String note) async {
    final row = await _db.from('task_follower_notes')
        .insert({'task_id': taskId, 'created_by': _uid, 'note': note.trim()})
        .select('id,task_id,created_by,note,created_at,updated_at,creator:profiles(full_name,avatar_url)')
        .single();
    return TaskFollowerNote.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> updateTaskFollowerNote(String id, String note) async {
    await _db.from('task_follower_notes').update({'note': note.trim()}).eq('id', id);
  }

  Future<void> deleteTaskFollowerNote(String id) async {
    await _db.from('task_follower_notes').delete().eq('id', id);
  }

  Future<List<TaskComment>> taskComments(String taskId) async {
    final rows = await _db
        .from('task_comments')
        .select(
          'id,task_id,content,created_by,created_at,creator:profiles(full_name,avatar_url)',
        )
        .eq('task_id', taskId)
        .order('created_at');

    return rows.map<TaskComment>((m) {
      final mm = Map<String, dynamic>.from(m);
      final c = mm['creator'];
      return TaskComment(
        id: mm['id'].toString(),
        taskId: mm['task_id'].toString(),
        content: (mm['content'] ?? '').toString(),
        createdBy: mm['created_by']?.toString(),
        creatorName:
            c is Map ? (c['full_name'] ?? 'User').toString() : 'User',
        creatorAvatarUrl: c is Map ? c['avatar_url']?.toString() : null,
        createdAt:
            DateTime.tryParse(mm['created_at'].toString()) ?? DateTime.now(),
      );
    }).toList();
  }

  Future<TaskComment> addTaskComment(String taskId, String content) async {
    final row = await _db.from('task_comments').insert({
      'task_id': taskId,
      'content': content.trim(),
      'created_by': _uid,
    }).select('id,task_id,content,created_by,created_at,creator:profiles(full_name,avatar_url)').single();
    final mm = Map<String, dynamic>.from(row);
    final c = mm['creator'];
    return TaskComment(
      id: mm['id'].toString(),
      taskId: mm['task_id'].toString(),
      content: (mm['content'] ?? '').toString(),
      createdBy: mm['created_by']?.toString(),
      creatorName: c is Map ? (c['full_name'] ?? 'User').toString() : 'User',
      creatorAvatarUrl: c is Map ? c['avatar_url']?.toString() : null,
      createdAt: DateTime.tryParse(mm['created_at'].toString()) ?? DateTime.now(),
    );
  }

  Future<List<MessageItem>> messages() async {
    final rows = await _db.rpc('get_visible_messages');
    return (rows as List)
        .map<MessageItem>(
          (m) => MessageItem.fromMap(
            Map<String, dynamic>.from(m as Map),
          ),
        )
        .toList();
  }

  Future<MessageItem> messageById(String id) async {
    await markMessageSeen(id);
    await markMessageCommentsRead(id);
    final row = await _db.rpc(
      'get_message_detail',
      params: {'p_message_id': id},
    );
    final list = row as List;
    if (list.isEmpty) {
      throw const PostgrestException(message: 'Message not found');
    }
    return MessageItem.fromMap(
      Map<String, dynamic>.from(list.first as Map),
    );
  }

  Future<void> createMessage({
    required String content,
    required String messageType,
    required String audienceType,
    required List<String> recipientIds,
  }) async {
    final result = await _db.rpc(
      'create_message',
      params: {
        'p_content': content.trim(),
        'p_message_type': messageType,
        'p_audience_type': audienceType,
        'p_target_user_ids': recipientIds,
      },
    );

    final messageId = result?.toString();
    if (messageId != null && messageId.isNotEmpty) {
      try {
        await _db.rpc(
          'notify_message_sent',
          params: {'p_message_id': messageId},
        );
      } catch (_) {}
    }
  }

  Future<void> markMessageSeen(String id) async {
    await _db.rpc(
      'mark_message_seen',
      params: {'p_message_id': id},
    );
  }

  Future<void> setMessageStatus(String messageId, String status) async {
    await _db.rpc(
      'set_message_recipient_status',
      params: {'p_message_id': messageId, 'p_status': status},
    );
  }

  Future<Map<String, int>> messageStatusCounts() async {
    final row = await _db.rpc('get_my_message_status_counts');
    if (row is List && row.isNotEmpty) {
      final m = Map<String, dynamic>.from(row.first as Map);
      return {
        'not_started': int.tryParse('${m['not_started'] ?? 0}') ?? 0,
        'in_progress': int.tryParse('${m['in_progress'] ?? 0}') ?? 0,
        'completed': int.tryParse('${m['completed'] ?? 0}') ?? 0,
      };
    }
    return {'not_started': 0, 'in_progress': 0, 'completed': 0};
  }

  Future<List<Profile>> messageRecipients(String messageId) async {
    final rows = await _db.rpc(
      'get_message_recipients',
      params: {'p_message_id': messageId},
    );

    return (rows as List)
        .map<Profile>((m) {
          final mm = Map<String, dynamic>.from(m as Map);
          return Profile(
            id: (mm['user_id'] ?? '').toString(),
            username: (mm['username'] ?? '').toString(),
            fullName: (mm['full_name'] ?? 'User').toString(),
            userCode: '',
            role: 'employee',
            department: '',
            preferredLanguage: 'ar',
            isActive: true,
            avatarUrl: mm['avatar_url']?.toString(),
          );
        })
        .where((p) => p.id.isNotEmpty)
        .toList();
  }

  Future<List<MessageComment>> messageComments(String messageId) async {
    final rows = await _db
        .from('message_comments')
        .select(
          'id,message_id,content,created_by,created_at,creator:profiles(full_name,avatar_url)',
        )
        .eq('message_id', messageId)
        .order('created_at');

    return rows.map<MessageComment>((m) {
      final mm = Map<String, dynamic>.from(m);
      final c = mm['creator'];
      return MessageComment(
        id: mm['id'].toString(),
        messageId: mm['message_id'].toString(),
        content: (mm['content'] ?? '').toString(),
        createdBy: mm['created_by']?.toString(),
        creatorName:
            c is Map ? (c['full_name'] ?? 'User').toString() : 'User',
        creatorAvatarUrl: c is Map ? c['avatar_url']?.toString() : null,
        createdAt:
            DateTime.tryParse(mm['created_at'].toString()) ?? DateTime.now(),
      );
    }).toList();
  }

  Future<int> unreadTaskCommentsCount(String taskId) async {
    final row = await _db.rpc('get_unread_task_comment_count', params: {'p_task_id': taskId});
    return int.tryParse(row.toString()) ?? 0;
  }

  Future<void> markTaskCommentsRead(String taskId) async {
    await _db.rpc('mark_task_comments_read', params: {'p_task_id': taskId});
  }

  Future<Map<String, int>> unreadMessageCommentsCounts() async {
    final rows = await _db.rpc('get_unread_message_comment_counts');
    final result = <String, int>{};
    for (final raw in (rows as List)) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = m['message_id']?.toString();
      if (id != null && id.isNotEmpty) result[id] = int.tryParse(m['unread_count'].toString()) ?? 0;
    }
    return result;
  }

  Future<int> unreadMessageConversationsCount() async {
    final row = await _db.rpc('get_unread_message_conversations_count');
    return int.tryParse(row.toString()) ?? 0;
  }

  Future<void> markMessageCommentsRead(String messageId) async {
    await _db.rpc('mark_message_comments_read', params: {'p_message_id': messageId});
  }

  Future<String> addMessageComment(
    String messageId,
    String content,
  ) async {
    final row = await _db.from('message_comments').insert({
      'message_id': messageId,
      'content': content.trim(),
      'created_by': _uid,
    }).select('id').single();
    return row['id'].toString();
  }

  Future<void> linkMessageToTask(String messageId, String taskId) async {
    await _db
        .from('messages')
        .update({'task_id': taskId})
        .eq('id', messageId);
  }

  Future<List<AttachmentItem>> attachmentsForTask(String taskId) async {
    final rows = await _db.from('attachments').select(
      'id,task_id,message_id,daily_update_id,message_comment_id,task_comment_id,is_completion_proof,file_name,storage_path,mime_type,file_size,uploaded_by,created_at,uploader:profiles(full_name,avatar_url)',
    ).eq('task_id', taskId).order('created_at', ascending: false);
    return rows.map<AttachmentItem>((m) => AttachmentItem.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  Future<List<AttachmentItem>> attachmentsForDailyUpdate(String updateId) async {
    final rows = await _db.from('attachments').select(
      'id,task_id,message_id,daily_update_id,message_comment_id,task_comment_id,is_completion_proof,file_name,storage_path,mime_type,file_size,uploaded_by,created_at,uploader:profiles(full_name,avatar_url)',
    ).eq('daily_update_id', updateId).order('created_at', ascending: false);
    return rows.map<AttachmentItem>((m) => AttachmentItem.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  Future<List<AttachmentItem>> attachmentsForMessageComment(String commentId) async {
    final rows = await _db.from('attachments').select(
      'id,task_id,message_id,daily_update_id,message_comment_id,task_comment_id,is_completion_proof,file_name,storage_path,mime_type,file_size,uploaded_by,created_at,uploader:profiles(full_name,avatar_url)',
    ).eq('message_comment_id', commentId).order('created_at', ascending: false);
    return rows.map<AttachmentItem>((m) => AttachmentItem.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  Future<List<AttachmentItem>> attachmentsForTaskComment(String commentId) async {
    final rows = await _db.from('attachments').select(
      'id,task_id,message_id,daily_update_id,message_comment_id,task_comment_id,is_completion_proof,file_name,storage_path,mime_type,file_size,uploaded_by,created_at,uploader:profiles(full_name,avatar_url)',
    ).eq('task_comment_id', commentId).order('created_at', ascending: false);
    return rows.map<AttachmentItem>((m) => AttachmentItem.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  Future<List<AttachmentItem>> attachmentsForMessage(String messageId) async {
    final rows = await _db.from('attachments').select(
      'id,task_id,message_id,daily_update_id,message_comment_id,task_comment_id,is_completion_proof,file_name,storage_path,mime_type,file_size,uploaded_by,created_at,uploader:profiles(full_name,avatar_url)',
    ).eq('message_id', messageId).order('created_at', ascending: false);
    return rows.map<AttachmentItem>((m) => AttachmentItem.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  Future<AttachmentItem> uploadAttachment({
    String? taskId,
    String? messageId,
    String? dailyUpdateId,
    String? messageCommentId,
    String? taskCommentId,
    bool isCompletionProof = false,
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final parentCount = [taskId, messageId, dailyUpdateId, messageCommentId, taskCommentId].whereType<String>().length;
    if (parentCount != 1) {
      throw const PostgrestException(message: 'Attachment must belong to exactly one parent');
    }
    final allowed = await hasPermission('attachments.upload');
    if (!allowed) throw const AuthException('Attachment upload permission required');
    if (dailyUpdateId != null) {
      final row = await _db.from('task_daily_updates').select('attachments_locked').eq('id', dailyUpdateId).maybeSingle();
      if (row == null || row['attachments_locked'] == true) {
        throw const AuthException('Attachments are locked for this saved work log');
      }
    }
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$_uid/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await _db.storage.from('attachments').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(upsert: false, contentType: mimeType),
    );
    try {
      final row = await _db.from('attachments').insert({
        'task_id': taskId,
        'message_id': messageId,
        'daily_update_id': dailyUpdateId,
        'message_comment_id': messageCommentId,
        'task_comment_id': taskCommentId,
        'is_completion_proof': isCompletionProof,
        'file_name': fileName,
        'storage_path': path,
        'mime_type': mimeType,
        'file_size': bytes.length,
        'uploaded_by': _uid,
      }).select('id,task_id,message_id,file_name,storage_path,mime_type,file_size,uploaded_by,created_at,uploader:profiles(full_name,avatar_url)').single();
      return AttachmentItem.fromMap(Map<String, dynamic>.from(row));
    } catch (e) {
      try { await _db.storage.from('attachments').remove([path]); } catch (_) {}
      rethrow;
    }
  }

  Future<void> finalizeDailyUpdateAttachments(String dailyUpdateId) async {
    await _db.rpc('finalize_daily_update_attachments', params: {'p_daily_update_id': dailyUpdateId});
  }

  Future<String> attachmentUrl(AttachmentItem item) async {
    // Use the database SECURITY DEFINER function so access is evaluated from
    // the attachment's actual parent (task/message/comment/daily update) and
    // the signed URL is generated consistently for every client/device.
    final result = await _db.rpc(
      'attachment_signed_url',
      params: {'p_attachment_id': item.id},
    );
    final url = result?.toString().trim() ?? '';
    if (url.isEmpty) {
      throw PostgrestException(
        message: 'تعذر إنشاء رابط آمن للمرفق',
        code: 'ATTACHMENT_URL_EMPTY',
      );
    }
    return url;
  }

  Future<void> deleteAttachment(AttachmentItem item) async {
    if (item.uploadedBy != _uid) {
      final p = await myProfile();
      if (p?.isGm != true) throw const AuthException('Not allowed');
    }
    await _db.from('attachments').delete().eq('id', item.id);
    try { await _db.storage.from('attachments').remove([item.storagePath]); } catch (_) {}
  }

  Future<List<NotificationItem>> notifications() async {
    await _syncDueNotifications();
    final rows = await _db
        .from('notifications')
        .select('*,actor:profiles!notifications_actor_id_fkey(full_name,avatar_url)')
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .limit(100);

    final taskIds = rows.map((r) => r['target_type'] == 'task' ? r['target_id']?.toString() : null).whereType<String>().toSet();
    final deletedIds = <String>{};
    if (taskIds.isNotEmpty) {
      final deleted = await _db.from('tasks').select('id').inFilter('id', taskIds.toList()).not('deleted_at', 'is', null);
      deletedIds.addAll(deleted.map((r) => r['id'].toString()));
    }

    return rows
        .where((r) => !(r['target_type'] == 'task' && deletedIds.contains(r['target_id']?.toString())))
        .map<NotificationItem>(
          (m) => NotificationItem.fromMap(
            Map<String, dynamic>.from(m),
          ),
        )
        .toList();
  }

  Future<void> markNotificationRead(String id) async {
    await _db
        .from('notifications')
        .update({
          'is_read': true,
          'read_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', _uid);
  }

  Future<void> markAllNotificationsRead() async {
    await _db
        .from('notifications')
        .update({
          'is_read': true,
          'read_at': DateTime.now().toIso8601String(),
        })
        .eq('user_id', _uid)
        .eq('is_read', false);
  }

  Future<void> _syncDueNotifications() async {
    try {
      await _db.rpc('sync_task_due_notifications');
    } catch (_) {
      // Notifications are best-effort; task/message loading should still work.
    }
  }
}
