import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/auth_bloc.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});
  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final email = TextEditingController(text: 'admin@demo.local');
  final password = TextEditingController();
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
      child: SingleChildScrollView(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: BlocBuilder<AuthBloc, AuthState>(
                          builder: (context, state) => Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Icon(Icons.forest_rounded,
                                        size: 42, color: Color(0xFF146C55)),
                                    const SizedBox(height: 14),
                                    const Text('Welcome back',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 24),
                                    TextField(
                                        controller: email,
                                        decoration: const InputDecoration(
                                            labelText: 'Email address',
                                            prefixIcon:
                                                Icon(Icons.mail_outline))),
                                    const SizedBox(height: 12),
                                    TextField(
                                        controller: password,
                                        obscureText: true,
                                        decoration: const InputDecoration(
                                            labelText: 'Password',
                                            prefixIcon:
                                                Icon(Icons.lock_outline))),
                                    const SizedBox(height: 20),
                                    FilledButton(
                                        onPressed:
                                            state.status == AuthStatus.loading
                                                ? null
                                                : () => context
                                                    .read<AuthBloc>()
                                                    .add(SignInRequested(
                                                        email.text.trim(),
                                                        password.text)),
                                        child: Text(
                                            state.status == AuthStatus.loading
                                                ? 'Signing in…'
                                                : 'Sign in')),
                                    if (state.error != null)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 12),
                                          child: Text(state.error!,
                                              style: const TextStyle(
                                                  color: Colors.red))),
                                    const SizedBox(height: 15),
                                    const Text(
                                        'Independent technical assessment demo',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 11)),
                                  ])))))));
}
