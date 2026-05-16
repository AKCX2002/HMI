import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
    text: '20',
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
    final menus = <String>['连接与指令', '打包机协议', '参数配置', '帧调试台', '协议日志'];
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

  Widget _buildSidebar(HmiController controller) {
    final menus = <(IconData, String)>[
      (Icons.link, '连接与指令'),
      (Icons.inventory_2_outlined, '打包机协议'),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: controller.isConnected
                            ? const Color(0x1E1FDC9A)
                            : const Color(0x33E53935),
                      ),
                      child: Center(
                        child: Text(
                          controller.isConnected ? '已连接' : '未连接',
                          style: GoogleFonts.ibmPlexSans(
                            color: controller.isConnected
                                ? const Color(0xFF9AF9D3)
                                : const Color(0xFFFF9595),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.device_hub,
                          color: Color(0xFF7DB5FF),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '协议: UART3 / 20B / CRC16',
                            style: GoogleFonts.ibmPlexMono(
                              color: const Color(0xFF9EC7FF),
                              fontSize: 11,
                            ),
                          ),
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
        return _buildPackerPage(controller);
      case 2:
        return _buildSettingsPage(controller);
      case 3:
        return _buildFrameDebuggerPage(controller);
      case 4:
        return _buildLogsPage(controller);
      case 0:
      default:
        return _buildCommandPage(controller);
    }
  }

  Widget _buildCommandPage(HmiController controller) {
    return Container(
      color: const Color(0xFF08152A),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _buildConnectionCard(controller),
          const SizedBox(height: 12),
          _buildCard(
            title:
                '功能码面板（0x01 / 0x03 / 0x05 / 0x07 / 0x09 / 0x0B / 0x0C / 0x10）',
            child: Wrap(
              runSpacing: 10,
              spacing: 10,
              children: <Widget>[
                _buildOpButton(
                  label: '0x10 初始化查询',
                  onPressed: controller.isConnected
                      ? () => _runCommand(controller.sendInitQuery, '初始化查询完成')
                      : null,
                ),
                _buildOpButton(
                  label: '0x09 状态查询',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendStatusQuery(
                            queryType: _safeInt(_statusQueryType, fallback: 1),
                          ),
                          '状态查询完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x01 订单下发',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendOrder(
                            orderId: _safeInt(_orderId, fallback: 1),
                            quantity: _safeInt(_quantity, fallback: 1),
                            cabinetAddress: _safeInt(
                              _cabinetAddress,
                              fallback: 1,
                            ),
                            layer: _safeInt(_layer, fallback: 1),
                            lane: _safeInt(_lane, fallback: 1),
                          ),
                          '订单下发完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x03 打包封口',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendPackSeal(
                            orderId: _safeInt(_sealOrderId, fallback: 1),
                            sealAction: _safeInt(_sealAction, fallback: 1),
                          ),
                          '打包封口指令完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x05 储物格存放',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendStore(
                            packageId: _safeInt(_storePackageId, fallback: 1),
                            cabinetNo: _safeInt(_storeCabinetNo, fallback: 1),
                          ),
                          '存放指令完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x07 取货开锁',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendPickupUnlock(
                            orderId: _safeInt(_unlockOrderId, fallback: 1),
                            cabinetNo: _safeInt(_unlockCabinetNo, fallback: 1),
                          ),
                          '开锁指令完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x0B 设备测试',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendDeviceTest(
                            testType: _safeInt(_testType, fallback: 2),
                            targetId: _safeInt(_testTargetId, fallback: 0),
                            action: _safeInt(_testAction, fallback: 11),
                          ),
                          '设备测试指令完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x0C 退货',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendReturnGoods(
                            orderId: _safeInt(_returnOrderId, fallback: 1),
                            cabinetNo: _safeInt(_returnCabinetNo, fallback: 1),
                          ),
                          '退货指令完成',
                        )
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildCard(
            title: '命令参数',
            child: Column(
              children: <Widget>[
                _buildRowFields(<Widget>[
                  _numberField('订单号', _orderId),
                  _numberField('数量', _quantity),
                  _numberField('货柜地址', _cabinetAddress),
                  _numberField('货层', _layer),
                  _numberField('货道', _lane),
                ]),
                const SizedBox(height: 10),
                _buildRowFields(<Widget>[
                  _numberField('封口订单号', _sealOrderId),
                  _numberField('封口动作', _sealAction),
                  _numberField('存放包裹ID', _storePackageId),
                  _numberField('存放格号', _storeCabinetNo),
                  _numberField('查询类型', _statusQueryType),
                ]),
                const SizedBox(height: 10),
                _buildRowFields(<Widget>[
                  _numberField('开锁订单号', _unlockOrderId),
                  _numberField('开锁格号', _unlockCabinetNo),
                  _numberField('测试类型(data[0])', _testType),
                  _numberField('测试目标ID(data[1-2])', _testTargetId),
                  _numberField('测试动作(data[3])', _testAction),
                ]),
                const SizedBox(height: 10),
                _buildRowFields(<Widget>[
                  _numberField('退货订单号', _returnOrderId),
                  _numberField('退货格号', _returnCabinetNo),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(HmiController controller) {
    return _buildCard(
      title: '串口连接',
      child: LayoutBuilder(
        builder: (_, constraints) {
          final compact = constraints.maxWidth < 760;
          final portField = DropdownButtonFormField<String>(
            initialValue: controller.selectedPort,
            decoration: _inputDecoration('串口'),
            dropdownColor: const Color(0xFF122B4D),
            style: const TextStyle(color: Color(0xFFD7E8FF)),
            items: controller.ports
                .map((p) => DropdownMenuItem<String>(value: p, child: Text(p)))
                .toList(),
            onChanged: controller.isConnected ? null : controller.setPort,
          );
          final baudField = DropdownButtonFormField<int>(
            initialValue: controller.baudRate,
            decoration: _inputDecoration('波特率'),
            dropdownColor: const Color(0xFF122B4D),
            style: const TextStyle(color: Color(0xFFD7E8FF)),
            items: const <int>[9600, 57600, 115200, 230400]
                .map((v) => DropdownMenuItem<int>(value: v, child: Text('$v')))
                .toList(),
            onChanged: controller.isConnected
                ? null
                : (v) => controller.setBaudRate(v ?? 115200),
          );

          return Column(
            children: <Widget>[
              if (compact) ...<Widget>[
                portField,
                const SizedBox(height: 10),
                baudField,
              ] else
                Row(
                  children: <Widget>[
                    Expanded(child: portField),
                    const SizedBox(width: 10),
                    SizedBox(width: 220, child: baudField),
                  ],
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: <Widget>[
                  _buildOpButton(
                    label: '扫描',
                    onPressed: controller.refreshPorts,
                  ),
                  _buildOpButton(
                    label: controller.isConnected ? '断开' : '连接',
                    onPressed: controller.connectOrDisconnect,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPackerPage(HmiController controller) {
    int nodeAddress() => _safeHex(_packerNodeAddr.text, fallback: 0x20);
    return Container(
      color: const Color(0xFF08152A),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _buildCard(
            title: '打包机节点（USART3 / RS485 / 20B / CRC16）',
            child: Column(
              children: <Widget>[
                _buildRowFields(<Widget>[
                  _textField('节点地址 HEX', _packerNodeAddr),
                  _numberField('避让动作 0清零/1缩进/2推出', _packerAvoidAction),
                  _numberField('清除标志 1出袋/2封口/3投料/4避让', _packerClearFlag),
                ]),
                const SizedBox(height: 10),
                _buildRowFields(<Widget>[
                  _numberField('心跳主控状态', _packerHostState),
                  _numberField('复位范围 0普通/1报警/2软复位', _packerResetScope),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildCard(
            title: '打包机功能码（0x40 - 0x49）',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _buildOpButton(
                  label: '0x40 启动',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendPackerControl(
                            nodeAddress: nodeAddress(),
                            action: 1,
                          ),
                          '打包机启动完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x40 停止',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendPackerControl(
                            nodeAddress: nodeAddress(),
                            action: 0,
                          ),
                          '打包机停止完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x41 状态',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendPackerStatus(
                            nodeAddress: nodeAddress(),
                          ),
                          '打包机状态查询完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x42 出袋',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendPackerTriggerBag(
                            nodeAddress: nodeAddress(),
                          ),
                          '出袋触发完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x43 封口',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendPackerTriggerSeal(
                            nodeAddress: nodeAddress(),
                          ),
                          '封口触发完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x44 避让',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendPackerAvoid(
                            nodeAddress: nodeAddress(),
                            action: _safeInt(
                              _packerAvoidAction,
                              fallback: 2,
                            ).clamp(0, 2),
                          ),
                          '避让控制完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x45 清标志',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendPackerClearFlag(
                            nodeAddress: nodeAddress(),
                            flagId: _safeInt(
                              _packerClearFlag,
                              fallback: 1,
                            ).clamp(1, 4),
                          ),
                          '清除标志完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x46 报警',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendPackerAlarmQuery(
                            nodeAddress: nodeAddress(),
                          ),
                          '报警查询完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x47 心跳',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendPackerHeartbeat(
                            nodeAddress: nodeAddress(),
                            hostState: _safeInt(
                              _packerHostState,
                              fallback: 0,
                            ).clamp(0, 255),
                          ),
                          '心跳完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x48 版本',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendPackerVersion(
                            nodeAddress: nodeAddress(),
                          ),
                          '版本查询完成',
                        )
                      : null,
                ),
                _buildOpButton(
                  label: '0x49 复位',
                  onPressed: controller.isConnected
                      ? () => _runCommand(
                          () => controller.sendPackerResetFault(
                            nodeAddress: nodeAddress(),
                            scope: _safeInt(
                              _packerResetScope,
                              fallback: 0,
                            ).clamp(0, 2),
                          ),
                          '故障复位完成',
                        )
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPage(HmiController controller) {
    final params = kParamDefsByGroup;
    final nodeAddr = _safeHex(_packerNodeAddr.text, fallback: 0x20);

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
                        style: GoogleFonts.ibmPlexMono(
                          color: const Color(0xFFD6E9FF), fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: '节点地址(HEX)',
                          isDense: true,
                        ),
                      ),
                    ),
                    _opBtn('读取全部', _paramsLoading,
                        () => _readAllParams(controller, nodeAddr)),
                    _opBtn('保存EEPROM', false,
                        () => _saveParams(controller, nodeAddr)),
                    _opBtn('加载EEPROM', false,
                        () => _loadParams(controller, nodeAddr, 0)),
                    _opBtn('恢复默认', false,
                        () => _loadParams(controller, nodeAddr, 1)),
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
              child: Text(_paramsStatus,
                  style: GoogleFonts.ibmPlexSans(
                      color: const Color(0xFF9DC1EB), fontSize: 12)),
            ),
          // ── 参数列表 ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                for (final group in params.entries) ...[
                  _buildParamGroup(
                      controller, nodeAddr, group.key, group.value),
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
              side: const BorderSide(color: Color(0xFF2C4F79))),
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label,
                style: GoogleFonts.ibmPlexSans(
                    fontSize: 12, fontWeight: FontWeight.w500)),
      ),
    );
  }

  /// 参数分组折叠面板
  Widget _buildParamGroup(HmiController controller, int nodeAddr,
      String groupName, List<HmiParamDef> params) {
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
        title: Text('$groupName (${params.length}项)',
            style: GoogleFonts.ibmPlexSans(
                color: const Color(0xFF5ED0FF),
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        children: <Widget>[
          for (final p in params)
            _buildParamRow(controller, nodeAddr, p),
        ],
      ),
    );
  }

  /// 单个参数行
  Widget _buildParamRow(
      HmiController controller, int nodeAddr, HmiParamDef param) {
    final value = _paramValues[param.id];
    final editor = _paramEditors.putIfAbsent(
        param.id, () => TextEditingController(text: value?.toString() ?? ''));
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
                    const SizedBox(height: 2),
                    Row(children: <Widget>[
                      Expanded(child: _paramCurValue(raw, param)),
                      const SizedBox(width: 6),
                      SizedBox(
                          width: 80,
                          child: _paramField(editor, inRange)),
                      const SizedBox(width: 4),
                      _writeBtn(controller, nodeAddr, param, editor),
                    ]),
                  ],
                )
              : Row(
                  children: <Widget>[
                    SizedBox(width: 160, child: _paramLabel(param)),
                    const SizedBox(width: 8),
                    SizedBox(width: 90, child: _paramCurValue(raw, param)),
                    const SizedBox(width: 6),
                    SizedBox(width: 90, child: _paramField(editor, inRange)),
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
    return Text('${p.name} (0x${toHex2(p.id)})',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.ibmPlexSans(
            color: const Color(0xFFD6E9FF), fontSize: 13));
  }

  Widget _paramCurValue(String raw, HmiParamDef p) {
    return Text(raw + (p.unit.isNotEmpty ? ' ${p.unit}' : ''),
        style: GoogleFonts.ibmPlexMono(
            color: const Color(0xFF9EC7FF), fontSize: 12));
  }

  Widget _paramField(TextEditingController editor, bool inRange) {
    return TextField(
      controller: editor,
      style: GoogleFonts.ibmPlexMono(
          color: inRange ? const Color(0xFFD6E9FF) : const Color(0xFFFF9595),
          fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
                color:
                    inRange ? const Color(0xFF2C4F79) : const Color(0xFF9F2D2D))),
        errorText: inRange ? null : '越界',
        errorStyle: const TextStyle(fontSize: 9),
      ),
    );
  }

  Widget _writeBtn(HmiController controller, int nodeAddr, HmiParamDef param,
      TextEditingController editor) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: () =>
            _writeParam(controller, nodeAddr, param, editor),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A3A5C),
          foregroundColor: const Color(0xFFD6E9FF),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6)),
        ),
        child: Text('写入',
            style: GoogleFonts.ibmPlexSans(fontSize: 11)),
      ),
    );
  }

  Widget _readBtn(HmiController controller, int nodeAddr, int paramId) {
    return SizedBox(
      height: 32, width: 32,
      child: IconButton(
        icon: const Icon(Icons.refresh, size: 16),
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
      HmiController controller, int nodeAddr, int paramId) async {
    final value = await controller.sendParamRead(
        nodeAddress: nodeAddr, paramId: paramId);
    if (!mounted) return;
    if (value != null) {
      setState(() {
        _paramValues[paramId] = value;
        _paramEditors[paramId]?.text = value.toString();
      });
    }
  }

  /// 写入单个参数
  Future<void> _writeParam(HmiController controller, int nodeAddr,
      HmiParamDef param, TextEditingController editor) async {
    final text = editor.text.trim();
    final v = int.tryParse(text);
    if (v == null) {
      setState(() => _paramsStatus = '${param.name}: 无效数值');
      return;
    }
    if (v < param.min || v > param.max) {
      setState(
          () => _paramsStatus = '${param.name}: 越界 (${param.min}~${param.max})');
      return;
    }
    final result =
        await controller.sendParamWrite(nodeAddress: nodeAddr, paramId: param.id, value: v);
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
  Future<void> _readAllParams(
      HmiController controller, int nodeAddr) async {
    setState(() {
      _paramsLoading = true;
      _paramsStatus = '正在读取全部参数...';
    });
    int count = 0;
    for (final p in kParamDefs) {
      final value = await controller.sendParamRead(
          nodeAddress: nodeAddr, paramId: p.id);
      if (value != null) {
        _paramValues[p.id] = value;
        _paramEditors[p.id]?.text = value.toString();
        count++;
      }
      // 每读 10 个更新一次 UI
      if (count % 10 == 0 && mounted) {
        setState(() => _paramsStatus = '已读取 $count/${kParamDefs.length}...');
      }
    }
    if (mounted) {
      setState(() {
        _paramsLoading = false;
        _paramsStatus = '读取完成: $count/${kParamDefs.length} 个参数';
      });
    }
  }

  /// 保存到 EEPROM
  Future<void> _saveParams(
      HmiController controller, int nodeAddr) async {
    final ok = await controller.sendParamSave(nodeAddress: nodeAddr);
    if (mounted) {
      setState(() => _paramsStatus = ok ? '已保存到 EEPROM' : '保存失败');
    }
  }

  /// 加载/恢复参数
  Future<void> _loadParams(
      HmiController controller, int nodeAddr, int action) async {
    final ok = await controller.sendParamLoad(
        nodeAddress: nodeAddr, action: action);
    if (mounted) {
      setState(() => _paramsStatus =
          action == 0 ? (ok ? '已从 EEPROM 加载' : '加载失败')
                      : (ok ? '已恢复默认值' : '恢复失败'));
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
                onPressed: controller.clearLogs,
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
                        itemCount: controller.logs.length,
                        itemBuilder: (_, i) {
                          final item = controller.logs[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              item.pretty,
                              style: GoogleFonts.ibmPlexMono(
                                color: item.direction == 'TX'
                                    ? const Color(0xFFFFE082)
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
      style: const TextStyle(color: Color(0xFFE6F2FF)),
      decoration: _inputDecoration(label),
    );
  }

  Widget _textField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
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
