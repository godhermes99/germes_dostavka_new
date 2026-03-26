import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const String _url = 'https://ixdjtrixddggmermdbgv.supabase.co';
  static const String _anonKey = 'sb_publishable_4f_gVgFW8hdeiq35yi1u6Q_lw0LOB4F';

  static Future<void> init() async {
    await Supabase.initialize(url: _url, anonKey: _anonKey);
  }

  static SupabaseClient get client => Supabase.instance.client;
}