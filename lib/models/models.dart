import '../widgets/common.dart';

DateTime? _date(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

double? _num(dynamic v) => v == null ? null : double.tryParse(v.toString());

bool _bool(dynamic value, [bool fallback = false]) {
  if (value == null) return fallback;
  if (value is bool) return value;
  return value.toString().toLowerCase() == 'true';
}

int? _int(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

class Profile implements ProfileLike {
  final String id;
  final String username;
  final String fullName;
  final String userCode;
  final String role;
  final String department;
  final String preferredLanguage;
  final bool isActive;
  final String? avatarUrl;

  const Profile({
    required this.id,
    required this.username,
    required this.fullName,
    required this.userCode,
    required this.role,
    required this.department,
    required this.preferredLanguage,
    required this.isActive,
    this.avatarUrl,
  });

  bool get isGm => role == 'gm';
  bool get isManager => role == 'manager';

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'].toString(),
        username: (m['username'] ?? '').toString(),
        fullName: (m['full_name'] ?? 'User').toString(),
        userCode: (m['user_code'] ?? '').toString(),
        role: (m['role'] ?? 'employee').toString(),
        department: (m['department'] ?? '').toString(),
        preferredLanguage: (m['preferred_language'] ?? 'ar').toString() == 'en' ? 'en' : 'ar',
        isActive: _bool(m['is_active'], true),
        avatarUrl: m['avatar_url']?.toString(),
      );
}

class Task {
  final String id;
  final String code;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final String? responsibleId;
  final String? followerId;
  final String? createdBy;
  final String? messageId;
  final DateTime? deadline;
  final bool evidenceRequired;
  final bool managerConfirmationRequired;
  final bool managerConfirmed;
  final String? managerConfirmedBy;
  final DateTime? managerConfirmedAt;
  final int? score;
  final String? evalComment;
  final DateTime? completionRequestedAt;
  final String? completionProofNote;
  final DateTime? followerReviewedAt;
  final String? followerReviewedBy;
  final DateTime? completedAt;
  final String? completedBy;
  final DateTime? reopenedAt;
  final String? reopenedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final double? totalQuantity;
  final String? quantityUnit;
  final DateTime? deletedAt;
  final String? deletedBy;

  const Task({
    required this.id,
    required this.code,
    required this.title,
    this.description,
    required this.status,
    required this.priority,
    this.responsibleId,
    this.followerId,
    this.createdBy,
    this.messageId,
    this.deadline,
    this.evidenceRequired = false,
    this.managerConfirmationRequired = true,
    this.managerConfirmed = false,
    this.managerConfirmedBy,
    this.managerConfirmedAt,
    this.score,
    this.evalComment,
    this.completionRequestedAt,
    this.completionProofNote,
    this.followerReviewedAt,
    this.followerReviewedBy,
    this.completedAt,
    this.completedBy,
    this.reopenedAt,
    this.reopenedBy,
    this.createdAt,
    this.updatedAt,
    this.totalQuantity,
    this.quantityUnit,
    this.deletedAt,
    this.deletedBy,
  });

  bool get isDeleted => deletedAt != null || status == 'deleted';

  bool get isOverdue {
    if (isDeleted || status == 'completed' || status == 'cancelled' || status == 'ready_for_completion' || status == 'awaiting_approval') return false;
    return deadline != null && deadline!.isBefore(DateTime.now());
  }

  String get effectiveStatus => isDeleted ? 'deleted' : (isOverdue ? 'overdue' : status);

  factory Task.fromMap(Map<String, dynamic> m) => Task(
        id: m['id'].toString(),
        code: (m['code'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        description: m['description']?.toString(),
        status: (m['status'] ?? 'not_started').toString(),
        priority: (m['priority'] ?? 'normal').toString(),
        responsibleId: m['responsible_id']?.toString(),
        followerId: m['follower_id']?.toString(),
        createdBy: m['created_by']?.toString(),
        messageId: m['message_id']?.toString(),
        deadline: _date(m['deadline']),
        evidenceRequired: _bool(m['evidence_required']),
        managerConfirmationRequired: _bool(m['manager_confirmation_required'], true),
        managerConfirmed: _bool(m['manager_confirmed']),
        managerConfirmedBy: m['manager_confirmed_by']?.toString(),
        managerConfirmedAt: _date(m['manager_confirmed_at']),
        score: _int(m['score']),
        evalComment: m['eval_comment']?.toString(),
        completionRequestedAt: _date(m['completion_requested_at']),
        completionProofNote: m['completion_proof_note']?.toString(),
        followerReviewedAt: _date(m['follower_reviewed_at']),
        followerReviewedBy: m['follower_reviewed_by']?.toString(),
        completedAt: _date(m['completed_at']),
        completedBy: m['completed_by']?.toString(),
        reopenedAt: _date(m['reopened_at']),
        reopenedBy: m['reopened_by']?.toString(),
        createdAt: _date(m['created_at']),
        updatedAt: _date(m['updated_at']),
        totalQuantity: _num(m['total_quantity']),
        quantityUnit: m['quantity_unit']?.toString(),
        deletedAt: _date(m['deleted_at']),
        deletedBy: m['deleted_by']?.toString(),
      );
}

class TaskStage {
  final String id;
  final String taskId;
  final String title;
  final DateTime deadline;
  final double? targetQuantity;
  final String? quantityUnit;
  final int sortOrder;
  final String? createdBy;
  final String creatorName;
  final String? creatorAvatarUrl;
  final DateTime? createdAt;

  const TaskStage({
    required this.id,
    required this.taskId,
    required this.title,
    required this.deadline,
    this.targetQuantity,
    this.quantityUnit,
    this.sortOrder = 1,
    this.createdBy,
    this.creatorName = 'User',
    this.creatorAvatarUrl,
    this.createdAt,
  });

  factory TaskStage.fromMap(Map<String, dynamic> m) {
    final creator = m['creator'];
    return TaskStage(
        id: m['id'].toString(),
        taskId: m['task_id'].toString(),
        title: (m['title'] ?? '').toString(),
        deadline: _date(m['deadline']) ?? DateTime.now(),
        targetQuantity: _num(m['target_quantity']),
        quantityUnit: m['quantity_unit']?.toString(),
        sortOrder: _int(m['sort_order']) ?? 1,
        createdBy: m['created_by']?.toString(),
        creatorName: creator is Map ? (creator['full_name'] ?? 'User').toString() : 'User',
        creatorAvatarUrl: creator is Map ? creator['avatar_url']?.toString() : null,
        createdAt: _date(m['created_at']),
      );
  }
}

class TaskDailyUpdate {
  final String id;
  final String taskId;
  final String? stageId;
  final DateTime workDate;
  final double? quantityDone;
  final String? workNote;
  final String? createdBy;
  final String creatorName;
  final String? creatorAvatarUrl;
  final DateTime? createdAt;

  const TaskDailyUpdate({
    required this.id,
    required this.taskId,
    this.stageId,
    required this.workDate,
    required this.quantityDone,
    this.workNote,
    this.createdBy,
    required this.creatorName,
    this.creatorAvatarUrl,
    this.createdAt,
  });

  factory TaskDailyUpdate.fromMap(Map<String, dynamic> m) {
    final creator = m['creator'];
    return TaskDailyUpdate(
      id: m['id'].toString(),
      taskId: m['task_id'].toString(),
      stageId: m['stage_id']?.toString(),
      workDate: _date(m['work_date']) ?? DateTime.now(),
      quantityDone: _num(m['quantity_done']),
      workNote: m['work_note']?.toString(),
      createdBy: m['created_by']?.toString(),
      creatorName: creator is Map ? (creator['full_name'] ?? 'User').toString() : 'User',
      creatorAvatarUrl: creator is Map ? creator['avatar_url']?.toString() : null,
      createdAt: _date(m['created_at']),
    );
  }
}


class TaskFollowerNote {
  final String id;
  final String taskId;
  final String createdBy;
  final String creatorName;
  final String? creatorAvatarUrl;
  final String note;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const TaskFollowerNote({
    required this.id,
    required this.taskId,
    required this.createdBy,
    required this.creatorName,
    this.creatorAvatarUrl,
    required this.note,
    required this.createdAt,
    this.updatedAt,
  });

  factory TaskFollowerNote.fromMap(Map<String, dynamic> m) {
    final creator = m['creator'];
    return TaskFollowerNote(
      id: m['id'].toString(),
      taskId: m['task_id'].toString(),
      createdBy: m['created_by'].toString(),
      creatorName: creator is Map ? (creator['full_name'] ?? 'User').toString() : 'User',
      creatorAvatarUrl: creator is Map ? creator['avatar_url']?.toString() : null,
      note: (m['note'] ?? '').toString(),
      createdAt: _date(m['created_at']) ?? DateTime.now(),
      updatedAt: _date(m['updated_at']),
    );
  }
}

class TaskComment {
  final String id;
  final String taskId;
  final String content;
  final String? createdBy;
  final String creatorName;
  final String? creatorAvatarUrl;
  final DateTime createdAt;

  const TaskComment({
    required this.id,
    required this.taskId,
    required this.content,
    this.createdBy,
    required this.creatorName,
    this.creatorAvatarUrl,
    required this.createdAt,
  });
}

class MessageItem {
  final String id;
  final String code;
  final String content;
  final String messageType;
  final String audienceType;
  final String? createdBy;
  final String senderName;
  final String? senderAvatarUrl;
  final String? taskId;
  final DateTime createdAt;
  final int recipientCount;
  final int seenCount;
  final bool seenByMe;

  const MessageItem({
    required this.id,
    required this.code,
    required this.content,
    required this.messageType,
    required this.audienceType,
    this.createdBy,
    required this.senderName,
    this.senderAvatarUrl,
    this.taskId,
    required this.createdAt,
    required this.recipientCount,
    required this.seenCount,
    required this.seenByMe,
  });

  factory MessageItem.fromMap(Map<String, dynamic> m) => MessageItem(
        id: m['id'].toString(),
        code: (m['code'] ?? '').toString(),
        content: (m['content'] ?? '').toString(),
        messageType: (m['message_type'] ?? 'information').toString(),
        audienceType: (m['audience_type'] ?? 'everyone').toString(),
        createdBy: m['created_by']?.toString(),
        senderName: (m['sender_name'] ?? 'User').toString(),
        senderAvatarUrl: m['sender_avatar_url']?.toString(),
        taskId: m['task_id']?.toString(),
        createdAt: _date(m['created_at']) ?? DateTime.now(),
        recipientCount: _int(m['recipient_count']) ?? 0,
        seenCount: _int(m['seen_count']) ?? 0,
        seenByMe: _bool(m['seen_by_me']),
      );
}

class MessageComment {
  final String id;
  final String messageId;
  final String content;
  final String? createdBy;
  final String creatorName;
  final String? creatorAvatarUrl;
  final DateTime createdAt;

  const MessageComment({
    required this.id,
    required this.messageId,
    required this.content,
    this.createdBy,
    required this.creatorName,
    this.creatorAvatarUrl,
    required this.createdAt,
  });
}

class NotificationItem {
  final String id;
  final String type;
  final String title;
  final String body;
  final String? targetType;
  final String? targetId;
  final bool isRead;
  final DateTime createdAt;
  final String? actorId;
  final String actorName;
  final String? actorAvatarUrl;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.targetType,
    this.targetId,
    required this.isRead,
    required this.createdAt,
    this.actorId,
    this.actorName = 'System',
    this.actorAvatarUrl,
  });

  factory NotificationItem.fromMap(Map<String, dynamic> m) => NotificationItem(
        id: m['id'].toString(),
        type: (m['type'] ?? 'system').toString(),
        title: (m['title'] ?? '').toString(),
        body: (m['body'] ?? '').toString(),
        targetType: m['target_type']?.toString(),
        targetId: m['target_id']?.toString(),
        isRead: _bool(m['is_read']),
        createdAt: _date(m['created_at']) ?? DateTime.now(),
        actorId: m['actor_id']?.toString(),
        actorName: m['actor'] is Map ? (m['actor']['full_name'] ?? 'System').toString() : 'System',
        actorAvatarUrl: m['actor'] is Map ? m['actor']['avatar_url']?.toString() : null,
      );
}

class DashboardStats {
  final int myTasks;
  final int teamTasks;
  final int overdueTasks;
  final int readyTasks;
  final int unreadMessages;
  final int unreadNotifications;

  const DashboardStats({
    required this.myTasks,
    required this.teamTasks,
    required this.overdueTasks,
    required this.readyTasks,
    required this.unreadMessages,
    required this.unreadNotifications,
  });
}


class AttachmentItem {
  final String id;
  final String? taskId;
  final String? messageId;
  final String? dailyUpdateId;
  final String? messageCommentId;
  final bool isCompletionProof;
  final String fileName;
  final String storagePath;
  final String? mimeType;
  final int? fileSize;
  final String? uploadedBy;
  final String uploaderName;
  final String? uploaderAvatarUrl;
  final DateTime? createdAt;

  const AttachmentItem({
    required this.id,
    this.taskId,
    this.messageId,
    this.dailyUpdateId,
    this.messageCommentId,
    this.isCompletionProof = false,
    required this.fileName,
    required this.storagePath,
    this.mimeType,
    this.fileSize,
    this.uploadedBy,
    this.uploaderName = 'User',
    this.uploaderAvatarUrl,
    this.createdAt,
  });

  factory AttachmentItem.fromMap(Map<String, dynamic> m) {
    final uploader = m['uploader'];
    return AttachmentItem(
      id: m['id'].toString(),
      taskId: m['task_id']?.toString(),
      messageId: m['message_id']?.toString(),
      dailyUpdateId: m['daily_update_id']?.toString(),
      messageCommentId: m['message_comment_id']?.toString(),
      isCompletionProof: _bool(m['is_completion_proof']),
      fileName: (m['file_name'] ?? '').toString(),
      storagePath: (m['storage_path'] ?? '').toString(),
      mimeType: m['mime_type']?.toString(),
      fileSize: _int(m['file_size']),
      uploadedBy: m['uploaded_by']?.toString(),
      uploaderName: uploader is Map ? (uploader['full_name'] ?? 'User').toString() : 'User',
      uploaderAvatarUrl: uploader is Map ? uploader['avatar_url']?.toString() : null,
      createdAt: _date(m['created_at']),
    );
  }
}

class UserPermission {
  final String userId;
  final String permissionKey;
  final bool enabled;

  const UserPermission({required this.userId, required this.permissionKey, required this.enabled});

  factory UserPermission.fromMap(Map<String, dynamic> m) => UserPermission(
    userId: m['user_id'].toString(),
    permissionKey: (m['permission_key'] ?? '').toString(),
    enabled: _bool(m['enabled']),
  );
}
