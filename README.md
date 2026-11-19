# 一格一局 · TapTap 数独小游戏

> 一款用 Lua 5.4 + UrhoX + TapTap Maker 开发的竖屏数独小游戏，附一套按实现顺序编排的开发教程。

## 这是什么

「一格一局」（原名「唯一解」）是一款完整可玩的数独游戏：四档难度按**解题所需的人类技巧**分级，提示分两步走（先讲理由、再落笔），支持自动候选、连续打卡、云存档与自定义错误上限。

这个仓库更有价值的部分是 **[docs/tutorial/](docs/tutorial/README.md)**——11 篇循序渐进的中文教程，把从算法到上架的每一步都拆开讲清楚。

## 快速导航

| 想了解什么 | 去哪里 |
|---|---|
| 完整教程目录与学习路线 | [docs/tutorial/README.md](docs/tutorial/README.md) |
| 数独生成与唯一解校验 | [02 数独生成与唯一解](docs/tutorial/02-数独生成与唯一解.md) |
| 难度分级怎么做 | [03 人类技巧评分器](docs/tutorial/03-人类技巧评分器.md) |
| 棋盘状态与撤销设计 | [05 棋盘会话状态机](docs/tutorial/05-棋盘会话状态机.md) |
| 引擎踩坑经验 | [10 音效与引擎避坑](docs/tutorial/10-音效与引擎避坑.md) |
| 测试与上架流程 | [11 测试、发布与迭代](docs/tutorial/11-测试发布与迭代.md) |

## 运行与自检

```bash
# 逻辑层自检（14 组断言）
NODE_OPTIONS="" npx -y @taptap/maker@latest preview validate \
  --target-dir "<本仓库绝对路径>" --entry dev/selftest.lua --mode validate

# 本地预览
NODE_OPTIONS="" npx -y @taptap/maker@latest preview run \
  --target-dir "<本仓库绝对路径>"
```

UI 部分依赖 TapTap Maker 的 UrhoX 运行时；`scripts/game/` 下的纯逻辑模块可单独测试。

## 目录结构

```
scripts/
├── main.lua          入口：生命周期、UI 组装、输入分发
├── game/             纯逻辑层：生成/评分/题库/状态/存档/音效
├── ui/               表现层：主题/棋盘/键盘/HUD
└── dev/              自检、题库生成与验收工具
assets/audio/         四个合成音效
.project/             Maker 工程配置与商店发布配置
docs/tutorial/        11 篇中文开发教程
```

## 技术要点

- **位掩码 + MRV 回溯**：生成保证唯一解的数独题
- **L1–L4 人类技巧评分**：唯一候选 / 唯一位置 / 区块排除 / 数对，用技巧等级定义难度
- **离线题库 + 日期哈希**：每档 20 题，每日一题无需服务端
- **快照式撤销**：填数与连带清笔记原子回滚
- **云变量 + 内存兜底**：适配引擎沙盒限制的存档方案
- **全面降级设计**：音效、云端、布局异常都不影响核心玩法

## 状态

已完成开发与真机验证，曾提交 TapTap 审核。首次因名称重名被驳回，已改名「一格一局」并重做物料。

教程中如实记录了开发过程中的设计取舍与踩坑经验，适合想了解「一款小游戏是怎么从零做到上架」的开发者阅读。
