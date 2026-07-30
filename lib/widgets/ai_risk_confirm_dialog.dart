import 'package:flutter/material.dart';

import '../models/server.dart';
import 'app_button_styles.dart';

class AiRiskConfirmDialog extends StatelessWidget {
  final AiStepRecord step;

  const AiRiskConfirmDialog({
    super.key,
    required this.step,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (step.riskLevel) {
      AiRiskLevel.high => AppColors.danger,
      AiRiskLevel.medium => AppColors.warning,
      AiRiskLevel.low => AppColors.primary,
      AiRiskLevel.safe => AppColors.success,
    };
    final label = switch (step.riskLevel) {
      AiRiskLevel.high => '高风险',
      AiRiskLevel.medium => '中风险',
      AiRiskLevel.low => '低风险',
      AiRiskLevel.safe => '安全',
    };

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(Icons.shield_outlined, color: color),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI 风险操作确认',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '以下命令需要你确认后才会执行',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1a2332),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                step.command,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF67e8f9),
                  fontFamily: 'Consolas',
                ),
              ),
            ),
            if (step.summary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                step.summary,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  height: 1.6,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: AppButtonStyles.text(),
                  child: const Text('跳过此命令'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: AppButtonStyles.primary(),
                  child: const Text('授权执行'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
