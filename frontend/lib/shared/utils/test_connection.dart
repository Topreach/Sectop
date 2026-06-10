import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';

/// Tests connectivity to the backend server.
/// Returns a descriptive string with the result.
/// Call this from a button or debug menu to verify backend reachability.
Future<String> testServerConnection() async {
  final String url = '${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/public/health';

  try {
    final response = await http.get(Uri.parse(url)).timeout(
      const Duration(seconds: 10),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return '✅ Connected! Server: ${data['service']} v${data['version']} at ${data['timestamp']}';
    } else {
      return '❌ Server returned status ${response.statusCode}: ${response.body}';
    }
  } catch (e) {
    return '❌ Connection Error: $e';
  }
}
