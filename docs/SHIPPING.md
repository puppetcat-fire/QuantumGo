# 上架清单 / Shipping checklist

用途：一份可以在 Steam 上卖的 Windows 版本。这份文档列清楚「已经做完的」和「还差什么的」，任何一项打勾之前都应该有可复现的验证。

## 一、产品层面

| 项 | 状态 | 说明 |
|---|---|---|
| 可玩的规则引擎 | ✅ | 确定性、可序列化；落子顺序由对局种子驱动，两边重放一致。215 项规则断言 + 134 项编码断言。虚子由种子决定、双方不可见（不完全信息），复盘时才揭示 |
| 本地双人 | ✅ | 同机双人，悔棋 / 停一手 / 认输 / 再来一局 |
| 联机对战 | ✅ | 房主权威 + ENet；局域网 / 直连可用，含断线与端口占用处理 |
| 结算 | ✅ | 双方停手后进入结算阶段：点掉死子、双方确认、拿走死子再数子 |
| 复盘 | ✅ | 对局结束后逐步回看；复盘里才显示当时哪颗是虚子，以及同一次分裂里对应的实子（宇宙编号 + 坐标） |
| 掉线处理 | ✅ | 对手掉线有明确提示，房主保持存活、不崩 |
| 排行榜 | ✅ 本地 / 🔌 在线 | 本地 Elo + 战绩 + 最近对局；在线走 Steam Leaderboards（代码已留接口，未接 SDK） |
| 新手引导 | ✅ | 五步互动教程，用真实棋盘和真实规则引擎带玩家走一遍分裂与坍缩（教程里会揭晓虚子） |
| 音效 | ✅ | 落子（逐手随机音高）/ 分裂 / 坍缩 / 停手 / 点击 / 标记死子 / 结算确认 / 胜负，全部程序合成，无第三方素材 |
| 音乐 | ✅ | 48 秒无缝循环氛围曲，`tools/make_music.py` 生成，设置里可关掉或调音量 |
| 双语界面 | ✅ | 中文为源文本，英文 372 条放在 `translations/en.json`；设置为「跟随系统 / 中文 / English」，切换即时生效 |

## 二、Steam 接入

| 项 | 说明 | 状态 |
|---|---|---|
| Steamworks 账号 | Steam Direct 100 美元/应用，收入满 1000 美元返还 | ⏳ 需要你办 |
| AppID | `src/game/qg_platform.gd` 里 `STEAM_APP_ID` 现在是 480（Spacewar 测试号），打包目录会带 `steam_appid.txt`，交付前换成正式号 | ⏳ |
| Steamworks SDK | 接 GodotSteam（GDExtension）。代码已按「有则用、无则跳过」写好，成就与排行榜的触发点已接并测试 | ⏳ 等 GDExtension |
| 成就 | 三个成就已定义并接入：首次量子步 / 首次坍缩 / 首胜。后台 API 名称见 `docs/STORE.md` | ⏳ 后台建成就 |
| 排行榜 | 每局结束提交加权总分 `TOTAL_WEIGHTED_SCORE`，后台建榜即可 | ⏳ 后台建榜 |
| 云存档 | 同步 `user://leaderboard.json` 与 `user://settings.cfg` | ⏳ |
| 内容调查 | Steam Content Survey 按实际填写 | ⏳ |
| 商店页 | 文案、截图清单、预告片脚本已写好，见 `docs/STORE.md` | ⏳ 上传素材 |

## 三、发行合规

- **税务**：中国个人开发者填 W-8BEN，版税预扣 10%；需要能收美元的银行账户或 Payoneer。
- **版号**：国际版 Steam 上架不要求版号；「蒸汽平台」版（Steam 中国）要求版号与出版资质。
- **许可**：仓库目前是木兰宽松协议 v2。商业发行前必须决定：转私有 / 换闭源 EULA / 双许可。注意已经按木兰发布的版本无法收回授权。
- **字体**：不要打包微软雅黑等系统字体（不可再分发）。目前用的是 OFL 授权的 Noto Sans SC，发布时带上 OFL 文本。
- **第三方素材**：所有音效、贴图必须自制或有可商用授权，并记录来源。本项目全部程序生成。

