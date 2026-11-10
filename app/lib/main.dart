import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'screens/home_shell.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'it_IT';
  await initializeDateFormatting('it');
  await initializeDateFormatting('it_IT');
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: C.surface,
  ));
  final store = AppStore();
  runApp(AppScope(store: store, child: const BetTrackerApp()));
  store.load();
}

class BetTrackerApp extends StatelessWidget {
  const BetTrackerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Bet Tracker',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('it', 'IT'),
        supportedLocales: const [Locale('it', 'IT')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomeShell(),
      );
}
