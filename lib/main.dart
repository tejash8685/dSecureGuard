import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_brand.dart';
import 'auth_session.dart';
import 'login_page.dart';
import 'management_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xfff6f8f7),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const ActivationApp());
}

class ActivationApp extends StatefulWidget {
  const ActivationApp({super.key});
  @override
  State<ActivationApp> createState() => _ActivationAppState();
}

class _ActivationAppState extends State<ActivationApp> {
  final session = AuthSession();
  @override
  void initState() {
    super.initState();
    session.restore();
  }

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder:
        (context, _) => MaterialApp(
          key: ValueKey(session.signedIn ? session.token : 'signed-out'),
          debugShowCheckedModeBanner: false,
          title: appName,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff216b51),
            ),
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xfff6f8f7),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              backgroundColor: Color(0xfff6f8f7),
              surfaceTintColor: Colors.transparent,
            ),
            cardTheme: CardTheme(
              elevation: 0,
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xffe2e9e5)),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xffcbd8d0)),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            navigationBarTheme: const NavigationBarThemeData(
              backgroundColor: Colors.white,
              elevation: 0,
              height: 76,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            ),
            snackBarTheme: SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            bottomSheetTheme: const BottomSheetThemeData(
              showDragHandle: true,
              backgroundColor: Colors.white,
            ),
          ),
          home:
              !session.ready
                  ? const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  )
                  : session.signedIn
                  ? ManagementPage(
                    key: ValueKey(session.token),
                    session: session,
                  )
                  : LoginPage(session: session),
        ),
  );
}
