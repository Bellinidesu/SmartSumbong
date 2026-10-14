// A tanod's dispatch, on the real screens over the preview backend.
import 'package:flutter_test/flutter_test.dart';
import 'support/app_harness.dart';

void main() {
  testWidgets('a tanod opens an incoming dispatch and accepts it', (tester) async {
    final backend = await bootApp(tester, role: 'tanod');
    expect(find.text('INCOMING DISPATCH'), findsOneWidget);
    await tester.tap(find.text('View Details'));
    await settle(tester);
    for (final expected in ['DISPATCH ORDER', 'Clogged Drainage', 'Complainant: Anonymous', 'Admin Directives:', 'Reroute', 'Accept']) {
      expect(screenText().any((t) => t.contains(expected)), isTrue, reason: expected);
    }
    await tester.ensureVisible(find.text('Accept'));
    await tester.tap(find.text('Accept'));
    await settle(tester);
    expect(find.text('Dispatch accepted'), findsOneWidget);
    expect(find.text("I'm on the way"), findsOneWidget);
    expect(backend.calls.where((c) => c == 'rpc accept_dispatch'), isNotEmpty);
    await finish(tester);
  });
}
