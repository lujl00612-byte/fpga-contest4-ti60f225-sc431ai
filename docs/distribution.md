# 公开整合包：2026-10-13

公开仓库：<https://github.com/lujl00612-byte/fpga-contest4-ti60f225-sc431ai>。

## 整合来源

- 原开发仓库的 A15 提交：`64df1a89e802d5f644a4b33fe46969b80e1ab1c6`。
- 从该提交独立克隆，保留原有 26 个提交及 26 个历史标签。
- `projects/`、`tests/`、`releases/`、`snapshots/` 的已跟踪内容保持一致。
- 新增整合标签 `public-package-20261013`，保存 README、工具入口配置、发布完整性校验和本次验证记录。
- 原开发目录保留；Efinity 安装、许可证、临时构建、缓存与波形不纳入公开仓库。

## 本次改动

1. README 统一说明三个工程、基础 / 进阶实现、A15 数据、版本选择、工具配置、仿真、构建和下载步骤。
2. `tools/toolchain.ps1` 支持 `EFINITY_HOME`、`IVERILOG_BIN`、`PYTHON_EXE`，并保留原环境的默认布局。
3. 仿真与构建入口使用上述配置；DSI 约束检查可指定 Efinity 安装根目录。
4. 独立 MIPI 测试入口自行创建缓存目录。
5. `tools/verify_release.py` 校验保存的 bit / hex 与可用证据清单，输出保存的时序状态，并明确不执行硬件验收。
6. 保留第三方版权声明，新增来源与许可说明。

## 验证

- 配置指定的 Efinity 2025.1.110、MSYS2 Icarus、Python 路径后，执行 `tools/test.ps1`：320,951 项常规检查通过，初始化延时 bit22 差值 4,194,304 周期通过。
- 缓存检查 388 项，100 次命中 / 65 次未命中；17 块供应商 RAM、快照对齐、4 个小场景独立 BFS、MIPI / AXI 及复位检查通过。
- `verify_release.py A15 WB03R1`：两个版本 bit / hex 哈希一致，A15 的 33 个证据文件长度 / 哈希一致。
- `check_dsi_constraints.py` 对 `projects/mipi`、`projects/mipi_diag` 均通过，供应商约束来源哈希不变。
- PowerShell 与修改的 Python 入口语法检查通过，README 的 14 个本地链接有效。
- 26 个历史标签指向原对象。历史 771 个 blob 的模式检查未发现所检查类型的令牌 / 私钥；最大 blob 约 2.37 MiB。

记录：[完整回归输出](public-package-20261013/regression.log)、[整合核对与文件哈希](public-package-20261013/verification.json)。

本次未改变 RTL / 约束，不生成新的算法位流或重跑 Efinity 综合。保存的 A15 / WB03R1 报告来自各自的原始构建，发布清单和证据保留原始内容。现场显示、颜色 / 白平衡、DDR 无撕裂、帧率、全帧实时完整 Canny 与演示录像的待验证状态不变。

## 离线 Git 包

整合版本另保存 Git bundle，包含完整历史、分支与版本标签，可独立恢复：

```powershell
git clone .\fpga-contest4-ti60f225-sc431ai-20261013.bundle fpga-contest4-offline
cd fpga-contest4-offline
git tag --list
```

bundle 与同名 `.sha256` 放在本地整合仓库的上级目录。GitHub 的 Code → Download ZIP 可以获取默认分支源码快照；ZIP 不包含 Git 历史和标签。
