import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hama_work/widgets/common.dart';
import '../providers/providers.dart';
import '../services/localization.dart';
import '../theme.dart';
import '../widgets/app_scaffold.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool busy = false;

  Future<void> _set(WidgetRef ref, String? code) async {
    if (code == null) return;
    await ref.read(repoProvider).setPreferredLanguage(code);
    AppI18n.setLocale(Locale(code));
    ref.read(languageProvider.notifier).state = Locale(code);
    ref.invalidate(profileProvider);
  }

  Future<void> _changePassword() async {
    final a = TextEditingController();
    final b = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Change password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: a, obscureText: true, decoration: InputDecoration(labelText: tr('New password'))),
          const SizedBox(height: 10),
          TextField(controller: b, obscureText: true, decoration: InputDecoration(labelText: tr('Confirm password'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Save')),
        ],
      ),
    );
    if (ok != true) { a.dispose(); b.dispose(); return; }
    if (a.text.length < 6 || a.text != b.text) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Password must be at least 6 characters and both passwords must match'))));
      a.dispose(); b.dispose(); return;
    }
    try {
      await ref.read(repoProvider).changeMyPassword(a.text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Password changed successfully'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    a.dispose(); b.dispose();
  }

  Future<void> _uploadAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (result == null || result.files.single.bytes == null) return;
      setState(() => busy = true);
      final name = result.files.single.name.toLowerCase();
      final ext = name.contains('.') ? name.split('.').last : 'jpg';
      await ref.read(repoProvider).uploadAvatar(result.files.single.bytes!, ext);
      ref.invalidate(profileProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Profile photo updated successfully'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(languageProvider).languageCode;
    final profile = ref.watch(profileProvider).valueOrNull;
    return AppScaffold(
      title: 'Settings',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const HamaSectionHeader(title: 'Settings', subtitle: 'Personalize your Hama Work experience', icon: Icons.tune_rounded),
          const SizedBox(height: 14),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            profile == null ? const SizedBox() : UserAvatar(user: profile, radius: 34),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(profile?.fullName ?? '', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), Text('@${profile?.username ?? ''}'), const SizedBox(height: 8), OutlinedButton.icon(onPressed: busy ? null : _uploadAvatar, icon: const Icon(Icons.photo_camera_rounded), label: T(busy ? 'Uploading...' : 'Change profile photo'))])),
          ]))),
          const SizedBox(height: 14),
          Card(child: Padding(padding: const EdgeInsets.all(8), child: Column(children: [
            const ListTile(leading: Icon(Icons.language_rounded, color: HamaColors.teal), title: T('Language'), subtitle: T('Choose language')),
            RadioListTile(value: 'ar', groupValue: current, title: const T('Arabic'), secondary: const Icon(Icons.translate_rounded), onChanged: (v) => _set(ref, v)),
            RadioListTile(value: 'en', groupValue: current, title: const T('English'), secondary: const Icon(Icons.language_rounded), onChanged: (v) => _set(ref, v)),
          ]))),
          const SizedBox(height: 14),
          Card(child: ListTile(leading: const Icon(Icons.lock_reset_rounded, color: HamaColors.orange), title: const T('Change password'), subtitle: const T('Change your own password'), onTap: _changePassword)),
          const SizedBox(height: 14),
          Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(gradient: const LinearGradient(colors: [HamaColors.navy, HamaColors.navy2]), borderRadius: BorderRadius.circular(18)), child: const Row(children: [HamaMark(size: 44), SizedBox(width: 12), Expanded(child: Text('Hama Work', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)))])),
        ],
      ),
    );
  }
}
