import 'package:flutter/material.dart';
import 'package:lore_ui/lore_ui.dart';

void main() {
  runApp(const LoreApp());
}

class LoreApp extends StatelessWidget {
  const LoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lore',
      theme: LoreTheme.light(),
      darkTheme: LoreTheme.dark(),
      home: const _WorkspacePlaceholder(),
    );
  }
}

class _WorkspacePlaceholder extends StatelessWidget {
  const _WorkspacePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lore')),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 48),
            SizedBox(height: 16),
            Text('书库尚未创建'),
            SizedBox(height: 8),
            Text('下一步将从本地书库初始化开始'),
          ],
        ),
      ),
    );
  }
}
