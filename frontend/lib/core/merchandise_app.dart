part of '../main.dart';

class MerchandiseApp extends StatelessWidget {
  const MerchandiseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mandai Merchandise • Assessment',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F8F6),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF146C55),
            primary: const Color(0xFF146C55),
            secondary: const Color(0xFFB47B3D),
            surface: Colors.white,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF5F8F6),
            foregroundColor: Color(0xFF173B33),
            elevation: 0,
            centerTitle: false,
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFFE3EBE6))),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF8FAF9),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFDCE7E1))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: Color(0xFF146C55), width: 1.7)),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
        home: MandaiSplashGate(
            builder: (onLandingReady) =>
                Shell(onInitialLandingReady: onLandingReady)),
      );
}
