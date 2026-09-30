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
| `A8-attempt`、`A8R1-attempt` | 完整连接开发中的两次硬件映射失败 | 算法仿真通过，保留失败源码和日志；无下载文件 |
| `A8R2` | 冻结 640×480 完整 8 邻域连接、打包 RAM、独立边缘标记 | 生成位流；像素时钟 setup +0.435 ns；全尺寸算法和跨 RAM 块测试通过；HDMI 实测待完成 |
| `WB02` | 按匹配的供应商示例补齐 DSI 时钟通道约束，增加适用配置检查 | 4,423 项白平衡检查；生成新位流；14 组 setup / 14 组 hold 均为正裕量；屏幕实测待完成 |
| `A9` | 利用原 ACK 周期寄存完整连接 RAM 写回，保持四周期接口 | 新 / 旧完整控制器各通过 640×480 对照；LUT −318、FF −61；像素 setup +0.556 ns；HDMI 实测待完成 |
| `A10` | 寄存 RAM 视频读出、后移边缘叠加，保持外部三拍与引擎四周期 | 像素 setup +0.916 ns；LUT +279、FF +85、RAM 不变；逐像素 / 边缘标记及全尺寸对照 PASS；HDMI 实测待完成 |

每个发布版本保存源码 Git 提交、位流、报告、SHA256 清单。工具产生的临时文件位于 `builds/`，不进入 Git。

## MIPI 白平衡操作

默认模式为彩色自动白平衡。使用原厂 3.5 寸屏的初始化配置，两个像素每时钟的 RGB888 数据通路。

- KEY0：白平衡 → 白平衡加增强 → 八色彩条 → 原色直通 → 白平衡。
- KEY3：选择增强模式，并循环增强强度。
- 红、蓝通道增益限制为 0.5–2.0，绿色作为参考；每帧统计使用原始像素，排除暗部、过曝和强烈彩色像素；增益缓慢变化。
- 彩条用于独立检查屏幕能否显示红、绿、蓝。若输入三个通道已完全相同，白平衡不能重建缺失的颜色。

WB01 在 2026-09-30 通过 SRAM JTAG 下载，IDCODE 为 `0x10660A79`，下载后状态 `0x0002D797`。这只能证明配置完成；用户目前不能查看板子，显示效果尚未验证。断电后 SRAM 配置丢失。

### 时序记录

视频时钟 `vid_clk_dvi2`：目标约 70 MHz，报告最高 152.393 MHz，setup 裕量 +7.724 ns。

DSI 路径 `i_mipi_tx_pclk → i_mipi_txd_sclk`：setup 裕量 **−0.900 ns**。WB01 是候选版本，不能标为全部时序通过；后续须检查原厂 DSI 时钟通道和约束依据。

WB02 已核对 Efinity 自带 Ti60F225 DSI 示例并补齐成对多周期约束：上述 DSI setup 为 +2.437 ns、hold 为 +1.842 ns，全报告静态时序通过。详见 `docs/WB02.md`。

后续现场排查：WB02 已下载，JTAG 状态正常，但用户报告没有摄像头画面。原厂 3.5 寸 Demo 的重新配置及断电重启对照也没有画面；当前板上保留原厂对照版本。显示链路、彩色和白平衡效果尚未验收。用户暂时没空看板子，先继续电脑上的迭代；独立彩条诊断与实际 GPIO 核对保留待做。记录见 `docs/hardware/20260930-mipi/validation.json`。

V4 原理图的 KEY0 对应实体丝印 **SW0**；装配图中四个用户按键为 SW0、SW1、SW2、SW3，上方另有复位按键。实际板卡的位置需结合其丝印核对；默认白平衡无需按键。

## 本地工具

- MSYS2：`E:\msys2`。
- Icarus Verilog：`E:\msys2\ucrt64\bin\iverilog.exe` / `vvp.exe`。
- Git：`E:\Git\cmd\git.exe`。
- Efinity 2025.1.110：`..\efinity2025_clean\PFiles\Efinity\2025.1`。

在本目录的 PowerShell 中运行：

```powershell
.\tools\test.ps1
.\tools\build.ps1 -Target mipi -Version WB03
.\tools\build.ps1 -Target hdmi -Version A11
& 'C:\Python314\python.exe' .\tools\jtag_load_sram.py --status
& 'C:\Python314\python.exe' .\tools\jtag_load_sram.py --status --program --bit .\releases\WB02\mipi\WB02.bit
```

构建脚本临时创建 H:（开发目录）和 V:（工具目录），正常完成或异常退出时解除映射。脚本会拒绝覆盖已存在的完整发布版本，并检查实际位流文件和时序，避免把工具空执行误认为构建成功。

MIPI 构建先检查供应商多周期约束的适用配置。上述构建命令中的版本号须为未占用名称；完成实质改进和验证后再建立发布标签。

赛题各项实现和缺口见 `docs/requirements.md`，迭代工作见 `docs/iteration-plan.md`。

A7 的具体功能、操作和资源对比见 `docs/A7.md`。

A8R2 的完整连接范围、O(P) 复杂度证明、RAM 优化和验证结果见 `docs/A8R2.md`。本机 MSYS2 / Efinity / Git / JTAG 核对结果见 `docs/environment.md`。

A9 的写回分级、实际四周期存储访问计数、资源与时序对照见 `docs/A9.md`。

A10 的视频读取分级、三拍像素与边缘标记对齐、资源代价及实际时序收益见 `docs/A10.md`。A9 和 A10 的计算周期相同；下一轮重点评估重复打包字访问的缓存，降低计算常数，复杂度仍须如实记录。

“赛题4持续迭代”后台任务已按用户要求暂停，应用任务 ID 为 4；本次 A10 已保存，后续计划及运行条件见 `docs/iteration-plan.md`。等待用户明确恢复后再继续。
