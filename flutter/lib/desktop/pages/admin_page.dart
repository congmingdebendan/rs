import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import '../../models/admin_model.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({Key? key}) : super(key: key);

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _model = AdminModel();
  bool _initialLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _model.refresh().then((_) {
        if (mounted) setState(() => _initialLoaded = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _model,
      builder: (context, _) => _buildContent(),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: _model.loading && !_initialLoaded
              ? const Center(child: CircularProgressIndicator())
              : _model.error != null && _model.devices.isEmpty
                  ? _buildError()
                  : _buildBody(),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(translate('管理后台'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (_model.stats.hbbsRunning || _model.stats.hbbrRunning) ...[
            _StatusDot(label: 'hbbs', active: _model.stats.hbbsRunning),
            const SizedBox(width: 12),
            _StatusDot(label: 'hbbr', active: _model.stats.hbbrRunning),
            const SizedBox(width: 16),
          ],
          if (_model.loading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: translate('刷新'),
              onPressed: () => _model.refresh().then((_) {
                if (mounted) setState(() {});
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(_model.error ?? '', textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _buildStatsRow(),
        const SizedBox(height: 16),
        _buildDevicesCard(),
        const SizedBox(height: 16),
        _buildSessionsCard(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _StatCard(
          label: '在线设备',
          value: '${_model.stats.onlineCount}',
          icon: Icons.devices,
          color: Colors.green,
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: '今日会话',
          value: '${_model.stats.todaySessions}',
          icon: Icons.swap_horiz,
          color: Colors.blue,
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: '总设备数',
          value: '${_model.stats.totalDevices}',
          icon: Icons.storage,
          color: Colors.orange,
        ),
      ],
    );
  }

  Widget _buildDevicesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(translate('设备列表'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_model.devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text(translate('暂无数据'))),
              )
            else
              _buildDevicesTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 24,
        headingRowHeight: 36,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 48,
        columns: [
          DataColumn(label: Text(translate('设备 ID'))),
          DataColumn(label: Text(translate('最后在线'))),
          DataColumn(label: Text(translate('IP 地址'))),
          DataColumn(label: Text(translate('状态'))),
          DataColumn(label: Text(translate('操作'))),
        ],
        rows: _model.devices.map((d) => _deviceRow(d)).toList(),
      ),
    );
  }

  DataRow _deviceRow(DeviceInfo d) {
    return DataRow(cells: [
      DataCell(SelectableText(d.id,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
      DataCell(Text(d.lastSeen != null ? _formatTime(d.lastSeen!) : '-',
          style: const TextStyle(fontSize: 13))),
      DataCell(Text(d.lastIp ?? '-', style: const TextStyle(fontSize: 13))),
      DataCell(_buildStatusChip(d)),
      DataCell(_buildActionButton(d)),
    ]);
  }

  Widget _buildStatusChip(DeviceInfo d) {
    if (d.blocked) {
      return Chip(
        label: Text(translate('已禁用'),
            style: const TextStyle(fontSize: 12, color: Colors.white)),
        backgroundColor: Colors.red,
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }
    if (d.online) {
      return Chip(
        label: Text(translate('在线'),
            style: const TextStyle(fontSize: 12, color: Colors.white)),
        backgroundColor: Colors.green,
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }
    return Text(translate('离线'),
        style: TextStyle(fontSize: 13, color: Colors.grey[500]));
  }

  Widget _buildActionButton(DeviceInfo d) {
    if (d.blocked) {
      return TextButton(
        child: Text(translate('解禁'),
            style: const TextStyle(color: Colors.green)),
        onPressed: () => _confirmAction(
          title: translate('解禁设备'),
          content: translate('确定解除对 ${d.id} 的禁用？'),
          onConfirm: () => _model.unblockDevice(d.id).then((ok) {
            if (!ok && mounted) {
              _showSnack(translate('操作失败，请检查连接'));
            }
          }),
        ),
      );
    }
    return TextButton(
      child: Text(translate('禁用'), style: const TextStyle(color: Colors.red)),
      onPressed: () => _confirmAction(
        title: translate('禁用设备'),
        content: translate('禁用后该设备将无法连接服务器，确定继续？'),
        onConfirm: () => _model.blockDevice(d.id).then((ok) {
          if (!ok && mounted) {
            _showSnack(translate('操作失败，请检查连接'));
          }
        }),
      ),
    );
  }

  Widget _buildSessionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(translate('连接记录（最近 100 条）'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_model.sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text(translate('暂无记录'))),
              )
            else
              _buildSessionsTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionsTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 24,
        headingRowHeight: 36,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 48,
        columns: [
          DataColumn(label: Text(translate('开始时间'))),
          DataColumn(label: Text(translate('发起方 IP'))),
          DataColumn(label: Text(translate('结束时间'))),
          DataColumn(label: Text(translate('时长'))),
          DataColumn(label: Text(translate('状态'))),
        ],
        rows: _model.sessions.map((s) => _sessionRow(s)).toList(),
      ),
    );
  }

  DataRow _sessionRow(SessionRecord s) {
    return DataRow(cells: [
      DataCell(Text(_formatTime(s.startTime),
          style: const TextStyle(fontSize: 13))),
      DataCell(Text(s.ip, style: const TextStyle(fontSize: 13))),
      DataCell(Text(s.endTime != null ? _formatTime(s.endTime!) : '-',
          style: const TextStyle(fontSize: 13))),
      DataCell(Text(s.durationText, style: const TextStyle(fontSize: 13))),
      DataCell(
        s.paired
            ? (s.endTime != null
                ? Text(translate('已结束'),
                    style: TextStyle(color: Colors.grey[500], fontSize: 13))
                : Text(translate('进行中'),
                    style: const TextStyle(color: Colors.green, fontSize: 13)))
            : Text(translate('未建立'),
                style:
                    const TextStyle(color: Colors.orange, fontSize: 13)),
      ),
    ]);
  }

  String _formatTime(String raw) {
    // 只取 "yyyy-MM-dd HH:mm:ss" 部分
    if (raw.length >= 19) return raw.substring(0, 19);
    return raw;
  }

  void _confirmAction({
    required String title,
    required String content,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            child: Text(translate('取消')),
            onPressed: () => Navigator.pop(ctx),
          ),
          TextButton(
            child: Text(translate('确定')),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  Text(translate(label),
                      style: const TextStyle(fontSize: 13)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String label;
  final bool active;

  const _StatusDot({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? Colors.green : Colors.red,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
