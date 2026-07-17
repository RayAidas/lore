import 'package:flutter/material.dart';
import 'package:lore_ui/lore_ui.dart';

import '../features/library/library_page.dart';

class LoreApp extends StatelessWidget {
  const LoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lore',
      theme: LoreTheme.light(),
      darkTheme: LoreTheme.dark(),
      home: const LibraryPage(),
    );
  }
}
