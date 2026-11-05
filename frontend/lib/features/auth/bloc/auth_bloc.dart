import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../data/auth_repository.dart';
import '../../products/data/product.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

final class SignInRequested extends AuthEvent {
  const SignInRequested(this.email, this.password);
  final String email, password;
  @override
  List<Object?> get props => [email, password];
}

final class SignOutRequested extends AuthEvent {
  const SignOutRequested();
}

enum AuthStatus { unauthenticated, loading, authenticated, failure }

class AuthState extends Equatable {
  const AuthState(
      {this.status = AuthStatus.unauthenticated, this.session, this.error});
  final AuthStatus status;
  final AuthSession? session;
  final String? error;
  bool get isAdmin => session?.role == 'admin';
  @override
  List<Object?> get props =>
      [status, session?.accessToken, session?.role, error];
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._repository) : super(const AuthState()) {
    on<SignInRequested>((event, emit) async {
      emit(const AuthState(status: AuthStatus.loading));
      try {
        final session = await _repository.signIn(event.email, event.password);
        emit(AuthState(status: AuthStatus.authenticated, session: session));
      } catch (error) {
        emit(AuthState(status: AuthStatus.failure, error: error.toString()));
      }
    });
    on<SignOutRequested>((event, emit) {
      _repository.signOut();
      emit(const AuthState());
    });
  }
  final AuthRepository _repository;
}
