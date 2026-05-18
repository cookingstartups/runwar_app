import 'dart:convert';
import 'package:http/http.dart' as http;

const _baseUrl = 'https://runwarlanding.vercel.app';

class WaitlistResult {
  final bool ok;
  final String message;
  const WaitlistResult({required this.ok, required this.message});
}

class WaitlistService {
  static Future<WaitlistResult> joinWaitlist({
    required String email,
    required String phone,
    required String city,
    String? instagram,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/waitlist'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'phone': phone,
              'city': city,
              if (instagram != null && instagram.isNotEmpty)
                'instagram': instagram,
            }),
          )
          .timeout(const Duration(seconds: 12));

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return WaitlistResult(
        ok: body['ok'] == true,
        message: body['message'] as String? ?? 'Unknown error',
      );
    } catch (_) {
      return const WaitlistResult(ok: false, message: 'Connection error. Try again.');
    }
  }

  static Future<List<String>> searchCities(String query) async {
    if (query.length < 2) return [];
    try {
      final res = await http
          .get(
            Uri.parse('$_baseUrl/api/cities?q=${Uri.encodeQueryComponent(query)}'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.cast<String>();
    } catch (_) {
      return [];
    }
  }
}
