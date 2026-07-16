import 'package:compliance_core/compliance_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// One compliance check row: pass/fail icon, the plain-language message, and
/// the measured value for transparency.
class CheckTile extends StatelessWidget {
  const CheckTile({super.key, required this.result});
  final CheckResult result;

  @override
  Widget build(BuildContext context) {
    final pass = result.pass;
    final isWarn = result.severity == Severity.warning;
    final color = pass
        ? AppTheme.ok
        : (isWarn ? AppTheme.warn : AppTheme.err);
    final icon = pass
        ? Icons.check_circle
        : (isWarn ? Icons.info : Icons.cancel);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.message,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: pass ? Colors.black87 : color,
                  ),
                ),
                if (result.measuredValue != null)
                  Text(
                    '${result.checkId} · ${result.measuredValue}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black45),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
