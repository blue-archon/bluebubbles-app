import 'dart:convert';

/// Recursively converts platform-channel / Gson maps into plain Dart JSON maps.
dynamic deepNormalizeJson(dynamic raw) {
  if (raw == null) return null;

  if (raw is String) {
    try {
      return deepNormalizeJson(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }

  if (raw is Map || raw is List) {
    try {
      return jsonDecode(jsonEncode(raw));
    } catch (_) {
      if (raw is Map) {
        // Rebuild key-by-key. `raw` may be a CastMap<String, Object> (produced by
        // `.cast<String, Object>()` on a JSON-decoded socket/method-channel payload):
        // iterating its entries — or the jsonEncode above — casts each value to the
        // non-nullable Object, which throws on a genuinely-null field before we ever
        // reach the recursive normalize. Read each value through a guarded lookup so
        // a single null can't abort the whole parse (dropping the chat/attachment).
        final result = <String, dynamic>{};
        for (final key in raw.keys) {
          dynamic value;
          try {
            value = raw[key];
          } catch (_) {
            value = null;
          }
          result[key.toString()] = deepNormalizeJson(value);
        }
        return result;
      }
      if (raw is List) {
        return raw.map(deepNormalizeJson).toList();
      }
    }
  }

  return raw;
}

Map<String, dynamic>? asStringDynamicMap(dynamic raw) {
  if (raw == null) return null;
  final normalized = deepNormalizeJson(raw);
  if (normalized is Map<String, dynamic>) return normalized;
  if (normalized is Map) return Map<String, dynamic>.from(normalized);
  return null;
}

Map<String, dynamic> asStringDynamicMapRequired(dynamic raw) {
  final map = asStringDynamicMap(raw);
  if (map != null) return map;
  throw FormatException('Expected Map<String, dynamic>, got ${raw.runtimeType}');
}

Map<String, dynamic>? normalizeMethodChannelArguments(dynamic raw) {
  if (raw == null) return null;

  try {
    final normalized = deepNormalizeJson(raw);
    if (normalized is Map<String, dynamic>) return normalized;
    if (normalized is Map) return Map<String, dynamic>.from(normalized);
  } catch (_) {}

  return null;
}