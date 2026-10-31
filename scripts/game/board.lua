-- ============================================================================
-- 棋盘会话状态：选中格、填数、笔记、错误、撤销、计时、通关判定
-- 只关心「状态怎么变」，不碰任何 UI；UI 层读状态后自己刷新
-- ============================================================================

local Sudoku = require "game.sudoku"
local Rating = require "game.rating"
local PuzzleBank = require "game.puzzle_bank"
local Daily = require "game.daily"

local Board = {}
Board.__index = Board

Board.DIFFICULTIES = Sudoku.DIFFICULTIES

local function copyNotes(notes)
    local t = {}
    for k, v in pairs(notes or {}) do
        if v then
            t[k] = true
        end
    end
    return t
end

function Board.new(difficulty)
    local self = setmetatable({}, Board)
    self:reset(difficulty)
    return self
end

--- 开新局
---@param difficulty string|nil
---@param opts table|nil { daily = "YYYY-MM-DD" } 每日一题：按日期确定性选题
function Board:reset(difficulty, opts)
    self.difficulty = difficulty or self.difficulty or "normal"
    opts = opts or {}
    self.dailyKey = opts.daily

    -- 优先从题库抽题（难度经过技巧校验）；题库缺档时退回实时生成
    local puzzle
    if self.dailyKey then
        puzzle = PuzzleBank.pickAt(self.difficulty, Daily.indexFor(self.dailyKey, PuzzleBank.count(self.difficulty)))
    end
    puzzle = puzzle or PuzzleBank.pick(self.difficulty)
    local solution = puzzle and Sudoku.solve(puzzle)
    if not puzzle or not solution then
        puzzle, solution = Sudoku.generate(self.difficulty)
    end
    self.puzzle = puzzle
    self.solution = solution

    self.values = {}
    self.notes = {}
    self.wrong = {}
    for i = 1, Sudoku.CELLS do
        self.values[i] = puzzle[i]
        self.notes[i] = {}
        self.wrong[i] = false
    end

    self.selected = nil
    self.history = {}
    self.mistakes = 0
    self.elapsed = 0
    self.started = false
    self.hintsUsed = 0
    self.notesMode = false
    self.solved = false
    self.lastAction = nil -- "place" | "wrong" | "erase" | "hint" | "note"，给表现层做反馈

    -- 辅助：简单/普通默认显示自动候选，困难/专家默认关闭（保留思考空间）
    self.showCandidates = (self.difficulty == "easy" or self.difficulty == "normal")
    self.hintIdx = nil
    self.hintReason = nil
    self.paused = false
    self.failed = false
    self.mistakeLimit = 0 -- 0 = 不限；>0 时错误达到上限即本局失败
    -- 填入正确数字时顺手清掉同行/列/宫里该数字的笔记（标准 QoL）
    self.autoCleanNotes = true
end

function Board:isGiven(idx)
    return idx ~= nil and self.puzzle[idx] ~= 0
end

function Board:canEdit(idx)
    return idx ~= nil and not self:isGiven(idx) and not self.solved and not self.failed
end

--- 设置错误上限（0 = 不限）
function Board:setMistakeLimit(limit)
    limit = math.max(0, math.floor(tonumber(limit) or 0))
    self.mistakeLimit = limit
end

--- 本局是否已因错误次数用尽而结束
function Board:isFailed()
    return self.failed == true
end

function Board:select(idx)
    if idx ~= nil then
        self.selected = idx
        self.started = true
        if idx ~= self.hintIdx then
            self:clearHint()
        end
    end
end

--- 键盘方向键移动选中格，返回新的选中格
function Board:moveSelection(dr, dc)
    local cur = self.selected or 41
    local r = math.min(9, math.max(1, Sudoku.ROW[cur] + dr))
    local c = math.min(9, math.max(1, Sudoku.COL[cur] + dc))
    self.selected = (r - 1) * 9 + c
    self.started = true
    return self.selected
end

-- ---------------------------------------------------------------------------
-- 撤销
-- ---------------------------------------------------------------------------

--- 单个格子的当前状态
function Board:cellSnapshot(idx)
    return {
        idx = idx,
        value = self.values[idx],
        notes = copyNotes(self.notes[idx]),
        wrong = self.wrong[idx],
    }
end

