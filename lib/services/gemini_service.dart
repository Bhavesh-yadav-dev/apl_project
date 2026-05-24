import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Calls Gemini 2.0 Flash (imagen via generateContent) to produce a
/// personalised IPL fan avatar image.
///
/// Returns the base64-encoded PNG bytes, or null on failure.
class GeminiService {
  // ── PASTE YOUR KEY HERE ──────────────────────────────────────────────────
  static const _apiKey = 'AIzaSyAqC0FIeQilF_ZSg2jHh8YgM3f0GM3zR3I';
  // ────────────────────────────────────────────────────────────────────────

  static const _model = 'gemini-2.0-flash-preview-image-generation';
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  /// Builds a vivid IPL-themed prompt from the fan's profile data and
  /// returns the raw PNG bytes of the generated image, or null on error.
  static Future<Uint8List?> generateFanAvatar({
    required String name,
    required String favouriteTeam,
    required String favouritePlayer,
    required String city,
    required String watchStyle,
    required String matchMood,
  }) async {
    final prompt = '''
Create a vibrant, cinematic IPL 2026 fan avatar illustration.
Fan details:
- Name: $name
- City: $city
- Favourite IPL team: $favouriteTeam
- Favourite player: $favouritePlayer
- How they watch matches: $watchStyle
- Their mood when their team wins: $matchMood

Style: Digital art, stadium atmosphere, team colours of $favouriteTeam dominating the palette,
confetti, cricket bat and ball motifs, dramatic lighting, ultra-detailed, 
portrait orientation, no text overlays. The fan should look passionate and joyful.
''';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {'responseModalities': ['TEXT', 'IMAGE']},
    });

    try {
      final response = await http.post(
        Uri.parse('$_endpoint?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final parts = (json['candidates'] as List?)
          ?.firstOrNull?['content']?['parts'] as List?;
      if (parts == null) return null;

      for (final part in parts) {
        final inlineData = part['inlineData'];
        if (inlineData != null) {
          final b64 = inlineData['data'] as String?;
          if (b64 != null) return base64Decode(b64);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
