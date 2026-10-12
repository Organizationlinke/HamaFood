// export 'attachment_opener_stub.dart'
//     if (dart.library.html) 'attachment_opener_web.dart';
// lib/services/attachment_opener.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// دالة موحدة لفتح ومعاينة المرفقات من داخل التطبيق
Future<bool> openAttachment(BuildContext context, String fileName, Future<String> Function() fetchUrl) async {
  await showDialog(
    context: context,
    builder: (context) => _AttachmentPreviewDialog(
      fileName: fileName,
      fetchUrl: fetchUrl,
    ),
  );
  return true; 
}

class _AttachmentPreviewDialog extends StatefulWidget {
  final String fileName;
  final Future<String> Function() fetchUrl;

  const _AttachmentPreviewDialog({
    Key? key,
    required this.fileName,
    required this.fetchUrl,
  }) : super(key: key);

  @override
  State<_AttachmentPreviewDialog> createState() => _AttachmentPreviewDialogState();
}

class _AttachmentPreviewDialogState extends State<_AttachmentPreviewDialog> {
  String? _url;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  // جلب الرابط أثناء عرض الـ Loading في النافذة
  Future<void> _loadUrl() async {
    try {
      final url = await widget.fetchUrl();
      if (mounted) {
        setState(() {
          _url = url;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'حدث خطأ أثناء جلب الرابط';
          _isLoading = false;
        });
      }
    }
  }

  // للتحقق مما إذا كان المرفق صورة لكي نعرضها
  bool _isImage(String name) {
    final ext = name.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
  }

  // زر التنزيل / الفتح
  void _downloadOrOpen() async {
    if (_url == null) return;
    final uri = Uri.parse(_url!);
    try {
      // بما أن الرابط جاهز، المتصفح سيسمح بالفتح فوراً لأنه استجابة لضغطة مباشرة
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح الملف')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isImg = _isImage(widget.fileName);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 400, // أقصى عرض للنافذة لتكون متناسقة على الكمبيوتر والموبايل
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // الشريط العلوي (عنوان واسم المرفق)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).primaryColor,
              child: Row(
                children: [
                  const Icon(Icons.attachment, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.fileName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            // منطقة عرض المرفق
            Container(
              padding: const EdgeInsets.all(24),
              constraints: const BoxConstraints(minHeight: 150, maxHeight: 400),
              child: Center(
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : _error != null
                        ? Text(_error!, style: const TextStyle(color: Colors.red))
                        : isImg
                            ? Image.network(
                                _url!,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => 
                                    const Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.broken_image, size: 64, color: Colors.grey),
                                        SizedBox(height: 8),
                                        Text('معاينة غير متاحة', style: TextStyle(color: Colors.grey)),
                                      ],
                                    ),
                              )
                            : const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.insert_drive_file, size: 80, color: Colors.grey),
                                  SizedBox(height: 16),
                                  Text('هذا الملف غير مدعوم للمعاينة المباشرة', style: TextStyle(color: Colors.grey)),
                                ],
                              ),
              ),
            ),
            
            // زر التنزيل
            if (!_isLoading && _error == null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: _downloadOrOpen,
                  icon: const Icon(Icons.download),
                  label: const Text('تنزيل / فتح الملف'),
                  style: ElevatedButton.styleFrom(
                    // minimumSize: const Size.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}