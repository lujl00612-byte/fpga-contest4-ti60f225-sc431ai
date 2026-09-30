# 赛题 4：Ti60F225 / SC431AI 视频处理

工作目录：`E:\EE design\FPGA\嵌入式比赛 4\contest4_work\contest4_dev`。

## 已保存的版本

| Git 标签 | 内容 | 验证范围 |
| --- | --- | --- |
| `legacy-V1`、`legacy-V2`、`legacy-V3` | 三个基础版本的原始源码和下载文件 | 保存原有构建报告；HDMI 现场验证待完成 |
| `legacy-A1` 至 `legacy-A6` | 六个进阶迭代版本 | 保存原有构建报告；完整滞后连接仍需补齐 |
| `baseline-20260930` | 从 A6 和原厂 3.5 寸彩色 Demo 建立的开发基线 | 原厂位流已核对 SHA256 |
| `WB01` | 3.5 寸 MIPI 屏白平衡、色彩增强、原色直通、彩条 | 4,423 项仿真检查；生成位流；JTAG 配置成功；DSI 时序有负裕量，画面待实测 |
| `A7` | 基础 L1 Sobel、原灰度 / 二值对照、整帧冻结、圆形 / 矩形文字 | 92,222 项检查 PASS；生成位流；像素时钟 setup +1.633 ns；HDMI 实测待完成 |

每个发布版本保存源码 Git 提交、位流、报告、SHA256 清单。工具产生的临时文件位于 `builds/`，不进入 Git。

## WB01 操作

默认模式为彩色自动白平衡。使用原厂 3.5 寸屏的初始化配置，两个像素每时钟的 RGB888 数据通路。

- KEY0：白平衡 → 白平衡加增强 → 八色彩条 → 原色直通 → 白平衡。
- KEY3：选择增强模式，并循环增强强度。
- 红、蓝通道增益限制为 0.5–2.0，绿色作为参考；每帧统计使用原始像素，排除暗部、过曝和强烈彩色像素；增益缓慢变化。
- 彩条用于独立检查屏幕能否显示红、绿、蓝。若输入三个通道已完全相同，白平衡不能重建缺失的颜色。

WB01 在 2026-09-30 通过 SRAM JTAG 下载，IDCODE 为 `0x10660A79`，下载后状态 `0x0002D797`。这只能证明配置完成；用户目前不能查看板子，显示效果尚未验证。断电后 SRAM 配置丢失。

### 时序记录

视频时钟 `vid_clk_dvi2`：目标约 70 MHz，报告最高 152.393 MHz，setup 裕量 +7.724 ns。

DSI 路径 `i_mipi_tx_pclk → i_mipi_txd_sclk`：setup 裕量 **−0.900 ns**。WB01 是候选版本，不能标为全部时序通过；后续须检查原厂 DSI 时钟通道和约束依据。

## 本地工具

- MSYS2：`E:\msys2`。
- Icarus Verilog：`E:\msys2\ucrt64\bin\iverilog.exe` / `vvp.exe`。
- Git：`E:\Git\cmd\git.exe`。
- Efinity 2025.1.110：`..\efinity2025_clean\PFiles\Efinity\2025.1`。

在本目录的 PowerShell 中运行：

```powershell
.\tools\test.ps1
.\tools\build.ps1 -Target mipi -Version WB02
.\tools\build.ps1 -Target hdmi -Version A7
& 'C:\Python314\python.exe' .\tools\jtag_load_sram.py --status
& 'C:\Python314\python.exe' .\tools\jtag_load_sram.py --status --program --bit .\releases\WB01\mipi\WB01.bit
```

构建脚本临时创建 H:（开发目录）和 V:（工具目录），正常完成或异常退出时解除映射。脚本会拒绝覆盖已存在的完整发布版本，并检查实际位流文件和时序，避免把工具空执行误认为构建成功。

赛题各项实现和缺口见 `docs/requirements.md`，迭代工作见 `docs/iteration-plan.md`。

A7 的具体功能、操作和资源对比见 `docs/A7.md`。
