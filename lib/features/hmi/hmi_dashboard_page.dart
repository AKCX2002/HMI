import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../util/log_exporter.dart';
import 'hmi_controller.dart';
import 'hmi_port_config.dart';
import 'hmi_protocol.dart';
import 'hmi_session_catalog.dart';
import 'hmi_serial_config_page.dart';
import 'stack_stats.dart';

/// HMI 主操作界面。
///
/// 布局参考用户提供的深色工业风控制台：
/// - 左侧导航栏
/// - 右侧工作台（命令面板/参数配置/帧调试/日志）
class HmiDashboardPage extends StatefulWidget {
  const HmiDashboardPage({super.key, required this.controller});

  final HmiController controller;

  @override
  State<HmiDashboardPage> createState() => _HmiDashboardPageState();
}

class _HmiDashboardPageState extends State<HmiDashboardPage> {
  int _menuIndex = 0;

  final TextEditingController _packerNodeAddr = TextEditingController(
    text: 'FA',
  );

  /// 参数配置页状态
  final Map<int, TextEditingController> _paramEditors =
      <int, TextEditingController>{};
  final Map<int, int> _paramValues = <int, int>{};
  bool _paramsLoading = false;
  String _paramsStatus = '';

  final TextEditingController _retryCount = TextEditingController(text: '1');
  final TextEditingController _timeoutMs = TextEditingController(text: '1200');
  final TextEditingController _retryIntervalMs = TextEditingController(
    text: '200',
  );

  final TextEditingController _rawAddr = TextEditingController(text: 'AF');
  final TextEditingController _rawFunc = TextEditingController(text: '09');
  final TextEditingController _rawPayload = TextEditingController(text: '01');
  final TextEditingController _rawExpected = TextEditingController(
    text: '09,0A',
  );

  /// DGUS 系统信息
  List<int>? _sysInfoData;
  String _sysInfoStatus = '';
  bool _sysInfoLoading = false;

  /// 端口覆写开关：每个面板可独立选择物理串口发送命令
  bool _packerUsePortB = false;
  final bool _dgusUsePortB = true;

  /// Port A 子标签页: 0=状态0x41, 1=封口0x43, 2=基础控制, 3=维护诊断, 4=电机点动
  int _packerSubTab = 0;

  /// USART1 子页面: 0=参数调节, 1=系统状态, 2=日志监控
  int _usart1SubPage = 0;

  int _logDisplayMode = 2; /* 0=HEX, 1=文本, 2=HEX+文本 */
  bool _logsPaused = false;

  /// 基础控制 0x40~0x44
  int _cmd40Action = 1;
  int _cmd42Action = 1;
  int _cmd43Action = 1;
  int _cmd44Action = 1;

  /// 维护诊断 0x45~0x49
  int _cmd45Flag = 1;
  final TextEditingController _cmd47PrinterCmd = TextEditingController(
    text: '81',
  );
  int _cmd49Scope = 0;

  /// 电机点动 0x4A~0x4C
  int _cmd4aMotor = 1;
  int _cmd4aDir = 1;
  final TextEditingController _cmd4aPulses = TextEditingController(
    text: '1000',
  );
  int _cmd4bDir = 1;
  final TextEditingController _cmd4bDuration = TextEditingController(
    text: '500',
  );
  int _cmd4cDir = 1;
  final TextEditingController _cmd4cDuration = TextEditingController(
    text: '500',
  );

  final TextEditingController _stackChartPoints = TextEditingController(
    text: '120',
  );

  @override
  void initState() {
    super.initState();
    widget.controller.refreshPorts();
    final policy = widget.controller.retryPolicy;
    _retryCount.text = '${policy.maxRetries}';
    _timeoutMs.text = '${policy.timeoutMs}';
    _retryIntervalMs.text = '${policy.retryIntervalMs}';
  }

  @override
  void dispose() {
    _packerNodeAddr.dispose();
    _retryCount.dispose();
    _timeoutMs.dispose();
    _retryIntervalMs.dispose();
    _stackChartPoints.dispose();
    _rawAddr.dispose();
    _rawFunc.dispose();
    _rawPayload.dispose();
    _rawExpected.dispose();
    _cmd47PrinterCmd.dispose();
    _cmd4aPulses.dispose();
    _cmd4bDuration.dispose();
    _cmd4cDuration.dispose();
    super.dispose();
  }

  int _safeInt(TextEditingController controller, {int fallback = 0}) {
    return int.tryParse(controller.text.trim()) ?? fallback;
  }

  int _safeHex(String text, {int fallback = 0}) {
    final t = text.trim().replaceAll('0x', '').replaceAll('0X', '');
    return int.tryParse(t, radix: 16) ?? fallback;
  }

  List<int> _parseHexBytes(String text) {
    final clean = text
        .replaceAll(',', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) {
      return const <int>[];
    }
    return clean.split(' ').map((e) => _safeHex(e)).toList();
  }

  Set<int> _parseHexSet(String text) {
    return _parseHexBytes(text).toSet();
  }

