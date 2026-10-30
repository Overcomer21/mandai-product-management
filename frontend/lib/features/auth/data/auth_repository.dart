import '../../../core/network/api_client.dart';
import '../../products/data/product.dart';

class AuthRepository {
  const AuthRepository(this._api);
  final ApiClient _api;
  Future<AuthSession> signIn(String email, String password) async {
    final response = await _api.request('POST', '/api/auth/login',
        data: {'email': email, 'password': password});
    final session = AuthSession.fromJson(requireJsonObject(response));
    _api.accessToken = session.accessToken;
    return session;
  }

  void signOut() => _api.accessToken = null;
}
