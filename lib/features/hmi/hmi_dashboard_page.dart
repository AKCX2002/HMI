import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/protocol/crc_algorithm.dart';
import 'hmi_controller.dart';
import 'hmi_param_config.dart';
import 'hmi_protocol.dart';

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

  final TextEditingController _orderId = TextEditingController(text: '1');
  final TextEditingController _quantity = TextEditingController(text: '1');
  final TextEditingController _cabinetAddress = TextEditingController(
    text: '3',
  );
  final TextEditingController _layer = TextEditingController(text: '1');
  final TextEditingController _lane = TextEditingController(text: '5');

  final TextEditingController _sealOrderId = TextEditingController(text: '1');
  final TextEditingController _sealAction = TextEditingController(text: '1');

  final TextEditingController _storePackageId = TextEditingController(
    text: '1',
  );
  final TextEditingController _storeCabinetNo = TextEditingController(
    text: '1',
  );

  final TextEditingController _unlockOrderId = TextEditingController(text: '1');
  final TextEditingController _unlockCabinetNo = TextEditingController(
    text: '1',
  );

  final TextEditingController _statusQueryType = TextEditingController(
    text: '1',
  );

  final TextEditingController _testType = TextEditingController(text: '2');
  final TextEditingController _testTargetId = TextEditingController(text: '0');
  final TextEditingController _testAction = TextEditingController(text: '11');

  final TextEditingController _returnOrderId = TextEditingController(text: '1');
  final TextEditingController _returnCabinetNo = TextEditingController(
    text: '1',
  );

  final TextEditingController _packerNodeAddr = TextEditingController(
    text: 'FA',
  );

  /// 参数配置页状态
  final Map<int, TextEditingController> _paramEditors =
      <int, TextEditingController>{};
  final Map<int, int> _paramValues = <int, int>{};
  bool _paramsLoading = false;
  String _paramsStatus = '';

  final TextEditingController _packerAvoidAction = TextEditingController(
    text: '2',
  );
  final TextEditingController _packerClearFlag = TextEditingController(
    text: '1',
  );
  final TextEditingController _packerHostState = TextEditingController(
    text: '0',
  );
  final TextEditingController _packerResetScope = TextEditingController(
    text: '0',
  );

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

  /// DGUS 调节面板状态
  final TextEditingController _dbusParamId = TextEditingController(text: '10');
  final TextEditingController _dbusValue = TextEditingController(text: '0');
  final TextEditingController _dbusNodeAddr = TextEditingController(text: 'FA');
  String _dbusStatus = '';
  int? _dbusReadResult;

  /// DGUS 系统信息
  List<int>? _sysInfoData;
  String _sysInfoStatus = '';
  bool _sysInfoLoading = false;

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
    _orderId.dispose();
    _quantity.dispose();
    _cabinetAddress.dispose();
    _layer.dispose();
    _lane.dispose();
    _sealOrderId.dispose();
    _sealAction.dispose();
    _storePackageId.dispose();
    _storeCabinetNo.dispose();
    _unlockOrderId.dispose();
    _unlockCabinetNo.dispose();
    _statusQueryType.dispose();
    _testType.dispose();
    _testTargetId.dispose();
    _testAction.dispose();
    _returnOrderId.dispose();
    _returnCabinetNo.dispose();
    _packerNodeAddr.dispose();
    _packerAvoidAction.dispose();
    _packerClearFlag.dispose();
    _packerHostState.dispose();
    _packerResetScope.dispose();
    _retryCount.dispose();
    _timeoutMs.dispose();
    _retryIntervalMs.dispose();
    _rawAddr.dispose();
    _rawFunc.dispose();
    _rawPayload.dispose();
    _rawExpected.dispose();
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
    Future<CommandExecutionResult> Function() action,
    String successText,
  ) async {
    final result = await action();
    if (!mounted) {
      return;
    }
    final ok = result.success;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ok ? const Color(0xFF2E7D32) : const Color(0xFF9F2D2D),
        content: Text(
          ok ? '$successText（尝试${result.attempts}次）' : result.message,
        ),
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
    final menus = <String>['主控制台', '参数配置', '帧调试台', '协议日志'];
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
      (Icons.dashboard, '主控制台'),
      (Icons.tune, '参数配置'),
      (Icons.memory, '帧调试台'),
      (Icons.receipt_long, '协议日志'),
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
                                '左协议: USART3 / 20B',
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
                                '右协议: USART1 / DGUS(5A A5)',
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
                  '上位机控制台',
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
                  '上位机控制台',
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
      case 1:
        return _buildSettingsPage(controller);
      case 2:
        return _buildFrameDebuggerPage(controller);
      case 3:
        return _buildLogsPage(controller);
      case 0:
      default:
        return _buildMainDashboard(controller);
    }
  }

  /// ────────────── 主控制台：左右协议完整集成 ──────────────

  Widget _buildMainDashboard(HmiController controller) {
    return Container(
      color: const Color(0xFF08152A),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          // ═══ 双端口配置栏 ═══
          _buildDualPortBar(controller),
          const SizedBox(height: 12),
          // ═══ 左右协议面板 ═══
          LayoutBuilder(
            builder: (_, constraints) {
              final compact = constraints.maxWidth < 1000;
              if (compact) {
                return Column(
                  children: <Widget>[
                    _buildPortAPanel(controller),
                    const SizedBox(height: 12),
                    _buildPortBPanel(controller),
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: _buildPortAPanel(controller)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildPortBPanel(controller)),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // ═══ 实时协议日志 ═══
          _buildLiveLogPanel(controller),
        ],
      ),
    );
  }

  /// ── 双端口紧凑配置栏 ──
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
            crcAlgorithm: controller.portAConfig.crcAlgorithm,
            canEdit: !controller.isConnectedA,
            onPortChanged: (v) => controller.setPortA(v),
            onBaudRateChanged: (v) => controller.setBaudRateA(v),
            onCrcChanged: (v) => controller.setCrcAlgorithmA(v),
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
            crcAlgorithm: controller.portBConfig.crcAlgorithm,
            canEdit: !controller.isConnectedB,
            onPortChanged: (v) => controller.setPortB(v),
            onBaudRateChanged: (v) => controller.setBaudRateB(v),
            onCrcChanged: (v) => controller.setCrcAlgorithmB(v),
            onRefresh: controller.refreshPortsB,
            onConnect: controller.connectPortB,
            onDisconnect: controller.disconnectPortB,
          );
          if (compact) {
            return Column(
              children: <Widget>[portA, const SizedBox(height: 8), portB],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: portA),
              const SizedBox(width: 10),
              Expanded(child: portB),
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
    required CrcAlgorithm crcAlgorithm,
    required bool canEdit,
    required ValueChanged<String?> onPortChanged,
    required ValueChanged<int> onBaudRateChanged,
    required ValueChanged<CrcAlgorithm> onCrcChanged,
    required VoidCallback onRefresh,
    required VoidCallback onConnect,
    required VoidCallback onDisconnect,
  }) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final veryCompact = constraints.maxWidth < 420;
        final somewhatCompact = constraints.maxWidth < 580;

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
          decoration: _miniInputDeco('串口'),
          dropdownColor: const Color(0xFF122B4D),
          style: const TextStyle(color: Color(0xFFD7E8FF), fontSize: 11),
          isDense: true,
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
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: canEdit ? (v) => onPortChanged(v) : null,
        );

        final baudDropdown = DropdownButtonFormField<int>(
          initialValue: baudRate,
          decoration: _miniInputDeco('波特率'),
          dropdownColor: const Color(0xFF122B4D),
          style: const TextStyle(color: Color(0xFFD7E8FF), fontSize: 11),
          isDense: true,
          items: const <int>[9600, 14400, 19200, 38400, 57600, 115200]
              .map(
                (v) => DropdownMenuItem<int>(
                  value: v,
                  child: Text('$v', style: const TextStyle(fontSize: 11)),
                ),
              )
              .toList(),
          onChanged: canEdit ? (v) => onBaudRateChanged(v ?? 9600) : null,
        );

        final crcDropdown = DropdownButtonFormField<CrcAlgorithm>(
          initialValue: crcAlgorithm,
          decoration: _miniInputDeco('CRC'),
          dropdownColor: const Color(0xFF122B4D),
          style: const TextStyle(color: Color(0xFFD7E8FF), fontSize: 11),
          isDense: true,
          items: CrcAlgorithm.values
              .map(
                (a) => DropdownMenuItem<CrcAlgorithm>(
                  value: a,
                  child: Text(
                    a.displayName,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              )
              .toList(),
          onChanged: canEdit
              ? (CrcAlgorithm? v) => onCrcChanged(v ?? CrcAlgorithm.modbus)
              : null,
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
          // 三行：标签+按钮 / 串口+波特率 / CRC
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
              Row(
                children: <Widget>[
                  Expanded(flex: 3, child: portDropdown),
                  const SizedBox(width: 4),
                  Expanded(flex: 2, child: baudDropdown),
                ],
              ),
              const SizedBox(height: 4),
              Row(children: <Widget>[Expanded(child: crcDropdown)]),
            ],
          );
        } else if (somewhatCompact) {
          // 两行：标签+串口+波特率 / CRC+按钮
          return Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  labelWidget,
                  const SizedBox(width: 4),
                  Expanded(flex: 3, child: portDropdown),
                  const SizedBox(width: 4),
                  Expanded(flex: 2, child: baudDropdown),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Expanded(child: crcDropdown),
                  const SizedBox(width: 4),
                  scanBtn,
                  const SizedBox(width: 3),
                  connBtn,
                ],
              ),
            ],
          );
        } else {
          // 一行：标签 + 串口 + 波特率 + CRC + 按钮
          return Row(
            children: <Widget>[
              labelWidget,
              const SizedBox(width: 4),
              Expanded(flex: 3, child: portDropdown),
              const SizedBox(width: 4),
              Expanded(flex: 2, child: baudDropdown),
              const SizedBox(width: 4),
              Expanded(flex: 2, child: crcDropdown),
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
                '左协议 — USART3 / 20B 固定帧 / CRC16-Modbus',
                style: GoogleFonts.ibmPlexSans(
                  color: const Color(0xFFE0EEFF),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── 协议收敛说明 ──
          Text(
            '已收敛为打包机现行协议(0x40~0x4C)，旧业务协议入口已移除',
            style: GoogleFonts.ibmPlexSans(
              color: const Color(0xFFA6C5EA),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          // ── 主控参数输入行 ──
          LayoutBuilder(
            builder: (_, constraints) {
              final compact = constraints.maxWidth < 500;
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  SizedBox(
                    width: compact ? 60 : 70,
                    child: _numberField('订单号', _orderId),
                  ),
                  SizedBox(
                    width: compact ? 60 : 70,
                    child: _numberField('数量', _quantity),
                  ),
                  SizedBox(
                    width: compact ? 70 : 80,
                    child: _numberField('货柜地址', _cabinetAddress),
                  ),
                  SizedBox(
                    width: compact ? 50 : 60,
                    child: _numberField('货层', _layer),
                  ),
                  SizedBox(
                    width: compact ? 50 : 60,
                    child: _numberField('货道', _lane),
                  ),
                  SizedBox(
                    width: compact ? 60 : 70,
                    child: _numberField('封口订单', _sealOrderId),
                  ),
                  SizedBox(
                    width: compact ? 60 : 70,
                    child: _numberField('查询类型', _statusQueryType),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          // ── 分隔线 ──
          const Divider(color: Color(0xFF233A62), height: 1),
          const SizedBox(height: 12),
          // ── 打包机功能码 ──
          Row(
            children: <Widget>[
              Text(
                '打包机节点命令 (0x40~0x49)',
                style: GoogleFonts.ibmPlexSans(
                  color: const Color(0xFFA6C5EA),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 90,
                height: 30,
                child: TextField(
                  controller: _packerNodeAddr,
                  smartQuotesType: SmartQuotesType.disabled,
                  smartDashesType: SmartDashesType.disabled,
                  style: GoogleFonts.ibmPlexMono(
                    color: const Color(0xFFD6E9FF),
                    fontSize: 11,
                  ),
                  decoration: const InputDecoration(
                    labelText: '节点HEX',
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
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              _miniBtn(
                '0x40 启动',
                true,
                () => _runCommand(
                  () => controller.sendPackerControl(
                    nodeAddress: nodeAddr,
                    action: 1,
                  ),
                  '打包机启动',
                ),
              ),
              _miniBtn(
                '0x40 停止',
                true,
                () => _runCommand(
                  () => controller.sendPackerControl(
                    nodeAddress: nodeAddr,
                    action: 0,
                  ),
                  '打包机停止',
                ),
              ),
              _miniBtn(
                '0x41 状态',
                true,
                () => _runCommand(
                  () => controller.sendPackerStatus(nodeAddress: nodeAddr),
                  '状态查询',
                ),
              ),
              _miniBtn(
                '0x42 出袋',
                true,
                () => _runCommand(
                  () => controller.sendPackerTriggerBag(nodeAddress: nodeAddr),
                  '出袋触发',
                ),
              ),
              _miniBtn(
                '0x43 封口',
                true,
                () => _runCommand(
                  () => controller.sendPackerTriggerSeal(nodeAddress: nodeAddr),
                  '封口触发',
                ),
              ),
              _miniBtn(
                '0x44 投料',
                true,
                () => _runCommand(
                  () => controller.sendPackerTriggerDeliver(nodeAddress: nodeAddr),
                  '投料触发',
                ),
              ),
              _miniBtn(
                '0x45 清标',
                true,
                () => _runCommand(
                  () => controller.sendPackerClearFlag(
                    nodeAddress: nodeAddr,
                    flagId: 1,
                  ),
                  '清除标志',
                ),
              ),
              _miniBtn(
                '0x46 报警',
                true,
                () => _runCommand(
                  () => controller.sendPackerAlarmQuery(nodeAddress: nodeAddr),
                  '报警查询',
                ),
              ),
              _miniBtn(
                '0x47 打印',
                true,
                () => _runCommand(
                  () => controller.sendPackerPrinterForward(nodeAddress: nodeAddr),
                  '打印机透传',
                ),
              ),
              _miniBtn(
                '0x48 版本',
                true,
                () => _runCommand(
                  () => controller.sendPackerVersion(nodeAddress: nodeAddr),
                  '版本查询',
                ),
              ),
              _miniBtn(
                '0x49 复位',
                true,
                () => _runCommand(
                  () => controller.sendPackerResetFault(
                    nodeAddress: nodeAddr,
                    scope: 0,
                  ),
                  '故障复位',
                ),
              ),
            ],
          ),
        ],
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

  /// ── 端口 B 面板：右协议 (USART1 / 日志+DGUS调节) ──
  Widget _buildPortBPanel(HmiController controller) {
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
                Icons.developer_mode,
                color: Color(0xFF5ED0FF),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                '右协议 — USART1 / 日志+DGUS调节 / 5A A5',
                style: GoogleFonts.ibmPlexSans(
                  color: const Color(0xFFE0EEFF),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── DGUS 参数调节 ──
          Text(
            'DGUS 参数调节（通过 USART1 的 5A A5 帧读写参数）',
            style: GoogleFonts.ibmPlexSans(
              color: const Color(0xFFA6C5EA),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (_, constraints) {
              final compact = constraints.maxWidth < 450;
              return Wrap(
                spacing: 6,
                runSpacing: 8,
                children: <Widget>[
                  SizedBox(
                    width: compact ? 70 : 90,
                    child: _textField('参数ID(HEX)', _dbusParamId),
                  ),
                  SizedBox(
                    width: compact ? 80 : 120,
                    child: _numberField('值', _dbusValue),
                  ),
                  SizedBox(
                    width: compact ? 70 : 90,
                    child: _textField('节点HEX', _dbusNodeAddr),
                  ),
                  _miniBtn('读取', true, () => _dbusRead(controller)),
                  _miniBtn('写入', true, () => _dbusWrite(controller)),
                  _miniBtn('保存EEPROM', true, () => _dbusSave(controller)),
                ],
              );
            },
          ),
          if (_dbusStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _dbusStatus,
                style: GoogleFonts.ibmPlexMono(
                  color: _dbusReadResult != null
                      ? const Color(0xFF9FFFC9)
                      : const Color(0xFFFFE082),
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 12),
          // ── 分隔线 + 批量操作 ──
          const Divider(color: Color(0xFF233A62), height: 1),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              _miniBtn('批量读取前10项', true, () => _dbusBatchRead(controller, 10)),
              _miniBtn('批量读取全部', true, () => _dbusBatchRead(controller, 53)),
              _miniBtn('恢复默认值', true, () => _dbusLoadDefault(controller)),
            ],
          ),
          const SizedBox(height: 12),
          // ── 系统信息区 ──
          const Divider(color: Color(0xFF233A62), height: 1),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const Icon(Icons.info_outline, color: Color(0xFF5ED0FF), size: 16),
              const SizedBox(width: 6),
              Text(
                'DGUS 系统信息 (VP 0x1000~0x1003)',
                style: GoogleFonts.ibmPlexSans(
                  color: const Color(0xFFA6C5EA),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              _miniBtn('读取状态', _sysInfoLoading == false, () => _dbusSysInfo(controller)),
            ],
          ),
          const SizedBox(height: 6),
          if (_sysInfoData != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1E3A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2D4F7E)),
              ),
              child: Row(
                children: <Widget>[
                  _sysInfoBadge('状态', '0x${toHex2(_sysInfoData![0])}', const Color(0xFF5ED0FF)),
                  const SizedBox(width: 12),
                  _sysInfoBadge('运行', '${_sysInfoData![1]}', _sysInfoData![1] == 1 ? const Color(0xFFFFE082) : const Color(0xFF90A4AE)),
                  const SizedBox(width: 12),
                  _sysInfoBadge('自检', '${_sysInfoData![2]}', _sysInfoData![2] == 1 ? const Color(0xFF9FFFC9) : const Color(0xFFFFE082)),
                  const SizedBox(width: 12),
                  _sysInfoBadge('报警', '0x${toHex2(_sysInfoData![3])}', _sysInfoData![3] != 0 ? const Color(0xFFFF6B6B) : const Color(0xFF90A4AE)),
                ],
              ),
            ),
          if (_sysInfoStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
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
          const SizedBox(height: 12),
          // ── 日志接收区 ──
          const Divider(color: Color(0xFF233A62), height: 1),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const Icon(Icons.terminal, color: Color(0xFF5ED0FF), size: 16),
              const SizedBox(width: 6),
              Text(
                '端口 B 日志输出实时监控',
                style: GoogleFonts.ibmPlexSans(
                  color: const Color(0xFFA6C5EA),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1E3A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2D4F7E)),
              ),
            child:
                controller.logs
                    .where((e) => e.portLabel.contains('端口 B'))
                    .isEmpty
                ? Center(
                    child: Text(
                      '等待端口 B 日志数据\u2026',
                      style: GoogleFonts.ibmPlexSans(
                        color: const Color(0xFFA7C7EB),
                        fontSize: 12,
                      ),
                    ),
                  )
                : ListView(
                    children: controller.logs
                        .where((e) => e.portLabel.contains('端口 B'))
                        .take(15)
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              e.pretty,
                              style: GoogleFonts.ibmPlexMono(
                                color: e.direction == 'TX'
                                    ? const Color(0xFFFFE082)
                                    : e.direction == 'LOG'
                                        ? const Color(0xFF90A4AE)
                                        : const Color(0xFF9FFFC9),
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
              ),
            ),
        ],
      ),
    );
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

  /// DGUS 读取参数
  Future<void> _dbusRead(HmiController controller) async {
    final paramId = _safeHex(_dbusParamId.text, fallback: 0x10);
    final nodeAddr = _safeHex(_dbusNodeAddr.text, fallback: 0xFA);
    final result = await controller.sendParamRead(
      nodeAddress: nodeAddr,
      paramId: paramId,
    );
    if (!mounted) return;
    if (result != null) {
      _dbusReadResult = result;
      _dbusValue.text = result.toString();
      setState(() => _dbusStatus = '参数 0x${toHex2(paramId)} = $result');
    } else {
      setState(() {
        _dbusStatus = '参数 0x${toHex2(paramId)} 读取失败';
        _dbusReadResult = null;
      });
    }
  }

  /// DGUS 写入参数
  Future<void> _dbusWrite(HmiController controller) async {
    final paramId = _safeHex(_dbusParamId.text, fallback: 0x10);
    final value = _safeInt(_dbusValue, fallback: 0);
    final nodeAddr = _safeHex(_dbusNodeAddr.text, fallback: 0xFA);
    final result = await controller.sendParamWrite(
      nodeAddress: nodeAddr,
      paramId: paramId,
      value: value,
    );
    if (!mounted) return;
    if (result != null) {
      _dbusReadResult = result;
      setState(() => _dbusStatus = '写入成功: 参数 0x${toHex2(paramId)} = $result');
    } else {
      setState(() {
        _dbusStatus = '参数 0x${toHex2(paramId)} 写入失败';
        _dbusReadResult = null;
      });
    }
  }

  /// DGUS 保存 EEPROM
  Future<void> _dbusSave(HmiController controller) async {
    final nodeAddr = _safeHex(_dbusNodeAddr.text, fallback: 0xFA);
    final ok = await controller.sendParamSave(nodeAddress: nodeAddr);
    if (!mounted) return;
    setState(() => _dbusStatus = ok ? '已保存到 EEPROM' : '保存失败');
  }

  /// DGUS 批量读取
  Future<void> _dbusBatchRead(HmiController controller, int count) async {
    final allParams = kParamDefs.take(count).toList();
    final nodeAddr = _safeHex(_dbusNodeAddr.text, fallback: 0xFA);
    setState(() => _dbusStatus = '批量读取 ${allParams.length} 项...');
    int ok = 0;
    for (final p in allParams) {
      final result = await controller.sendParamRead(
        nodeAddress: nodeAddr,
        paramId: p.id,
      );
      if (result != null) {
        _paramValues[p.id] = result;
        _paramEditors[p.id]?.text = result.toString();
        ok++;
      }
    }
    if (!mounted) return;
    setState(() => _dbusStatus = '批量读取完成: $ok/${allParams.length} 项成功');
  }

  /// DGUS 恢复默认值
  Future<void> _dbusLoadDefault(HmiController controller) async {
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
    final nodeAddr = _safeHex(_dbusNodeAddr.text, fallback: 0xFA);
    final ok = await controller.sendParamLoad(nodeAddress: nodeAddr, action: 1);
    if (!mounted) return;
    setState(() => _dbusStatus = ok ? '已恢复默认值，请重新读取' : '恢复默认值失败');
  }

  /// DGUS 读取系统信息 (VP 0x1000~0x1003)
  Future<void> _dbusSysInfo(HmiController controller) async {
    final nodeAddr = _safeHex(_dbusNodeAddr.text, fallback: 0xFA);
    setState(() {
      _sysInfoLoading = true;
      _sysInfoStatus = '读取 DGUS 系统信息...';
    });
    final data = await controller.sendDgusSystemInfo(nodeAddress: nodeAddr);
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
                controller.logs.isNotEmpty
                    ? '共 ${controller.logs.length} 条'
                    : '',
                style: GoogleFonts.ibmPlexMono(
                  color: const Color(0xFFA7C7EB),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _confirmClearLogs(controller),
                icon: const Icon(
                  Icons.cleaning_services_outlined,
                  color: Color(0xFF8ED3FF),
                  size: 16,
                ),
                label: const Text(
                  '清空',
                  style: TextStyle(color: Color(0xFF8ED3FF), fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: (MediaQuery.of(context).size.height * 0.2).clamp(100, 350).toDouble(),
            width: double.infinity,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF08152A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2D4F7E)),
              ),
              child: controller.logs.isEmpty
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
                    itemCount: controller.logs.length > 30
                        ? 30
                        : controller.logs.length,
                    itemBuilder: (_, i) {
                      final item = controller.logs[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          item.pretty,
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

  // (removed unused _buildPortPanel)
  Widget _buildSettingsPage(HmiController controller) {
    final params = kParamDefsByGroup;
    final nodeAddr = _safeHex(_packerNodeAddr.text, fallback: 0xFA);

    return Container(
      color: const Color(0xFF08152A),
      child: Column(
        children: <Widget>[
          // ── 工具栏 ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1E3A),
              border: Border(bottom: BorderSide(color: Color(0xFF213D65))),
            ),
            child: LayoutBuilder(
              builder: (_, constraints) {
                final compact = constraints.maxWidth < 600;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    SizedBox(
                      width: compact ? 100 : 130,
                      child: TextField(
                        controller: _packerNodeAddr,
                        smartQuotesType: SmartQuotesType.disabled,
                        smartDashesType: SmartDashesType.disabled,
                        style: GoogleFonts.ibmPlexMono(
                          color: const Color(0xFFD6E9FF),
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          labelText: '节点地址(HEX)',
                          isDense: true,
                        ),
                      ),
                    ),
                    _opBtn(
                      '读取全部',
                      _paramsLoading,
                      () => _readAllParams(controller, nodeAddr),
                    ),
                    _opBtn(
                      '保存EEPROM',
                      false,
                      () => _saveParams(controller, nodeAddr),
                    ),
                    _opBtn(
                      '加载EEPROM',
                      false,
                      () => _loadParams(controller, nodeAddr, 0),
                    ),
                    _opBtn(
                      '恢复默认',
                      false,
                      () => _loadParams(controller, nodeAddr, 1),
                    ),
                  ],
                );
              },
            ),
          ),
          // ── 状态栏 ──
          if (_paramsStatus.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              color: const Color(0x2214345A),
              child: Text(
                _paramsStatus,
                style: GoogleFonts.ibmPlexSans(
                  color: const Color(0xFF9DC1EB),
                  fontSize: 12,
                ),
              ),
            ),
          // ── 参数列表 ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                for (final group in params.entries) ...[
                  _buildParamGroup(
                    controller,
                    nodeAddr,
                    group.key,
                    group.value,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
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
    int nodeAddr,
    String groupName,
    List<HmiParamDef> params,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF233A62)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        initiallyExpanded: params.length <= 6,
        title: Text(
          '$groupName (${params.length}项)',
          style: GoogleFonts.ibmPlexSans(
            color: const Color(0xFF5ED0FF),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: <Widget>[
          for (final p in params) _buildParamRow(controller, nodeAddr, p),
        ],
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
  Widget _paramRange(HmiParamDef p) {
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
  Widget _buildParamRow(
    HmiController controller,
    int nodeAddr,
    HmiParamDef param,
  ) {
    final value = _paramValues[param.id];
    final editor = _paramEditors.putIfAbsent(
      param.id,
      () => TextEditingController(text: value?.toString() ?? ''),
    );
    final raw = value?.toString() ?? '?';
    final inRange = _validateParam(param, editor.text);

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
                        SizedBox(
                          width: 80,
                          child: _paramField(editor, inRange),
                        ),
                        const SizedBox(width: 4),
                        _writeBtn(controller, nodeAddr, param, editor),
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
                    const SizedBox(width: 6),
                    SizedBox(width: 80, child: _paramField(editor, inRange)),
                    const SizedBox(width: 4),
                    _writeBtn(controller, nodeAddr, param, editor),
                    const SizedBox(width: 4),
                    _readBtn(controller, nodeAddr, param.id),
                  ],
                );
        },
      ),
    );
  }

  Widget _paramLabel(HmiParamDef p) {
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

  Widget _paramCurValue(String raw, HmiParamDef p) {
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
    int nodeAddr,
    HmiParamDef param,
    TextEditingController editor,
  ) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: () => _writeParam(controller, nodeAddr, param, editor),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A3A5C),
          foregroundColor: const Color(0xFFD6E9FF),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text('写入', style: GoogleFonts.ibmPlexSans(fontSize: 11)),
      ),
    );
  }

  Widget _readBtn(HmiController controller, int nodeAddr, int paramId) {
    return SizedBox(
      height: 32,
      width: 32,
      child: IconButton(
        icon: const Icon(Icons.refresh, size: 16),
        tooltip: '读取参数当前值',
        color: const Color(0xFF5ED0FF),
        padding: EdgeInsets.zero,
        onPressed: () => _readParam(controller, nodeAddr, paramId),
      ),
    );
  }

  /// 校验参数值是否在范围内
  bool _validateParam(HmiParamDef param, String text) {
    final v = int.tryParse(text.trim());
    if (v == null) return false;
    return v >= param.min && v <= param.max;
  }

  /// 读取单个参数
  Future<void> _readParam(
    HmiController controller,
    int nodeAddr,
    int paramId,
  ) async {
    final value = await controller.sendParamRead(
      nodeAddress: nodeAddr,
      paramId: paramId,
    );
    if (!mounted) return;
    if (value != null) {
      setState(() {
        _paramValues[paramId] = value;
        _paramEditors[paramId]?.text = value.toString();
      });
    }
  }

  /// 写入单个参数
  Future<void> _writeParam(
    HmiController controller,
    int nodeAddr,
    HmiParamDef param,
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
      nodeAddress: nodeAddr,
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
      setState(() => _paramsStatus = '${param.name}: 写入失败');
    }
  }

  /// 批量读取全部参数
  Future<void> _readAllParams(HmiController controller, int nodeAddr) async {
    setState(() {
      _paramsLoading = true;
      _paramsStatus = '正在读取全部参数\u2026';
    });
    int count = 0;
    int errors = 0;
    for (final p in kParamDefs) {
      try {
        final value = await controller.sendParamRead(
          nodeAddress: nodeAddr,
          paramId: p.id,
        );
        if (value != null) {
          _paramValues[p.id] = value;
          _paramEditors[p.id]?.text = value.toString();
          count++;
        } else {
          errors++;
        }
      } catch (e) {
        errors++;
      }
      // 每读 10 个更新一次 UI
      if ((count + errors) % 10 == 0 && mounted) {
        setState(() => _paramsStatus =
            '已读取 $count/${kParamDefs.length}\u2026 ($errors项失败)');
      }
    }
    if (mounted) {
      setState(() {
        _paramsLoading = false;
        _paramsStatus = errors > 0
            ? '读取完成: $count/${kParamDefs.length} 个参数 ($errors 项失败)'
            : '读取完成: $count/${kParamDefs.length} 个参数';
      });
    }
  }

  /// 保存到 EEPROM
  Future<void> _saveParams(HmiController controller, int nodeAddr) async {
    final ok = await controller.sendParamSave(nodeAddress: nodeAddr);
    if (mounted) {
      setState(() => _paramsStatus = ok ? '已保存到 EEPROM' : '保存失败');
    }
  }

  /// 加载/恢复参数
  Future<void> _loadParams(
    HmiController controller,
    int nodeAddr,
    int action,
  ) async {
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
      nodeAddress: nodeAddr,
      action: action,
    );
    if (mounted) {
      setState(
        () => _paramsStatus = action == 0
            ? (ok ? '已从 EEPROM 加载' : '加载失败')
            : (ok ? '已恢复默认值' : '恢复失败'),
      );
      if (ok) {
        // 重新读取全部参数显示最新值
        _readAllParams(controller, nodeAddr);
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
    return Container(
      color: const Color(0xFF08152A),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            _buildCardHeader(
              title: '协议日志',
              trailing: TextButton.icon(
                onPressed: () => _confirmClearLogs(controller),
                icon: const Icon(
                  Icons.cleaning_services_outlined,
                  color: Color(0xFF8ED3FF),
                ),
                label: const Text(
                  '清空',
                  style: TextStyle(color: Color(0xFF8ED3FF)),
                ),
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
                child: controller.logs.isEmpty
                    ? Center(
                        child: Text(
                          '暂无日志',
                          style: GoogleFonts.ibmPlexSans(
                            color: const Color(0xFFA7C7EB),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: controller.logs.length > 200
                            ? 200
                            : controller.logs.length,
                        itemBuilder: (_, i) {
                          final item = controller.logs[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
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

  Widget _numberField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      smartQuotesType: SmartQuotesType.disabled,
      smartDashesType: SmartDashesType.disabled,
      style: const TextStyle(color: Color(0xFFE6F2FF)),
      decoration: _inputDecoration(label),
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
