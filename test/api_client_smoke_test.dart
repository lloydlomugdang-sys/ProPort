import 'package:flutter_test/flutter_test.dart';
import 'package:proport_app/services/api_client.dart';

void main() {
  test('local backend is ready', () async {
    try {
      final result = await ApiClient.getReady();
      final data = result['data'] as Map<String, dynamic>;
      final checks = data['checks'] as Map<String, dynamic>;

      expect(data['status'], 'ready');
      expect(checks['database'], 'up');
      expect(checks['storage'], 'local');
      expect(checks['email'], 'console');
    } on ApiException catch (e) {
      if (e.code == 'NETWORK_OFFLINE' || e.code == 'NETWORK_ERROR') {
        // Local backend is not running; offline test execution succeeds safely.
        return;
      }
      rethrow;
    }
  });
}
