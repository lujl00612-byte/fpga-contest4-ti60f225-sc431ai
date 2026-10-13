# FPGA 赛题 4：Ti60F225 / SC431AI 视频处理

Ti60F225 FPGA 上的摄像头采集、Sobel / Canny 边缘检测、帧冻结、简单形状识别，以及 3.5 寸 MIPI 屏白平衡与显示诊断工程。

本仓库整合了三个基础版本、进阶算法迭代、MIPI 候选、测试、构建报告和下载文件，保留完整 Git 历史与版本标签。整合日期：**2026-10-13**。最新 HDMI 算法版本为 **A15**，独立 MIPI 彩条诊断版本为 **WB03R1**。

**当前状态：电脑端验证已记录，实机验收尚未全部完成。** 完整 Canny 滞后连接目前处理冻结的右侧 640×480 ROI；连续视频仍采用局部近似，全帧实时完整 Canny 待完成。详见 [要求与验收状态](docs/requirements.md)。

## 1. 硬件与工具

| 项目 | 配置 |
| --- | --- |
| FPGA | 易灵思 Titanium Ti60F225I3 |
| 摄像头 | SC431AI MIPI CSI |
| 板载存储 | DDR3；算法状态使用 FPGA RAM |
| 显示输出 | HDMI 工程；3.5 寸 MIPI DSI 工程，两者分开构建 |
| 综合与布局布线 | Efinity 2025.1.110，匹配的设备支持与许可 |
| RTL 仿真 | Icarus Verilog，供应商 `EFX_RAM10` 模型 |
| 脚本环境 | Windows PowerShell、Python 3、Git |

Efinity 安装包、许可证、MSYS2、Icarus、Python 和 FTDI 驱动需自行安装。仓库包含项目所用示例 / IP 文件，第三方声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

实际板卡 PCB 版本、GPIO 方向与 IO 电平必须与工程匹配。当前 GPIO 的离线对照及差异记录见 [MIPI 诊断计划](docs/hardware/mipi-diagnostic-plan.md)，现场映射尚未确认。

## 2. 功能与实现范围

| 功能 | 实现与验证状态 |
| --- | --- |
| 摄像头接收、FIFO / DDR 缓冲 | 继承板卡参考采集链路；长时间帧计数与无丢帧实测待完成 |
| RGB 转灰度 | `(77R + 150G + 29B) >> 8`，使用乘加 / 移位 |
| 基础 Sobel | 3×3，两行缓冲，幅值 `abs(Gx) + abs(Gy)`，可调阈值 |
| HDMI 显示 | 1080p60 工程，灰度 / 二值分屏或红色边缘叠加；现场显示与无撕裂待验收 |
| 滤波、控制与识别 | 中值 / Gaussian、按键消抖、帧冻结、简单圆形 / 矩形标签；保存独立参考检查 |
| 完整滞后连接 | 冻结 640×480 ROI，完整 8 邻域连接，独立 BFS 对照，时间 O(P)、状态 4P 位加固定控制 / 缓存 |
| 连续 Canny | Gaussian、梯度、方向、NMS、双阈值与局部连接近似；全帧连续完整连接待完成 |
| MIPI 白平衡 | WB02 彩色直通、自动白平衡、色彩增强和依赖相机同步的彩条；显示效果待实测 |
| MIPI 独立诊断 | WB03R1 独立 RGB888 彩条 / 同步，两像素每拍，完整 32 位初始化延时；未下载到板子 |

### A15 的实际数据

| 指标 | A15 |
| --- | ---: |
| LUT / FF | 14,255 / 9,819 |
| RAM10 + DPRAM10 | 250 + 4 = 254/256 |
| 像素 setup / hold 裕量 | +1.241 ns / +0.026 ns |
| 时序关系 | 18 组 setup、18 组 hold 全为正 |
| 最长像素路径 | 9 级逻辑；A14 为 19 级 |
| 实际像素时钟 | 148.5 MHz |
| 缓存命中 / 未命中 | 2 / 4 周期 |
| 输出 RGB / DE / HS / VS / 边缘标记 | 三拍对齐 |
| 640×480 全弱无种子处理周期 | 1,044,480 |
| 640×480 全连通处理周期 | 11,768,920 |

处理段按 148.5 MHz 折算约 7.03 / 79.25 ms，未包括冻结、捕获、发布，尚未板上计时。全连通处理超过 60 Hz 单帧预算；报告分析频率 182.050 MHz 没有用于提高实际时钟。A15 与 A14 的处理周期相同，主要收益是译码路径缩短与时序裕量提高，代价为 FF 增加 82 个。完整记录见 [A15 报告](docs/A15.md)。

