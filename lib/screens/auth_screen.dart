import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../services/localization.dart';
import '../theme.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final username = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool obscure = true;
  String? error;

  @override
  void dispose() { username.dispose(); password.dispose(); super.dispose(); }

  Future<void> submit() async {
    if (username.text.trim().isEmpty || password.text.isEmpty) { setState(() => error = tr('Could not sign in')); return; }
    setState(() { busy = true; error = null; });
    try {
      await ref.read(repoProvider).loginWithUsername(username: username.text, password: password.text);
      ref.invalidate(profileProvider);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> chooseLanguage() async {
    final current = ref.read(languageProvider).languageCode;
    final picked = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Choose language'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          RadioListTile(value: 'ar', groupValue: current, title: const T('Arabic'), onChanged: (v) => Navigator.pop(c, v)),
          RadioListTile(value: 'en', groupValue: current, title: const T('English'), onChanged: (v) => Navigator.pop(c, v)),
        ]),
      ),
    );
    if (picked != null) { AppI18n.setLocale(Locale(picked)); ref.read(languageProvider.notifier).state = Locale(picked); setState(() {}); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF071126), HamaColors.navy2, Color(0xFF0B8F8F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470),
              child: Card(
                elevation: 0,
                color: Colors.white.withOpacity(.98),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(30, 22, 30, 30),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Align(alignment: AlignmentDirectional.topEnd, child: IconButton(onPressed: chooseLanguage, icon: const Icon(Icons.language_rounded))),
                    const HamaMark(size: 72),
                    const SizedBox(height: 16),
                    const Text('HF Team', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: HamaColors.navy)),
                    const SizedBox(height: 6),
                    const T('Internal Work & Communication', style: TextStyle(color: HamaColors.muted)),
                    const SizedBox(height: 30),
                    TextField(controller: username, decoration: InputDecoration(labelText: tr('Username'), prefixIcon: const Icon(Icons.person_outline_rounded)), textInputAction: TextInputAction.next),
                    const SizedBox(height: 14),
                    TextField(controller: password, obscureText: obscure, decoration: InputDecoration(labelText: tr('Password'), prefixIcon: const Icon(Icons.lock_outline_rounded), suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined))), onSubmitted: (_) => submit()),
                    if (error != null) ...[const SizedBox(height: 14), Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: HamaColors.red.withOpacity(.07), borderRadius: BorderRadius.circular(12)), child: Text(error!, style: const TextStyle(color: HamaColors.red), textAlign: TextAlign.center))],
                    const SizedBox(height: 22),
                    SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: busy ? null : submit, icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.login_rounded), label: T(busy ? 'Signing in...' : 'Sign in', style: const TextStyle(fontWeight: FontWeight.w800)))),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
