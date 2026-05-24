import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/platform_model.dart';

class DeviceInfo {
  final String id;
  final String? createdAt;
  final String? lastSeen;
  final String? lastIp;
  final bool online;
  final bool blocked;

  const DeviceInfo({
    required this.id,
    this.createdAt,
    this.lastSeen,
    this.lastIp,
    required this.online,
    required this.blocked,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        id: json['id'] ?? '',
        createdAt: json['created_at'],
        lastSeen: json['last_seen'],
        lastIp: json['last_ip'],
        online: json['online'] == true,
        blocked: json['blocked'] == true,
      );

  DeviceInfo copyWith({bool? blocked}) => DeviceInfo(
        id: id,
        createdAt: createdAt,
        lastSeen: lastSeen,
        lastIp: lastIp,
        online: online,
        blocked: blocked ?? this.blocked,
      );
}

class SessionRecord {
  final String id;
  final String startTime;
  final String? endTime;
  final String ip;
  final bool paired;
  final int? durationSeconds;

  const SessionRecord({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.ip,
    required this.paired,
    this.durationSeconds,
  });

  factory SessionRecord.fromJson(Map<String, dynamic> json) => SessionRecord(
        id: json['id'] ?? '',
        startTime: json['start_time'] ?? '',
        endTime: json['end_time'],
        ip: json['ip'] ?? '',
        paired: json['paired'] == true,
        durationSeconds: json['duration_seconds'],
      );

  String get durationText {
    if (durationSeconds == null) return '-';
    if (durationSeconds! < 60) return '${durationSeconds}秒';
    if (durationSeconds! < 3600) return '${durationSeconds! ~/ 60}分钟';
    return '${durationSeconds! ~/ 3600}小时${(durationSeconds! % 3600) ~/ 60}分钟';
  }
}

class AdminStats {
  final int totalDevices;
  final int onlineCount;
  final int todaySessions;
  final bool hbbsRunning;
  final bool hbbrRunning;

  const AdminStats({
    this.totalDevices = 0,
    this.onlineCount = 0,
    this.todaySessions = 0,
    this.hbbsRunning = false,
    this.hbbrRunning = false,
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) => AdminStats(
        totalDevices: json['total_devices'] ?? 0,
        onlineCount: json['online_count'] ?? 0,
        todaySessions: json['today_sessions'] ?? 0,
        hbbsRunning: json['hbbs_running'] == true,
        hbbrRunning: json['hbbr_running'] == true,
      );
}

class AdminModel with ChangeNotifier {
  List<DeviceInfo> devices = [];
  List<SessionRecord> sessions = [];
  AdminStats stats = const AdminStats();
  bool loading = false;
  String? error;

  String get baseUrl {
    var url = bind.mainGetOptionSync(key: 'admin-url');
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
  String get token => bind.mainGetOptionSync(key: 'admin-password');

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  bool get isConfigured => baseUrl.isNotEmpty && token.isNotEmpty;

  Future<void> refresh() async {
    if (!isConfigured) {
      error = '请先在网络设置中配置管理后台地址和密码';
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      await Future.wait([
        _fetchStats(),
        _fetchDevices(),
        _fetchSessions(),
      ]);
    } catch (e) {
      error = '请求失败：$e';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _fetchStats() async {
    final r = await http
        .get(Uri.parse('$baseUrl/api/stats'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (r.statusCode == 200) {
      stats = AdminStats.fromJson(jsonDecode(r.body));
    } else {
      throw Exception('stats 请求失败 ${r.statusCode}');
    }
  }

  Future<void> _fetchDevices() async {
    final r = await http
        .get(Uri.parse('$baseUrl/api/devices'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body);
      devices = (data['devices'] as List)
          .map((e) => DeviceInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> _fetchSessions() async {
    final r = await http
        .get(Uri.parse('$baseUrl/api/sessions'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body);
      sessions = (data['sessions'] as List)
          .map((e) => SessionRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<bool> blockDevice(String id) async {
    try {
      final r = await http
          .post(Uri.parse('$baseUrl/api/blocklist/$id'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        devices = devices
            .map((d) => d.id == id ? d.copyWith(blocked: true) : d)
            .toList();
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> unblockDevice(String id) async {
    try {
      final r = await http
          .delete(Uri.parse('$baseUrl/api/blocklist/$id'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        devices = devices
            .map((d) => d.id == id ? d.copyWith(blocked: false) : d)
            .toList();
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }
}
