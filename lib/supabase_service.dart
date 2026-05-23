import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  SupabaseClient get client => _client;

  Future<Map<String, dynamic>?> loginUser({
    required String email,
    required String sifre,
  }) async {
    try {
      final response = await _client
          .from('users')
          .select()
          .eq('email', email)
          .eq('sifre', sifre)
          .maybeSingle();

      if (response == null) return null;
      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (e) {
      throw Exception('Giriş hatası: ${e.message}');
    } catch (e) {
      throw Exception('Beklenmeyen hata: $e');
    }
  }

  Future<Map<String, dynamic>> registerUser({
    required String ad,
    required String soyad,
    required String tcKimlik,
    required String telefon,
    required String sehir,
    required String email,
    required String username,
    required String sifre,
    String rol = 'kullanici',
    String? avatarUrl,
  }) async {
    try {
      final existingUsername = await _client
          .from('users')
          .select('id')
          .eq('username', username)
          .maybeSingle();

      if (existingUsername != null) {
        throw Exception('Bu kullanıcı adı zaten kullanılıyor.');
      }

      final existingTc = await _client
          .from('users')
          .select('id')
          .eq('tc_kimlik', tcKimlik)
          .maybeSingle();

      if (existingTc != null) {
        throw Exception('Bu TC Kimlik ile zaten kayıt var.');
      }

      final existingEmail = await _client
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (existingEmail != null) {
        throw Exception('Bu e-posta adresi zaten kayıtlı.');
      }

      final response = await _client
          .from('users')
          .insert({
            'username': username,
            'email': email,
            'sifre': sifre,
            'ad': ad,
            'soyad': soyad,
            'tc_kimlik': tcKimlik,
            'telefon': telefon,
            'sehir': sehir,
            'rol': rol,
            'avatar_url': avatarUrl,
          })
          .select()
          .single();

      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (e) {
      final errorText = '${e.message} ${e.details ?? ''}'.toLowerCase();

      if (errorText.contains('username')) {
        throw Exception('Bu kullanıcı adı zaten kullanılıyor.');
      }
      if (errorText.contains('tc_kimlik')) {
        throw Exception('Bu TC Kimlik ile zaten kayıt var.');
      }
      if (errorText.contains('email')) {
        throw Exception('Bu e-posta adresi zaten kayıtlı.');
      }

      throw Exception('Kayıt hatası: ${e.message}');
    } catch (e) {
      rethrow;
    }
  }
}
