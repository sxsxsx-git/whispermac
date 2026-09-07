# WhisperMac UI 改进执行计划

视觉补充（2026-09-07）：[视觉与状态规格](ui-visual-spec.zh-CN.md) · [三态设计图、交互原型与检查记录](design/README.md)。后续实现须同时遵循视觉规格，不只按功能清单搬移控件。

## 0. 文档用途与基线

- **用途：** 给后续 AI 或开发者直接执行的 UI 改进计划；本文件本身不改变产品行为。
- **调查日期：** 2026-09-06。
- **代码基线：** `e9bf33fe159bc2f3be2636023ff17218ff68671a`（`Fix flaky notification content test racing LocalizationTests language switching`）。
- **调查方式：** 审计 Swift 源码、测试、README 和仓库内旧截图，并查阅 Apple 官方界面指南；没有修改应用源码。
- **证据边界：** 没有启动或操作当前 UI，也没有用户访谈；截图和 README 已落后于源码，布局问题属于静态审计发现的风险，不是当前界面的实测结论。
- **结论性质：** 下文的“现状”均以代码为准；布局、措辞和优先级是项目设计选择，不是 Apple 的强制规则。

## 1. 本轮目标和非目标

目标是在不改变本地转写引擎语义的前提下，让用户在 980×720 的原生 macOS 窗口中清楚完成：

1. 了解是否能开始、还缺什么，以及下一步是什么。
2. 添加和整理一批媒体文件，设置真正会影响这次任务的选项。
3. 在运行中看到可信的批次状态、可取消动作和诊断入口。
4. 结束后辨别成功、失败、取消，找到实际生成的结果。

本轮不做以下事情：

- 不改 `whisper-cli` 参数、模型解析、音频预处理、并发策略或输出命名语义。
- 不添加云端上传、账号、同步、字幕编辑器、播放器或结果编辑器。
- 不承诺每个导入扩展名的每一种编码都能被 `afconvert` 解码。
- 不把 README 的旧“没有内置下载 / 只有 TXT、SRT”描述反向实现到 UI。

## 2. 事实审计（实现前必须保留）

### 2.1 真实功能面

| 能力 | 代码证据 | 对 UI 的含义 |
| --- | --- | --- |
| 多文件选择、拖放、去重 | `PanelHelper.supportedMediaTypes`、`mediaFileAdditions`、`AppModel.addMediaURLs` | 队列应呈现批次，而不是暗示逐文件独立任务。 |
| 允许的导入类型 | MP4、M4A、MP3、WAV、AAC、MOV、M4V、FLAC | “可选择”只表示扩展名被接受；转码失败须显示真实 `afconvert` 错误。 |
| 输出格式 | `OutputFormat`: TXT、SRT、VTT、JSON；`WhisperInvocation.arguments` | 选项区必须露出全部四种格式。 |
| 语言与翻译 | `WhisperLanguage.common`、`sourceLanguage`、`translatesToEnglish` | 显示语言为本次任务选项；翻译写成“输出为英语”。 |
| 运行时补全 | `RuntimeInstaller`、`AppModel.startRuntimeDownload` | 缺模型 / Core ML encoder 时已有下载、进度、取消和错误状态。 |
| 加速模式 | `RuntimeModelResolver.prepare` | 请求 GPU + ANE 而缺 encoder 时会降级为 GPU，不应阻断基础转写。 |
| 结果 | `TranscriptionHistoryStore`、`installPreviewFiles` | 成功批次写历史，最多 100 条；内置预览目前**只解析 SRT**。 |
| 运行可见性 | `logs`、`LiveSegmentParser`、`TranscriptPreview` | 有日志和实时文本；后者最多 300 段。 |

代码导航（路径相对仓库根目录，符号优先于可能变化的行号）：

| 文件 | 首先检查的符号 / 内容 |
| --- | --- |
| `Sources/whispermac/ContentView.swift` | `body`、`fileSection`、`toolSection`、`actionSection`、`liveTranscriptSection`、`previewSection` |
| `Sources/whispermac/WhisperMacApp.swift` | `WindowGroup`、最小窗口及共享 `AppModel` |
| `Sources/whispermac/AppModel.swift` | `canStart`、`startTranscription`、`runTranscription`、`finishTranscriptionRun`、`installPreviewFiles` |
| `Sources/whispermac/TranscriptionService.swift` | `transcribeBatch`、进度和片段回调 |
| `Sources/whispermac/RuntimeInstaller.swift` | `install`、`RuntimeInstallerEvent`、下载与校验 |
| `Sources/whispermac/RuntimeModelResolver.swift` | `prepare`、请求模式和有效模式 |
| `Sources/whispermac/PanelHelper.swift` | `supportedMediaTypes`、`mediaFileAdditions` |
| `Sources/whispermac/TranscriptionHistory.swift` | `HistoryEntry`、`TranscriptionHistoryStore` |
| `Sources/whispermac/TranscriptPreview.swift` | SRT 解析、实时片段上限 |