  Future<void> _runCommand(
    Future<CommandExecutionResult> Function() action, [
    String? successText,
  ]) async {
    final result = await action();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: result.success
            ? const Color(0xFF2E7D32)
            : const Color(0xFF9F2D2D),
        content: Text(result.message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF08152A),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (_, constraints) {
                final compact = constraints.maxWidth < 1150;
                return compact
                    ? Column(
                        children: <Widget>[
                          _buildTopBar(controller),
                          _buildCompactMenuBar(),
                          Expanded(child: _buildWorkArea(controller)),
                        ],
                      )
                    : Row(
                        children: <Widget>[
                          _buildSidebar(controller),
                          Expanded(
                            child: Column(
                              children: <Widget>[
                                _buildTopBar(controller),
                                Expanded(child: _buildWorkArea(controller)),
                              ],
                            ),
                          ),
                        ],
                      );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactMenuBar() {
    final menus = <String>[
      '串口配置',
      'USART3调试',
      'USART1会话',
      '帧调试台',
      '协议日志',
      '栈水位统计',
    ];
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFF0B1E3A),
        border: Border(bottom: BorderSide(color: Color(0xFF213D65))),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, i) {
          final selected = _menuIndex == i;
          return InkWell(
            onTap: () => setState(() => _menuIndex = i),
            borderRadius: BorderRadius.circular(8),
            hoverColor: const Color(0x3314345A),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF14345A)
                    : const Color(0x2214345A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2C4F79)),
              ),
              alignment: Alignment.center,
              child: Text(
                menus[i],
                style: GoogleFonts.ibmPlexSans(
                  color: const Color(0xFFD6E9FF),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemCount: menus.length,
      ),
    );
  }

  Widget _buildPortIndicator({required bool connected, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: connected
                ? const Color(0xFF4CAF50)
                : const Color(0xFFE53935),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            color: connected
                ? const Color(0xFF9AF9D3)
                : const Color(0xFFFF9595),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar(HmiController controller) {
    final menus = <(IconData, String)>[
      (Icons.settings_ethernet, '串口配置'),
      (Icons.satellite_alt, 'USART3调试'),
      (Icons.developer_mode, 'USART1会话'),
      (Icons.memory, '帧调试台'),
      (Icons.receipt_long, '协议日志'),
      (Icons.show_chart, '栈水位统计'),
    ];

    return Container(
      width: 230,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF0F1B32), Color(0xFF0B1327)],
        ),
        border: Border(right: BorderSide(color: Color(0xFF233A62))),
      ),
      child: LayoutBuilder(
        builder: (_, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'HMI HOST',
                      style: GoogleFonts.ibmPlexSans(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  // ── 双端口状态 ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: const Color(0x0DFFFFFF),
                      ),
                      child: Column(
                        children: <Widget>[
                          _buildPortIndicator(
                            connected: controller.isConnectedA,
                            label: '端口 A (USART3)',
                          ),
                          const SizedBox(height: 6),
                          _buildPortIndicator(
                            connected: controller.isConnectedB,
                            label: '端口 B (USART1)',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < menus.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        hoverColor: const Color(0x3314345A),
                        onTap: () => setState(() => _menuIndex = i),
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: _menuIndex == i
                                ? const Color(0xFF14345A)
                                : Colors.transparent,
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                menus[i].$1,
                                color: const Color(0xFF5ED0FF),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  menus[i].$2,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.ibmPlexSans(
                                    color: const Color(0xFFD6E9FF),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.device_hub,
                              color: Color(0xFF7DB5FF),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '端口 A: USART3 / 20B / CRC16-Modbus',
                                style: GoogleFonts.ibmPlexMono(
                                  color: const Color(0xFF9EC7FF),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.developer_mode,
                              color: Color(0xFF7DB5FF),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '端口 B: USART1 / HMI Session',
                                style: GoogleFonts.ibmPlexMono(
                                  color: const Color(0xFF9EC7FF),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopBar(HmiController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1E3A),
        border: Border(bottom: BorderSide(color: Color(0xFF213D65))),
      ),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final compact = constraints.maxWidth < 760;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  controller.deviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.ibmPlexSans(
                    color: const Color(0xFFE5F2FF),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  controller.statusMessage ?? '就绪',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.ibmPlexSans(
                    color: const Color(0xFF9DC1EB),
                    fontSize: 12,
                  ),
                ),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  controller.deviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.ibmPlexSans(
                    color: const Color(0xFFE5F2FF),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  controller.statusMessage ?? '就绪',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.ibmPlexSans(
                    color: const Color(0xFF9DC1EB),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWorkArea(HmiController controller) {
    switch (_menuIndex) {
      case 0:
        return HmiSerialConfigPage(controller: controller);
      case 1:
        return _buildUsart3DebugPage(controller);
      case 2:
        return _buildUsart1SessionPage(controller);
      case 3:
        return _buildFrameDebuggerPage(controller);
      case 4:
        return _buildLogsPage(controller);
      case 5:
        return _buildStackLevelPage(controller);
      default:
        return _buildUsart3DebugPage(controller);
    }
  }

  Widget _buildUsart3DebugPage(HmiController controller) {
    return Container(
      color: const Color(0xFF08152A),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          _buildSinglePortBar(controller, portA: true),
          const SizedBox(height: 12),
          _buildPortAPanel(controller),
          const SizedBox(height: 12),
          _buildLiveLogPanel(controller),
        ],
      ),
    );
  }

  Widget _buildUsart1SessionPage(HmiController controller) {
    return Container(
      color: const Color(0xFF08152A),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          _buildSinglePortBar(controller, portA: false),
          const SizedBox(height: 12),
          _buildPortBPanel(controller),
          const SizedBox(height: 12),
          _buildUsart1ControlPanel(controller),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildMainDashboard(HmiController controller) =>
      _buildUsart3DebugPage(controller);

  Widget _buildSinglePortBar(HmiController controller, {required bool portA}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF233A62)),
      ),
      child: _buildMiniPortConfig(
        label: portA ? 'USART3 / 20B 调试' : 'USART1 / HMI Session',
        isConnected: portA ? controller.isConnectedA : controller.isConnectedB,
        ports: portA ? controller.portsA : controller.portsB,
        selectedPort: portA
            ? controller.portAConfig.portName
            : controller.portBConfig.portName,
        baudRate: portA
            ? controller.portAConfig.baudRate
            : controller.portBConfig.baudRate,
        canEdit: portA ? !controller.isConnectedA : !controller.isConnectedB,
        onPortChanged: portA ? controller.setPortA : controller.setPortB,
        onBaudRateChanged: portA
            ? controller.setBaudRateA
            : controller.setBaudRateB,
        onRefresh: portA ? controller.refreshPortsA : controller.refreshPortsB,
        onConnect: portA ? controller.connectPortA : controller.connectPortB,
        onDisconnect: portA
            ? controller.disconnectPortA
            : controller.disconnectPortB,
      ),
    );
  }

  /// ── 双端口紧凑配置栏 ──
  // ignore: unused_element
  Widget _buildDualPortBar(HmiController controller) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF233A62)),
      ),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final compact = constraints.maxWidth < 700;
          final portA = _buildMiniPortConfig(
            label: '端口 A',
            isConnected: controller.isConnectedA,
            ports: controller.portsA,
            selectedPort: controller.portAConfig.portName,
            baudRate: controller.portAConfig.baudRate,
            canEdit: !controller.isConnectedA,
            onPortChanged: (v) => controller.setPortA(v),
            onBaudRateChanged: (v) => controller.setBaudRateA(v),
            onRefresh: controller.refreshPortsA,
            onConnect: controller.connectPortA,
            onDisconnect: controller.disconnectPortA,
          );
          final portB = _buildMiniPortConfig(
            label: '端口 B',
            isConnected: controller.isConnectedB,
            ports: controller.portsB,
            selectedPort: controller.portBConfig.portName,
            baudRate: controller.portBConfig.baudRate,
            canEdit: !controller.isConnectedB,
            onPortChanged: (v) => controller.setPortB(v),
            onBaudRateChanged: (v) => controller.setBaudRateB(v),
            onRefresh: controller.refreshPortsB,
            onConnect: controller.connectPortB,
            onDisconnect: controller.disconnectPortB,
          );
          if (compact) {
            return Column(
              children: <Widget>[portA, const SizedBox(height: 8), portB],
            );
          }
          final pw = (constraints.maxWidth - 10) / 2;
          return Row(
            children: <Widget>[
              SizedBox(width: pw, child: portA),
              const SizedBox(width: 10),
              SizedBox(width: pw, child: portB),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMiniPortConfig({
    required String label,
    required bool isConnected,
    required List<String> ports,
    required String? selectedPort,
    required int baudRate,
    required bool canEdit,
    required ValueChanged<String?> onPortChanged,
    required ValueChanged<int> onBaudRateChanged,
    required VoidCallback onRefresh,
    required VoidCallback onConnect,
    required VoidCallback onDisconnect,
  }) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final veryCompact = constraints.maxWidth < 460;
        final somewhatCompact = constraints.maxWidth < 700;

        // ── 控件构建 ──
        final labelWidget = Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: isConnected
                ? const Color(0x1E1FDC9A)
                : const Color(0x33E53935),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              color: isConnected
                  ? const Color(0xFF9AF9D3)
                  : const Color(0xFFFF9595),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

        final portDropdown = DropdownButtonFormField<String?>(
          initialValue: selectedPort,
          isExpanded: true,
          decoration: _miniInputDeco('串口'),
          dropdownColor: const Color(0xFF122B4D),
          style: const TextStyle(color: Color(0xFFD7E8FF), fontSize: 11),
          isDense: true,
          selectedItemBuilder: (_) {
            return <String?>[null, ...ports].map((p) {
              final label = p ?? '— 关闭 —';
              final color = p == null
                  ? const Color(0xFF888888)
                  : const Color(0xFFD7E8FF);
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 11),
                ),
              );
            }).toList();
          },
          items: <DropdownMenuItem<String?>>[
            // 关闭选项（清空串口选择）
            const DropdownMenuItem<String?>(
              value: null,
              child: Text(
                '— 关闭 —',
                style: TextStyle(color: Color(0xFF888888), fontSize: 11),
              ),
            ),
            // 可用串口列表
            ...ports.map(
              (p) => DropdownMenuItem<String?>(
                value: p,
                child: Text(
                  p,
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: canEdit ? (v) => onPortChanged(v) : null,
        );

        final baudDropdown = DropdownButtonFormField<int>(
          initialValue: baudRate,
          isExpanded: true,
          decoration: _miniInputDeco('波特率'),
          dropdownColor: const Color(0xFF122B4D),
          style: const TextStyle(color: Color(0xFFD7E8FF), fontSize: 11),
          isDense: true,
          items: HmiPortConfig.baudRateOptionsFor(baudRate)
              .map(
                (v) => DropdownMenuItem<int>(
                  value: v,
                  child: Text('$v', style: const TextStyle(fontSize: 11)),
                ),
              )
              .toList(),
          onChanged: canEdit ? (v) => onBaudRateChanged(v ?? 9600) : null,
        );

        final baudControl = _buildMiniBaudControl(
          baudRate: baudRate,
          canEdit: canEdit,
          dropdown: baudDropdown,
          onBaudRateChanged: onBaudRateChanged,
        );

        final scanBtn = Tooltip(
          message: '扫描可用串口',
          child: SizedBox(
            height: 30,
            width: 36,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B91D8),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF445E78),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: onRefresh,
              child: Text('扫', style: GoogleFonts.ibmPlexSans(fontSize: 10)),
            ),
          ),
        );

        final connBtn = Tooltip(
          message: isConnected ? '断开串口连接' : '连接串口',
          child: SizedBox(
            height: 30,
            width: 36,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isConnected
                    ? const Color(0xFF9F2D2D)
                    : const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: isConnected ? onDisconnect : onConnect,
              child: Text(
                isConnected ? '断' : '连',
                style: GoogleFonts.ibmPlexSans(fontSize: 10),
              ),
            ),
          ),
        );

        // ── 布局策略 ──
        if (veryCompact) {
          // 三行：标签+按钮 / 串口 / 波特率
          return Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  labelWidget,
                  const Spacer(),
                  scanBtn,
                  const SizedBox(width: 4),
                  connBtn,
                ],
              ),
              const SizedBox(height: 4),
              Row(children: <Widget>[Expanded(child: portDropdown)]),
              const SizedBox(height: 4),
              Row(children: <Widget>[Expanded(child: baudControl)]),
            ],
          );
        } else if (somewhatCompact) {
          // 两行：标签+按钮 / 串口+波特率
          return Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  labelWidget,
                  const Spacer(),
                  scanBtn,
                  const SizedBox(width: 3),
                  connBtn,
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Expanded(flex: 5, child: portDropdown),
                  const SizedBox(width: 4),
                  Expanded(flex: 2, child: baudControl),
                ],
              ),
            ],
          );
        } else {
          // 一行：标签 + 串口 + 波特率 + 按钮
          return Row(
            children: <Widget>[
              labelWidget,
              const SizedBox(width: 4),
              Expanded(flex: 5, child: portDropdown),
              const SizedBox(width: 4),
              Expanded(flex: 2, child: baudControl),
              const SizedBox(width: 4),
              scanBtn,
              const SizedBox(width: 3),
              connBtn,
            ],
          );
        }
      },
    );
  }

  InputDecoration _miniInputDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFFA6C5EA), fontSize: 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      filled: true,
      fillColor: const Color(0xFF0A1D36),
      border: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF2A4F79)),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  Widget _buildMiniBaudControl({
    required int baudRate,
    required bool canEdit,
    required Widget dropdown,
    required ValueChanged<int> onBaudRateChanged,
  }) {
    return Row(
      children: <Widget>[
        Expanded(child: dropdown),
        const SizedBox(width: 4),
        Tooltip(
          message: '自定义波特率',
          child: SizedBox(
            height: 30,
            width: 30,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF375A7F),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF445E78),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: canEdit
                  ? () async {
                      final custom = await _showCustomBaudRateDialog(
                        currentValue: baudRate,
                        title: '自定义波特率',
                      );
                      if (custom != null) {
                        onBaudRateChanged(custom);
                      }
                    }
                  : null,
              child: Text('自', style: GoogleFonts.ibmPlexSans(fontSize: 10)),
            ),
          ),
        ),
      ],
    );
  }

  Future<int?> _showCustomBaudRateDialog({
    required int currentValue,
    required String title,
  }) async {
    var textValue = '$currentValue';
    var errorText = '';
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0D1A30),
              title: Text(
                title,
                style: GoogleFonts.ibmPlexSans(color: const Color(0xFFD7E8FF)),
              ),
              content: SizedBox(
                width: 320,
                child: TextFormField(
                  initialValue: textValue,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: const TextStyle(color: Color(0xFFD7E8FF)),
                  decoration: InputDecoration(
                    labelText:
                        '范围 ${HmiPortConfig.minCustomBaudRate}-${HmiPortConfig.maxCustomBaudRate}',
                    labelStyle: const TextStyle(
                      color: Color(0xFFA6C5EA),
                      fontSize: 12,
                    ),
                    errorText: errorText.isEmpty ? null : errorText,
                  ),
                  onChanged: (value) => textValue = value,
                  onSubmitted: (_) {
                    final value = int.tryParse(textValue.trim());
                    if (value == null ||
                        !HmiPortConfig.isValidBaudRate(value)) {
                      setLocalState(() {
                        errorText =
                            '请输入 ${HmiPortConfig.minCustomBaudRate}-${HmiPortConfig.maxCustomBaudRate} 的整数';
                      });
                      return;
                    }
                    Navigator.of(ctx).pop(value);
                  },
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final value = int.tryParse(textValue.trim());
                    if (value == null ||
                        !HmiPortConfig.isValidBaudRate(value)) {
                      setLocalState(() {
                        errorText =
                            '请输入 ${HmiPortConfig.minCustomBaudRate}-${HmiPortConfig.maxCustomBaudRate} 的整数';
                      });
                      return;
                    }
                    Navigator.of(ctx).pop(value);
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
    return result;
  }

  /// ── 端口 A 面板：左协议 (USART3 / 20B 主控协议) ──
  Widget _buildPortAPanel(HmiController controller) {
    final nodeAddr = _safeHex(_packerNodeAddr.text, fallback: 0xFA);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF102744),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF274E7A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ── 标题 ──
          Row(
            children: <Widget>[
              const Icon(
                Icons.satellite_alt,
                color: Color(0xFF5ED0FF),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                '端口 A — USART3 / 20B 固定帧 / CRC16-Modbus（主控协议）',
                style: GoogleFonts.ibmPlexSans(
                  color: const Color(0xFFE0EEFF),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ── 端口覆写 + 节点地址 ──
          Row(
            children: <Widget>[
              Text(
                'TX:',
                style: GoogleFonts.ibmPlexSans(
                  color: const Color(0xFFA6C5EA),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 6),
              _buildPortToggle(
                labelA: 'A',
                labelB: 'B',
                value: _packerUsePortB,
                onChanged: (v) => setState(() => _packerUsePortB = v),
                connectedA: controller.isConnectedA,
                connectedB: controller.isConnectedB,
              ),
              const SizedBox(width: 16),
              Text(
                '节点:',
                style: GoogleFonts.ibmPlexSans(
                  color: const Color(0xFFA6C5EA),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 72,
                height: 28,
                child: TextField(
                  controller: _packerNodeAddr,
                  smartQuotesType: SmartQuotesType.disabled,
                  smartDashesType: SmartDashesType.disabled,
                  style: GoogleFonts.ibmPlexMono(
                    color: const Color(0xFFD6E9FF),
                    fontSize: 12,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF233A62), height: 1),
          const SizedBox(height: 6),
          // ── 子标签页切换 ──
          _buildSubTabBar(),
          const SizedBox(height: 6),
          const Divider(color: Color(0xFF233A62), height: 1),
          const SizedBox(height: 6),
          // ── 子标签页内容 ──
          if (_packerSubTab == 0) ..._buildStatus41Tab(controller, nodeAddr),
          if (_packerSubTab == 1) ..._buildSeal43Tab(controller, nodeAddr),
          if (_packerSubTab == 2) ..._buildBasicTab(controller, nodeAddr),
          if (_packerSubTab == 3) ..._buildMaintTab(controller, nodeAddr),
          if (_packerSubTab == 4) ..._buildMotorTab(controller, nodeAddr),
        ],
      ),
    );
  }

  /// 子标签页切换栏
  Widget _buildSubTabBar() {
    const tabs = <String>['0x41状态', '0x43封口', '基础控制', '维护诊断', '电机点动'];
    return Row(
      children: <Widget>[
        for (var i = 0; i < tabs.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () => setState(() => _packerSubTab = i),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _packerSubTab == i
                      ? const Color(0xFF1B91D8)
                      : const Color(0xFF14345A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _packerSubTab == i
                        ? const Color(0xFF5ED0FF)
                        : const Color(0xFF2A4F79),
                  ),
                ),
                child: Text(
                  tabs[i],
                  style: GoogleFonts.ibmPlexSans(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildStatus41Tab(HmiController controller, int nodeAddr) {
    return <Widget>[
      _cmdRow(
        controller,
        nodeAddr,
        '0x41',
        '状态查询',
        onSend: () => _runCommand(
          () => controller.sendPackerStatus(
            nodeAddress: nodeAddr,
            usePortB: false,
          ),
          '状态查询',
        ),
      ),
    ];
  }

  List<Widget> _buildSeal43Tab(HmiController controller, int nodeAddr) {
    return <Widget>[
      _cmdRow(
        controller,
        nodeAddr,
        '0x43',
        '封口启动/查询',
        config: _buildDropdown(
          value: _cmd43Action,
          items: const <int>[1, 0, 2],
          labels: const <String>['启动', '查询', '完成?'],
          onChanged: (v) => setState(() => _cmd43Action = v ?? 1),
        ),
        onSend: () => _runCommand(
          () => controller.sendPackerTriggerSeal(
            nodeAddress: nodeAddr,
            action: _cmd43Action,
            usePortB: false,
          ),
          '封口触发',
        ),
      ),
      _cmdRow(
        controller,
        nodeAddr,
        '0x45',
        '清封口完成',
        onSend: () => _runCommand(
          () => controller.sendPackerClearFlag(
            nodeAddress: nodeAddr,
            flagId: 2,
            usePortB: false,
          ),
          '清封口完成标志',
        ),
      ),
    ];
  }

  /// ── 基础控制 0x40~0x44 ──
  List<Widget> _buildBasicTab(HmiController controller, int nodeAddr) {
    return <Widget>[
      _cmdRow(
        controller,
        nodeAddr,
        '0x40',
        '启停控制',
        config: _buildDropdown(
          value: _cmd40Action,
          items: const <int>[1, 0],
          labels: const <String>['启动', '停止'],
          onChanged: (v) => setState(() => _cmd40Action = v ?? 1),
        ),
        onSend: () => _runCommand(
          () => controller.sendPackerControl(
            nodeAddress: nodeAddr,
            action: _cmd40Action,
            usePortB: _packerUsePortB,
          ),
          '打包机${_cmd40Action == 1 ? "启动" : "停止"}',
        ),
      ),
      _cmdRow(
        controller,
        nodeAddr,
        '0x41',
        '状态查询',
        onSend: () => _runCommand(
          () => controller.sendPackerStatus(
            nodeAddress: nodeAddr,
            usePortB: _packerUsePortB,
          ),
          '状态查询',
        ),
      ),
      _cmdRow(
        controller,
        nodeAddr,
        '0x42',
        '出袋',
        config: _buildDropdown(
          value: _cmd42Action,
          items: const <int>[1, 0, 2],
          labels: const <String>['启动', '查询', '完成?'],
          onChanged: (v) => setState(() => _cmd42Action = v ?? 1),
        ),
        onSend: () => _runCommand(
          () => controller.sendPackerTriggerBag(
            nodeAddress: nodeAddr,
            action: _cmd42Action,
            usePortB: _packerUsePortB,
          ),
          '出袋触发',
        ),
      ),
      _cmdRow(
        controller,
        nodeAddr,
        '0x43',
        '封口',
        config: _buildDropdown(
          value: _cmd43Action,
          items: const <int>[1, 0, 2],
          labels: const <String>['启动', '查询', '完成?'],
          onChanged: (v) => setState(() => _cmd43Action = v ?? 1),
        ),
        onSend: () => _runCommand(
          () => controller.sendPackerTriggerSeal(
            nodeAddress: nodeAddr,
            action: _cmd43Action,
            usePortB: _packerUsePortB,
          ),
          '封口触发',
        ),
      ),
      _cmdRow(
        controller,
        nodeAddr,
        '0x44',
        '投料',
        config: _buildDropdown(
          value: _cmd44Action,
          items: const <int>[1, 0, 2],
          labels: const <String>['启动', '查询', '完成?'],
          onChanged: (v) => setState(() => _cmd44Action = v ?? 1),
        ),
        onSend: () => _runCommand(
          () => controller.sendPackerTriggerDeliver(
            nodeAddress: nodeAddr,
            action: _cmd44Action,
            usePortB: _packerUsePortB,
          ),
          '投料触发',
        ),
      ),
    ];
  }

  /// ── 维护诊断 0x45~0x49 ──
  List<Widget> _buildMaintTab(HmiController controller, int nodeAddr) {
    return <Widget>[
      _cmdRow(
        controller,
        nodeAddr,
        '0x45',
        '清除标志',
        config: _buildDropdown(
          value: _cmd45Flag,
          items: const <int>[1, 2, 3],
          labels: const <String>['装袋完成', '封口完成', '传送完成'],
          onChanged: (v) => setState(() => _cmd45Flag = v ?? 1),
        ),
        onSend: () => _runCommand(
          () => controller.sendPackerClearFlag(
            nodeAddress: nodeAddr,
            flagId: _cmd45Flag,
            usePortB: _packerUsePortB,
          ),
          '清除标志',
        ),
      ),
      _cmdRow(
        controller,
        nodeAddr,
        '0x46',
        '报警查询',
        onSend: () => _runCommand(
          () => controller.sendPackerAlarmQuery(
            nodeAddress: nodeAddr,
            usePortB: _packerUsePortB,
          ),
          '报警查询',
        ),
      ),
      _cmdRow(
        controller,
        nodeAddr,
        '0x47',
        '打印机透传',
        config: SizedBox(
          width: 52,
          height: 28,
          child: TextField(
            controller: _cmd47PrinterCmd,
            smartQuotesType: SmartQuotesType.disabled,
            smartDashesType: SmartDashesType.disabled,
            style: GoogleFonts.ibmPlexMono(
              color: const Color(0xFFD6E9FF),
              fontSize: 12,
            ),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            ),
          ),
        ),
        onSend: () => _runCommand(
          () => controller.sendPackerPrinterForward(
            nodeAddress: nodeAddr,
            printerCmd: _safeHex(_cmd47PrinterCmd.text, fallback: 0x81),
            usePortB: _packerUsePortB,
          ),
          '打印机透传',
        ),
      ),
      _cmdRow(
        controller,
        nodeAddr,
        '0x48',
        '版本查询',
        onSend: () => _runCommand(
          () => controller.sendPackerVersion(
            nodeAddress: nodeAddr,
            usePortB: _packerUsePortB,
          ),
          '版本查询',
        ),
      ),
      _cmdRow(
        controller,
        nodeAddr,
        '0x49',
        '故障复位',
        config: _buildDropdown(
          value: _cmd49Scope,
          items: const <int>[0, 1, 2],
          labels: const <String>['清除报警', '+锁存', '+全部清零'],
          onChanged: (v) => setState(() => _cmd49Scope = v ?? 0),
        ),
        onSend: () => _runCommand(
          () => controller.sendPackerResetFault(
            nodeAddress: nodeAddr,
            scope: _cmd49Scope,
            usePortB: _packerUsePortB,
          ),
          '故障复位',
        ),
      ),
    ];
  }

  /// ── 电机点动 0x4A~0x4C ──
  List<Widget> _buildMotorTab(HmiController controller, int nodeAddr) {
    return <Widget>[
      _cmdRow(
        controller,
        nodeAddr,
        '0x4A',
        '步进点动',
        config: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildDropdown(
              value: _cmd4aMotor,
              items: const <int>[1, 2],
              labels: const <String>['M1', 'M2'],
              onChanged: (v) => setState(() => _cmd4aMotor = v ?? 1),
            ),
            const SizedBox(width: 4),
            _buildDropdown(
              value: _cmd4aDir,
              items: const <int>[1, 0],
              labels: const <String>['正', '反'],
              onChanged: (v) => setState(() => _cmd4aDir = v ?? 1),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 60,
              height: 28,
              child: TextField(
                controller: _cmd4aPulses,
                keyboardType: TextInputType.number,
                smartQuotesType: SmartQuotesType.disabled,
                smartDashesType: SmartDashesType.disabled,
                style: GoogleFonts.ibmPlexMono(
                  color: const Color(0xFFD6E9FF),
                  fontSize: 12,
                ),
                decoration: const InputDecoration(
                  hintText: '脉冲',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                ),
              ),
            ),
          ],
        ),
        onSend: () => _runCommand(
          () => controller.sendPackerStepperJog(
            nodeAddress: nodeAddr,
            motor: _cmd4aMotor,
            direction: _cmd4aDir,
            pulses: _safeInt(_cmd4aPulses, fallback: 1000),
            usePortB: _packerUsePortB,
          ),
          '步进点动',
        ),
      ),
      _cmdRow(
        controller,
        nodeAddr,
        '0x4B',
        '直流1点动',
        config: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildDropdown(
              value: _cmd4bDir,
              items: const <int>[1, 0],
              labels: const <String>['正', '反'],
              onChanged: (v) => setState(() => _cmd4bDir = v ?? 1),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 60,
              height: 28,
              child: TextField(
                controller: _cmd4bDuration,
                keyboardType: TextInputType.number,
                smartQuotesType: SmartQuotesType.disabled,
                smartDashesType: SmartDashesType.disabled,
                style: GoogleFonts.ibmPlexMono(
                  color: const Color(0xFFD6E9FF),
                  fontSize: 12,
                ),
                decoration: const InputDecoration(
                  hintText: 'ms',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                ),
              ),
            ),
          ],
        ),
        onSend: () => _runCommand(
          () => controller.sendPackerDcMotor1Jog(
            nodeAddress: nodeAddr,
            direction: _cmd4bDir,
            durationMs: _safeInt(_cmd4bDuration, fallback: 500),
            usePortB: _packerUsePortB,
          ),
          '直流1点动',
        ),
      ),
      _cmdRow(
        controller,
        nodeAddr,
        '0x4C',
        '直流2点动',
        config: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildDropdown(
              value: _cmd4cDir,
              items: const <int>[1, 0],
              labels: const <String>['正', '反'],
              onChanged: (v) => setState(() => _cmd4cDir = v ?? 1),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 60,
              height: 28,
              child: TextField(
                controller: _cmd4cDuration,
                keyboardType: TextInputType.number,
                smartQuotesType: SmartQuotesType.disabled,
                smartDashesType: SmartDashesType.disabled,
                style: GoogleFonts.ibmPlexMono(
                  color: const Color(0xFFD6E9FF),
                  fontSize: 12,
                ),
                decoration: const InputDecoration(
                  hintText: 'ms',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                ),
              ),
            ),
          ],
        ),
        onSend: () => _runCommand(
          () => controller.sendPackerDcMotor2Jog(
            nodeAddress: nodeAddr,
            direction: _cmd4cDir,
            durationMs: _safeInt(_cmd4cDuration, fallback: 500),
            usePortB: _packerUsePortB,
          ),
          '直流2点动',
        ),
      ),
    ];
  }

  /// 构建单条命令行：标签 | 配置参数 | 发送按钮
  Widget _cmdRow(
    HmiController controller,
    int nodeAddr,
    String code,
    String label, {
    Widget? config,
    required VoidCallback onSend,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              '$code $label',
              style: GoogleFonts.ibmPlexSans(
                color: const Color(0xFFC5DAF0),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (config != null) ...[
            config,
            const SizedBox(width: 8),
          ] else
            const Spacer(),
          SizedBox(
            height: 28,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B91D8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: onSend,
              child: Text('发送', style: GoogleFonts.ibmPlexSans(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  /// 紧凑型下拉框
  Widget _buildDropdown({
    required int value,
    required List<int> items,
    required List<String> labels,
    required ValueChanged<int?> onChanged,
  }) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1D36),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A4F79)),
      ),
      child: DropdownButton<int>(
        value: value,
        isDense: true,
        underline: const SizedBox.shrink(),
        dropdownColor: const Color(0xFF122B4D),
        style: GoogleFonts.ibmPlexSans(
          color: const Color(0xFFD6E9FF),
          fontSize: 12,
        ),
        items: List<DropdownMenuItem<int>>.generate(
          items.length,
          (i) => DropdownMenuItem<int>(
            value: items[i],
            child: Text(labels[i], style: const TextStyle(fontSize: 12)),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }

  /// 双端口选择开关：在 A/B 之间切换发送目标。
  Widget _buildPortToggle({
    required String labelA,
    required String labelB,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool connectedA,
    required bool connectedB,
  }) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFF0B1E3A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A4F79)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _toggleTab(
            label: labelA,
            selected: !value,
            connected: connectedA,
            onTap: () => onChanged(false),
          ),
          _toggleTab(
            label: labelB,
            selected: value,
            connected: connectedB,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _toggleTab({
    required String label,
    required bool selected,
    required bool connected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1B91D8) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFF666666),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.ibmPlexSans(
                color: selected
                    ? Colors.white
                    : connected
                    ? const Color(0xFF9AF9D3)
                    : const Color(0xFF888888),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBtn(String label, bool enabled, VoidCallback? onPressed) {
    return SizedBox(
      height: 30,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF14345A),
          foregroundColor: const Color(0xFFD6E9FF),
          disabledBackgroundColor: const Color(0xFF2A3F58),
          disabledForegroundColor: const Color(0xFF6A7F99),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color: enabled
                  ? const Color(0xFF2C4F79)
                  : const Color(0xFF1A2F48),
            ),
          ),
        ),
        onPressed: enabled ? onPressed : null,
        child: Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _sysInfoBadge(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            color: const Color(0xFFA7C7EB),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.ibmPlexMono(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  /// ── 端口 B 面板：USART1 HMI Session ──
  Widget _buildPortBPanel(HmiController controller) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF274E7A)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x55030A14),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF132A3B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2D6F86)),
                ),
                child: const Icon(
                  Icons.developer_mode,
                  color: Color(0xFF54D6C6),
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '端口 B — USART1 / HMI Session',
                      style: GoogleFonts.ibmPlexSans(
                        color: const Color(0xFFE0EEFF),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '参数调试、系统状态、日志监控分区处理',
                      style: GoogleFonts.ibmPlexSans(
                        color: const Color(0xFF8FB6C8),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              _buildUsart1StatusPill(controller),
            ],
          ),
          const SizedBox(height: 14),
          _buildUsart1SubPageBar(),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: KeyedSubtree(
              key: ValueKey<int>(_usart1SubPage),
              child: switch (_usart1SubPage) {
                0 => _buildUsart1ParamsPage(controller),
                1 => _buildUsart1StatusPage(controller),
                _ => _buildUsart1LogsPage(controller),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsart1StatusPill(HmiController controller) {
    final connected = controller.isConnectedB;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: connected ? const Color(0xFF103B35) : const Color(0xFF3A1E24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: connected ? const Color(0xFF3DBE9F) : const Color(0xFFB85A66),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            connected ? Icons.link : Icons.link_off,
            color: connected
                ? const Color(0xFF9AF9D3)
                : const Color(0xFFFFA8A8),
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            connected ? '已连接' : '未连接',
            style: GoogleFonts.ibmPlexSans(
              color: connected
                  ? const Color(0xFF9AF9D3)
                  : const Color(0xFFFFA8A8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsart1SubPageBar() {
    const pages = <({IconData icon, String label, String hint})>[
      (icon: Icons.tune, label: '参数调节', hint: '读写 / 批量 / EEPROM'),
      (icon: Icons.monitor_heart_outlined, label: '系统状态', hint: '状态 / 运行 / 报警'),
      (icon: Icons.terminal, label: '日志监控', hint: 'LOG_PUSH / 会话帧'),
    ];

    return LayoutBuilder(
      builder: (_, constraints) {
        final compact = constraints.maxWidth < 760;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (var i = 0; i < pages.length; i++)
              InkWell(
                onTap: () => setState(() => _usart1SubPage = i),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: compact ? constraints.maxWidth : 220,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _usart1SubPage == i
                        ? const Color(0xFF173447)
                        : const Color(0xFF091D2E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _usart1SubPage == i
                          ? const Color(0xFF54D6C6)
                          : const Color(0xFF24425D),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        pages[i].icon,
                        color: _usart1SubPage == i
                            ? const Color(0xFF54D6C6)
                            : const Color(0xFF7CA5B8),
                        size: 18,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              pages[i].label,
                              style: GoogleFonts.ibmPlexSans(
                                color: const Color(0xFFE0EEFF),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              pages[i].hint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.ibmPlexSans(
                                color: const Color(0xFF7CA5B8),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildUsart1SectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Row(
      children: <Widget>[
        Icon(icon, color: const Color(0xFF54D6C6), size: 17),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: GoogleFonts.ibmPlexSans(
                  color: const Color(0xFFE0EEFF),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.ibmPlexSans(
                  color: const Color(0xFF8FB6C8),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
  }

  Widget _buildUsart1ParamsPage(HmiController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF102744),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2D4F7E)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildUsart1SectionHeader(
                icon: Icons.tune,
                title: '参数调节',
                subtitle: '通过 USART1 HMI Session 动态加载目录并批量读写运行时参数',
                trailing: _miniBtn(
                  '重新同步',
                  !controller.sessionSyncInProgress,
                  () => controller.syncSessionCatalog(),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '状态: ${controller.sessionState.name}  分组 ${controller.sessionGroups.length}  参数 ${controller.sessionParams.length}',
                style: GoogleFonts.ibmPlexMono(
                  color: const Color(0xFF9DC1EB),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (_, constraints) {
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _opBtn(
                        '读取全部',
                        _paramsLoading,
                        () => _readAllParams(controller),
                      ),
                      _opBtn('保存EEPROM', false, () => _saveParams(controller)),
                      _opBtn(
                        '加载EEPROM',
                        false,
                        () => _loadParams(controller, 0),
                      ),
                      _opBtn('恢复默认', false, () => _loadParams(controller, 1)),
                    ],
                  );
                },
              ),
              if (_paramsStatus.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _paramsStatus,
                  style: GoogleFonts.ibmPlexSans(
                    color: const Color(0xFF9DC1EB),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(height: 640, child: _buildSettingsPage(controller)),
      ],
    );
  }

  Widget _buildUsart1StatusPage(HmiController controller) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF102744),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2D4F7E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildUsart1SectionHeader(
            icon: Icons.monitor_heart_outlined,
            title: '系统状态',
            subtitle: '按需读取 VP 0x1000~0x1003 聚合状态',
            trailing: _miniBtn(
              '读取状态',
              _sysInfoLoading == false,
              () => _dbusSysInfo(controller),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (_, constraints) {
              final data = _sysInfoData;
              final compact = constraints.maxWidth < 620;
              final badges = <Widget>[
                _buildStatusTile(
                  label: '状态',
                  value: data == null ? '--' : '0x${toHex2(data[0])}',
                  color: const Color(0xFF5ED0FF),
                ),
                _buildStatusTile(
                  label: '运行',
                  value: data == null ? '--' : '${data[1]}',
                  color: data != null && data[1] == 1
                      ? const Color(0xFFFFE082)
                      : const Color(0xFF90A4AE),
                ),
                _buildStatusTile(
                  label: '自检',
                  value: data == null ? '--' : '${data[2]}',
                  color: data != null && data[2] == 1
                      ? const Color(0xFF9FFFC9)
                      : const Color(0xFFFFE082),
                ),
                _buildStatusTile(
                  label: '报警',
                  value: data == null ? '--' : '0x${toHex2(data[3])}',
                  color: data != null && data[3] != 0
                      ? const Color(0xFFFF6B6B)
                      : const Color(0xFF90A4AE),
                ),
              ];
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: badges
                    .map(
                      (widget) => SizedBox(
                        width: compact
                            ? (constraints.maxWidth - 10) / 2
                            : (constraints.maxWidth - 30) / 4,
                        child: widget,
                      ),
                    )
                    .toList(),
              );
            },
          ),
          if (_sysInfoStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _sysInfoStatus,
                style: GoogleFonts.ibmPlexMono(
                  color: _sysInfoData != null
                      ? const Color(0xFF9FFFC9)
                      : const Color(0xFFFFE082),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ────────────── USART1 Session 控制命令快捷面板 ──────────────

  Widget _buildUsart1ControlPanel(HmiController controller) {
    final connected = controller.isConnectedB;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF102744),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2D4F7E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildUsart1SectionHeader(
            icon: Icons.gamepad_outlined,
            title: '快捷控制',
            subtitle: '通过 Session 协议透传 20B 控制命令',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _miniBtn(
                '启动',
                connected,
                () => controller.sessionControlRunState(1),
              ),
              _miniBtn(
                '停机',
                connected,
                () => controller.sessionControlRunState(0),
              ),
              _miniBtn('出袋', connected, () => controller.sessionTriggerBag()),
              _miniBtn('封口', connected, () => controller.sessionTriggerSeal()),
              _miniBtn(
                '投料',
                connected,
                () => controller.sessionTriggerDeliver(),
              ),
              _miniBtn('清标志', connected, () => controller.sessionClearFlag(1)),
              _miniBtn('复位', connected, () => controller.sessionResetFault(0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTile({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF081D31),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF264762)),
      ),
      child: _sysInfoBadge(label, value, color),
    );
  }

  Widget _buildUsart1LogsPage(HmiController controller) {
    final portBLogs = controller.logs
        .where((e) => e.portLabel.contains('端口 B'))
        .toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF102744),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2D4F7E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildUsart1SectionHeader(
            icon: Icons.terminal,
            title: '日志监控',
            subtitle: '只显示端口 B 的 USART1 Session 日志与会话帧',
            trailing: Text(
              '${portBLogs.length} 条',
              style: GoogleFonts.ibmPlexMono(
                color: const Color(0xFF8FB6C8),
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: (MediaQuery.of(context).size.height * 0.48)
                .clamp(260, 620)
                .toDouble(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF071625),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF254963)),
              ),
              child: portBLogs.isEmpty
                  ? Center(
                      child: Text(
                        '等待端口 B 日志数据...',
                        style: GoogleFonts.ibmPlexSans(
                          color: const Color(0xFFA7C7EB),
                          fontSize: 12,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: portBLogs.length,
                      itemBuilder: (_, i) {
                        final item = portBLogs[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: SelectableText(
                            item.pretty,
                            style: GoogleFonts.ibmPlexMono(
                              color: item.direction == 'TX'
                                  ? const Color(0xFFFFE082)
                                  : item.direction == 'LOG'
                                  ? const Color(0xFF90A4AE)
                                  : const Color(0xFF9FFFC9),
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建日志纯文本。
  String _buildLogText(HmiController controller) {
    final buffer = StringBuffer();
    buffer.writeln('=== HMI 协议日志 ===');
    buffer.writeln('导出时间: ${DateTime.now()}');
    buffer.writeln('共 ${controller.logs.length} 条');
    buffer.writeln('');
    for (final log in controller.logs) {
      buffer.writeln(log.pretty);
    }
    return buffer.toString();
  }

  /// 复制全部日志到剪贴板。
  Future<void> _copyAllLogs(HmiController controller) async {
    final text = _buildLogText(controller);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('日志已复制到剪贴板'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// 导出日志到文件（PC/Android 保存到文件，Web 回退到剪贴板）。
  Future<void> _exportLogs(HmiController controller) async {
    try {
      final manifest = await controller.prepareLogBundleManifest();
      final sourceFiles = <LogBundleSourceFile>[
        if (manifest.rollingLogPath != null &&
            manifest.rollingLogPath!.isNotEmpty)
          LogBundleSourceFile(
            archiveName: 'raw/hmi_live_log.jsonl',
            path: manifest.rollingLogPath!,
          ),
        if (manifest.rollingStackLogPath != null &&
            manifest.rollingStackLogPath!.isNotEmpty)
          LogBundleSourceFile(
            archiveName: 'raw/hmi_stack_stats.jsonl',
            path: manifest.rollingStackLogPath!,
          ),
      ];
      final path = await exportLogBundle(
        bundleBaseName: 'hmi_logs',
        textFiles: <LogBundleTextFile>[
          LogBundleTextFile(
            name: 'protocol_logs.txt',
            content: _buildLogText(controller),
          ),
        ],
        sourceFiles: sourceFiles,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('日志已导出: $path'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } on LogExportCancelledException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已取消导出'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on UnsupportedError {
      final text = _buildLogText(controller);
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Web 平台: 日志内容已复制到剪贴板'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      final text = _buildLogText(controller);
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('日志打包保存失败 ($e)，内容已复制到剪贴板'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// 清空日志前确认对话框。
  Future<void> _confirmClearLogs(HmiController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有协议日志吗？此操作不可撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      controller.clearLogs();
    }
  }

  /// DGUS 读取系统信息 (VP 0x1000~0x1003)
  Future<void> _dbusSysInfo(HmiController controller) async {
    final nodeAddr = _safeHex(_packerNodeAddr.text, fallback: 0xFA);
    setState(() {
      _sysInfoLoading = true;
      _sysInfoStatus = '读取 DGUS 系统信息...';
    });
    final data = await controller.sendDgusSystemInfo(
      nodeAddress: nodeAddr,
      usePortB: _dgusUsePortB,
    );
    if (!mounted) return;
    if (data != null) {
      final running = data[1];
      final bootDone = data[2];
      setState(() {
        _sysInfoData = data;
        _sysInfoLoading = false;
        _sysInfoStatus = running == 1
            ? '机器运行中 — DGUS 参数调节被门禁锁定'
            : bootDone == 1
            ? '空闲停机 — DGUS 参数调节允许'
            : '自检中 — DGUS 参数调节被门禁锁定';
      });
    } else {
      setState(() {
        _sysInfoData = null;
        _sysInfoLoading = false;
        _sysInfoStatus = '读取失败（门禁锁定或串口未连通）';
      });
    }
  }

  /// ── 实时协议日志面板 ──
  Widget _buildLiveLogPanel(HmiController controller) {
    final hasLogs = controller.logs.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF233A62)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.receipt_long,
                color: Color(0xFF5ED0FF),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                '实时协议日志',
                style: GoogleFonts.ibmPlexSans(
                  color: const Color(0xFFE0EEFF),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                hasLogs ? '共 ${controller.logs.length} 条' : '',
                style: GoogleFonts.ibmPlexMono(
                  color: const Color(0xFFA7C7EB),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              _buildDropdown(
                value: _logDisplayMode,
                items: const <int>[0, 1, 2],
                labels: const <String>['HEX', '文本', 'HEX+文本'],
                onChanged: (v) => setState(() => _logDisplayMode = v ?? 2),
              ),
              const SizedBox(width: 4),
              _buildMiniToolButton(
                icon: _logsPaused ? Icons.play_arrow : Icons.pause,
                label: _logsPaused ? '继续' : '暂停',
                enabled: true,
                onPressed: () => setState(() => _logsPaused = !_logsPaused),
              ),
              const SizedBox(width: 4),
              _buildMiniToolButton(
                icon: Icons.copy_all,
                label: '复制',
                enabled: hasLogs,
                onPressed: () => _copyAllLogs(controller),
              ),
              const SizedBox(width: 4),
              _buildMiniToolButton(
                icon: Icons.cleaning_services_outlined,
                label: '清空',
                enabled: hasLogs,
                onPressed: () => _confirmClearLogs(controller),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: (MediaQuery.of(context).size.height * 0.2)
                .clamp(100, 350)
                .toDouble(),
            width: double.infinity,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF08152A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2D4F7E)),
              ),
              child: !hasLogs
                  ? Center(
                      child: Text(
                        '暂无日志 — 连接串口后操作将在此显示',
                        style: GoogleFonts.ibmPlexSans(
                          color: const Color(0xFFA7C7EB),
                          fontSize: 12,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _logsPaused
                          ? controller.logs.take(300).length
                          : controller.logs.length,
                      itemBuilder: (_, i) {
                        final item = controller.logs[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: SelectableText(
                            _formatLogForDisplay(item),
                            style: GoogleFonts.ibmPlexMono(
                              color: item.direction == 'TX'
                                  ? const Color(0xFFFFE082)
                                  : item.direction == 'LOG'
                                  ? const Color(0xFF90A4AE)
                                  : const Color(0xFF9FFFC9),
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatLogForDisplay(HmiLogEntry item) {
    final time =
        '${item.timestamp.hour.toString().padLeft(2, '0')}:'
        '${item.timestamp.minute.toString().padLeft(2, '0')}:'
        '${item.timestamp.second.toString().padLeft(2, '0')}.'
        '${item.timestamp.millisecond.toString().padLeft(3, '0')}';
    final prefix = '$time ${item.portLabel} ${item.direction}';
    final hex = item.decoded.rawDataHex.isNotEmpty
        ? item.decoded.rawDataHex
        : item.frame.encode().map((e) => toHex2(e)).join(' ');
    final text = item.decoded.summary;
    if (_logDisplayMode == 0) return '$prefix  $hex';
    if (_logDisplayMode == 1) return '$prefix  $text';
    return '$prefix  $hex\n$text';
  }

  // (removed unused _buildPortPanel)
  Widget _buildSettingsPage(HmiController controller) {
    final params = controller.sessionCatalogByGroup;

    return Container(
      color: const Color(0xFF08152A),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          for (final group in params.entries) ...[
            _buildParamGroup(controller, group.key, group.value),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  /// 操作按钮 (带 loading 状态)
  Widget _opBtn(String label, bool loading, VoidCallback? onPressed) {
    return SizedBox(
      height: 36,
      child: ElevatedButton(
        onPressed: (loading || onPressed == null) ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF14345A),
          foregroundColor: const Color(0xFFD6E9FF),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFF2C4F79)),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                label,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }

  /// 参数分组折叠面板
  Widget _buildParamGroup(
    HmiController controller,
    HmiSessionGroupDef group,
    List<HmiSessionParamDef> params,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF233A62)),
      ),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          initiallyExpanded: params.length <= 6,
          title: Text(
            '${group.groupName} (${params.length}项)',
            style: GoogleFonts.ibmPlexSans(
              color: const Color(0xFF5ED0FF),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: <Widget>[
            for (final p in params) _buildParamRow(controller, p),
          ],
        ),
      ),
    );
  }

  /// 格式化大整数（加千分位逗号）
  static String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// 参数范围指示
  Widget _paramRange(HmiSessionParamDef p) {
    return Text(
      '${_fmt(p.min)} ~ ${_fmt(p.max)}${p.unit.isNotEmpty ? ' ${p.unit}' : ''}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.ibmPlexMono(
        color: const Color(0xFF4A6A8A),
        fontSize: 11,
      ),
    );
  }

  /// 单个参数行
  Widget _buildParamRow(HmiController controller, HmiSessionParamDef param) {
    final value =
        controller.sessionParamValues[param.id] ?? _paramValues[param.id];
    final editor = _paramEditors.putIfAbsent(
      param.id,
      () => TextEditingController(text: value?.toString() ?? ''),
    );
    final raw = value?.toString() ?? '?';
    final inRange = value != null && value >= param.min && value <= param.max;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final compact = constraints.maxWidth < 500;
          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _paramLabel(param),
                    _paramRange(param),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        Expanded(child: _paramCurValue(raw, param)),
                        const SizedBox(width: 6),
                        if (!param.isReadOnly)
                          SizedBox(
                            width: 80,
                            child: _paramField(editor, inRange),
                          ),
                        const SizedBox(width: 4),
                        _writeBtn(controller, param, editor),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: <Widget>[
                    SizedBox(width: 130, child: _paramLabel(param)),
                    const SizedBox(width: 6),
                    SizedBox(width: 100, child: _paramRange(param)),
                    const SizedBox(width: 6),
                    SizedBox(width: 80, child: _paramCurValue(raw, param)),
                    if (!param.isReadOnly) ...[
                      const SizedBox(width: 6),
                      SizedBox(width: 80, child: _paramField(editor, inRange)),
                      const SizedBox(width: 4),
                    ],
                    _writeBtn(controller, param, editor),
                    const SizedBox(width: 4),
                    _readBtn(controller, param.id),
                  ],
                );
        },
      ),
    );
  }

  Widget _paramLabel(HmiSessionParamDef p) {
    return Text(
      '${p.name} (0x${toHex2(p.id)})',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.ibmPlexSans(
        color: const Color(0xFFD6E9FF),
        fontSize: 13,
      ),
    );
  }

  Widget _paramCurValue(String raw, HmiSessionParamDef p) {
    return Text(
      raw + (p.unit.isNotEmpty ? ' ${p.unit}' : ''),
      style: GoogleFonts.ibmPlexMono(
        color: const Color(0xFF9EC7FF),
        fontSize: 12,
      ),
    );
  }

  Widget _paramField(TextEditingController editor, bool inRange) {
    return TextField(
      controller: editor,
      smartQuotesType: SmartQuotesType.disabled,
      smartDashesType: SmartDashesType.disabled,
      style: GoogleFonts.ibmPlexMono(
        color: inRange ? const Color(0xFFD6E9FF) : const Color(0xFFFF9595),
        fontSize: 12,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: inRange ? const Color(0xFF2C4F79) : const Color(0xFF9F2D2D),
          ),
        ),
        errorText: inRange ? null : '越界',
        errorStyle: const TextStyle(fontSize: 9),
      ),
    );
  }

  Widget _writeBtn(
    HmiController controller,
    HmiSessionParamDef param,
    TextEditingController editor,
  ) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: param.isReadOnly
            ? null
            : () => _writeParam(controller, param, editor),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A3A5C),
          foregroundColor: const Color(0xFFD6E9FF),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(
          param.isReadOnly ? '只读' : '写入',
          style: GoogleFonts.ibmPlexSans(fontSize: 11),
        ),
      ),
    );
  }

  Widget _readBtn(HmiController controller, int paramId) {
    return SizedBox(
      height: 32,
      width: 32,
      child: IconButton(
        icon: const Icon(Icons.refresh, size: 16),
        tooltip: '读取参数当前值',
        color: const Color(0xFF5ED0FF),
        padding: EdgeInsets.zero,
        onPressed: () => _readParam(controller, paramId),
      ),
    );
  }

  /// 读取单个参数
  Future<void> _readParam(HmiController controller, int paramId) async {
    final value = await controller.sendParamRead(
      nodeAddress: 0xFA,
      paramId: paramId,
    );
    if (!mounted) return;
    if (value != null) {
      setState(() {
        _paramValues[paramId] = value;
        _paramEditors[paramId]?.text = value.toString();
        _paramsStatus = '参数 0x${toHex2(paramId)} 读取成功 → $value';
      });
    } else {
      setState(
        () => _paramsStatus = _formatDgusParamFailure(
          controller,
          '参数 0x${toHex2(paramId)} 读取失败',
        ),
      );
    }
  }

  /// 写入单个参数
  Future<void> _writeParam(
    HmiController controller,
    HmiSessionParamDef param,
    TextEditingController editor,
  ) async {
    final text = editor.text.trim();
    final v = int.tryParse(text);
    if (v == null) {
      setState(() => _paramsStatus = '${param.name}: 无效数值');
      return;
    }
    if (v < param.min || v > param.max) {
      setState(
        () => _paramsStatus = '${param.name}: 越界 (${param.min}~${param.max})',
      );
      return;
    }
    final result = await controller.sendParamWrite(
      nodeAddress: 0xFA,
      paramId: param.id,
      value: v,
    );
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _paramValues[param.id] = result;
        _paramsStatus = '${param.name}: 写入成功 → $result ${param.unit}';
      });
    } else {
      setState(
        () => _paramsStatus = _formatDgusParamFailure(
          controller,
          '${param.name}: 写入失败',
        ),
      );
    }
  }

  String _formatDgusParamFailure(HmiController controller, String prefix) {
    final detail = controller.statusMessage?.trim();
    if (detail == null || detail.isEmpty) {
      return '$prefix（可能为门禁锁定、串口未连通或超时）';
    }
    if (detail.contains('超时')) {
      return '$prefix（$detail，可能为门禁锁定或串口未连通）';
    }
    return '$prefix（$detail）';
  }

  /// 批量读取全部参数
  Future<void> _readAllParams(HmiController controller) async {
    try {
      await controller.readAllSessionParams();
      final count = controller.sessionParamValues.length;
      final total = controller.sessionParams.length;
      if (mounted) {
        setState(() {
          _paramsLoading = false;
          _paramsStatus = total > 0 ? '读取完成: $count/$total 个参数' : '读取完成: 无参数';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _paramsLoading = false;
          _paramsStatus = '读取失败: $e';
        });
      }
    }
  }

  /// 保存到 EEPROM
  Future<void> _saveParams(HmiController controller) async {
    final ok = await controller.sendParamSave(nodeAddress: 0xFA);
    if (mounted) {
      setState(() => _paramsStatus = ok ? '已保存到 EEPROM' : '保存失败');
    }
  }

  /// 加载/恢复参数
  Future<void> _loadParams(HmiController controller, int action) async {
    // 恢复默认值需要确认
    if (action == 1) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认恢复默认'),
          content: const Text('确定要恢复打包机所有运行时参数为默认值吗？参数修改将丢失。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final ok = await controller.sendParamLoad(
      nodeAddress: 0xFA,
      action: action,
    );
    if (mounted) {
      setState(
        () => _paramsStatus = action == 0
            ? (ok ? '已从 EEPROM 加载' : '加载失败')
            : (ok ? '已恢复默认值，请重新读取参数' : '恢复失败'),
      );
      if (ok) {
        _readAllParams(controller);
      }
    }
  }

  Widget _buildFrameDebuggerPage(HmiController controller) {
    return Container(
      color: const Color(0xFF08152A),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _buildCard(
            title: '帧调试台（原始帧）',
            child: Column(
              children: <Widget>[
                _buildRowFields(<Widget>[
                  _textField('地址(HEX)', _rawAddr),
                  _textField('功能码(HEX)', _rawFunc),
                ]),
                const SizedBox(height: 10),
                _textField('Payload HEX（空格分隔，最多16字节）', _rawPayload),
                const SizedBox(height: 10),
                _textField('期望响应功能码 HEX（逗号分隔）', _rawExpected),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    _buildOpButton(
                      label: '发送调试帧',
                      onPressed: controller.isConnected
                          ? () => _runCommand(
                              () => controller.sendCustomFrame(
                                address: _safeHex(
                                  _rawAddr.text,
                                  fallback: 0xAF,
                                ),
                                functionCode: _safeHex(
                                  _rawFunc.text,
                                  fallback: 0x09,
                                ),
                                payload: _parseHexBytes(_rawPayload.text),
                                expectedFunctions: _parseHexSet(
                                  _rawExpected.text,
                                ),
                                note: '帧调试台',
                              ),
                              '调试帧发送完成',
                            )
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsPage(HmiController controller) {
    final hasLogs = controller.logs.isNotEmpty;
    return Container(
      color: const Color(0xFF08152A),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            _buildCardHeader(
              title: '协议日志',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _buildMiniToolButton(
                    icon: Icons.copy_all,
                    label: '复制',
                    enabled: hasLogs,
                    onPressed: () => _copyAllLogs(controller),
                  ),
                  const SizedBox(width: 6),
                  _buildMiniToolButton(
                    icon: Icons.file_download_outlined,
                    label: '导出',
                    enabled: hasLogs,
                    onPressed: () => _exportLogs(controller),
                  ),
                  const SizedBox(width: 6),
                  _buildMiniToolButton(
                    icon: Icons.cleaning_services_outlined,
                    label: '清空',
                    enabled: hasLogs,
                    onPressed: () => _confirmClearLogs(controller),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1E3A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2D4F7E)),
                ),
                child: !hasLogs
                    ? Center(
                        child: Text(
                          '暂无日志',
                          style: GoogleFonts.ibmPlexSans(
                            color: const Color(0xFFA7C7EB),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: controller.logs.length,
                        itemBuilder: (_, i) {
                          final item = controller.logs[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: SelectableText(
                              item.pretty,
                              style: GoogleFonts.ibmPlexMono(
                                color: item.direction == 'TX'
                                    ? const Color(0xFFFFE082)
                                    : item.direction == 'LOG'
                                    ? const Color(0xFF90A4AE)
                                    : const Color(0xFF9FFFC9),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStackLevelPage(HmiController controller) {
    final samples = controller.stackLevelSamples;
    final snapshot = controller.latestStackSnapshot;
    final taskStats = controller.stackTaskStats.values.toList();
    final maxPoints = _safeInt(_stackChartPoints, fallback: 120).clamp(10, 600);
    final points = samples.take(maxPoints).toList().reversed.toList();
    final levels = points.map((e) => e.level).toList();
    final current = levels.isEmpty ? 0 : levels.last;
    final minLevel = levels.isEmpty ? 0 : levels.reduce(math.min);
    final maxLevel = levels.isEmpty ? 0 : levels.reduce(math.max);
    final avg = levels.isEmpty
        ? 0
        : (levels.reduce((a, b) => a + b) / levels.length).toStringAsFixed(1);

    return Container(
      color: const Color(0xFF08152A),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _buildCard(
            title: '任务栈统计总览',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _miniBtn('清空样本', true, controller.clearStackLevelSamples),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    SizedBox(
                      width: 220,
                      child: _stackMetric(
                        '总栈',
                        '${snapshot?.summary.totalWords ?? 0}',
                        const Color(0xFF9EC7FF),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: _stackMetric(
                        '当前总已占用',
                        '${snapshot?.summary.totalUsedWords ?? 0}',
                        const Color(0xFFFFC978),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: _stackMetric(
                        '当前总剩余',
                        '${snapshot?.summary.totalFreeWords ?? 0}',
                        const Color(0xFF9FFFC9),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: _stackMetric(
                        '最危险任务',
                        snapshot?.summary.riskiestTaskName ?? '-',
                        const Color(0xFFFF8A80),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                taskStats.isEmpty
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1E3A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2D4F7E)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(
                              Icons.terminal,
                              color: Color(0xFF54D6C6),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '暂无完整任务栈快照。新协议下，任务栈快照从 USART1 Session 日志解析：'
                                '收到 LOG_PUSH 中的 STACK_SNAPSHOT_BEGIN / STACK_TASK / '
                                'STACK_SNAPSHOT_END 后会自动刷新。',
                                style: GoogleFonts.ibmPlexSans(
                                  color: const Color(0xFFA7C7EB),
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : _buildStackStatsTable(
                        taskStats,
                        snapshot?.summary.riskiestTaskName,
                      ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildCard(
            title: '最小剩余栈辅助趋势',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 110,
                      child: _textField('显示点数', _stackChartPoints),
                    ),
                    SizedBox(
                      width: 180,
                      child: _stackMetric(
                        '样本数',
                        '${samples.length}',
                        const Color(0xFF9EC7FF),
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: _stackMetric(
                        '当前值',
                        '$current',
                        const Color(0xFF9FFFC9),
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: _stackMetric(
                        '最小/最大',
                        '$minLevel / $maxLevel',
                        const Color(0xFFFFE082),
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: _stackMetric(
                        '平均值',
                        '$avg',
                        const Color(0xFF8ED3FF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 260,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1E3A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2D4F7E)),
                    ),
                    child: points.length < 2
                        ? Center(
                            child: Text(
                              '样本不足，请先采集至少 2 个点',
                              style: GoogleFonts.ibmPlexSans(
                                color: const Color(0xFFA7C7EB),
                                fontSize: 12,
                              ),
                            ),
                          )
                        : CustomPaint(painter: _StackLevelChartPainter(points)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStackStatsTable(
    List<StackTaskStats> taskStats,
    String? riskiestTaskName,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0B1E3A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2D4F7E)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF102744)),
          dataRowMinHeight: 48,
          dataRowMaxHeight: 64,
          columns: const <DataColumn>[
            DataColumn(label: Text('任务名')),
            DataColumn(label: Text('总栈')),
            DataColumn(label: Text('当前剩余')),
            DataColumn(label: Text('当前已占用')),
            DataColumn(label: Text('占用率')),
            DataColumn(label: Text('历史最小剩余')),
            DataColumn(label: Text('历史最大占用')),
            DataColumn(label: Text('更新时间')),
          ],
          rows: taskStats.map<DataRow>((StackTaskStats stat) {
            final isRisk = stat.name == riskiestTaskName;
            final nameColor = isRisk
                ? const Color(0xFFFF8A80)
                : const Color(0xFFE6F2FF);
            final valueColor = stat.freeWords <= 200
                ? const Color(0xFFFFB74D)
                : const Color(0xFF9FFFC9);
            return DataRow(
              color: WidgetStateProperty.all(
                isRisk ? const Color(0x221B91D8) : Colors.transparent,
              ),
              cells: <DataCell>[
                DataCell(
                  Text(
                    stat.name,
                    style: GoogleFonts.ibmPlexSans(
                      color: nameColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                DataCell(
                  _monoCell('${stat.totalWords}', const Color(0xFF9EC7FF)),
                ),
                DataCell(_monoCell('${stat.freeWords}', valueColor)),
                DataCell(
                  _monoCell('${stat.usedWords}', const Color(0xFFFFE082)),
                ),
                DataCell(
                  _monoCell(
                    '${(stat.usedRatio * 100.0).toStringAsFixed(1)}%',
                    isRisk ? const Color(0xFFFF8A80) : const Color(0xFF8ED3FF),
                  ),
                ),
                DataCell(
                  _monoCell('${stat.minFreeWords}', const Color(0xFF90CAF9)),
                ),
                DataCell(
                  _monoCell('${stat.maxUsedWords}', const Color(0xFFFFCC80)),
                ),
                DataCell(
                  Text(
                    _formatTime(stat.updatedAt),
                    style: GoogleFonts.ibmPlexMono(
                      color: const Color(0xFFA7C7EB),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _monoCell(String value, Color color) {
    return Text(
      value,
      style: GoogleFonts.ibmPlexMono(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  String _formatTime(DateTime value) {
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    final ss = value.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  Widget _stackMetric(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF233A62)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              color: const Color(0xFFA7C7EB),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.ibmPlexMono(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// 工具栏迷你按钮（复制/导出/清空 等）。
  Widget _buildMiniToolButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 24,
      child: TextButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 10)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: const Color(0xFF8ED3FF),
          disabledForegroundColor: const Color(0xFF4A6A8A),
        ),
      ),
    );
  }

  Widget _buildOpButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF1B91D8),
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFF445E78),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  Widget _buildCard({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF102744),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF274E7A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildCardHeader(title: title, trailing: trailing),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildCardHeader({required String title, Widget? trailing}) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.ibmPlexSans(
              color: const Color(0xFFE0EEFF),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        trailing ?? const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildRowFields(List<Widget> fields) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final compact = constraints.maxWidth < 1000;
        if (compact) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: fields
                .map((e) => SizedBox(width: constraints.maxWidth, child: e))
                .toList(),
          );
        }
        return Row(
          children: fields
              .map(
                (w) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: w,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _textField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      smartQuotesType: SmartQuotesType.disabled,
      smartDashesType: SmartDashesType.disabled,
      style: const TextStyle(color: Color(0xFFE6F2FF)),
      decoration: _inputDecoration(label),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFFA6C5EA)),
      filled: true,
      fillColor: const Color(0xFF0A1D36),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF2A4F79)),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF52B3FF)),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _StackLevelChartPainter extends CustomPainter {
  _StackLevelChartPainter(this.points);

  final List<StackLevelSample> points;

  @override
  void paint(Canvas canvas, Size size) {
    const padding = EdgeInsets.fromLTRB(36, 16, 16, 28);
    final chartRect = Rect.fromLTWH(
      padding.left,
      padding.top,
      size.width - padding.horizontal,
      size.height - padding.vertical,
    );
    if (chartRect.width <= 0 || chartRect.height <= 0 || points.length < 2) {
      return;
    }

    final levels = points.map((e) => e.level).toList();
    final minLevel = levels.reduce(math.min).toDouble();
    final maxLevel = levels.reduce(math.max).toDouble();
    final span = (maxLevel - minLevel).abs() < 0.001
        ? 1.0
        : (maxLevel - minLevel);

    final axisPaint = Paint()
      ..color = const Color(0xFF2D4F7E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(chartRect, axisPaint);

    final gridPaint = Paint()
      ..color = const Color(0x332D4F7E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = chartRect.top + chartRect.height * i / 4;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = chartRect.left + chartRect.width * i / (points.length - 1);
      final norm = (points[i].level - minLevel) / span;
      final y = chartRect.bottom - norm * chartRect.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = const Color(0xFF5ED0FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _StackLevelChartPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
