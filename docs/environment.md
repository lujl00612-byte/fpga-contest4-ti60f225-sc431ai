# 本地环境（2026-09-30 已运行核对）

实际目录是 `E:\EE design\FPGA\嵌入式比赛 4`，环境元数据里的 `E:\电子设计\FPGA\嵌入式比赛 4` 已不存在。

| 工具 / 设备 | 本地位置 | 检查结果 |
| --- | --- | --- |
| MSYS2 | `E:\msys2` | 已找到，使用 UCRT64 环境 |
| Icarus Verilog | `E:\msys2\ucrt64\bin\iverilog.exe` | 12.0 stable，RTL 仿真可用 |
| Icarus runtime | `E:\msys2\ucrt64\bin\vvp.exe` | 12.0 stable，已执行回归 |
| Efinity | `..\efinity2025_clean\PFiles\Efinity\2025.1` | 2025.1.110 已实际生成 WB01 和 A7 位流 |
| Git | `E:\Git\cmd\git.exe` | 2.54.0.windows.1，仓库在 `contest4_dev` |
| Python | `C:\Python314\python.exe` | 3.14.3，用于本地 JTAG 工具 |
| USB FTDI | 本机 USB 设备 | A/B/C/D 四路正常；COM6、COM7、COM8、COM9 可见 |
| FPGA JTAG | FT4232 通道 B | IDCODE `0x10660A79`，配置状态 `0x0002D797` |

运行 Icarus 时，把 `E:\msys2\ucrt64\bin` 放在当前进程 PATH 前面，以便找到 DLL；`tools/test.ps1` 已自动处理。未修改全局 PATH。Efinity 2025.1 可以继续使用，当前任务不要求另装新版本。

本地环境包含实际可运行的 RTL 仿真、FPGA 综合 / 布局布线 / 位流生成和 SRAM 下载工具。构建过程临时 H: / V: 映射由脚本在退出时解除。
