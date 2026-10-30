-- ============================================================================
-- HUD：顶部状态条（难度 / 用时 / 错误）+ 通关覆盖层
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require "ui.theme"
local Sudoku = require "game.sudoku"

local HUD = {}
HUD.__index = HUD

local C = Theme.COLORS
local S = Theme.SIZE
local F = Theme.FONT

local function difficultyLabel(key)
    for _, d in ipairs(Sudoku.DIFFICULTIES) do
        if d.key == key then
            return d.label
        end
    end
    return "普通"
end

---@param handlers table { onNewGame, onCycleDifficulty }
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

    local newGameButton = UI.Button {
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
            newGameButton,
        },
    }

    -- ---------------------------------------------------------------------
    -- 通关覆盖层
    -- ---------------------------------------------------------------------
    self.resultTimeLabel = UI.Label { text = "", fontSize = F.body, fontColor = C.textSecondary }
    self.resultDetailLabel = UI.Label { text = "", fontSize = F.small, fontColor = C.textMuted }

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

    return self
end

--- 每帧/每秒同步状态
---@param board table
function HUD:update(board)
    local timeText = board:timeText()
    if timeText ~= self.lastTimeText then
        self.lastTimeText = timeText
        self.timerLabel:SetText("用时 " .. timeText)
    end
    self.mistakesLabel:SetText("错误 " .. board.mistakes)
    self.difficultyButton:SetText("难度 " .. difficultyLabel(board.difficulty))
end

--- 通关时展示结果
---@param board table
function HUD:showResult(board)
    self.resultTimeLabel:SetText("用时 " .. board:timeText())
    self.resultDetailLabel:SetText(string.format("错误 %d 次 · 提示 %d 次", board.mistakes, board.hintsUsed))
    self.overlay:SetVisible(true)
end

function HUD:hideResult()
    self.overlay:SetVisible(false)
end

return HUD
