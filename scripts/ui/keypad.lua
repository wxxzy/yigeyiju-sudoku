-- ============================================================================
-- 键盘区：1-9 数字键 + 剩余个数 + 工具键（撤销 / 擦除 / 笔记 / 提示）
-- 只负责触发回调，状态显示由 update(board) 同步
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require "ui.theme"

local Keypad = {}
Keypad.__index = Keypad

local C = Theme.COLORS
local S = Theme.SIZE
local F = Theme.FONT

---@param handlers table { onDigit, onErase, onNotes, onHint, onUndo }
function Keypad.new(handlers)
    local self = setmetatable({ digitButtons = {}, countLabels = {} }, Keypad)

    local digitCells = {}
    local countCells = {}
    for n = 1, 9 do
        local btn = UI.Button {
            text = tostring(n),
            flex = 1,
            height = S.keypadHeight,
            fontSize = F.keypad,
            backgroundColor = C.surface,
            hoverBackgroundColor = C.accentSoft,
            pressedBackgroundColor = C.accentSoft,
            textColor = C.digitUser,
            borderRadius = 8,
            onClick = function()
                handlers.onDigit(n)
            end,
        }
        self.digitButtons[n] = btn
        digitCells[#digitCells + 1] = btn

        local count = UI.Label {
            text = "9",
            flex = 1,
            fontSize = F.tiny,
            fontColor = C.textMuted,
            textAlign = "center",
        }
        self.countLabels[n] = count
        countCells[#countCells + 1] = count
    end

    self.notesButton = UI.Button {
        text = "笔记 关",
        flex = 1,
        height = S.toolHeight,
        fontSize = F.body,
        backgroundColor = C.surfaceMuted,
        hoverBackgroundColor = C.accentSoft,
        pressedBackgroundColor = C.accentPressed,
        textColor = C.textSecondary,
        borderRadius = 8,
        onClick = function()
            handlers.onNotes()
        end,
    }

    self.candidatesButton = UI.Button {
        text = "候选 开",
        flex = 1,
        height = S.toolHeight,
        fontSize = F.body,
        backgroundColor = C.surfaceMuted,
        hoverBackgroundColor = C.accentSoft,
        pressedBackgroundColor = C.accentPressed,
        textColor = C.textSecondary,
        borderRadius = 8,
        onClick = function()
            handlers.onCandidates()
        end,
    }

    local toolRow = UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 6,
        children = {
            UI.Button {
                text = "撤销",
                flex = 1,
                height = S.toolHeight,
                fontSize = F.body,
                backgroundColor = C.surfaceMuted,
                hoverBackgroundColor = C.accentSoft,
                pressedBackgroundColor = C.accentSoft,
                textColor = C.textSecondary,
                borderRadius = 8,
                onClick = function()
                    handlers.onUndo()
                end,
            },
            UI.Button {
                text = "擦除",
                flex = 1,
                height = S.toolHeight,
                fontSize = F.body,
                backgroundColor = C.surfaceMuted,
                hoverBackgroundColor = C.accentSoft,
                pressedBackgroundColor = C.accentSoft,
                textColor = C.textSecondary,
                borderRadius = 8,
                onClick = function()
                    handlers.onErase()
                end,
            },
            self.notesButton,
            self.candidatesButton,
            UI.Button {
                text = "提示",
                flex = 1,
                height = S.toolHeight,
                fontSize = F.body,
                backgroundColor = C.surfaceMuted,
                hoverBackgroundColor = C.accentSoft,
                pressedBackgroundColor = C.accentSoft,
                textColor = C.textSecondary,
                borderRadius = 8,
                onClick = function()
                    handlers.onHint()
                end,
            },
        },
    }

    self.root = UI.Panel {
        width = "100%",
        maxWidth = S.boardMax, -- 大屏 / 横屏下不让数字键拉成整屏宽
        alignSelf = "center",
        flexDirection = "column",
        gap = 6,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 6,
                children = digitCells,
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 6,
                children = countCells,
            },
            toolRow,
        },
    }

    return self
end

--- 同步剩余个数与笔记开关状态
---@param board table
function Keypad:update(board)
    local counts = board:digitCounts()
    -- 当前选中格里的数字，用来在键盘上同步高亮，强化「这个数字在哪」
    local selDigit = 0
    if board.selected and board.values[board.selected] then
        selDigit = board.values[board.selected]
    end

    for n = 1, 9 do
        local left = 9 - (counts[n] or 0)
        local label = self.countLabels[n]
        if left > 0 then
            label:SetText(tostring(left))
            label:SetFontColor(C.textMuted)
        else
            label:SetText("✓")
            label:SetFontColor(C.accent)
        end

        local isActive = (n == selDigit)
        self.digitButtons[n]:SetStyle {
            -- 该数字已用满时弱化按键，但不禁用（避免误判后无法继续操作）
            opacity = (left > 0) and 1 or 0.45,
            backgroundColor = isActive and C.cellSameDigit or C.surface,
            textColor = isActive and C.accent or C.digitUser,
        }
    end

    self.notesButton:SetText(board.notesMode and "笔记 开" or "笔记 关")
    self.notesButton:SetStyle {
        backgroundColor = board.notesMode and C.accentSoft or C.surfaceMuted,
        textColor = board.notesMode and C.accent or C.textSecondary,
    }

    self.candidatesButton:SetText(board.showCandidates and "候选 开" or "候选 关")
    self.candidatesButton:SetStyle {
        backgroundColor = board.showCandidates and C.accentSoft or C.surfaceMuted,
        textColor = board.showCandidates and C.accent or C.textSecondary,
    }
end

return Keypad
