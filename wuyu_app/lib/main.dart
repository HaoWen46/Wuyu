import 'package:flutter/material.dart';
import 'package:wuyu_app/dev_connect_screen.dart';

void main() {
  runApp(const WuyuApp());
}

class WuyuApp extends StatelessWidget {
  const WuyuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '无域',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const DevConnectScreen(),
    );
  }
}
