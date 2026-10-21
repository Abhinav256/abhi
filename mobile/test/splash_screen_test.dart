import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abhi_share/screens/abhishare_splash_animation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AbhiShareSplash Tests', () {
    testWidgets('AbhiShareSplash renders without crashing and invokes onFinished after wait', (tester) async {
      bool finished = false;
      final completer = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: AbhiShareSplash(
            waitFor: completer.future,
            duration: const Duration(milliseconds: 200),
            maxWait: const Duration(milliseconds: 500),
            onFinished: (_) {
              finished = true;
            },
          ),
        ),
      );

      expect(find.byType(AbhiShareSplash), findsOneWidget);
      expect(finished, isFalse);

      // Complete the startup future
      completer.complete();
      await tester.pump();

      // Fast forward past duration and safety maxWait
      await tester.pump(const Duration(milliseconds: 600));

      expect(finished, isTrue);
    });

    testWidgets('AbhiShareSplash renders CustomPaint on very first frame', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AbhiShareSplash(
            duration: const Duration(milliseconds: 200),
            onFinished: (_) {},
          ),
        ),
      );

      // On first frame, CustomPaint should be rendered immediately without waiting
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('fadeReplace replaces current screen smoothly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  fadeReplace(context, const Scaffold(body: Text('Next Screen')));
                },
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Go'), findsOneWidget);
      expect(find.text('Next Screen'), findsNothing);

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Next Screen'), findsOneWidget);
      expect(find.text('Go'), findsNothing);
    });
  });
}
