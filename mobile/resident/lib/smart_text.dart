// SmartSumbong — what SMART's pick says, in the reader's language (0140).
//
// The database saves the reasons for a pick as short English phrases
// ("330 m away", "1 job(s) in hand"). The tanod's "Why you" card shows them,
// so they are put into Filipino here when the app is. Pure functions: the
// widgets pass whether the language is Filipino.

/// One reason, say in Filipino when [fil]. Anything not recognised is shown as it came.
String smartReasonText(String detail, {required bool fil}) {
  final d = detail.trim();
  final m = RegExp(r'^(\d+) m away$').firstMatch(d);
  if (m != null) return fil ? '${m[1]} m ang layo' : d;
  final j = RegExp(r'^(\d+) job\(s\) in hand$').firstMatch(d);
  if (j != null) return fil ? '${j[1]} gawain ang hawak' : '${j[1]} job(s) in hand';
  final c = RegExp(r'^(\d+) case\(s\) closed within 300 m, last 90 days$').firstMatch(d);
  if (c != null) return fil ? '${c[1]} kaso ang naresolba sa loob ng 300 m (90 araw)' : d;
  if (d == 'no location yet') return fil ? 'wala pang lokasyon' : d;
  return d;
}

/// The reasons worth showing a tanod: distance, workload, knowing the area. (The age of
/// their own location reading is left out: it is theirs to know.)
List<String> smartPickLines(Object? reasons, {required bool fil}) {
  if (reasons is! List) return const [];
  const shown = {'distance', 'workload', 'knows the area'};
  return [
    for (final r in reasons)
      if (r is Map && shown.contains(r['factor']) && (r['detail'] as String?)?.isNotEmpty == true)
        smartReasonText(r['detail'] as String, fil: fil),
  ];
}

/// "SMART's first choice" or "SMART ranked you #2 of 4".
String smartPickTitle(int rank, int? of, {required bool fil}) {
  if (rank == 1) return fil ? 'Ikaw ang unang pinili ng SMART.' : "You were SMART's first choice.";
  final total = of == null ? '' : (fil ? ' sa $of' : ' of $of');
  return fil ? 'Nasa #$rank$total ang ranggo mo sa SMART.' : 'SMART ranked you #$rank$total.';
}
