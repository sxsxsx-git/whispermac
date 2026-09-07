<div align="center">

<img src="Assets/whispermac-app-icon-v2.png" width="160" alt="WhisperMac 应用图标" />

# WhisperMac

**免费、本地优先的 Apple Silicon 批量转写工具。**

你的媒体文件永远不离开你的 Mac —— 由 [whisper.cpp](https://github.com/ggml-org/whisper.cpp) 驱动，
Metal GPU 加速，可选 Core ML / 苹果神经网络引擎（ANE）encoder。

[English](README.md) · [简体中文](README.zh-CN.md)

<a href="https://github.com/sxsxsx-git/whispermac/releases">
  <img src="https://img.shields.io/github/v/release/sxsxsx-git/whispermac?display_name=tag&style=flat-square" alt="最新发布" />
</a>
<a href="https://github.com/sxsxsx-git/whispermac/stargazers">
  <img src="https://img.shields.io/github/stars/sxsxsx-git/whispermac?style=flat-square" alt="Stars" />
</a>
<img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square" alt="macOS 14+" />
<img src="https://img.shields.io/badge/Apple%20Silicon-必需-111111?style=flat-square" alt="需要 Apple Silicon" />
<img src="https://img.shields.io/badge/SwiftUI-原生%20macOS-0A84FF?style=flat-square" alt="SwiftUI 原生 macOS" />
<a href="LICENSE">
  <img src="https://img.shields.io/badge/许可证-MIT-success?style=flat-square" alt="MIT 许可证" />
</a>

[安装指南](docs/installation.md) · [常见问题](docs/faq.md) · [产品定位](docs/positioning.md) · [参与贡献](CONTRIBUTING.md) · [发布版本](https://github.com/sxsxsx-git/whispermac/releases)

<img src="docs/screenshots/ui-p0/02-ready-zh-light.png" width="840" alt="WhisperMac 就绪状态" />

**如果这个项目对你有帮助，欢迎点一个 Star ★ —— 这是对项目继续维护最明确的信号。**

</div>

---

## ✨ 为什么选 WhisperMac

大多数转写工具都让你二选一：把文件上传到云端服务，或者自己动手拼一套
`whisper.cpp` 命令行流程。WhisperMac 是第三条路 —— 一个**完全本地运行**的**原生
macOS 应用**：

- 🔒 **本地优先** —— 转写全部在你的 Mac 上完成；没有上传、没有账号
- 🖥️ **真正的 Mac 应用** —— SwiftUI 界面，带批量队列、实时文本和历史记录，不是终端的薄壳
- ⚡ **吃透 Apple Silicon** —— 明确的 `GPU（Metal）` 与 `GPU + ANE（Core ML）` 运行模式，并如实显示实际生效的是哪一种
- 📦 **一键运行时准备** —— 在应用内下载默认模型和 Core ML encoder，下载带校验
- 🌐 **界面本地化** —— English、简体中文、日本語

## 🎯 功能特性

| | 特性 | 说明 |
| --- | --- | --- |
| 🗂 | **批量队列** | 拖入 MP4 / MOV / M4V / M4A / MP3 / WAV / AAC / FLAC，自动去重，开始前可随时移除 |
| 📄 | **导出格式** | `TXT` · `SRT` · `VTT` · `JSON` —— 每次任务自由组合 |
| 🏠 | **输出位置合理** | 默认每个转写结果保存在源文件旁边；也可指定统一输出目录 |
| ⚡ | **加速模式** | `仅 GPU`（Metal）或 `GPU + ANE`（Metal + Core ML encoder）；缺 encoder 时自动回退 GPU 并提示 |
| 📥 | **内置运行时下载** | 从 Hugging Face 下载 `ggml-large-v3-turbo` 及 encoder 压缩包，SHA-256 校验、可看进度、可取消 |
| 📡 | **实时文本** | whisper 工作时逐段流式显示，支持“跟随最新”开关 |
| 👀 | **SRT 预览** | 批次刚结束就能在应用内直接阅读生成的字幕 |
| 🕘 | **历史记录** | 最近 100 条成功批次，一键在 Finder 中定位 |
| 🌍 | **语言控制** | 自动检测或固定音频语言；可选“输出为英语”翻译 |
| 🎹 | **键盘友好** | `⌘O` 添加媒体，支持完整键盘导航 |
| 🪟 | **响应式布局** | 从 980 px 最小窗口到全屏，工作区自适应重排 |
| 🔧 | **无需 FFmpeg** | 音频预处理使用 macOS 内置的 `afconvert` |

## 🚀 快速开始

### 方式 A —— 使用发布版

1. 从 [Releases 页面](https://github.com/sxsxsx-git/whispermac/releases) 下载最新的
   `WhisperMac-<tag>-app-only-macos-arm64.zip`。
2. 解压并把 `WhisperMac.app` 移到 `/Applications`（或任意位置）。
   如果被 macOS 拦截：右键 → **打开**，或执行 `xattr -cr /path/to/WhisperMac.app`。
3. 首次启动：如果缺少模型，点击 **下载默认模型…** —— WhisperMac 会自动下载并校验。
   你也可以在设置里指向已有的 `ggml` 模型文件。
4. 拖入文件、选择格式、按下 **开始转写**。

### 方式 B —— 从源码构建

```bash
git clone https://github.com/sxsxsx-git/whispermac.git
cd whispermac

# 一次性准备工具链 + whisper.cpp 运行时
xcode-select -s /Applications/Xcode.app
brew install cmake python@3.11
./scripts/setup-whispercpp.sh

# 运行
swift run

# 或构建可双击的 ./dist/WhisperMac.app
./scripts/build-app-bundle.sh
```

日常开发快捷方式：`./make-app.sh` 会在仓库根目录刷新一个 `WhisperMac.app`。

> [!TIP]
> 需要一个模型文件（如 `ggml-large-v3-turbo.bin`）。应用内下载器可以直接处理；
> 手动放置方法和可选的 Core ML encoder 见[安装指南](docs/installation.md)。

## ⚡ 性能实测

在单个 47 分钟的样本文件上（相同预处理 WAV 输入，两次运行间隔 120 秒散热，
被动散热的 Apple Silicon MacBook Air）：

| 模式 | 耗时 | 相对 |
| --- | --- | --- |
| `GPU + ANE` | 177.62 s | 快约 15.5% |
| `仅 GPU` | 205.22 s | 基准 |

这**不是**普适基准 —— 实际速度取决于模型选择、媒体内容、散热状况和当前
`whisper.cpp` 的行为。

## 🔍 工作原理

```
媒体文件 ──▶ afconvert（16 kHz 单声道 WAV）──▶ whisper-cli ──▶ TXT / SRT / VTT / JSON
                  macOS 内置                      whisper.cpp        默认保存在每个
                                                 Metal（+ANE）        源文件旁边
```

1. WhisperMac 用 macOS 内置的 `afconvert` 把每个输入转成 16 kHz 单声道 PCM WAV —— 不依赖 FFmpeg。
2. 整个批次通过一次 `whisper.cpp` 调用在你的机器上完成。
3. 在 Apple Silicon 上，`仅 GPU` 使用 Metal 后端；`GPU + ANE` 在存在匹配的
   `ggml-large-v3-turbo-encoder.mlmodelc` 时叠加 Core ML encoder。

> [!NOTE]
> 在当前 `whisper.cpp` 架构下，ANE 不会加速完整流水线：Core ML 路径加速的是
> **encoder**，解码仍使用 GPU/CPU。WhisperMac 始终如实显示实际生效的模式。

## 📸 界面一览

| 就绪（中文） | 运行中 | 完成（日本語） |
| :---: | :---: | :---: |
| <img src="docs/screenshots/ui-p0/02-ready-zh-light.png" width="280" alt="就绪状态" /> | <img src="docs/screenshots/ui-p0/03-running-zh-light.png" width="280" alt="运行状态" /> | <img src="docs/screenshots/ui-p0/05-complete-ja-light.png" width="280" alt="完成状态" /> |

窗口骨架（工具栏 / 任务队列 / 底部动作栏）保持稳定，右侧工作区在准备、运行、
结果三种状态之间切换。

## 🧭 产品定位

| | WhisperMac | 云端转写应用 | `whisper.cpp` 命令行 |
| --- | :---: | :---: | :---: |
| 文件留在本地 | ✅ | ❌ | ✅ |
| 带批量队列的图形界面 | ✅ | ✅ | ❌ |
| 免费且开源 | ✅ | ❌ | ✅ |
| 明确的 GPU/ANE 模式 | ✅ | 不一定 | 手动参数 |
| 字幕编辑 | ❌ | ✅ | ❌ |

完整对比见 [docs/positioning.md](docs/positioning.md)。

## 📚 文档

- [安装指南](docs/installation.md) —— 发布版、模型、首次运行
- [常见问题](docs/faq.md)
- [产品定位与对比](docs/positioning.md)
- [推广素材](docs/promotion-pack.md)
- [参与贡献](CONTRIBUTING.md)

## 🤝 参与贡献

欢迎提 Issue 和 Pull Request。开发细节见
[CONTRIBUTING.md](CONTRIBUTING.md) —— 测试套件用 `swift test` 运行。

## ⭐ Star History

[![Star History Chart](https://api.star-history.com/svg?repos=sxsxsx-git/whispermac&type=Date)](https://star-history.com/#sxsxsx-git/whispermac&Date)

## ⚠️ 已知限制

- 仅支持 Apple Silicon；Intel Mac 不是当前目标。
- 应用不会自动下载 `whisper-cli`（发布版已内置；源码构建请运行 `./scripts/setup-whispercpp.sh`）。
- `GPU + ANE` 需要在所选模型旁放置匹配的 Core ML encoder。
- 发布产物为 ad-hoc 签名，未做 Developer ID 签名或公证。
- 专注于转写与导出 —— 不是字幕编辑器。

## 📄 许可证

- 项目许可证：**MIT** —— 见 [LICENSE](LICENSE)
- 第三方声明：[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

WhisperMac 不打包或分发 FFmpeg。
