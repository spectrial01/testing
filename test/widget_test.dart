import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:project_nexus/main.dart';
import 'package:project_nexus/ui/services/theme_provider.dart';
import 'package:project_nexus/screens/splash_screen.dart';
import 'package:project_nexus/utils/constants.dart';

void main() {
  group('Project Nexus App Tests', () {
    testWidgets('App starts with splash screen', (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (context) => ThemeProvider(),
          child: const MyApp(),
        ),
      );

      // Verify that splash screen is displayed
      expect(find.byType(SplashScreen), findsOneWidget);
    });

    testWidgets('Theme provider works correctly', (WidgetTester tester) async {
      final themeProvider = ThemeProvider();
      
      // Test initial theme mode
      expect(themeProvider.themeMode, ThemeMode.system);
      expect(themeProvider.isDarkMode, false);
      
      // Test theme toggle
      await themeProvider.toggleTheme();
      expect(themeProvider.isDarkMode, true);
      expect(themeProvider.themeMode, ThemeMode.dark);
    });

    testWidgets('App constants are properly defined', (WidgetTester tester) async {
      // Test that app constants are accessible
      expect(AppConstants.appTitle, isNotEmpty);
      expect(AppConstants.appMotto, isNotEmpty);
      expect(AppConstants.baseUrl, isNotEmpty);
    });

    testWidgets('Signal status helper works correctly', (WidgetTester tester) async {
      // Test signal status color mapping
      expect(SignalStatus.getColor(SignalStatus.strong), Colors.green);
      expect(SignalStatus.getColor(SignalStatus.weak), Colors.orange);
      expect(SignalStatus.getColor(SignalStatus.poor), Colors.red);
      
      // Test signal status values
      expect(SignalStatus.allValues, contains(SignalStatus.strong));
      expect(SignalStatus.allValues, contains(SignalStatus.weak));
      expect(SignalStatus.allValues, contains(SignalStatus.poor));
    });
  });
}
