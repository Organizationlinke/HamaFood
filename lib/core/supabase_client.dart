import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get supabase => Supabase.instance.client;

class AppConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const authDomain = String.fromEnvironment(
    'HAMA_AUTH_DOMAIN',
    defaultValue: 'auth.hamaholding.com',
  );
  static bool get configured => url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;
}
