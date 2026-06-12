import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const _url = 'https://dgquwkdzmufnrnwquvci.supabase.co';
  static const _anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRncXV3a2R6bXVmbnJud3F1dmNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEyMjcxMDQsImV4cCI6MjA5NjgwMzEwNH0.GYV7WyfBYLhKk0TpASOP5mff2UnsDkHJm9nAoTwu2Y8';

  static Future<void> initialize() async {
    await Supabase.initialize(url: _url, anonKey: _anonKey);
  }
}
