-- ============================================================================
-- HUD：顶部状态条（难度 / 每日 / 用时 / 错误 / 暂停 / 新局）+ 通关 / 确认 / 暂停覆盖层
--   · 难度按钮只切换「待开局难度」，不直接开新局（避免误触冲掉进度）
--   · 开新局由 main 判断是否有进度，需要时走 showConfirm 二次确认
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require "ui.theme"
local Sudoku = require "game.sudoku"

local HUD = {}
HUD.__index = HUD

local C = Theme.COLORS
local S = Theme.SIZE
local F = Theme.FONT

local function pad2(n)
    n = math.floor(tonumber(n) or 0)
    if n < 10 then
        return "0" .. n
    end
    return tostring(n)
end

--- 秒 → mm:ss（不用 string.format，避免引擎 i18n 包装对浮点报错）
local function fmtTime(sec)
    sec = math.floor(tonumber(sec) or 0)
    if sec < 0 then
        sec = 0
    end
    return pad2(math.floor(sec / 60)) .. ":" .. pad2(sec % 60)
end

HUD.fmtTime = fmtTime

local function difficultyLabel(key)
    for _, d in ipairs(Sudoku.DIFFICULTIES) do
        if d.key == key then
            return d.label
        end
    end
    return "普通"
end

---@param handlers table { onNewGame, onCycleDifficulty, onConfirmNewGame, onDaily, onPause, onResume, onSettings, onToggleSound, onToggleAutoClean, onCycleFont, onCycleLimit, onRetry, onHome }
function HUD.new(handlers)
    local self = setmetatable({ lastTimeText = "" }, HUD)

    self.difficultyButton = UI.Button {
        text = "难度 普通",
        height = 32,
        fontSize = F.small,
        backgroundColor = C.accentSoft,
        hoverBackgroundColor = C.cellSelected,
        pressedBackgroundColor = C.cellSelected,
        textColor = C.accent,
        borderRadius = 16,
        paddingHorizontal = 12,
        onClick = function()
            handlers.onCycleDifficulty()
        end,
    }

    self.timerLabel = UI.Label {
        text = "用时 00:00",
        fontSize = F.body,
        fontColor = C.textPrimary,
    }

    self.mistakesLabel = UI.Label {
        text = "错误 0",
        fontSize = F.small,
        fontColor = C.textMuted,
    }

    self.newGameButton = UI.Button {
        text = "新局",
        height = 32,
        fontSize = F.small,
        backgroundColor = C.surface,
        hoverBackgroundColor = C.accentSoft,
        pressedBackgroundColor = C.accentSoft,
        textColor = C.textPrimary,
        borderRadius = 16,
        paddingHorizontal = 12,
        onClick = function()
            handlers.onNewGame()
        end,
    }

    self.dailyButton = UI.Button {
        text = "每日",
        height = 32,
        fontSize = F.small,
        backgroundColor = C.surface,
        hoverBackgroundColor = C.accentSoft,
        pressedBackgroundColor = C.accentSoft,
        textColor = C.textPrimary,
        borderRadius = 16,
        paddingHorizontal = 10,
        onClick = function()
            handlers.onDaily()
        end,
    }

    self.pauseButton = UI.Button {
        text = "暂停",
        height = 28,
        fontSize = F.small,
        backgroundColor = { 0, 0, 0, 0 },
        hoverBackgroundColor = C.accentSoft,
        pressedBackgroundColor = C.accentSoft,
        textColor = C.textMuted,
        borderRadius = 14,
        paddingHorizontal = 8,
        onClick = function()
            handlers.onPause()
        end,
    }

    -- 常驻返回入口：对局中任意状态（进行中 / 暂停 / 通关后看盘 / 失败）一键回主菜单，
    -- 进度由 main 的 GoHome 自动保存，不会丢
    self.homeButton = UI.Button {
        text = "主界面",
        height = 28,
        fontSize = F.small,
        backgroundColor = { 0, 0, 0, 0 },
        hoverBackgroundColor = C.accentSoft,
        pressedBackgroundColor = C.accentSoft,
        textColor = C.textMuted,
        borderRadius = 14,
        paddingHorizontal = 8,
        onClick = function()
            handlers.onHome()
        end,
    }

    -- 上排：操作（难度 / 每日 / 新局）
    self.primaryRow = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = {
            self.difficultyButton,
            self.dailyButton,
            UI.Spacer(),
            self.newGameButton,
        },
    }

    self.settingsButton = UI.Button {
        text = "设置",
        height = 28,
        fontSize = F.small,
        backgroundColor = { 0, 0, 0, 0 },
        hoverBackgroundColor = C.accentSoft,
        pressedBackgroundColor = C.accentSoft,
        textColor = C.textMuted,
        borderRadius = 14,
        paddingHorizontal = 8,
        onClick = function()
            handlers.onSettings()
        end,
    }

    -- 下排：状态（用时 / 错误）与暂停
    self.statusRow = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = {
            self.timerLabel,
            UI.Label { text = "·", fontSize = F.small, fontColor = C.textMuted },
            self.mistakesLabel,
            UI.Spacer(),
            self.settingsButton,
            self.pauseButton,
            self.homeButton,
        },
    }

    self.root = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 4,
        children = {
            self.primaryRow,
            self.statusRow,
        },
    }

    -- 成绩条：连续打卡 / 累计通关 / 当前难度最佳
    self.statsLabel = UI.Label {
        text = "",
        fontSize = F.tiny,
        fontColor = C.textMuted,
        textAlign = "center",
        width = "100%",
    }

    self.statsBar = UI.Panel {
        width = "100%",
        height = 22,
        alignItems = "center",
        justifyContent = "center",
        children = { self.statsLabel },
    }

    -- ---------------------------------------------------------------------
    -- 通关覆盖层
    -- ---------------------------------------------------------------------
    self.resultTimeLabel = UI.Label { text = "", fontSize = F.body, fontColor = C.textSecondary }
    self.resultDetailLabel = UI.Label { text = "", fontSize = F.small, fontColor = C.textMuted }
    self.recordLabel = UI.Label { text = "", fontSize = F.small, fontColor = C.accent }
    self.extraLabel = UI.Label { text = "", fontSize = F.tiny, fontColor = C.textMuted }

    self.overlay = UI.Panel {
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        visible = false,
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = C.overlay,
        children = {
            UI.Panel {
                width = 280,
                padding = 24,
                gap = 10,
                alignItems = "center",
                backgroundColor = C.surface,
                borderRadius = 16,
                children = {
                    UI.Label {
                        text = "通关！",
                        fontSize = 22,
                        fontColor = C.textPrimary,
                    },
                    self.resultTimeLabel,
                    self.resultDetailLabel,
                    self.recordLabel,
                    self.extraLabel,
                    UI.Panel { height = 6 },
                    UI.Button {
                        text = "再来一局",
                        width = "100%",
                        height = 44,
                        fontSize = F.body,
                        variant = "primary",
                        backgroundColor = C.accent,
                        hoverBackgroundColor = C.accentPressed,
                        pressedBackgroundColor = C.accentPressed,
                        textColor = C.surface,
                        onClick = function()
                            handlers.onNewGame()
                        end,
                    },
                    UI.Button {
                        text = "看看棋盘",
                        width = "100%",
                        height = 38,
                        fontSize = F.small,
                        backgroundColor = C.surfaceMuted,
                        hoverBackgroundColor = C.accentSoft,
                        pressedBackgroundColor = C.accentSoft,
                        textColor = C.textSecondary,
                        borderRadius = 8,
                        onClick = function()
                            self.overlay:SetVisible(false)
                        end,
                    },
                    UI.Button {
                        text = "回到主界面",
                        width = "100%",
                        height = 38,
                        fontSize = F.small,
                        backgroundColor = C.surfaceMuted,
                        hoverBackgroundColor = C.accentSoft,
                        pressedBackgroundColor = C.accentSoft,
                        textColor = C.textSecondary,
                        borderRadius = 8,
                        onClick = function()
                            self.overlay:SetVisible(false)
                            handlers.onHome()
                        end,
                    },
                },
            },
        },
    }

    -- ---------------------------------------------------------------------
    -- 确认弹层（开新局会丢进度 / 广告换提示等通用二选一）
    -- ---------------------------------------------------------------------
    self.confirmTitleLabel = UI.Label {
        text = "开新局？",
        fontSize = 18,
        fontColor = C.textPrimary,
    }

    self.confirmMessageLabel = UI.Label {
        text = "",
        fontSize = F.small,
        fontColor = C.textSecondary,
        textAlign = "center",
        whiteSpace = "normal",
        width = "100%",
    }

    -- 确认按钮：文案与确认回调由 showConfirm(message, opts) 动态设置
    self.confirmButton = UI.Button {
        text = "开新局",
        flex = 1,
        height = 40,
        fontSize = F.small,
        variant = "primary",
        backgroundColor = C.accent,
        hoverBackgroundColor = C.accentPressed,
        pressedBackgroundColor = C.accentPressed,
        textColor = C.surface,
        onClick = function()
            self.confirmOverlay:SetVisible(false)
            local action = self.confirmAction_
            if action then
                action()
            else
                handlers.onConfirmNewGame()
            end
        end,
    }

    self.confirmOverlay = UI.Panel {
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        visible = false,
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = C.overlay,
        children = {
            UI.Panel {
                width = 280,
                padding = 22,
                gap = 12,
                alignItems = "center",
                backgroundColor = C.surface,
                borderRadius = 16,
                children = {
                    self.confirmTitleLabel,
                    self.confirmMessageLabel,
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 10,
                        children = {
                            UI.Button {
                                text = "继续这局",
                                flex = 1,
                                height = 40,
                                fontSize = F.small,
                                backgroundColor = C.surfaceMuted,
                                hoverBackgroundColor = C.accentSoft,
                                pressedBackgroundColor = C.accentSoft,
                                textColor = C.textSecondary,
                                borderRadius = 8,
                                onClick = function()
                                    self.confirmOverlay:SetVisible(false)
                                end,
                            },
                            self.confirmButton,
                        },
                    },
                },
            },
        },
    }

    -- ---------------------------------------------------------------------
    -- 设置弹层
    -- ---------------------------------------------------------------------
    local function settingRow(labelText, button)
        return UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 10,
            children = {
                UI.Label {
                    text = labelText,
                    flex = 1,
                    fontSize = F.small,
                    fontColor = C.textSecondary,
                },
                button,
            },
        }
    end

    local function toggleButton(text, onClick)
        return UI.Button {
            text = text,
            width = 84,
            height = 32,
            fontSize = F.small,
            backgroundColor = C.surfaceMuted,
            hoverBackgroundColor = C.accentSoft,
            pressedBackgroundColor = C.accentSoft,
            textColor = C.textPrimary,
            borderRadius = 8,
            onClick = onClick,
        }
    end

    self.btnSound = toggleButton("开", function()
        handlers.onToggleSound()
    end)
    self.btnAutoClean = toggleButton("开", function()
        handlers.onToggleAutoClean()
    end)
    self.btnFont = toggleButton("11", function()
        handlers.onCycleFont()
    end)
    self.btnLimit = toggleButton("不限", function()
        handlers.onCycleLimit()
    end)

    self.settingsOverlay = UI.Panel {
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        visible = false,
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = { 15, 23, 42, 200 },
        children = {
            UI.Panel {
                width = 300,
                padding = 20,
                gap = 12,
                alignItems = "center",
                backgroundColor = C.surface,
                borderRadius = 16,
                children = {
                    UI.Label { text = "设置", fontSize = 18, fontColor = C.textPrimary },
                    settingRow("音效", self.btnSound),
                    settingRow("自动清笔记", self.btnAutoClean),
                    settingRow("候选字号", self.btnFont),
                    settingRow("错误上限", self.btnLimit),
                    UI.Panel { height = 2 },
                    UI.Button {
                        text = "去 TapTap 支持我们",
                        width = "100%",
                        height = 38,
                        fontSize = F.small,
                        backgroundColor = C.accentSoft,
                        hoverBackgroundColor = C.cellSelected,
                        pressedBackgroundColor = C.cellSelected,
                        textColor = C.accent,
                        borderRadius = 8,
                        onClick = function()
                            self.settingsOverlay:SetVisible(false)
                            handlers.onJumpTapTap()
                        end,
                    },
                    UI.Button {
                        text = "关闭",
                        width = "100%",
                        height = 40,
                        fontSize = F.small,
                        backgroundColor = C.surfaceMuted,
                        hoverBackgroundColor = C.accentSoft,
                        pressedBackgroundColor = C.accentSoft,
                        textColor = C.textSecondary,
                        borderRadius = 8,
                        onClick = function()
                            self.settingsOverlay:SetVisible(false)
                        end,
                    },
                },
            },
        },
    }

    -- ---------------------------------------------------------------------
    -- 失败弹层（错误次数用尽）
    -- ---------------------------------------------------------------------
    self.failDetailLabel = UI.Label {
        text = "",
        fontSize = F.small,
        fontColor = C.textMuted,
        textAlign = "center",
        whiteSpace = "normal",
        width = "100%",
    }

    -- 告诉玩家为什么会结束、以及去哪里改
    self.failHintLabel = UI.Label {
        text = "",
        fontSize = F.tiny,
        fontColor = C.textMuted,
        textAlign = "center",
        whiteSpace = "normal",
        width = "100%",
    }

    self.failOverlay = UI.Panel {
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        visible = false,
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = { 15, 23, 42, 200 },
        children = {
            UI.Panel {
                width = 280,
                padding = 22,
                gap = 10,
                alignItems = "center",
                backgroundColor = C.surface,
                borderRadius = 16,
                children = {
                    UI.Label { text = "本局结束", fontSize = 20, fontColor = C.textPrimary },
                    self.failDetailLabel,
                    self.failHintLabel,
                    UI.Panel { height = 2 },
                    UI.Button {
                        text = "去设置里调整",
                        width = "100%",
                        height = 32,
                        fontSize = F.tiny,
                        backgroundColor = { 0, 0, 0, 0 },
                        hoverBackgroundColor = C.accentSoft,
                        pressedBackgroundColor = C.accentSoft,
                        textColor = C.accent,
                        borderRadius = 8,
                        onClick = function()
                            -- 失败弹层在设置之上，先关掉自己再打开设置
                            self.failOverlay:SetVisible(false)
                            self.settingsOverlay:SetVisible(true)
                        end,
                    },
                    UI.Button {
                        text = "再来一局",
                        width = "100%",
                        height = 42,
                        fontSize = F.body,
                        variant = "primary",
                        backgroundColor = C.accent,
                        hoverBackgroundColor = C.accentPressed,
                        pressedBackgroundColor = C.accentPressed,
                        textColor = C.surface,
                        onClick = function()
                            self.failOverlay:SetVisible(false)
                            handlers.onRetry()
                        end,
                    },
                    UI.Button {
                        text = "先歇会",
                        width = "100%",
                        height = 36,
                        fontSize = F.small,
                        backgroundColor = C.surfaceMuted,
                        hoverBackgroundColor = C.accentSoft,
                        pressedBackgroundColor = C.accentSoft,
                        textColor = C.textSecondary,
                        borderRadius = 8,
                        onClick = function()
                            self.failOverlay:SetVisible(false)
                        end,
                    },
                    UI.Button {
                        text = "回到主界面",
                        width = "100%",
                        height = 36,
                        fontSize = F.small,
                        backgroundColor = C.surfaceMuted,
                        hoverBackgroundColor = C.accentSoft,
                        pressedBackgroundColor = C.accentSoft,
                        textColor = C.textSecondary,
                        borderRadius = 8,
                        onClick = function()
                            self.failOverlay:SetVisible(false)
                            handlers.onHome()
                        end,
                    },
                },
            },
        },
    }

    -- ---------------------------------------------------------------------
    -- 暂停遮罩：挡住棋盘（防止暂停后还能继续看盘面推演），点「继续」恢复
    -- ---------------------------------------------------------------------
    self.pauseTimeLabel = UI.Label { text = "", fontSize = F.small, fontColor = C.textMuted }

    self.pauseOverlay = UI.Panel {
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        visible = false,
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = { 15, 23, 42, 235 },
        children = {
            UI.Panel {
                width = 240,
                padding = 22,
                gap = 10,
                alignItems = "center",
                backgroundColor = C.surface,
                borderRadius = 16,
                children = {
                    UI.Label { text = "已暂停", fontSize = 20, fontColor = C.textPrimary },
                    self.pauseTimeLabel,
                    UI.Label {
                        text = "暂停期间不计时",
                        fontSize = F.tiny,
                        fontColor = C.textMuted,
                    },
                    UI.Button {
                        text = "继续",
                        width = "100%",
                        height = 42,
                        fontSize = F.body,
                        variant = "primary",
                        backgroundColor = C.accent,
                        hoverBackgroundColor = C.accentPressed,
                        pressedBackgroundColor = C.accentPressed,
                        textColor = C.surface,
                        onClick = function()
                            handlers.onResume()
                        end,
                    },
                    UI.Button {
                        text = "回到主界面",
                        width = "100%",
                        height = 36,
                        fontSize = F.small,
                        backgroundColor = C.surfaceMuted,
                        hoverBackgroundColor = C.accentSoft,
                        pressedBackgroundColor = C.accentSoft,
                        textColor = C.textSecondary,
                        borderRadius = 8,
                        onClick = function()
                            self.pauseOverlay:SetVisible(false)
                            handlers.onHome()
                        end,
                    },
                },
            },
        },
    }

    -- ---------------------------------------------------------------------
    -- 轻提示（提示理由等），绝对定位在键盘上方
    -- ---------------------------------------------------------------------
    self.toastLabel = UI.Label {
        text = "",
        fontSize = F.small,
        fontColor = C.surface,
        textAlign = "center",
        whiteSpace = "normal",
        width = "100%",
    }

    self.toastPanel = UI.Panel {
        position = "absolute",
        left = 16,
        right = 16,
        bottom = 196, -- 抬到数字键上方，避免遮挡
        paddingVertical = 10,
        paddingHorizontal = 14,
        backgroundColor = { 30, 41, 59, 235 },
        borderRadius = 10,
        visible = false,
        alignItems = "center",
        pointerEvents = "none",
        children = { self.toastLabel },
    }
    self.toastTimer_ = 0

    return self