### 2.2 当前层级与痛点

`ContentView.body` 将标题、输入、输出、运行时、动作、实时文本、预览、日志、历史依次放在一个纵向 `ScrollView`。信息量随运行状态增长，主动作离输入和结果较远；低频路径、日志、历史也占据主流程空间。

`WhisperMacApp` 已规定最小窗口为 **980×720**。P0 以此为必须可用的工作尺寸；不要在本轮把最小尺寸降到 860×640。那是 P2 的独立可行性评估，须先有真实布局测试。

README 与 `docs/screenshots/screenshot.png` 仍写 / 展示 TXT+SRT、无内置下载等旧信息。计划实施时可单列文档更新任务，但不得拿它们作为现状依据。

### 2.3 关键行为限制

- `AppModel.canStart` 检查：非运行、非下载、有输入、可解析的 CLI 和模型路径、至少一个格式。
- `configurationLooksReady` 只覆盖可解析的 CLI / 模型；两者都不是“该批一定可成功”的完整可用性校验。
- 输出目录会在服务中创建；权限、磁盘、媒体编码、启动子进程和模型准备仍可在运行时失败。
- 空输出路径的真实含义是“跟随每个输入文件所在目录”，不是全部保存到第一个文件的目录，也不是固定 Documents 目录。结果动作必须使用实际报告中的 URL；多目录结果不能用一个含糊的“打开输出目录”冒充全部结果。
- `RuntimeModelResolver.prepare` 会进行运行前文件操作：纯 GPU 且发现 Core ML 时创建临时符号链接。因此不要从 SwiftUI `body` 或频繁刷新路径中调用它；只在显式开始时调用。
- `startTranscription()` 构造 `AppConfigurationSnapshot`。运行中的参数应以该快照为准。
- 但“添加媒体”按钮和拖放当前并未在运行中禁用，`addMediaURLs` 也没有 `isRunning` guard；新项不会加入已开始的快照，容易造成 UI 队列与实际批次不一致。
- 清空和移除已有输入会因 `isBusy` / `isRunning` 被阻止；新添加的这条路径须在 P0 一并处理。
- `setFormat` 在只剩一种格式时静默拒绝关闭最后一个 Toggle。应明确告知“至少选择一种输出格式”，不能让控件看似已操作但无变化。

### 2.4 批处理与进度真实性

`TranscriptionService.transcribeBatch` 会先**依序预处理所有输入**为 WAV，再以一个 `whisper-cli` 调用传入全部 WAV 和输出前缀。`onInputStageChange` 有输入索引，适合展示预处理阶段的当前文件。

进入 Whisper 阶段后，服务只暴露一个批次进度数值和没有文件 ID 的 `onSegment(TranscriptSegment)`。当前 UI 用 18% 给全部预处理、82% 给 CLI 进度（`0.18 + 0.82 * progress`）。因此：

- 可以诚实显示“正在预处理第 2/4 个文件”以及“正在转写这个批次”。
- 不能伪造逐文件转写百分比、实时片段归属、逐项成功/失败、部分成功，或单项取消。
- 不能把 `100%` 等同于成功：当前异常路径也可能在结束时把进度置为 100%。最终结果必须单独显示 `成功`、`失败` 或 `已取消`。
- `finishTranscriptionRun` 令 `isRunning = false` 并清空 `liveSegments`；运行结束后实时文本区会消失。结果区必须接住结束后的信息，且只在有 SRT 时显示解析预览。

## 3. 原生 macOS 定位和设计原则

WhisperMac 是一个本地、单窗口、批量转写工具。它更接近“文件工作区 + 明确任务状态”，不是网页仪表盘，也不是具有复杂导航的编辑器。

采用以下 Apple Human Interface Guidelines 作为参考，而非把其中每条当作本项目约束：

- [Settings](https://developer.apple.com/design/human-interface-guidelines/settings/)：把低频、持久化的路径和界面语言归入设置。
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars/)：把常用、即时的窗口级动作放到工具栏或紧邻工作区的清晰动作区。
- [Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators/)：仅为已知进度使用确定式进度；下载未知总量时使用不确定式指示器并说明状态。
- [Color](https://developer.apple.com/design/human-interface-guidelines/color/)：成功、警告、失败使用语义色和文字，不把纯红 / 绿当作唯一信号。
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/)：键盘可达、VoiceOver 标签、动态文字和对比度从组件设计开始覆盖。

