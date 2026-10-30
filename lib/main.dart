import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Parallel load scripts and stylesheets before rendering
  final scripts = await Future.wait([
    rootBundle.loadString('assets/scripts/pure_adblock.js'),
    rootBundle.loadString('assets/styles/pure_clean.css'),
  ]);
  final ytJs = scripts[0];
  final ytCss = scripts[1];

  // Pure Dark OLED System Overlay Style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0F0F0F),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(PureTubeApp(ytJsCode: ytJs, ytCssCode: ytCss));
}

class PureTubeApp extends StatelessWidget {
  final String ytJsCode;
  final String ytCssCode;

  const PureTubeApp({
    super.key,
    required this.ytJsCode,
    required this.ytCssCode,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PureTube',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: const ColorScheme.dark(
          primary: Colors.redAccent,
          surface: Color(0xFF1E1E1E),
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(ytJsCode: ytJsCode, ytCssCode: ytCssCode),
    );
  }
}