end

--- 显示一条短提示，seconds 秒后自动消失
function HUD:toast(text, seconds)
    self.toastLabel:SetText(text or "")
    self.toastPanel:SetVisible(true)
    self.toastTimer_ = seconds or 3
end

function HUD:hideToast()
    self.toastTimer_ = 0
    self.toastPanel:SetVisible(false)
end

--- 设置顶部难度按钮文案（显示的是「待开局难度」，不是当前盘面难度）
function HUD:setDifficulty(key)
    self.difficultyButton:SetText("难度 " .. difficultyLabel(key))
end

--- 当前盘面难度与新局难度不一致时给个视觉提示
function HUD:setPendingMismatch(mismatch)
    self.difficultyButton:SetStyle {
        backgroundColor = mismatch and C.cellSameDigit or C.accentSoft,
        textColor = mismatch and C.textPrimary or C.accent,
    }
end

--- 每日一题入口的状态：今天是否已完成、连续多少天
---@param dateKey string|nil
---@param streak integer
---@param doneToday boolean
function HUD:setDaily(dateKey, streak, doneToday)
    self.dailyKey_ = dateKey
    self.dailyStreak_ = streak or 0
    self.dailyDone_ = doneToday == true

    if doneToday then
        self.dailyButton:SetText("每日 ✓")
        self.dailyButton:SetStyle { backgroundColor = C.accentSoft, textColor = C.accent }
    elseif (streak or 0) > 0 then
        self.dailyButton:SetText("每日 ×" .. tostring(streak))
        self.dailyButton:SetStyle { backgroundColor = C.surface, textColor = C.textPrimary }
    else
        self.dailyButton:SetText("每日")
        self.dailyButton:SetStyle { backgroundColor = C.surface, textColor = C.textPrimary }
    end