项目选择：保留既有 `GroupBox` 的原生语感、SF Symbols、系统字体、`.borderedProminent` 主按钮。避免自定义大面积渐变、网页式卡片墙和用颜色代替状态文案。

## 4. 推荐的信息架构

### 4.1 主窗口：全高任务队列 + 状态化主工作区 + 常驻底部动作栏

```text
┌──────────────────────────────── WhisperMac ─────────────────────────────────┐
│ WhisperMac                              [＋ 添加媒体] [历史] [设置…]     │
├───────────────────────────────┬─────────────────────────────────────────────┤
│ 任务队列                       │ 任务选项                                  │
│ ┌───────────────────────────┐ │ 输出位置  [跟随每个输入文件夹        ▾] │
│ │ ◉ interview.m4a           │ │ 格式      [✓ TXT] [✓ SRT] [ VTT] [JSON]│
│ │ ◉ meeting.mp4             │ │ 语言      [自动检测 ▾] [翻译为英语 ☐] │
│ │ ◉ lecture.flac            │ │ 加速      [GPU + ANE ▾]  实际：GPU     │
│ └───────────────────────────┘ │                                             │
│ 拖入媒体，或点“添加媒体”       │ 准备状态                                   │
│ [移除] [清空列表]              │ ● 可开始 / ! 缺少模型 [下载模型…]         │
│                               │ 运行时：任务摘要 + 实时文本               │
│                               │ 完成后：文件选择 + 仅 SRT 的只读预览       │
├───────────────────────────────┴─────────────────────────────────────────────┤
│ 状态：正在预处理 2/3 · meeting.mp4  ━━━━━━━━━━━━──── [停止] [开始转写]     │
└─────────────────────────────────────────────────────────────────────────────┘
```

实现含义：窗口由 64 pt 标题工具栏、236 pt 全高左队列、右侧状态化主工作区和 80 pt 常驻底栏组成。准备态右栏显示任务选项和就绪状态；运行态用冻结的任务摘要和实时文本取代可编辑选项；完成态用所选文件和仅 SRT 的只读预览取代运行内容，完整实际 URL 放入“全部输出…”sheet。没有旧式“上方两栏 + 下方结果与活动四分屏”。设置从工具栏进入；日志和历史按需以 sheet、检查器或明确入口打开，默认不占主区。

空队列是单独画面：左列给出轻量提示，右侧显示“准备转写”、40 pt 系统图标、添加媒体主按钮和输出/格式/语言三行默认摘要；“调整选项”打开完整准备表单。添加至少一个文件后才进入完整就绪态。配套的视觉规格和 HTML 原型见 [ui-visual-spec.zh-CN.md](ui-visual-spec.zh-CN.md) 与 `docs/design/whispermac-ui-prototype.html`；后者只是设计参考，不是 SwiftUI 截图或已实现功能。

建议起点（项目设计值，不是平台硬性要求）：工具栏 64 pt、底栏 80 pt、内容区顶部/水平内边距 28/32 pt、区块间距 24 pt、队列宽 236 pt（220–280 pt 可调），右栏弹性扩展。采用 8 pt 间距体系，主标题/正文/字幕/辅助/小标识为系统字体 22/13/14/12/11 pt；单一系统蓝 accent、语义状态色和细分隔，不堆叠阴影卡片或大标题渐变。队列行约 64 pt，含文件名与父目录。四种格式在窄空间固定两行，标签不要继续统一硬编码为 108 pt。保留系统正文样式，次要路径可中间截断，但必须可展开或复制。主区和队列各自滚动，底栏不参与页面滚动；错误说明可换行。P0 不新增装饰图或自绘控件。

### 4.2 设置、历史与日志归位

| 位置 | 内容 | 交互原则 |
| --- | --- | --- |
| 主工作区 | 空态入口/默认摘要；就绪时的输入、输出目录、格式、语言、翻译、加速；运行时的任务摘要和实时文本；完成时的产物与 SRT 预览 | 只呈现当前状态最需要的内容。 |
| Settings 场景或设置表单 | CLI 路径、模型路径、界面语言、运行时诊断、下载、帮助/README/GitHub 入口 | 持久化或低频维护项；打开后仍显示解析状态，帮助入口放在 sheet 底部。 |
| 按需入口 / 历史 | 成功批次的文件名、时间、输出、在 Finder 中显示、清除历史 | 历史是回顾，不是当前任务设置。保留清除确认。 |
| 按需入口 / 日志 | 可复制的过滤日志、失败详情、下载诊断 | 默认隐藏，不抢占主工作流；失败时自动打开。 |

