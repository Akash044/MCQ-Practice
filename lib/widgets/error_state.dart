import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../utils/network_error.dart';

/// Renders a friendly "you're offline" message in place of a raw
/// API/exception string when [error] is a [NoInternetException]; otherwise
/// falls back to a generic failure message with the error detail.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.error,
    this.label = 'Something went wrong',
  });

  final Object error;
  final String label;

  @override
  Widget build(BuildContext context) {
    final offline = error is NoInternetException;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(offline ? FIcons.wifiOff : FIcons.circleAlert, size: 32),
            const SizedBox(height: 12),
            Text(
              offline ? 'No internet connection' : label,
              textAlign: TextAlign.center,
            ),
            if (offline) ...[
              const SizedBox(height: 4),
              const Text(
                'Check your connection and try again.',
                textAlign: TextAlign.center,
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text('$error', textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
