-- ============================================================================
-- 棋盘视图：9x9 格子树 + 按状态刷新（选中 / 同宫同行同列 / 同数字 / 错误 / 笔记）
-- 只做「渲染与命中」，规则一律问 Board
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require "ui.theme"
local Sudoku = require "game.sudoku"

local BoardView = {}
BoardView.__index = BoardView

local C = Theme.COLORS
local S = Theme.SIZE

---@param onCellTap fun(idx: integer)
function BoardView.new(onCellTap)
    local self = setmetatable({
        cells = {},
        labels = {},
        font_ = Theme.FONT.candidate,
        baseBg_ = {},
        anims_ = {},
    }, BoardView)

    local rows = {}
    for r = 1, 9 do
        local cells = {}
        for c = 1, 9 do
            local idx = (r - 1) * 9 + c

            local label = UI.Label {
                text = "",
                fontSize = Theme.FONT.cell,
                fontColor = C.digitGiven,
                textAlign = "center",
                verticalAlign = "middle",
                whiteSpace = "normal",
                lineHeight = 1.0,
                width = "100%",
                pointerEvents = "none",
            }

            -- 只画右边和下边，避免相邻格子双线叠加；3 的倍数处加粗做宫界
            local cell = UI.Panel {
                flex = 1,
                alignItems = "center",
                justifyContent = "center",
                backgroundColor = C.surface,
                borderRadius = 0,
                borderRightWidth = (c < 9) and ((c % 3 == 0) and S.gridLineBold or S.gridLineThin) or 0,
                borderRightColor = (c % 3 == 0) and C.gridBold or C.gridThin,
                borderBottomWidth = (r < 9) and ((r % 3 == 0) and S.gridLineBold or S.gridLineThin) or 0,
                borderBottomColor = (r % 3 == 0) and C.gridBold or C.gridThin,
                onClick = function()
                    onCellTap(idx)
                end,
                children = { label },
            }

            self.cells[idx] = cell
            self.labels[idx] = label
            cells[#cells + 1] = cell
        end

        rows[#rows + 1] = UI.Panel {
            width = "100%",
            flex = 1,
            flexDirection = "row",
            borderRadius = 0,
            children = cells,
        }
    end

    self.root = UI.Panel {
        width = "100%",
        maxWidth = S.boardMax,
        aspectRatio = 1,
        flexDirection = "column",
        backgroundColor = C.surface,
        borderWidth = 2,
        borderColor = C.gridBold,
        borderRadius = 6,
        overflow = "hidden",
        children = rows,
    }

    return self
end

--- 3x3 小字排版：present(n) 决定该位置是否显示数字 n
local function gridText(present)
    local lines = {}
    for row = 0, 2 do
        local parts = {}
        for col = 1, 3 do
            local n = row * 3 + col
            if present(n) then
                parts[#parts + 1] = tostring(n)
            else
                parts[#parts + 1] = " "
            end
        end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    return table.concat(lines, "\n")
end

--- 笔记文本（玩家手写的铅笔标记）
local function notesText(notes)
    return gridText(function(n)
        return notes[n] == true
    end)
end

--- 自动候选文本
local function candidatesText(list)
    local set = {}
    for _, n in ipairs(list or {}) do
        set[n] = true
    end
    return gridText(function(n)
        return set[n] == true
    end)
end

--- 显式指定棋盘边长（由外层按可用空间算，兼顾横屏 / 平板 / 大屏）
--- 不调用时保留默认的「100% 宽 + maxWidth + 正方形」自适应
function BoardView:setSize(px)
    px = math.floor(px or 0)
    -- nan / inf 一律拒绝（本引擎 nan 的数值比较不可靠，走字符串判定）
    local label = tostring(px)
    if label:find("nan") or label:find("inf") then
        return false
    end
    if px < 1 or px == self.size_ then
        return false
    end
    self.size_ = px
    self.root:SetStyle { width = px, height = px }
    return true
end

--- 按当前棋盘状态整盘刷新
---@param board table
function BoardView:refresh(board)
    local sel = board.selected
    local selRow = sel and Sudoku.ROW[sel] or nil
    local selCol = sel and Sudoku.COL[sel] or nil
    local selBox = sel and Sudoku.BOX[sel] or nil
    local selValue = sel and board.values[sel] or 0

    -- 自动候选只在开启时才算，省掉每次点击的推算开销
    local auto = board.showCandidates and board:autoCandidates() or nil

    for idx = 1, Sudoku.CELLS do
        local cell = self.cells[idx]
        local label = self.labels[idx]
        local value = board.values[idx]
        local isWrong = board.wrong[idx]

        -- 背景：提示 > 选中 > 同数字 > 同行同列同宫 > 默认
        local bg
        if board.hintIdx == idx then
            bg = C.cellHint
        elseif sel == idx then
            bg = C.cellSelected
        elseif selValue ~= 0 and value == selValue then
            bg = C.cellSameDigit
        elseif selRow and (Sudoku.ROW[idx] == selRow or Sudoku.COL[idx] == selCol or Sudoku.BOX[idx] == selBox) then
            bg = C.cellPeer
        else
            bg = C.surface
        end
        if isWrong then
            bg = C.cellError
        end
        self.baseBg_[idx] = bg
        cell:SetStyle { backgroundColor = bg }

        -- 文字：数字 > 手写笔记 > 自动候选 > 空
        if value ~= 0 then
            label:SetText(tostring(value))
            label:SetFontSize(Theme.FONT.cell)
            label:SetStyle { textAlign = "center", paddingLeft = 0 }
            local isSameDigit = (selValue ~= 0 and value == selValue and sel ~= idx)
            if isWrong then
                label:SetFontColor(C.digitError)
            elseif board:isGiven(idx) then
                -- 同数字的给定格用更深的蓝，方便一眼扫出同一数字分布
                label:SetFontColor(isSameDigit and C.digitGivenHighlight or C.digitGiven)
            else
                label:SetFontColor(C.digitUser)
            end
        elseif next(board.notes[idx]) ~= nil then
            label:SetText(notesText(board.notes[idx]))
            label:SetFontSize(Theme.FONT.note)
            label:SetFontColor(C.digitNote)
            -- 小字必须左对齐：居中会把行尾空格吃掉，导致 3x3 列错位
            label:SetStyle { textAlign = "left", paddingLeft = 5 }
        elseif auto and auto[idx] and #auto[idx] > 0 then
            label:SetText(candidatesText(auto[idx]))
            label:SetFontSize(self.font_)
            label:SetFontColor(C.digitAuto)
            label:SetStyle { textAlign = "left", paddingLeft = 5 }
        else
            label:SetText("")
        end
    end

    -- 刷新会把底色写回基础色，这里再把进行中的动画盖回去，避免闪一下
    self:update(0)
end

--- 落子 / 填错 / 提示的瞬时反馈：从高亮色衰减回该格的常态底色
---@param idx integer
---@param kind string|nil "place" | "error" | "hint"
function BoardView:flash(idx, kind)
    if not idx then
        return
    end
    local from, dur
    -- 注意：闪色必须比「同数字高亮」更饱和，否则在满是同数字的盘面上看不出变化
    if kind == "error" then
        from, dur = { 248, 113, 113, 255 }, 0.5 -- red-400
    elseif kind == "hint" then
        from, dur = { 251, 191, 36, 255 }, 0.5 -- amber-400
    else
        from, dur = { 96, 165, 250, 255 }, 0.26 -- blue-400
    end
    self.anims_[idx] = { t = 0, dur = dur, from = from }
end

--- 每帧推进动画；没有动画时是一次空表判断，几乎无开销
function BoardView:update(dt)
    if next(self.anims_) == nil then
        return
    end
    for idx, a in pairs(self.anims_) do
        a.t = a.t + (dt or 0)
        local k = a.t / a.dur
        if k >= 1 then
            self.anims_[idx] = nil
            local cell = self.cells[idx]
            if cell then
                cell:SetStyle { backgroundColor = self.baseBg_[idx] or C.surface }
            end
        else
            local base = self.baseBg_[idx] or C.surface
            local f = a.from
            local e = (1 - k) * (1 - k)
            local cell = self.cells[idx]
            if cell then
                cell:SetStyle {
                    backgroundColor = {
                        math.floor(base[1] + (f[1] - base[1]) * e + 0.5),
                        math.floor(base[2] + (f[2] - base[2]) * e + 0.5),
                        math.floor(base[3] + (f[3] - base[3]) * e + 0.5),
                        255,
                    },
                }
            end
        end
    end
end

--- 候选字号（设置里可调）
function BoardView:setCandidateFont(size)
    local n = math.floor(tonumber(size) or 0)
    if n < 8 or n > 16 or n == self.font_ then
        return false
    end
    self.font_ = n
    return true
end

--- 通关时的收尾表现：把用户填的数字统一染色
function BoardView:markSolved()
    for idx = 1, Sudoku.CELLS do
        local label = self.labels[idx]
        if label then
            label:SetFontColor(C.digitGiven)
        end
    end
end

return BoardView
