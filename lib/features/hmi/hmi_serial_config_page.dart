import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'hmi_controller.dart';
import 'hmi_port_config.dart';

/// USART 串口配置子页面。
///
/// 集中管理端口 A (USART3) 和端口 B (USART1) 的全部串口参数：
/// - 端口名称、波特率、数据位、停止位、校验位、流控制
/// - 连接/断开、扫描刷新
class HmiSerialConfigPage extends StatefulWidget {
  const HmiSerialConfigPage({super.key, required this.controller});

  final HmiController controller;

  @override
  State<HmiSerialConfigPage> createState() => _HmiSerialConfigPageState();
}

class _HmiSerialConfigPageState extends State<HmiSerialConfigPage> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return AnimatedBuilder(
      animation: c,
      builder: (_, _) {
        return Container(
          color: const Color(0xFF08152A),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _buildSectionTitle('端口 A — USART3 / 20B 固定帧 (主控协议)'),
              const SizedBox(height: 10),
              _buildPortConfigCard(
                config: c.portAConfig,
                isConnected: c.isConnectedA,
                ports: c.portsA,
                canEdit: !c.isConnectedA,
                onPortChanged: c.setPortA,
                onBaudRateChanged: c.setBaudRateA,
                onDataBitsChanged: c.setDataBitsA,
                onStopBitsChanged: c.setStopBitsA,
                onParityChanged: c.setParityA,
                onFlowControlChanged: c.setFlowControlA,
                onRefresh: c.refreshPortsA,
                onConnect: c.connectPortA,
                onDisconnect: c.disconnectPortA,
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('端口 B — USART1 / HMIS-BAM Session'),
              const SizedBox(height: 10),
              _buildPortConfigCard(
                config: c.portBConfig,
                isConnected: c.isConnectedB,
                ports: c.portsB,
                canEdit: !c.isConnectedB,
                onPortChanged: c.setPortB,
                onBaudRateChanged: c.setBaudRateB,
                onDataBitsChanged: c.setDataBitsB,
                onStopBitsChanged: c.setStopBitsB,
                onParityChanged: c.setParityB,
                onFlowControlChanged: c.setFlowControlB,
                onRefresh: c.refreshPortsB,
                onConnect: c.connectPortB,
                onDisconnect: c.disconnectPortB,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.ibmPlexSans(
        color: const Color(0xFFA6C5EA),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  /// 单个端口的完整配置卡片。
  Widget _buildPortConfigCard({
    required HmiPortConfig config,
    required bool isConnected,
    required List<String> ports,
    required bool canEdit,
    required ValueChanged<String?> onPortChanged,
    required ValueChanged<int> onBaudRateChanged,
    required ValueChanged<HmiDataBits> onDataBitsChanged,
    required ValueChanged<HmiStopBits> onStopBitsChanged,
    required ValueChanged<HmiParity> onParityChanged,
    required ValueChanged<HmiFlowControl> onFlowControlChanged,
    required VoidCallback onRefresh,
    required VoidCallback onConnect,
    required VoidCallback onDisconnect,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF2E7D32)
              : const Color(0xFF233A62),
        ),
      ),
      child: LayoutBuilder(
        builder: (_, constraints) {
          // 配置项较多，桌面测试默认视口也可能不足以容纳单行布局。
          final compact = constraints.maxWidth < 1100;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // ── 状态栏 ──
              _buildStatusBar(
                isConnected,
                config,
                onRefresh,
                onConnect,
                onDisconnect,
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF213D65), height: 1),
              const SizedBox(height: 12),
              // ── 参数区 ──
              Text(
                '串口参数',
                style: GoogleFonts.ibmPlexSans(
                  color: const Color(0xFF7DB5FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (compact)
                ..._buildCompactConfigRows(
                  config,
                  ports,
                  canEdit,
                  onPortChanged,
                  onBaudRateChanged,
                  onDataBitsChanged,
                  onStopBitsChanged,
                  onParityChanged,
                  onFlowControlChanged,
                )
              else
                ..._buildWideConfigRows(
                  config,
                  ports,
                  canEdit,
                  onPortChanged,
                  onBaudRateChanged,
                  onDataBitsChanged,
                  onStopBitsChanged,
                  onParityChanged,
                  onFlowControlChanged,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusBar(
    bool isConnected,
    HmiPortConfig config,
    VoidCallback onRefresh,
    VoidCallback onConnect,
    VoidCallback onDisconnect,
  ) {
    return Row(
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isConnected
                ? const Color(0xFF4CAF50)
                : const Color(0xFFE53935),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            isConnected
                ? '已连接 — ${config.summary}'
                : '未连接 — ${config.portName ?? "未选择端口"}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.ibmPlexMono(
              color: isConnected
                  ? const Color(0xFF9AF9D3)
                  : const Color(0xFFFF9595),
              fontSize: 11,
            ),
          ),
        ),
        Tooltip(
          message: '扫描可用串口',
          child: SizedBox(
            height: 32,
            width: 40,
            child: ElevatedButton(
              style: _btnStyle(const Color(0xFF1B91D8)),
              onPressed: onRefresh,
              child: const Icon(Icons.refresh, size: 16),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: isConnected ? '断开连接' : '连接串口',
          child: SizedBox(
            height: 32,
            width: 40,
            child: ElevatedButton(
              style: _btnStyle(
                isConnected ? const Color(0xFF9F2D2D) : const Color(0xFF2E7D32),
              ),
              onPressed: isConnected ? onDisconnect : onConnect,
              child: Icon(isConnected ? Icons.link_off : Icons.link, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildWideConfigRows(
    HmiPortConfig config,
    List<String> ports,
    bool canEdit,
    ValueChanged<String?> onPortChanged,
    ValueChanged<int> onBaudRateChanged,
    ValueChanged<HmiDataBits> onDataBitsChanged,
    ValueChanged<HmiStopBits> onStopBitsChanged,
    ValueChanged<HmiParity> onParityChanged,
    ValueChanged<HmiFlowControl> onFlowControlChanged,
  ) {
    return <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: _buildPortDropdown(
              ports,
              config.portName,
              canEdit,
              onPortChanged,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _buildBaudDropdown(
              config.baudRate,
              canEdit,
              onBaudRateChanged,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: _buildDataBitsDropdown(
              config.dataBits,
              canEdit,
              onDataBitsChanged,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: _buildParityDropdown(
              config.parity,
              canEdit,
              onParityChanged,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: _buildStopBitsDropdown(
              config.stopBits,
              canEdit,
              onStopBitsChanged,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _buildFlowDropdown(
              config.flowControl,
              canEdit,
              onFlowControlChanged,
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildCompactConfigRows(
    HmiPortConfig config,
    List<String> ports,
    bool canEdit,
    ValueChanged<String?> onPortChanged,
    ValueChanged<int> onBaudRateChanged,
    ValueChanged<HmiDataBits> onDataBitsChanged,
    ValueChanged<HmiStopBits> onStopBitsChanged,
    ValueChanged<HmiParity> onParityChanged,
    ValueChanged<HmiFlowControl> onFlowControlChanged,
  ) {
    return <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: _buildPortDropdown(
              ports,
              config.portName,
              canEdit,
              onPortChanged,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildBaudDropdown(
              config.baudRate,
              canEdit,
              onBaudRateChanged,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          Expanded(
            child: _buildDataBitsDropdown(
              config.dataBits,
              canEdit,
              onDataBitsChanged,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildParityDropdown(
              config.parity,
              canEdit,
              onParityChanged,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStopBitsDropdown(
              config.stopBits,
              canEdit,
              onStopBitsChanged,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          Expanded(
            child: _buildFlowDropdown(
              config.flowControl,
              canEdit,
              onFlowControlChanged,
            ),
          ),
        ],
      ),
    ];
  }

  // ═══════════════════════════════════════════════
  //  控件构建
  // ═══════════════════════════════════════════════

  Widget _buildPortDropdown(
    List<String> ports,
    String? selected,
    bool canEdit,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String?>(
      initialValue: selected,
      isExpanded: true,
      decoration: _fieldDeco('端口'),
      dropdownColor: const Color(0xFF122B4D),
      style: const TextStyle(color: Color(0xFFD7E8FF), fontSize: 12),
      isDense: true,
      selectedItemBuilder: (_) {
        return <String?>[null, ...ports].map((p) {
          final label = p ?? '— 未选择 —';
          final color = p == null
              ? const Color(0xFF888888)
              : const Color(0xFFD7E8FF);
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12),
            ),
          );
        }).toList();
      },
      items: <DropdownMenuItem<String?>>[
        const DropdownMenuItem<String?>(
          value: null,
          child: Text(
            '— 未选择 —',
            style: TextStyle(color: Color(0xFF888888), fontSize: 12),
          ),
        ),
        ...ports.map(
          (p) => DropdownMenuItem<String?>(
            value: p,
            child: Text(
              p,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: canEdit ? onChanged : null,
    );
  }

  Widget _buildBaudDropdown(
    int value,
    bool canEdit,
    ValueChanged<int> onChanged,
  ) {
    return _InlineBaudRateField(
      value: value,
      canEdit: canEdit,
      fontSize: 12,
      decoration: _fieldDeco('波特率'),
      onChanged: onChanged,
    );
  }

  Widget _buildDataBitsDropdown(
    HmiDataBits value,
    bool canEdit,
    ValueChanged<HmiDataBits> onChanged,
  ) {
    return DropdownButtonFormField<HmiDataBits>(
      initialValue: value,
      isExpanded: true,
      decoration: _fieldDeco('数据位'),
      dropdownColor: const Color(0xFF122B4D),
      style: const TextStyle(color: Color(0xFFD7E8FF), fontSize: 12),
      isDense: true,
      items: HmiPortConfig.supportedDataBits
          .map(
            (v) => DropdownMenuItem<HmiDataBits>(
              value: v,
              child: Text(v.label, style: const TextStyle(fontSize: 12)),
            ),
          )
          .toList(),
      onChanged: canEdit ? (v) => onChanged(v ?? HmiDataBits.bits8) : null,
    );
  }

  Widget _buildStopBitsDropdown(
    HmiStopBits value,
    bool canEdit,
    ValueChanged<HmiStopBits> onChanged,
  ) {
    return DropdownButtonFormField<HmiStopBits>(
      initialValue: value,
      isExpanded: true,
      decoration: _fieldDeco('停止位'),
      dropdownColor: const Color(0xFF122B4D),
      style: const TextStyle(color: Color(0xFFD7E8FF), fontSize: 12),
      isDense: true,
      items: HmiStopBits.values
          .map(
            (v) => DropdownMenuItem<HmiStopBits>(
              value: v,
              child: Text(v.label, style: const TextStyle(fontSize: 12)),
            ),
          )
          .toList(),
      onChanged: canEdit ? (v) => onChanged(v ?? HmiStopBits.one) : null,
    );
  }

  Widget _buildParityDropdown(
    HmiParity value,
    bool canEdit,
    ValueChanged<HmiParity> onChanged,
  ) {
    return DropdownButtonFormField<HmiParity>(
      initialValue: value,
      isExpanded: true,
      decoration: _fieldDeco('校验'),
      dropdownColor: const Color(0xFF122B4D),
      style: const TextStyle(color: Color(0xFFD7E8FF), fontSize: 12),
      isDense: true,
      items: HmiParity.values
          .map(
            (v) => DropdownMenuItem<HmiParity>(
              value: v,
              child: Text(v.label, style: const TextStyle(fontSize: 12)),
            ),
          )
          .toList(),
      onChanged: canEdit ? (v) => onChanged(v ?? HmiParity.none) : null,
    );
  }

  Widget _buildFlowDropdown(
    HmiFlowControl value,
    bool canEdit,
    ValueChanged<HmiFlowControl> onChanged,
  ) {
    return DropdownButtonFormField<HmiFlowControl>(
      initialValue: value,
      isExpanded: true,
      decoration: _fieldDeco('流控制'),
      dropdownColor: const Color(0xFF122B4D),
      style: const TextStyle(color: Color(0xFFD7E8FF), fontSize: 12),
      isDense: true,
      items: HmiFlowControl.values
          .map(
            (v) => DropdownMenuItem<HmiFlowControl>(
              value: v,
              child: Text(v.label, style: const TextStyle(fontSize: 12)),
            ),
          )
          .toList(),
      onChanged: canEdit ? (v) => onChanged(v ?? HmiFlowControl.none) : null,
    );
  }

  InputDecoration _fieldDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFFA6C5EA), fontSize: 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      filled: true,
      fillColor: const Color(0xFF0A1D36),
      border: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF2A4F79)),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  ButtonStyle _btnStyle(Color bg) {
    return ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: Colors.white,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    );
  }
}

class _InlineBaudRateField extends StatefulWidget {
  const _InlineBaudRateField({
    required this.value,
    required this.canEdit,
    required this.fontSize,
    required this.decoration,
    required this.onChanged,
  });

  final int value;
  final bool canEdit;
  final double fontSize;
  final InputDecoration decoration;
  final ValueChanged<int> onChanged;

  @override
  State<_InlineBaudRateField> createState() => _InlineBaudRateFieldState();
}

class _InlineBaudRateFieldState extends State<_InlineBaudRateField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
  }

  @override
  void didUpdateWidget(covariant _InlineBaudRateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != '${widget.value}') {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commitValue() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed != null && HmiPortConfig.isValidBaudRate(parsed)) {
      if (parsed != widget.value) {
        widget.onChanged(parsed);
      }
      _controller.text = '$parsed';
      return;
    }
    _controller.text = '${widget.value}';
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      enabled: widget.canEdit,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      style: TextStyle(
        color: const Color(0xFFD7E8FF),
        fontSize: widget.fontSize,
      ),
      decoration: widget.decoration.copyWith(
        hintText:
            '${HmiPortConfig.minCustomBaudRate}-${HmiPortConfig.maxCustomBaudRate}',
        hintStyle: TextStyle(
          color: const Color(0x667DB5FF),
          fontSize: widget.fontSize,
        ),
      ),
      onFieldSubmitted: (_) => _commitValue(),
      onEditingComplete: _commitValue,
    );
  }
}