不要在 P0 删除现有“选择 CLI / 模型”能力。若 Settings 场景的生命周期或共享 `AppModel` 复杂，先用主窗口的 Settings sheet，之后再拆为 `Settings` Scene。

## 5. 用户故事和完整流程

### 5.1 第一次启动：没有模型

1. 用户打开应用，主窗口显示空队列和“需要模型才能开始”的准备状态。
2. 若 CLI 可用、模型缺失，右侧空态显示“需要模型才能转写”，以“下载默认模型…”为主路径、“选择已有模型…”为次路径；工具栏添加媒体仍可用，但不应把添加写成当前主要修复动作。底栏禁用开始并写明“缺少模型”。用户明确点击后才开始联网下载。说明联网用于获取运行资源，转写媒体仍留在本机。下载总量未知时使用旋转指示和文字，已知时显示当前资源已下载字节 / 百分比。
3. 若缺 Core ML encoder 且请求 GPU + ANE，显示“将以 GPU 转写；可下载 encoder 以启用 ANE”，不能把它写成阻塞错误。
4. 若 CLI 缺失，优先显示“选择 CLI…”（现有下载器不自动下载 CLI），并保留可复制诊断信息。
5. 运行时完成后重新解析路径并更新为“可开始”；不承诺下载本身已验证真实转写。

### 5.2 从导入到结果

1. 用户点“添加媒体”或拖放；显示去重后的文件、文件数和可移除动作。
2. 用户设置输出位置、至少一种格式、音频语言、可选翻译和加速模式。
3. 开始前显示“本次将处理 N 个文件 / 输出为 TXT、SRT …”；点击开始后冻结可影响本次的 UI，或在允许添加时明确标为“将在下次任务处理”。P0 推荐直接禁用添加和拖放。
4. 预处理中显示“正在预处理 2/3：文件名”；转写中显示“正在转写此批次（3 个文件）”与 CLI 已报告的进度。
5. 用户可停止整个批次。停止后显示“已取消”，而不是“完成”。
6. 成功时显示“成功完成 N 个文件”，输出位置和 Finder 动作；如有 SRT，提供 SRT 预览；没有 SRT 时说明“此格式没有内置预览”。
7. 失败时显示“批次失败”，提供展开的真实错误和“查看日志”；不能填充未产生的输出或失败历史。

## 6. 可呈现的真实状态模型

| UI 状态 | 进入条件 | 主文案 | 主动作 | 禁用 / 提示 |
| --- | --- | --- | --- | --- |
| 空队列 | `inputFiles.isEmpty` 且资源可用 | 添加媒体以开始 | 添加媒体 | 开始按钮禁用，原因“先添加媒体”。 |
| 空队列 + 缺模型/CLI | `inputFiles.isEmpty` 且资源不可用 | 需要模型才能转写 / 需要 CLI 才能转写 | 下载默认模型 / 选择 CLI | 阻断资源动作优先；添加媒体保留为工具栏次级入口，禁用原因指出具体缺项。 |
| 配置不完整 | CLI 或模型无法解析 | 缺少 CLI / 模型 | 下载或选择 | 显示具体缺项，不能只显示橙色。 |
| 可开始 | `canStart` 为真 | 已准备好处理 N 个文件 | 开始转写 | 仍说明输出将会在开始时创建。 |
| 下载中 | `isDownloadingRuntime` | 下载 / 解压的当前状态 | 取消下载 | 禁用开始和会造成配置竞争的控制项。 |
| 预处理 | 快照已开始、`onInputStageChange` | 正在预处理 i/N | 停止 | 锁定队列与任务选项。 |
| 批次转写 | `onStageChange(.transcribing)` | 正在转写此批次 | 停止 | 不显示伪造的“第 i/N 个转写”。 |
| 取消中 | `isCancelling` | 正在停止… | 停止（禁用） | 保持状态直到任务真正结束。 |
| 成功 | 服务正常返回 | 批次处理完成 | 显示所选字幕 / 输出 | 主区只预览所选 SRT；“全部输出…”sheet 列实际报告 URL。若预期文件缺失，另显示输出异常，不能承诺全部导出成功。 |
| 失败 | 非取消错误或准备失败 | 批次失败 | 查看日志 / 重试 | 进度即使到 100% 也要显示失败。 |
| 已取消 | `CancellationError` | 已取消 | 重新开始 / 调整选项 | 独立终态；不写作成功，也不伪造部分成功。 |

