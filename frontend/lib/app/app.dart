import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/network/api_client.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/products/data/product_repository.dart';
import '../features/products/bloc/product_bloc.dart';
import '../features/purchases/data/purchase_repository.dart';
import '../features/purchases/bloc/purchase_bloc.dart';
import 'shell.dart';

class MerchandiseApp extends StatefulWidget {
  const MerchandiseApp({super.key});
  @override
  State<MerchandiseApp> createState() => _MerchandiseAppState();
}

class _MerchandiseAppState extends State<MerchandiseApp> {
  late final ApiClient api = ApiClient();
  late final AuthRepository auth = AuthRepository(api);
  late final ProductRepository products = ProductRepository(api);
  late final PurchaseRepository purchases = PurchaseRepository(api);
  @override
  void dispose() {
    api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiRepositoryProvider(
          providers: [
            RepositoryProvider<AuthRepository>.value(value: auth),
            RepositoryProvider<ProductRepository>.value(value: products),
            RepositoryProvider<PurchaseRepository>.value(value: purchases),
          ],
          child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthBloc>(
                    create: (context) =>
                        AuthBloc(context.read<AuthRepository>())),
                BlocProvider<ProductBloc>(
                    create: (context) =>
                        ProductBloc(context.read<ProductRepository>())),
                BlocProvider<PurchaseBloc>(
                    create: (context) =>
                        PurchaseBloc(context.read<PurchaseRepository>())),
              ],
              child: MaterialApp(
                  title: 'Mandai Merchandise • Assessment',
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(
                    useMaterial3: true,
                    scaffoldBackgroundColor: const Color(0xFFF5F8F6),
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: const Color(0xFF146C55),
                        primary: const Color(0xFF146C55),
                        secondary: const Color(0xFFB47B3D),
                        surface: Colors.white),
                    appBarTheme: const AppBarTheme(
                        backgroundColor: Color(0xFFF5F8F6),
                        foregroundColor: Color(0xFF173B33),
                        elevation: 0),
                    cardTheme: CardThemeData(
                        color: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: const BorderSide(color: Color(0xFFE3EBE6)))),
                    inputDecorationTheme: InputDecorationTheme(
                        filled: true,
                        fillColor: const Color(0xFFF8FAF9),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14))),
                    filledButtonTheme: FilledButtonThemeData(
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)))),
                  ),
                  home: const AppShell())));
}
