量子围棋 / Quantum Go

双击 play.cmd 开始游戏。

命令行启动：
    QuantumGo.exe --main-pack QuantumGo.pck

这个目录是用「编辑器运行时 + pck」打的临时包：能直接跑，但运行时约 170 MB。
正式上架时，先在编辑器里下载 Godot 4.6.1 导出模板
（编辑器 → 管理导出模板 → 下载），然后执行：

    powershell -ExecutionPolicy Bypass -File tools/build_windows.ps1 -Full

就能得到体积正常的独立 exe。

Steam 上架时的启动选项填：
    可执行文件：QuantumGo.exe
    参数：--main-pack QuantumGo.pck
（换成 -Full 打包后，参数清空即可。）

steam_appid.txt 里现在是 480（Spacewar，Valve 的测试 AppID）。
拿到正式 AppID 后，把它改成正式值，并把
src/game/qg_platform.gd 里的 STEAM_APP_ID 同步改掉。