## 3. 仓库结构

```text
projects/
  hdmi/                 当前 A15 算法与 HDMI 工程、RTL、SDC、外设 XML、IP
  mipi/                 WB02 相机 → 白平衡 → 3.5 寸 DSI 工程
  mipi_diag/            WB03R1 独立 RGB888 彩条工程
tests/                  独立参考、缓存 / RAM / 同步 / AXI 检查与快速 RAM 模型
tools/                  仿真、构建、发布校验、GPIO 对照和 SRAM JTAG 脚本
docs/                   要求、各版报告、现场记录和后续计划
releases/               新位流、hex、资源 / 时序报告、验证记录和 SHA256
snapshots/              V1–V3、早期 A1–A6 等历史工程快照
THIRD_PARTY_NOTICES.md   第三方来源与许可说明
```

`builds/`、`.cache/` 和波形文件是本机输出，已在 `.gitignore` 中排除。历史失败候选有单独标签和诊断，不用旧位流替代失败构建。

## 4. 获取与配置

```powershell
git clone https://github.com/lujl00612-byte/fpga-contest4-ti60f225-sc431ai.git
cd fpga-contest4-ti60f225-sc431ai
git tag --list
```

在当前 PowerShell 会话中配置工具路径。下面是路径示例，请替换成自己的安装位置：

```powershell
$env:EFINITY_HOME = 'C:\Efinity\2025.1'
$env:IVERILOG_BIN = 'C:\msys64\ucrt64\bin'
$env:PYTHON_EXE = 'C:\Python314\python.exe'
```

- `EFINITY_HOME` 指向包含 `bin/efx_run.bat`、`sim_models/`、`ipm/` 的 Efinity 安装根目录。
- `IVERILOG_BIN` 指向同时包含 `iverilog.exe`、`vvp.exe` 的目录；二者已在 PATH 中时可不设置。
- `PYTHON_EXE` 指向 Python 可执行文件；`python.exe` 已在 PATH 中时可不设置。

当前脚本仍支持原开发机的工具布局作为默认值。原始构建日志、历史复现脚本和环境记录保留当时的本机路径；使用历史标签复现时，应按记录配置对应环境。新整合提交只调整入口脚本的工具定位，不改变已发布 RTL、约束或位流。

## 5. 仿真与发布完整性检查

完整常规回归：

```powershell
.\tools\test.ps1
```

A15 原始回归保存了 **320,951 项**检查，另含初始化延时 bit22 边界测试。缓存专项为 388 项；640×480 两场景 614,400 个单元以独立 BFS 对照通过。全尺寸检查使用经过小场景供应商模型校准的快速 RAM 模型；全部 120 块供应商 RAM 的连续读出、跨组及复位检查另有记录。详见 [A15 验证清单](releases/A15/hdmi/validation.json)。

独立 MIPI 诊断和完整 1080p 彩条检查：

```powershell
.\tools\test_mipi_diag.ps1 -DelayBoundary
.\tools\test_mipi_diag.ps1 -FullFrame -DelayBoundary
```

核对已保存 bit / hex 与证据 SHA256，**不访问板子**：

```powershell
& $env:PYTHON_EXE .\tools\verify_release.py A15 WB03R1
```

若使用 PATH 中的 Python，可将 `& $env:PYTHON_EXE` 替换为 `python`。发布完整性通过只说明文件与保存的哈希一致，实机验收状态见对应报告。

## 6. 构建与下载

在本仓库根目录运行，构建名称需使用尚未占用的新名字：

```powershell
.\tools\build.ps1 -Target hdmi -Version A15-reproduce
.\tools\build.ps1 -Target mipi -Version WB02-reproduce
.\tools\build.ps1 -Target mipi_diag -Version WB03R1-reproduce
```

流程依次执行 map、interface、pnr、pgm，输出到 `builds/<名称>/<目标>/`，保存文件到 `releases/<名称>/<目标>/`。已有完整发布目录不可覆盖。构建前需让 H:、V: 空闲；脚本临时映射仓库与工具目录，只清理由本次构建创建的映射。

**构建结束后检查 `manifest.json` 的 `timing_status`、setup / hold 负路径列表和报告。** 生成 bit 本身不等于时序通过。

下载文件入口：

