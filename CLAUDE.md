# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# 调试构建并运行（需要 libsciter）
cargo run

# Flutter 桌面版
python3 build.py --flutter
python3 build.py --flutter --release

# 带特定 feature 构建
cargo build --features hwcodec
cargo build --features "flutter,hwcodec"

# Flutter 移动端
cd flutter && flutter build android
cd flutter && flutter build ios
cd flutter && flutter run

# 测试
cargo test
cd flutter && flutter test
```

**前置依赖**：设置 `VCPKG_ROOT` 环境变量；vcpkg 需安装 `libvpx libyuv opus aom`。

CI 构建通过 `.github/workflows/flutter-build.yml` 在 GitHub Actions 上自动执行，推送代码即可触发。

## Feature Flags

| Feature | 说明 | 平台 |
|---------|------|------|
| `flutter` | 启用 Flutter UI | 全平台 |
| `hwcodec` | 硬件视频编解码 | 全平台 |
| `vram` | VRAM 优化 | 仅 Windows |
| `screencapturekit` | macOS ScreenCaptureKit 屏幕捕获 | 仅 macOS |
| `unix-file-copy-paste` | Unix 文件剪贴板 | Linux/macOS |
| `plugin_framework` | 插件系统框架 | 全平台 |

## 架构概览

### 整体分层

```
Flutter UI (Dart)
      ↕  flutter_rust_bridge FFI
src/flutter.rs + src/flutter_ffi.rs   ← Rust 侧 FFI 接口层
      ↕
src/ui_interface.rs / ui_session_interface.rs / ui_cm_interface.rs
      ↕
src/client.rs (客户端) / src/server/ (服务端)
      ↕
libs/hbb_common/   ← 协议、网络、配置
libs/scrap/        ← 屏幕捕获
libs/enigo/        ← 键鼠模拟
libs/clipboard/    ← 剪贴板
```

### Flutter ↔ Rust FFI 边界

- **Rust 侧**：`src/flutter.rs`、`src/flutter_ffi.rs`（FFI 导出函数）
- **Dart 侧**：`flutter/lib/common.dart`（FFI 调用封装）
- 绑定通过 `flutter_rust_bridge` 自动生成

添加新接口：在 `flutter_ffi.rs` 导出函数，在 `flutter/lib/common.dart` 添加 Dart 封装。

### Server 模块（src/server/）

被控端运行的服务，每个服务独立 async 任务：

| 文件 | 职责 |
|------|------|
| `connection.rs` | 核心连接管理，处理完整连接生命周期 |
| `video_service.rs` | 屏幕捕获 + 视频编码 + 流传输 |
| `audio_service.rs` | 音频捕获与编码（Opus） |
| `input_service.rs` | 接收并执行远端键鼠指令 |
| `clipboard_service.rs` | 剪贴板同步 |
| `video_qos.rs` | 视频质量自适应控制 |

### 网络协议

- 会合服务器通信：`src/rendezvous_mediator.rs`（UDP/TCP）
- 传输层：支持 TCP 和 KCP（低延迟，`src/kcp_stream.rs`）
- 协议定义：`libs/hbb_common/src/protos/`（Protobuf）

### 配置系统

所有配置集中在 `libs/hbb_common/src/config.rs`，4 种类型：`Settings`、`Local`、`Display`、`Built-in`。

## 代码规范

### Rust

- 生产代码避免 `unwrap()` / `expect()`，用 `Result` + `?` 或显式处理
- 例外：测试代码、锁获取（失败即 poison，非正常控制流）
- 避免不必要的 `.clone()`，优先借用
- 不引入非必要依赖

### Tokio 异步

- 假设运行时已存在，不创建嵌套 runtime
- 不在 async 代码里调用 `Runtime::block_on()` 或 `std::thread::sleep()`
- 不跨 `.await` 持锁
- 阻塞操作用 `spawn_blocking` 或独立线程

### 编辑原则

- 只改必要的代码，保持最小 diff
- 不重构无关代码，不做纯格式修改
- 命名和风格与周边代码保持一致

## 忽略目录

- `target/` — Rust 构建产物
- `flutter/build/` — Flutter 构建输出
- `flutter/.dart_tool/` — Flutter 工具文件