end

--- 棋盘下方的成绩条（空字符串时隐藏）
---@param text string
function HUD:setStats(text)
    local t = text or ""
    if t == self.statsText_ then
        return
    end
    self.statsText_ = t
    self.statsLabel:SetText(t)
    self.statsBar:SetVisible(t ~= "")
end

--- 刷新设置弹层上的按钮文案（HUD 不关心业务取值，只负责显示）
---@param view table { sound=boolean, autoClean=boolean, fontText=string, limitText=string }
function HUD:setSettingsView(view)
    view = view or {}
    self.btnSound:SetText(view.sound and "开" or "关")
    self.btnAutoClean:SetText(view.autoClean and "开" or "关")
    self.btnFont:SetText(tostring(view.fontText or "11"))
    self.btnLimit:SetText(tostring(view.limitText or "不限"))
end

function HUD:showSettings()
    self.settingsOverlay:SetVisible(true)
end

function HUD:hideSettings()
    self.settingsOverlay:SetVisible(false)
end

--- 失败结算（错误次数用尽）
---@param board table
function HUD:showFail(board)
    self.failDetailLabel:SetText(
        difficultyLabel(board.difficulty)
            .. " · 坚持了 " .. board:timeText()
            .. " · 错误 " .. board.mistakes .. " 次"
    )

    local limit = math.floor(tonumber(board.mistakeLimit) or 0)
    if limit > 0 then
        self.failHintLabel:SetText("错误上限 " .. tostring(limit) .. " 次，可在设置里改成「不限」")
    else
        self.failHintLabel:SetText("本局已结束")
    end

    self.failOverlay:SetVisible(true)