## 7. 依赖顺序的可执行任务包

### P0 — 先建立可理解的任务工作区与真实终态

#### P0.1 定义呈现层状态合同

- **文件范围：** `Sources/whispermac/AppModel.swift`、必要时新增小型状态类型文件、`Sources/whispermac/Resources/{en,zh-Hans,ja}.lproj/Localizable.strings`。
- **实施：** 从现有 published 字段派生一个只读的 UI 状态 / 禁用原因；区分空队列、缺 CLI、缺模型、下载、预处理、批次转写、取消、成功、失败。保存最近一次终态摘要（状态、输出目录、错误摘要），以免 `isRunning` 结束后丢失结果语境。
- **状态合同：** 明确记录阶段和终态，不要反向解析本地化 `statusText`。下载、运行、取消中的状态优先于空队列提示；缺 CLI / 模型提示可以与空队列提示并存。需要新增终态字段时在真实完成 / catch 分支赋值，开始下一次任务时重置；不做全面 AppModel 架构重写。
- **实施：** 保持 `AppConfigurationSnapshot` 为唯一执行配置；运行中禁用添加和拖放，或将新项明确隔离到“下次任务”。首选前者，避免队列与快照不一致。
- **验收：** 不运行时，主按钮旁能读出准确禁用原因；取消、准备失败、转写失败和成功有不同文案。
- **风险：** 不要在 computed view state 内调用 `RuntimeModelResolver.prepare`；使用已有解析结果或仅在显式开始时准备。

#### P0.2 重组 `ContentView` 为两栏和常驻动作栏

- **文件范围：** `Sources/whispermac/ContentView.swift`、`Sources/whispermac/WhisperMacApp.swift`（只在需要窗口行为时）、本地化资源。
- **设计输入：** 以 `docs/ui-visual-spec.zh-CN.md` 为尺寸、颜色、三态和无障碍规格；在开始编码前查看 `docs/design/whispermac-ui-prototype.html`。HTML 仅帮助评审布局，不替代真实 SwiftUI 验证。
- **实施：** 提取 `TaskQueueView`、`EmptyTaskView`、`TaskOptionsView`、`RunSummaryView`、`LiveTranscriptView`、`RunResultView`、`PersistentActionBar` 等私有子视图。采用 64 pt 工具栏、236 pt 全高队列、右侧状态化主区、80 pt 常驻底栏；工具栏右侧为添加媒体、历史、设置，帮助入口在设置 sheet 底部。宽度至少 980 时采用该布局，保持小空间内可滚动且不裁切关键按钮。
- **实施：** 空队列时左列仅轻量提示，右侧显示“准备转写”、添加/拖放入口和输出/格式/语言默认摘要；已有输入后展示完整准备表单。运行时右侧改为冻结任务摘要与实时文本；完成时改为所选 SRT 的只读预览和“全部输出…”sheet。没有 SRT 时显示所选实际输出及无预览说明。不要实现旧式下方“结果与活动”分段大区，也不要在产品工具栏加入原型实验台的状态/语言/主题切换器。
- **实施：** 将开始 / 停止、状态文案和两种进度移到底部常驻区域；运行中不允许列表、输出格式、语言、翻译、加速、路径改变本次任务。停止为普通 destructive 边框按钮，不使用蓝色 prominent 样式；完成后底栏主动作显示所选字幕/输出，次动作“新建任务”不得自动开始或清空队列。
- **实施：** 以明确的辅助文字或禁用的最后格式 Toggle 实现“至少一种格式”；控制本身必须说明原因，不能继续静默拒绝操作。
- **实施：** 把 CLI / 模型路径与界面语言迁移到共享同一个 `AppModel` 的设置 sheet；主区保留准备摘要和“设置…”入口。README、GitHub 等帮助入口置于设置 sheet 底部，保留既有入口能力。首轮不要求独立 Settings Scene。
- **验收：** 在 980×720 不滚到页面底部也能看到开始 / 停止和状态；空态、就绪、运行和完成态不互相叠加；队列、当前选项、结果入口都可见或一键可达。检查 EN/ZH/JA、深浅色、大文字、键盘焦点、VoiceOver 和减少动态效果。
- **风险：** SwiftUI `List` 嵌套滚动区域容易抢滚动和压缩高度，优先实际试用后调 `frame`，不要只靠 Preview 判断。

#### P0.3 真实进度与终态展示

