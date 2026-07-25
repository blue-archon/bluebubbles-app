import 'dart:convert';

/// Recursively rebuilds platform-channel / Gson maps into plain Dart JSON maps.
///
/// Each map value is read through a guarded lookup: a socket/method-channel
/// payload can arrive as a `CastMap<String, Object>` (from `.cast<String, Object>()`
/// on a decoded payload) whose entry access re-casts every value to the
/// non-nullable `Object` and throws on a genuinely-null field, which would
/// otherwise abort the parse and drop the whole chat/attachment. Strings are
/// returned untouched — a value that is itself a JSON-encoded string is decoded
/// by its own field's fromMap, not blindly here (doing so would corrupt numeric
/// message text like "1234" into an int). Single pass, no jsonEncode round-trip.
dynamic deepNormalizeJson(dynamic raw) {
  if (raw is Map) {
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
    // The method channel can hand us the payload as a top-level JSON string.
    // deepNormalizeJson no longer decodes strings itself, so decode here, the one
    // entry point where a JSON-encoded string is genuinely expected.
    if (raw is String) raw = jsonDecode(raw);
    final normalized = deepNormalizeJson(raw);
    if (normalized is Map<String, dynamic>) return normalized;
    if (normalized is Map) return Map<String, dynamic>.from(normalized);
  } catch (_) {}

  return null;
}
