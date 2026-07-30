import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shellguard_free/main.dart';

void main() {
  testWidgets('应用启动后显示基础导航与空状态提示', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 960));
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('ShellGuard'), findsWidgets);
    expect(find.text('暂无服务器，请添加'), findsOneWidget);
    expect(find.text('仪表盘'), findsWidgets);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('应用启动后顶部连接按钮初始可见', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 960));
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('连接'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });
}