- **文件范围：** `Sources/whispermac/AppModel.swift`、`Sources/whispermac/ContentView.swift`、三套 `Localizable.strings`、必要的 `Tests/whispermacTests/*`。
- **实施：** 预处理阶段显示 `onInputStageChange` 提供的 i/N；转写阶段标为“批次转写”。保留 `18/82` 映射时标为“估算进度”，具体权重仅写在开发注释中；没有可靠进度事件时显示不确定式状态，不凭时间模拟百分比，也不估算剩余时间。
- **实施：** 成功必须由正常服务返回确认；失败和取消不能被 100% 覆盖。不要新增无法由现有服务提供的数据模型。
- **实施：** P0 在新布局内交付最近终态摘要、已确认的实际产物、以及当前已有 SRT 的选择和只读预览；无 SRT 时展示所选实际输出与无预览说明。完整实际 URL 可通过“全部输出…”sheet 查看。此项是结果布局的第一轮，不留给 P1 重做。
- **验收：** 用可控服务 / 测试覆盖成功、异常、取消三种结束路径；失败末尾仍显示失败，取消不创建成功摘要。
- **风险：** 不要声称逐文件转写进度、片段文件归属、部分成功或单项取消；这需要先修改服务回调和引擎编排，超出 P0。

### P1 — 补齐运行时、错误和辅助诊断

#### P1.1 缺失运行时和下载体验

- **文件范围：** `ContentView.swift`、`AppModel.swift`、`RuntimeInstaller.swift`（仅为已有事件补充展示信息）、三套本地化资源、下载测试。
- **边界：** P0 已将现有“下载默认模型 / 选择 CLI”置于空态的阻断资源主路径；本包只补足下载资源级阶段、错误、取消和回退信息，不改变 P0 的主窗口骨架或重做首次空态。
- **实施：** 将已有下载、取消、校验失败和解压状态放到准备状态及 Settings；未知下载总量使用不确定式进度，已知后切换确定式。
- **数据限制：** 现有安装器会顺序处理模型和 encoder，进度是当前下载文件的局部值，会重新从零开始。先补充类型化的资源名称 / 阶段事件，再显示“下载模型 / 下载 encoder / 校验 / 解压”；不要把局部进度写成整个安装的总进度，也不要声称现有下载只补齐用户缺失的单个组件。
- **实施：** 区分阻断项（CLI、模型）和可选项（Core ML encoder），显示请求模式与有效模式。
- **验收：** 现有运行时下载成功、取消、checksum / 失败 fixture 都能生成可理解文案；GPU + ANE 缺 encoder 仍可开始并显示 GPU 回退。
- **风险：** 不承诺下载或网络可靠性；保留错误原文在日志中供诊断。

#### P1.2 输出详情、日志和历史补强

- **文件范围：** `ContentView.swift`、`AppModel.swift`、`TranscriptPreview.swift`、`TranscriptionHistory.swift`、三套本地化资源、对应测试。
- **边界：** P0 已在新布局交付终态摘要、确认产物、当前已有 SRT 预览和“全部输出…”入口。本包只补充输出详情交互、日志/历史、实时跟随和异常场景，不能重新设计或移动 P0 的完成态骨架。
- **实施：** 补强“全部输出…”sheet 的实际 URL、格式和每项 Finder 动作；只有报告含 `.srt` 时才保留 SRT 选择器。无 SRT 时保持 P0 的所选实际输出与“此格式没有内置预览”。
- **实施：** 日志默认隐藏，失败时自动打开诊断入口；历史从明确入口或单独 sheet 打开，继续只记录成功批次、最新 100 条和现有清除确认。不要重新引入常驻的“结果与活动”四分屏。
- **实施：** 增加“复制日志”；实时文本提供“跟随最新”开关，用户向上阅读时暂停自动滚动。同名 SRT 的选择项附带父目录以便区分。运行结束后以最终产物为准；若额外保留实时草稿，须显式缓存并标为“实时草稿，非最终输出”，不能只改显示条件。
- **验收：** TXT/VTT/JSON-only 成功时不显示空的“转录预览”；SRT 成功可切换每个 SRT；失败 / 取消不会被计划为已有历史条目。
- **风险：** 若希望预览 TXT、VTT、JSON，需分别定义解析与错误语义，另开任务，不要复用 SRT parser 假装支持。

#### P1.3 错误可操作化

- **文件范围：** `AppModel.swift`、`ContentView.swift`、本地化资源、`ShellCommand.swift`（仅在错误结构确实缺字段时）。
- **实施：** 用户面显示动作导向摘要（如“模型文件不存在”“无法解码此媒体”“没有权限创建输出目录”），并提供“查看日志 / 重试 / 选择路径”；日志保留原始子进程错误。
- **验收：** 缺模型、不可执行 CLI、`afconvert` 失败、输出目录创建失败和非零 CLI 退出都有可读摘要和日志入口。
- **风险：** 不根据扩展名预先许诺可解码性；把实际运行失败解释为运行时失败。

