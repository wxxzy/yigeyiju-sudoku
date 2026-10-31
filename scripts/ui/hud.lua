-- ============================================================================
-- HUD：顶部状态条（难度 / 用时 / 错误）+ 通关覆盖层 + 确认弹层
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

local function difficultyLabel(key)
    for _, d in ipairs(Sudoku.DIFFICULTIES) do
        if d.key == key then
            return d.label
        end
    end
    return "普通"
end

---@param handlers table { onNewGame, onCycleDifficulty, onConfirmNewGame }
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
        fontSize = F.small,
        fontColor = C.textSecondary,
    }

    self.mistakesLabel = UI.Label {
        text = "错误 0",
        fontSize = F.small,
        fontColor = C.textSecondary,
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

    self.root = UI.Panel {
        width = "100%",
        height = S.hudHeight,
        flexDirection = "row",
        alignItems = "center",
        gap = 10,
        children = {
            self.difficultyButton,
            UI.Spacer(),
            self.timerLabel,
            self.mistakesLabel,
            self.newGameButton,
        },
    }

    -- ---------------------------------------------------------------------
    -- 通关覆盖层
    -- ---------------------------------------------------------------------
    self.resultTimeLabel = UI.Label { text = "", fontSize = F.body, fontColor = C.textSecondary }
    self.resultDetailLabel = UI.Label { text = "", fontSize = F.small, fontColor = C.textMuted }
    self.recordLabel = UI.Label { text = "", fontSize = F.small, fontColor = C.accent }

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
                    UI.Panel { height = 6 },
                    UI.Button {
                        text = "再来一局",
                        width = "100%",
                        height = 44,
                        fontSize = F.body,
                        variant = "primary",
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
                },
            },
        },
    }

    -- ---------------------------------------------------------------------
    -- 确认弹层（开新局会丢进度时使用）
    -- ---------------------------------------------------------------------
    self.confirmMessageLabel = UI.Label {
        text = "",
        fontSize = F.small,
        fontColor = C.textSecondary,
        textAlign = "center",
        whiteSpace = "normal",
        width = "100%",
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
                    UI.Label {
                        text = "开新局？",
                        fontSize = 18,
                        fontColor = C.textPrimary,
                    },
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
                            UI.Button {
                                text = "开新局",
                                flex = 1,
                                height = 40,
                                fontSize = F.small,
                                variant = "primary",
                                onClick = function()
                                    self.confirmOverlay:SetVisible(false)
                                    handlers.onConfirmNewGame()
                                end,
                            },
                        },
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
    self.resultDetailLabel:SetText(
        difficultyLabel(board.difficulty)
            .. " · 错误 " .. board.mistakes .. " 次 · 提示 " .. board.hintsUsed .. " 次"
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

    self.overlay:SetVisible(true)
end

function HUD:hideResult()
    self.overlay:SetVisible(false)
end

--- 开新局前的二次确认
---@param message string
function HUD:showConfirm(message)
    self.confirmMessageLabel:SetText(message or "")
    self.confirmOverlay:SetVisible(true)
end

function HUD:hideConfirm()
    self.confirmOverlay:SetVisible(false)
end

--- 覆盖层是否正在显示（用于挡住背后的键盘操作）
function HUD:isModalOpen()
    return self.overlay:IsVisible() or self.confirmOverlay:IsVisible()
end

return HUD