## 四、打包

| 项 | 状态 |
|---|---|
| 导出模板 | ❌ **拦路虎**：Godot 4.6.1 的 export templates 约 1.2 GB，这台机器的网络拉不下来（GitHub 直连约 4 MB/min，镜像多并发 Range 请求返回 429）。在编辑器里 `编辑器 → 管理导出模板 → 下载` 一次即可 |
| 临时可运行包 | ✅ `tools/build_windows.ps1` 能产出 `build/windows/`（`QuantumGo.exe` + `QuantumGo.pck` + `play.cmd`），用编辑器二进制当运行时，双击可玩，代价是 164 MB。Steam 启动选项填 `--main-pack QuantumGo.pck` |
| 正式导出版 | ⏳ 装好导出模板后跑 `tools/build_windows.ps1 -Full` |
| Windows 导出预设 | ✅ `export_presets.cfg` 已配好（x86_64、嵌入 pck、ico、版本号、排除 tests/tools/docs） |
| 图标 | ✅ `assets/icon.ico`（16–256 多尺寸）、`assets/icon.png`，由 `tools/make_icon.py` 生成 |
| 版本号 | ✅ `project.godot` 里 1.0.0 / 1.0.0.0 |
| 安装器 | ✅ 走 Steam depot 上传，不需要自建安装器 |

## 五、商店页

- 预告片（30–60 秒，必须出现「分裂 → 两个宇宙 → 坍缩」的镜头）
- 截图 5 张以上（多宇宙布局 / 坍缩瞬间 / 结算 / 复盘）
- 短描述与长描述（见 `docs/STORE.md`）
- 标签：`Board Game`、`Strategy`、`Abstract Strategy`、`Local Multiplayer`、`Online PvP`、`Turn-Based`
- 定价：参考同类抽象棋类独立游戏，2.99–9.99 美元区间

## 六、当前验证方式

```powershell
# 规则引擎 + 网络编码
godot --headless --path . --script res://tests/run_tests.gd          # 215 + 134 checks
# 会话层整体（含排行榜、存档、序列化、结算确认）
godot --headless --path . --script res://tests/run_session.gd        # 26 checks
# 联机集成（两个进程，4 个场景：完整对局 / 中途杀进程 / 拒绝连接 / 端口占用）
powershell -ExecutionPolicy Bypass -File tests/net/run_net_test.ps1
# 界面
godot --headless --path . --script res://tests/ui_shell/smoke.gd     # 98 checks
godot --headless --path . --script res://tests/ui_board/smoke.gd     # 58 checks
godot --path . --script res://tests/ui_board/click_smoke.gd          # 12 checks（真实鼠标事件路径）
godot --path . --script res://tests/ui_board/scoring_smoke.gd        # 13 checks（结算阶段）
godot --path . --script res://tests/ui_board/replay_smoke.gd         # 20 checks（隐藏虚子 + 复盘）
godot --path . --script res://tests/ui_tutorial/smoke.gd             # 21 checks + 4 张教程截图
godot --headless --path . --script res://tests/i18n/smoke.gd         # 26 checks（中英切换）
godot --headless --path . --script res://tests/platform/smoke.gd     # 21 checks（成就 / 排行榜触发点）
# 真实入口冒烟
godot --headless --path . --quit-after 30
# 打一个可以直接双击运行的包（临时方式，见上文）
powershell -ExecutionPolicy Bypass -File tools/build_windows.ps1
# 界面截图验收
godot --path . --script res://tools/shot.gd -- res://src/ui/match/match.tscn res://tmp/screens/match.png split 12
```

截图产物在 `tmp/screens/`：主菜单、联机大厅、排行榜、规则、设置、教程（1–5 步）、对局（1/2/3/4/6 宇宙、13 路聚焦、19 路聚焦、量子待选、封印、结算）、复盘。