#### P1.4 导入反馈

- **文件范围：** `PanelHelper.swift`、`AppModel.swift`、`ContentView.swift`、三套本地化资源、`PanelHelperMediaAdditionTests.swift`。
- **实施：** 保留已有过滤和去重行为，返回或派生“已加入 / 重复 / 不支持”数量；拖放区域明确文案及高亮。全部拒绝时不再无条件返回成功；运行期间统一阻止按钮、拖放及文件打开入口加入本次队列。
- **验收：** 混合支持 / 不支持文件、重复路径、全部拒绝和运行中导入都有准确反馈；支持的扩展名仍可由现有选择器导入。
- **风险：** 本任务不改变文件去重算法；文件可导入不等于已验证可解码。

### P2 — 打磨，须在 P0/P1 稳定后再做

- 评估 860×640 的最小窗口、列折叠和紧凑文案；若关键动作被截断，维持 980×720。
- 为 50 项以上队列评估紧凑 48 pt 行，同时保留文件名和父目录辅助文字；可再评估文件大小、完整路径、排序或拖动重排，前提是它们不会暗示并行 / 逐项控制。
- 为成功结果增加“复制输出路径”或“再次使用相同选项”，并明确其是否复用持久化值还是上次快照。
- 在实际 UI 录制后更新 README、截图和安装文档，另行核对发布资产与文档叙述。

## 8. 可访问性与本地化验收矩阵

| 维度 | 必测场景 | 通过标准 |
| --- | --- | --- |
| EN / ZH / JA | 空队列、缺模型、下载、运行、成功、失败、取消 | 无硬编码英文；长文案不遮挡主按钮；状态含义三语一致。 |
| 键盘 | Tab、Shift-Tab、Space、Return、Esc | 添加、格式、开始、停止、日志、Finder 动作都有可预测焦点和操作。 |
| VoiceOver | 读队列、格式、禁用开始、进度、错误、停止 | 每项有文件名 / 状态；进度含阶段；禁用原因和最后格式限制可被读出。 |
| 深色 / 浅色 | 空、警告、错误、成功、选中队列 | 系统语义色和文字共同传意；对比足够，未只靠红绿。 |
| 980×720 | 空队列、就绪、运行、完成、失败、取消 | 主动作栏始终可见；236 pt 队列和状态化右区不重叠；滚动不会困住焦点。 |
| 更大窗口 | 1440×900 或更大 | 队列和选项合理扩展，不留下无意义的大空白。 |
| 文件和错误 | 1 文件、3 文件、无 SRT、失败、取消 | 不制造单项进度 / 成功；结果与历史符合真实服务能力。 |
| 压力与路径 | 50 个队列项、同名不同目录、长文件名、不同输出目录 | 列表可滚动、名称可区分、Finder 指向实际产物。 |
| 运行时 | 缺 CLI、缺模型、仅缺 encoder、下载未知大小、阶段切换、取消、校验失败 | 不把可选 encoder 当阻断项；下载进度阶段明确，无虚假总百分比。 |
| 系统辅助设置 | 增大文字、增强对比度、减少动态效果 | 文案不裁切，状态仍可辨识，动画不是理解状态的必要条件。 |

## 9. 实施和评审约束

- 每个任务包形成独立、可审查的改动；先完成 P0.1，再做 P0.2 和 P0.3，P1 依赖 P0 的状态合同。未收到指令不自行提交、合并或发布。
- 遵循既有 `L.tr` 与三套 `.strings`；新增键必须同步 EN、简体中文、日文并补 `LocalizationTests`。
- 修改状态或业务映射时，优先测试纯状态映射；现有测试目录没有完整的 AppModel UI 测试基础设施，必要时加小型注入点或无副作用 fixture，避免测试下载真实模型或改写用户设置。布局变更须运行实际 app，而非只依赖 SwiftUI Preview。
- P0 实现后的最低验证：`swift build`、`swift test`、在 980×720 手工走空队列 / 缺模型 / 成功 / 失败 / 取消，以及 VoiceOver 和明暗主题抽查。回归重点为 `LocalizationTests`、`WhisperInvocationTests`、`OutputCollisionTests`、`RuntimeModelResolverTests`、`ShellCommandCancellationTests`、`TranscriptPreviewTests` 和 `TranscriptionHistoryTests`。
- 交付至少包含空队列、运行中、成功、失败四张当前 UI 截图，以及 EN/ZH/JA 和明暗主题的检查记录。缺真实媒体或模型时明确记录尚未完成的端到端验证，不把 fixture 当真实转写验证。
- 任何声称“逐文件转写”“部分成功”或“单项停止”的 PR，必须同时提交 `TranscriptionService` 能力改造、可归属回调和端到端测试；否则拒绝该表述。
- 不改引擎和数据语义的 UI PR 应避免触碰 `WhisperInvocation.swift`、`TranscriptionService.swift`、`RuntimeModelResolver.swift`；若必须触碰，先说明为何仅靠呈现层无法满足验收。

