// How a person's name is written (Ace, 7 Oct 2026), same as the portal:
//   formal (records, profiles, lists, documents)  "Lediac, Ace"  — as stored
//   casual (greetings, bylines, chips)             "Ace Lediac"   — casualName()

/// "Lediac, Ace" -> "Ace Lediac". A name with no comma is returned as is.
String casualName(String? stored) {
  final s = (stored ?? '').trim();
  final c = s.indexOf(',');
  if (c <= 0) return s;
  final first = s.substring(c + 1).trim();
  final last = s.substring(0, c).trim();
  return first.isEmpty ? last : '$first $last';
}

/// [casualName], or null when there is no name to show.
String? casualNameOrNull(String? stored) {
  final n = casualName(stored);
  return n.isEmpty ? null : n;
}