--- 记录一次改动；extra 是被这次操作连带改掉的其它格（如被清理的笔记）
function Board:pushHistory(idx, extra)
    local cells = { self:cellSnapshot(idx) }
    for _, i in ipairs(extra or {}) do
        cells[#cells + 1] = self:cellSnapshot(i)
    end

    local snap = { cells = cells, mistakes = self.mistakes }
    table.insert(self.history, snap)
    if #self.history > 100 then
        table.remove(self.history, 1)
    end
    return snap
end

--- 同行/列/宫里带该数字笔记的格子
function Board:notePeersOf(idx, n)
    local list = {}
    if not idx or not n then
        return list
    end
    for i = 1, Sudoku.CELLS do
        if i ~= idx and Sudoku.isPeer(idx, i) and self.notes[i] and self.notes[i][n] then
            list[#list + 1] = i
        end
    end
    return list
end

function Board:undo()
    local snap = table.remove(self.history)
    if not snap or type(snap.cells) ~= "table" or #snap.cells == 0 then
        return false
    end
    self:clearHint()
    for _, cell in ipairs(snap.cells) do
        self.values[cell.idx] = cell.value
        self.notes[cell.idx] = cell.notes
        self.wrong[cell.idx] = cell.wrong
    end
    self.mistakes = snap.mistakes
    self.selected = snap.cells[1].idx
    self.solved = false
    self.lastAction = "undo"
    return true
end

-- ---------------------------------------------------------------------------
-- 填数 / 笔记 / 擦除 / 提示
-- ---------------------------------------------------------------------------

--- 输入数字 n（1..9）。笔记模式下列表切换，否则填数
function Board:input(n)
    local idx = self.selected
    if not self:canEdit(idx) then
        return false
    end
    self:clearHint()

    if self.notesMode then
        if self.values[idx] ~= 0 then
            return false -- 已有数字时不写笔记
        end
        self:pushHistory(idx)
        if self.notes[idx][n] then
            self.notes[idx][n] = nil
        else
            self.notes[idx][n] = true
        end
        self.lastAction = "note"
        return true
    end

    -- 先判断这次落子会不会顺带清掉同行/列/宫的笔记，把受影响的格子一起入栈，
    -- 这样一次撤销能把「填数 + 清笔记」整体回滚
    local willBeCorrect = (self.values[idx] ~= n) and (n == self.solution[idx])
    local cleanList = {}
    if willBeCorrect and self.autoCleanNotes then
        cleanList = self:notePeersOf(idx, n)
    end
    self:pushHistory(idx, cleanList)

    if self.values[idx] == n then
        -- 同一格再按同一个数字 = 清除
        self.values[idx] = 0
        self.wrong[idx] = false
        self.selected = idx
        self.lastAction = "erase"
        return true
    end

    self.values[idx] = n
    self.notes[idx] = {}
    for _, i in ipairs(cleanList) do
        self.notes[i][n] = nil
    end
    local ok = (n == self.solution[idx])
    self.wrong[idx] = not ok
    if not ok then
        self.mistakes = self.mistakes + 1
        if self.mistakeLimit and self.mistakeLimit > 0 and self.mistakes >= self.mistakeLimit then
            self.failed = true
        end
        self.lastAction = "wrong"
    else
        self.lastAction = "place"
    end
    self:checkSolved()
    return true
end

--- 擦除当前格（数字与笔记都清掉）
function Board:erase()
    local idx = self.selected
    if not self:canEdit(idx) then
        return false
    end
    self:clearHint()
    if self.values[idx] == 0 and next(self.notes[idx]) == nil then
        return false
    end
    self:pushHistory(idx)
    self.values[idx] = 0
    self.notes[idx] = {}
    self.wrong[idx] = false
    self.lastAction = "erase"
    return true
end

--- 提示：填对当前格；当前格不可用时找任意空格补一个
function Board:hint()
    if self.solved then
        return false
    end
    local idx = self.selected
    if not self:canEdit(idx) or self.values[idx] == self.solution[idx] then
        idx = nil
        for _, i in ipairs(self:emptyCells()) do
            idx = i
            break
        end
    end
    if not idx then
        return false
    end

    self:pushHistory(idx)
    self.values[idx] = self.solution[idx]
    self.notes[idx] = {}
    self.wrong[idx] = false
    self.selected = idx
    self.hintsUsed = self.hintsUsed + 1
    self.lastAction = "hint"
    self:checkSolved()
    return true
end

-- ---------------------------------------------------------------------------
-- 辅助：自动候选 + 下一步提示
-- ---------------------------------------------------------------------------

--- 清掉当前提示标记（任何落子/选中变化后调用）
function Board:clearHint()
    self.hintIdx = nil
    self.hintReason = nil
end

--- 切换自动候选显示
function Board:toggleCandidatesMode()
    self.showCandidates = not self.showCandidates
    return self.showCandidates
end

--- 自动候选：按当前已填数字推算每格的候选，返回 idx -> {数字...}
function Board:autoCandidates()
    return Rating.candidates(self.values)
end

--- 求「下一步」：只找唯一候选 / 唯一位置，不直接填
--- 同一格再点一次才会填入（见 main 的提示流程）
---@return table|nil { idx, value, level, reason }
function Board:requestHint()
    if self.solved then
        return nil
    end
    local step = Rating.nextStep(self.values)
    if not step then
        self:clearHint()
        return nil
    end
    self.hintIdx = step.idx
    self.hintReason = step.reason
    self.selected = step.idx
    return step
end

--- 把当前提示的格子直接填上（第二次点提示时调用）
function Board:applyHint()
    local idx = self.hintIdx
    if not idx then
        return false
    end
    local step = Rating.nextStep(self.values)
    if not step or step.idx ~= idx then
        return false
    end
    self:pushHistory(idx)
    self.values[idx] = step.value
    self.notes[idx] = {}
    self.wrong[idx] = false
    self.hintsUsed = self.hintsUsed + 1
    self.lastAction = "hint"
    self:clearHint()
    self:checkSolved()
    return true
end

-- ---------------------------------------------------------------------------
-- 查询
-- ---------------------------------------------------------------------------

--- 所有未正确填入的格子（空格或填错的）
function Board:emptyCells()
    local list = {}
    for i = 1, Sudoku.CELLS do
        if self.values[i] == 0 then
            list[#list + 1] = i
        end
    end
    return list
end

function Board:emptyCount()
    return #self:emptyCells()
end

function Board:checkSolved()
    for i = 1, Sudoku.CELLS do
        if self.values[i] ~= self.solution[i] then
            self.solved = false
            return false
        end
    end
    self.solved = true
    self.selected = nil
    return true
end

function Board:digitCounts()
    return Sudoku.correctCounts(self.values, self.solution)
end

function Board:toggleNotesMode()
    self.notesMode = not self.notesMode
    return self.notesMode
end

--- 暂停/继续；暂停期间不计时（输入由 UI 遮罩挡住）
function Board:togglePause()
    if self.solved or self.failed or not self.started then
        return false
    end
    self.paused = not self.paused
    return self.paused
end

function Board:isPaused()
    return self.paused == true
end

--- 计时：首次选中格子后才开始走表，通关后停止
function Board:tick(dt)
    if self.started and not self.solved and not self.failed and not self.paused then
        self.elapsed = self.elapsed + dt
    end
end

function Board:timeText()
    local total = math.floor(self.elapsed)
    return string.format("%02d:%02d", math.floor(total / 60), total % 60)
end

-- ---------------------------------------------------------------------------
-- 存档序列化：只存纯数据，solution 由 puzzle 反解得到（题目唯一解，必能还原）
-- ---------------------------------------------------------------------------

function Board:serialize()
    local puzzle, values, wrong, notes = {}, {}, {}, {}
    for i = 1, Sudoku.CELLS do
        puzzle[i] = self.puzzle[i]
        values[i] = self.values[i]
        wrong[i] = self.wrong[i] and 1 or 0
        local list = {}
        for n = 1, 9 do
            if self.notes[i][n] then
                list[#list + 1] = n
            end
        end
        notes[i] = list
    end

    return {
        v = 1,
        difficulty = self.difficulty,
        puzzle = puzzle,
        values = values,
        notes = notes,
        wrong = wrong,
        mistakes = self.mistakes,
        elapsed = math.floor(self.elapsed),
        hints = self.hintsUsed,
        solved = self.solved and 1 or 0,
        selected = self.selected or 0,
        daily = self.dailyKey or "",
    }
end

local function isGrid(t)
    if type(t) ~= "table" or #t ~= Sudoku.CELLS then
        return false
    end
    for i = 1, Sudoku.CELLS do
        local v = t[i]
        if type(v) ~= "number" or v < 0 or v > 9 then
            return false
        end
    end
    return true
end

--- 从存档恢复；数据不合法返回 false，调用方继续开新局
function Board:restore(data)
    if type(data) ~= "table" or not isGrid(data.puzzle) then
        return false
    end

    local solution = Sudoku.solve(data.puzzle)
    if not solution then
        return false
    end

    local values = isGrid(data.values) and data.values or data.puzzle

    self.difficulty = data.difficulty or "normal"
    self.puzzle = {}
    for i = 1, Sudoku.CELLS do
        self.puzzle[i] = data.puzzle[i]
    end
    self.solution = solution

    self.values, self.notes, self.wrong = {}, {}, {}
    for i = 1, Sudoku.CELLS do
        local v = values[i] or 0
        if self.puzzle[i] ~= 0 then
            v = self.puzzle[i] -- 已知格永远以题目为准
        end
        self.values[i] = v
        self.wrong[i] = (v ~= 0 and v ~= solution[i])

        local notes = {}
        local saved = data.notes and data.notes[i]
        if type(saved) == "table" then
            for _, n in ipairs(saved) do
                if type(n) == "number" and n >= 1 and n <= 9 then
                    notes[n] = true
                end
            end
        end
        self.notes[i] = notes
    end

    self.mistakes = math.max(0, math.floor(tonumber(data.mistakes) or 0))
    self.elapsed = math.max(0, tonumber(data.elapsed) or 0)
    self.hintsUsed = math.max(0, math.floor(tonumber(data.hints) or 0))
    self.selected = (type(data.selected) == "number" and data.selected >= 1 and data.selected <= Sudoku.CELLS)
        and data.selected
        or nil
    local key = data.daily
    self.dailyKey = (type(key) == "string" and #key == 10) and key or nil
    self.paused = false
    self.failed = false
    self.history = {}
    self.notesMode = false
    self.started = (self.elapsed > 0) or (self.selected ~= nil)
    self.solved = false
    self.lastAction = "restore"

    self:checkSolved() -- 不信任存档里的 solved，按盘面重新判定
    if self.solved then
        self.selected = nil
    end
    return true
end

return Board