- [A15 HDMI 位流](releases/A15/hdmi/A15.bit) · [构建清单](releases/A15/hdmi/manifest.json) · [证据哈希](releases/A15/hdmi/evidence-sha256.json)
- [WB02 白平衡位流](releases/WB02/mipi/WB02.bit) · [说明](docs/WB02.md)
- [WB03R1 独立彩条位流](releases/WB03R1/mipi_diag/WB03R1.bit) · [说明](docs/WB03R1.md)

可以使用 Efinity Programmer 配置 SRAM。自带 `tools/jtag_load_sram.py` 为 Windows FTDI D2XX 脚本，固定使用原开发机 FT4232 的接口索引 B / 1，预期 IDCODE 为 `0x10660A79`；在其他电脑先核对设备枚举、`ftd2xx.dll` 和板卡，不能直接假定索引相同。

```powershell
# 查询配置状态；会访问 JTAG
& $env:PYTHON_EXE .\tools\jtag_load_sram.py --status
# 在硬件映射和接线确认后，临时配置 SRAM
& $env:PYTHON_EXE .\tools\jtag_load_sram.py --status --program --bit .\releases\WB02\mipi\WB02.bit
```

这个脚本不写 SPI Flash；断电后 SRAM 配置丢失。

## 7. MIPI 模式与现场状态

WB02 默认自动白平衡，KEY0 循环白平衡 → 白平衡加增强 → 八色彩条 → 原色直通；KEY3 选择增强模式并循环强度。红 / 蓝增益限制 0.5–2.0，绿色作为参考，按帧平滑调整；统计排除暗部、过曝和强烈彩色像素。

WB02 的彩条继续依赖相机视频同步。WB03R1 自行产生同步，启动即显示独立彩条，不依赖相机 / DDR 视频或白平衡。WB03R1 的双 DSI 使能、首次 AXI 状态读地址和完整 32 位初始化延时已离线验证；采用 V4 参考 GPIO，实际 PCB 与电平尚待确认。

最近现场记录中，WB02 JTAG 配置成功但没有摄像头画面，原厂 3.5 寸 Demo 重载 / 冷启动对照也未恢复画面；板上保留原厂对照配置。HDMI 尚未连接。独立彩条、颜色、白平衡、D-PHY 启停、DDR 无撕裂、帧率和演示录像均有待现场验证，不能用仿真 / 时序 / JTAG 成功替代。

## 8. 版本与复现

| 标签 | 内容 |
| --- | --- |
| `legacy-V1`、`legacy-V2`、`legacy-V3` | 三个原始基础版本及快照 |
| `legacy-A1`–`legacy-A6` | 早期进阶版本及快照 |
| `A7`、`A8R2` | 基础 L1 Sobel、控制 / 识别、冻结 ROI 完整连接 |
| `A9`、`A10` | 写回和视频读出的流水分级 |
| `A11`、`A12` | 单字、双字缓存，减少处理常数 |
| `A13`、`A14`、`A15` | 分组 RAM 读出、两周期命中、基地址译码 |
| `WB01`、`WB02` | 白平衡、色彩增强及 DSI 时序修正 |
| `WB03R1` | 独立彩条与完整 32 位初始化延时 |
| `A8-attempt`、`A8R1-attempt`、`WB03-attempt` | 保存失败源码和诊断的候选 |
| `baseline-20260930`、`build-tools-01` | 开发基线与工具历史 |
| `public-package-20261013` | README、可配置工具入口、校验脚本和公开整合版本 |

查看历史版本可使用独立工作目录，避免改变当前源码：

```powershell
git worktree add --detach ..\contest4-A15 A15
```

标签保留当时源码与报告；对应版本的复现命令、输入哈希和验证范围见 `docs/<版本>.md` 及 `releases/<版本>/`。A15 原提交为 `64df1a89e802d5f644a4b33fe46969b80e1ab1c6`。

## 9. 后续工作与许可

下一步评估 RAM 未命中等待周期，在独立参考、缓存一致性和真实时序通过的条件下优化；继续补齐全帧实时完整 Canny、实际 GPIO 与 MIPI 显示、HDMI / DDR 现场验收和演示录像。计划见 [iteration-plan.md](docs/iteration-plan.md)。

本仓库未声明统一开源许可证；第三方示例、加密 IP 与资料的适用条件见 [第三方说明](THIRD_PARTY_NOTICES.md)。

本次整合内容、验证记录与离线 bundle 用法见 [公开整合包说明](docs/distribution.md)。
