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
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF08152A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D423B),
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.ibmPlexSansTextTheme(ThemeData.dark().textTheme),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF0A1D36),
          labelStyle: TextStyle(color: Color(0xFFA6C5EA)),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF2A4F79)),
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF52B3FF)),
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: HmiDashboardPage(controller: controller),
    );
  }
}