## 10. 交给执行 AI 的可复制提示词

```text
请在 WhisperMac 仓库实现 docs/ui-improvement-plan.zh-CN.md 的 P0.1 → P0.2 → P0.3，完成第一轮后交付。视觉规格以 docs/ui-visual-spec.zh-CN.md 为准，并在编码前查看 docs/design/whispermac-ui-prototype.html；HTML 是设计参考，不是已有 SwiftUI 功能或截图。P1/P2 是后续范围，本轮不自动展开。若我另行指定任务包，以该范围为准并检查其依赖是否已完成。

边界：只修改该任务包列出的文件及必要测试/三套本地化资源；不要改 whisper-cli 参数、批处理编排、云端能力或做字幕编辑器。保留用户已有的未提交改动。

先检查 git status、适用 AGENTS.md 和当前分支差异，再阅读 Sources/whispermac 下的 ContentView.swift、AppModel.swift、WhisperMacApp.swift、Models.swift、TranscriptionService.swift、RuntimeModelResolver.swift、TranscriptPreview.swift 和相关测试。以源码为准：已有模型下载、TXT/SRT/VTT/JSON、语言、翻译、实时片段、SRT 预览和成功历史；README/旧截图可能过时。若当前源码已完成计划中的某项，验证后跳过重复改造。

视觉要求：采用 64 pt 工具栏、236 pt 全高任务队列、状态化右主区、80 pt 固定底栏。工具栏右侧为添加媒体、历史、设置；帮助入口放在设置 sheet 底部。空队列左栏只显示轻量提示，右主区显示添加/拖放入口和三行默认摘要；若首次空态缺模型或 CLI，则阻断资源主动作优先为下载默认模型或选择 CLI，添加保持工具栏次级入口，底栏指出缺项。就绪时显示完整配置；运行时显示任务摘要和实时文本；完成时以所选 SRT 和只读预览为主，“全部输出…”sheet 列实际 URL；无 SRT 显示所选输出及无预览说明。完成底栏主动作显示所选字幕/输出，次动作为新建任务，不能自动开始或清空队列；取消是独立终态，给重新开始和调整选项。不要实现旧的下方“结果与活动”四分屏；日志按需显示。保持 macOS 原生系统字体主标题/正文/字幕/辅助/小标识为 22/13/14/12/11 pt，内容区顶部/水平内边距 28/32 pt、8 pt 间距、单一系统蓝 accent、语义状态色和细分隔；队列行约 64 pt，50 项后续可试 48 pt 而不丢父目录。停止是普通 destructive 边框按钮，不能做成蓝色 prominent。大文字 1.2×时底栏可增至 96 pt，关键动作仍可见。不要大标题渐变、网页卡片或阴影装饰。

真实性要求：服务先预处理全部输入，再以一个 whisper-cli 调用处理批次；onSegment 没有文件 ID。不得实现或文案宣称逐文件转写进度、片段归属、部分成功、单项取消。18/82 是当前估算映射；100% 绝不等于成功。明确成功、失败、已取消终态。GPU+ANE 缺 encoder 必须可回退 GPU。不要在 body 中调用 RuntimeModelResolver.prepare。

完成后：给出修改文件、关键行为、运行的命令与结果、截图、未运行的验证和风险。执行 swift build 和与改动相称的 swift test；如有视觉改动，启动 app 在 980x720 检查 EN/ZH/JA、键盘、VoiceOver、深/浅色。不要声称未执行的验证已经通过。不要自行提交、合并或发布。
```

## 11. 完成定义

当 P0 完成时，用户能在 980×720 清楚地了解“能否开始、为何不能、当前批次在做什么、结束是成功/失败/取消”，且 UI 未承诺现有服务不能提供的细粒度信息。

当 P1 完成时，首次缺模型引导、运行时下载、错误、SRT 结果预览、日志和成功历史都在合适位置，三种语言和基本辅助技术路径经实际运行验证。
