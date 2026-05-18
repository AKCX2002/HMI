import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/serial/serial_transport_impl.dart';
import 'features/hmi/hmi_controller.dart';
import 'features/hmi/hmi_dashboard_page.dart';

/// 应用入口。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = HmiController(SerialTransportImpl());
  runApp(HmiHostApp(controller: controller));
}

/// HMI 上位机根组件。
class HmiHostApp extends StatelessWidget {
  const HmiHostApp({super.key, required this.controller});

  final HmiController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HMI Host',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D423B),
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.ibmPlexSansTextTheme(),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFF8F8F4),
        ),
      ),
      home: HmiDashboardPage(controller: controller),
    );
  }
}
