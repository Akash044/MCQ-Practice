import 'package:connectivity_plus/connectivity_plus.dart';

/// Thrown in place of whatever raw exception a failed Supabase call produced
/// when the device turns out to have no connectivity, so the UI can show a
/// plain "no internet" message instead of a raw API/socket error.
class NoInternetException implements Exception {
  const NoInternetException();

  @override
  String toString() => 'No internet connection';
}

/// Runs [call]; if it throws, checks connectivity and rethrows as
/// [NoInternetException] when the device is offline, otherwise rethrows the
/// original error untouched. Checking connectivity only after a failure
/// (rather than before every call) avoids delaying the common, successful
/// case with an extra round trip.
Future<T> withConnectivityCheck<T>(Future<T> Function() call) async {
  try {
    return await call();
  } catch (e) {
    final results = await Connectivity().checkConnectivity();
    if (results.every((r) => r == ConnectivityResult.none)) {
      throw const NoInternetException();
    }
    rethrow;
  }
}