end

function HUD:hideFail()
    self.failOverlay:SetVisible(false)
end

--- 暂停态同步：遮罩显示 + 按钮文案
---@param paused boolean
---@param timeText string
function HUD:setPaused(paused, timeText)
    self.pauseButton:SetText(paused and "继续" or "暂停")
    self.pauseTimeLabel:SetText("用时 " .. tostring(timeText or "00:00"))
    self.pauseOverlay:SetVisible(paused and true or false)
end

--- 同步实时状态（只更新计时与错误数，不复写难度）
---@param board table
---@param dt number|nil 帧间隔，用于轻提示倒计时
function HUD:update(board, dt)
    local timeText = board:timeText()
    if timeText ~= self.lastTimeText then
        self.lastTimeText = timeText
        self.timerLabel:SetText("用时 " .. timeText)
    end
    self.mistakesLabel:SetText("错误 " .. board.mistakes)

    if self.pauseOverlay:IsVisible() then
        self.pauseTimeLabel:SetText("用时 " .. timeText)
    end

    if self.toastTimer_ > 0 then
        self.toastTimer_ = self.toastTimer_ - (dt or 0)
        if self.toastTimer_ <= 0 then
            self:hideToast()
        end
    end
end

--- 通关结果
---@param board table
---@param ctx table|nil { isRecord = boolean, prevBest = table|nil }
function HUD:showResult(board, ctx)
    ctx = ctx or {}
    self.resultTimeLabel:SetText("用时 " .. board:timeText())

    local hintLimit = math.floor(tonumber(board.hintLimit) or 0)
    local hintPart
    if hintLimit > 0 then
        hintPart = "提示 " .. board.hintsUsed .. "/" .. hintLimit .. " 次"
    else
        hintPart = "提示 " .. board.hintsUsed .. " 次"
    end
    self.resultDetailLabel:SetText(
        difficultyLabel(board.difficulty)
            .. " · 错误 " .. board.mistakes .. " 次 · " .. hintPart
    )

    if ctx.isRecord then
        if ctx.prevBest then
            self.recordLabel:SetText("新纪录！上局最佳 " .. fmtTime(ctx.prevBest.time))
        else
            self.recordLabel:SetText("首个记录已保存")
        end
        self.recordLabel:SetFontColor(C.accent)
        self.recordLabel:SetVisible(true)
    elseif ctx.prevBest then
        self.recordLabel:SetText("该难度最佳 " .. fmtTime(ctx.prevBest.time)
            .. " · 错误 " .. ctx.prevBest.mistakes .. " 次")
        self.recordLabel:SetFontColor(C.textMuted)
        self.recordLabel:SetVisible(true)
    else
        -- 没有可显示的成绩时整行隐藏，避免弹层里留一条空白
        self.recordLabel:SetText("")
        self.recordLabel:SetVisible(false)
    end

    local extra = ctx.extra
    if type(extra) == "string" and extra ~= "" then
        self.extraLabel:SetText(extra)
        self.extraLabel:SetVisible(true)
    else
        self.extraLabel:SetText("")
        self.extraLabel:SetVisible(false)
    end

    self.overlay:SetVisible(true)
end

function HUD:hideResult()
    self.overlay:SetVisible(false)
end

--- 二选一确认弹层（不传 opts 时保持原「开新局」行为）
---@param message string 正文
---@param opts table|nil { title, confirmText, cancelText, onConfirm }
function HUD:showConfirm(message, opts)
    opts = opts or {}
    self.confirmTitleLabel:SetText(opts.title or "开新局？")
    self.confirmMessageLabel:SetText(message or "")
    self.confirmButton:SetText(opts.confirmText or "开新局")
    self.confirmAction_ = opts.onConfirm -- nil 时确认按钮走默认的 onConfirmNewGame
    self.confirmOverlay:SetVisible(true)
end

function HUD:hideConfirm()
    self.confirmOverlay:SetVisible(false)
end

--- 覆盖层是否正在显示（用于挡住背后的键盘操作）
function HUD:isModalOpen()
    return self.overlay:IsVisible()
        or self.confirmOverlay:IsVisible()
        or self.pauseOverlay:IsVisible()
        or self.settingsOverlay:IsVisible()
        or self.failOverlay:IsVisible()
end

return HUD
