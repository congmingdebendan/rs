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

  // 设备分组筛选
  String _groupFilter = '全部';
  // 连接记录筛选
  String _sessionIpFilter = '';
  String _sessionStatusFilter = '全部';

  List<DeviceInfo> get _filteredDevices {
    if (_groupFilter == '全部' || !_model.allGroups.contains(_groupFilter)) {
      return _model.devices;
    }
    return _model.devices
        .where((d) => (_model.groups[d.id] ?? '') == _groupFilter)
        .toList();
  }

  List<SessionRecord> get _filteredSessions {
    return _model.sessions.where((s) {
      if (_sessionIpFilter.isNotEmpty && !s.ip.contains(_sessionIpFilter)) {
        return false;
      }
      switch (_sessionStatusFilter) {
        case '已配对':
          return s.paired;
        case '未配对':
          return !s.paired;
        case '进行中':
          return s.paired && s.endTime == null;
        default:
          return true;
      }
    }).toList();
  }

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
  void dispose() {
    _model.dispose();
    super.dispose();
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(translate('自动刷新'),
                  style: const TextStyle(fontSize: 12)),
              Switch(
                value: _model.autoRefresh,
                onChanged: (v) => _model.setAutoRefresh(v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(width: 4),
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
    final hasGroups = _model.allGroups.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(translate('设备列表'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            if (hasGroups) ...[
              const SizedBox(height: 8),
              _buildGroupFilter(),
            ],
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

  Widget _buildGroupFilter() {
    final groups = ['全部', ..._model.allGroups];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: groups
            .map((g) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(g, style: const TextStyle(fontSize: 13)),
                    selected: _groupFilter == g,
                    onSelected: (_) => setState(() => _groupFilter = g),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildDevicesTable() {
    final filtered = _filteredDevices;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 24,
        headingRowHeight: 36,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 48,
        columns: [
          DataColumn(label: Text(translate('设备 ID'))),
          DataColumn(label: Text(translate('备注'))),
          DataColumn(label: Text(translate('分组'))),
          DataColumn(label: Text(translate('系统'))),
          DataColumn(label: Text(translate('最后在线'))),
          DataColumn(label: Text(translate('IP 地址'))),
          DataColumn(label: Text(translate('状态'))),
          DataColumn(label: Text(translate('操作'))),
        ],
        rows: filtered.map((d) => _deviceRow(d)).toList(),
      ),
    );
  }

  DataRow _deviceRow(DeviceInfo d) {
    final note = _model.notes[d.id];
    final group = _model.groups[d.id];
    return DataRow(cells: [
      DataCell(SelectableText(d.id,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
      DataCell(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              note?.isNotEmpty == true ? note! : '-',
              style: TextStyle(
                fontSize: 13,
                color: note?.isNotEmpty == true ? null : Colors.grey[400],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.edit, size: 12, color: Colors.grey),
          ],
        ),
        onTap: () => _showNoteDialog(d),
      ),
      DataCell(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              group?.isNotEmpty == true ? group! : '-',
              style: TextStyle(
                fontSize: 13,
                color: group?.isNotEmpty == true ? null : Colors.grey[400],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.edit, size: 12, color: Colors.grey),
          ],
        ),
        onTap: () => _showGroupDialog(d),
      ),
      DataCell(Text(d.platform ?? '-', style: const TextStyle(fontSize: 13))),
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
    final filtered = _filteredSessions;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '连接记录（${filtered.length} / ${_model.sessions.length}）',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildSessionFilter(),
            const SizedBox(height: 12),
            if (_model.sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text(translate('暂无记录'))),
              )
            else if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text(translate('无匹配记录'))),
              )
            else
              _buildSessionsTable(filtered),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionFilter() {
    return Row(
      children: [
        SizedBox(
          width: 160,
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'IP 过滤',
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search, size: 16),
            ),
            style: const TextStyle(fontSize: 13),
            onChanged: (v) => setState(() => _sessionIpFilter = v.trim()),
          ),
        ),
        const SizedBox(width: 12),
        DropdownButton<String>(
          value: _sessionStatusFilter,
          isDense: true,
          items: ['全部', '已配对', '未配对', '进行中']
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s, style: const TextStyle(fontSize: 13)),
                  ))
              .toList(),
          onChanged: (v) =>
              setState(() => _sessionStatusFilter = v ?? '全部'),
        ),
      ],
    );
  }

  Widget _buildSessionsTable(List<SessionRecord> sessions) {
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
        rows: sessions.map((s) => _sessionRow(s)).toList(),
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
                    style:
                        const TextStyle(color: Colors.green, fontSize: 13)))
            : Text(translate('未建立'),
                style: const TextStyle(color: Colors.orange, fontSize: 13)),
      ),
    ]);
  }

  String _formatTime(String raw) {
    if (raw.length >= 19) return raw.substring(0, 19);
    return raw;
  }

  Future<void> _showNoteDialog(DeviceInfo d) async {
    final controller =
        TextEditingController(text: _model.notes[d.id] ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('设备备注 · ${d.id}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入备注（留空则删除备注）',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            child: Text(translate('取消')),
            onPressed: () => Navigator.pop(ctx),
          ),
          TextButton(
            child: Text(translate('保存')),
            onPressed: () {
              _model.saveNote(d.id, controller.text.trim());
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showGroupDialog(DeviceInfo d) async {
    final controller =
        TextEditingController(text: _model.groups[d.id] ?? '');
    final existingGroups = _model.allGroups;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('设备分组 · ${d.id}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '输入分组名（留空则不分组）',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              autofocus: existingGroups.isEmpty,
            ),
            if (existingGroups.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: existingGroups
                    .map((g) => ActionChip(
                          label: Text(g,
                              style: const TextStyle(fontSize: 12)),
                          onPressed: () => controller.text = g,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            child: Text(translate('取消')),
            onPressed: () => Navigator.pop(ctx),
          ),
          TextButton(
            child: Text(translate('保存')),
            onPressed: () {
              _model.saveGroup(d.id, controller.text.trim());
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
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
