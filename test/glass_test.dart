import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnilink/ui/glass.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'painel de vidro ${brightness.name} respeita largura de celular e texto ampliado',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: omniTheme(brightness),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
                child: const Padding(
                  padding: EdgeInsets.all(24),
                  child: Glass(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Nenhum dispositivo pareado.'),
                        SizedBox(height: 20),
                        Text(
                          'Abra o OmniLink nos dois aparelhos e crie um convite.',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Nenhum dispositivo pareado.'), findsOneWidget);
      },
    );
  }
}
