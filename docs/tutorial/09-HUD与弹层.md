# 09 · HUD 与弹层

> 本篇目标：理解 HUD 的两行布局、六个覆盖层的职责，以及结算 / 失败 / 设置等交互流程。

## 9.1 HUD 是最大的 UI 文件

`scripts/ui/hud.lua` 有 807 行，是整个项目最长的文件。但它做的事情很单纯：**只显示状态，不碰业务规则**。所有决策（要不要开新局、要不要弹窗）都由 `main.lua` 通过 handler 回调注入。

## 9.2 两行 HUD

```lua
-- 第一行：难度 / 每日标记 / 新局
primaryRow = UI.Panel {
    children = {
        difficultyButton,   -- "难度 普通"
        dailyBadge,         -- "每日 ✓3" 或隐藏
        UI.Spacer{},
        newGameButton,      -- "新局"
    },
}

-- 第二行：用时 · 错误 / 设置 / 暂停
statusRow = UI.Panel {
    children = {
        timeLabel, mistakesLabel,
        UI.Spacer{},
        settingsButton, pauseButton,
    },
}
```

两行布局是后来重排的结果：早期把用时、错误、难度、按钮都塞在一行，手机上挤成一条。拆成两行后信息层级更清晰。

`statsBar`（成绩条）单独抽出来，由 `main.lua` 挂进 `boardArea_`，让它紧贴棋盘下方（见第 7 篇）。

## 9.3 时间格式化的坑

```lua
local function pad2(n)
    return (n < 10 and "0" or "") .. tostring(n)
end

function HUD.fmtTime(sec)
    local m = math.floor(sec / 60)
    local s = math.floor(sec % 60)
    return pad2(m) .. ":" .. pad2(s)
end
```

为什么手写 `pad2` 而不用 `string.format("%02d:%02d", m, s)`？

因为引擎的 i18n 模块重写了 `string.format`，而且 `.project/i18n.json` 里 `code.concat_to_format = true` 会把字符串拼接也改写成 format。结果是：传浮点给 `%d` 会抛错。

手写 pad + 字符串拼接 + 先 `math.floor`，彻底绕开这个坑。详见第 10 篇。

## 9.4 六个覆盖层

| 覆盖层 | 触发时机 | 主要内容 |
|---|---|---|
| `overlay` | 通关 | 用时、难度、错误数、提示次数、是否新纪录、再来一局 |
| `confirmOverlay` | 点新局 / 切换难度 | 二次确认，防止误触丢进度 |
| `pauseOverlay` | 点暂停 / 按 P | 遮住棋盘，防推演；继续 / 设置 |
| `settingsOverlay` | 点设置 | 4 项设置循环切换 |
| `failOverlay` | 错误次数达上限 | 失败提示 + **「去设置里调整」引导** |
| `toastPanel` | 轻提示 | 底部浮层，`bottom=196` 抬到键盘上方，`pointerEvents="none"` |

覆盖层用绝对定位挂在根节点末尾，按声明顺序层级递增。`isModalOpen()` 检查前五个任一可见，`main.lua` 据此屏蔽输入。

## 9.5 难度切换的两阶段

HUD 的难度按钮**只改待开局难度**，不立即换题：

```lua
function HUD.setDifficulty(label) ... end      -- 显示用
function HUD.setPendingMismatch(bool) ... end  -- 视觉提示"改动尚未生效"
```

真正的换题流程：

```
玩家点难度按钮 → pendingDifficulty_ 改变 → HUD 显示新标签 + mismatch 提示
→ 玩家点「新局」→ main 比较 pendingDifficulty_ 与 board_.difficulty
→ 不同则弹 confirmOverlay → 确认后 board_:reset(新难度)
```

这样避免了「手滑点一下难度，当前进度就没了」。

## 9.6 设置面板

四个设置项，每项点击循环切换：

| 设置 | 取值 | 说明 |
|---|---|---|
| 音效 | 开 / 关 | 控制 `Sfx.setEnabled` |
| 自动清笔记 | 开 / 关 | 填数后是否清同行列宫的同数字笔记 |
| 候选字号 | 10 / 11 / 12 | 传给 `boardView_:setCandidateFont` |
| 错误上限 | 不限 / 3 / 5 | 达到上限判负 |

`settingsOverlay` 里的每个按钮点击后：`settings:cycleXXX()` → `ApplySettings()` → `Storage.saveStats()`。设置内嵌在 `records.settings` 里一起落盘（第 6 篇）。

失败弹层里的「去设置里调整」按钮会关闭失败层并直接打开设置面板，让被错误上限卡住的玩家能立刻改规则。

## 9.7 每日标记

```lua
function HUD.setDaily(key, streak, clearedToday)
    if not key then dailyBadge:SetVisible(false); return end
    dailyBadge:SetVisible(true)
    dailyBadge:SetText("每日 " .. (clearedToday and "✓" or "×") .. streak)
end
```

每日局显示「每日 ✓3」表示已连续打卡 3 天，或「每日 ×3」表示今天还没做、当前连续 3 天。这个标记只在每日局出现。

## 9.8 Toast 的定位

`toastPanel` 的 `bottom = 196`，是刻意抬高的：

数字键盘高 52px，工具行高 42px，加上间距大约 196px。如果 toast 贴在屏幕最底部，会被键盘盖住。抬高后浮在键盘上方，玩家能看见提示。

`pointerEvents = "none"` 让 toast 不拦截点击——它只是提示，不该挡住下面的按钮。

## 9.9 结算展示

通关结算显示：

- 用时（大字）
- 难度 / 错误数 / 提示次数
- 是否刷新最佳（「首个记录已保存」或「比上次快 12 秒」）
- 「再来一局」和「看看棋盘」两个按钮

`main.lua` 在调用 `showResult` 之前已经完成：写记录、播胜利音、清存档。HUD 只负责展示传入的数据。

## 9.10 本篇小结

- HUD 只显示状态，所有决策通过 handler 回调交给 `main`。
- 两行布局把难度/新局和用时/设置分开，避免手机上拥挤。
- 时间格式化手写 pad，绕开 i18n 重写的 `string.format`。
- 六个覆盖层用绝对定位，`isModalOpen` 统一屏蔽输入。
- 难度切换是两阶段：先改待开局难度，点新局后才确认切换。
- 失败弹层提供「去设置里调整」的逃生口。

下一篇：[10 音效与引擎避坑](10-音效与引擎避坑.md) —— 汇总整个项目踩过的引擎陷阱。
