-- ============================================================================
-- 数独技巧评分器（纯逻辑，不依赖引擎）
--   用人类可解释的技巧逐层推进，记录「解开这盘最少需要到哪一层」：
--     L1 唯一候选（naked single）        —— 扫描即得
--     L2 唯一位置（hidden single）       —— 行/列/宫里某数只有一个落脚点
--     L3 区块排除（locked candidates）   —— 指向/声明排除
--     L4 数对（naked pair）              —— 两格共两数，排除其余
--   生成题目时用它给题目定级，游戏中用它给出「下一步」提示
-- ============================================================================

local Rating = {}

Rating.LEVEL = {
    NAKED = 1,
    HIDDEN = 2,
    LOCKED = 3,
    PAIR = 4,
}

local FULL = 0x1FF

local function bit(v)
    return 1 << (v - 1)
end

local function has(mask, v)
    return (mask & bit(v)) ~= 0
end

local function popcount(m)
    local n = 0
    while m ~= 0 do
        m = m & (m - 1)
        n = n + 1
    end
    return n
end

-- ---------------------------------------------------------------------------
-- 索引基础设施：行/列/宫、单元列表、邻居
-- ---------------------------------------------------------------------------

local ROW, COL, BOX = {}, {}, {}
for i = 1, 81 do
    local r = math.floor((i - 1) / 9)
    local c = (i - 1) % 9
    ROW[i] = r + 1
    COL[i] = c + 1
    BOX[i] = math.floor(r / 3) * 3 + math.floor(c / 3) + 1
end

local UNITS = {}
do
    local function pushUnit(cells, kind, label)
        local set = {}
        for _, i in ipairs(cells) do
            set[i] = true
        end
        UNITS[#UNITS + 1] = { cells = cells, set = set, kind = kind, label = label }
    end

    for r = 1, 9 do
        local cells = {}
        for c = 1, 9 do
            cells[#cells + 1] = (r - 1) * 9 + c
        end
        pushUnit(cells, "row", "第" .. r .. "行")
    end
    for c = 1, 9 do
        local cells = {}
        for r = 1, 9 do
            cells[#cells + 1] = (r - 1) * 9 + c
        end
        pushUnit(cells, "col", "第" .. c .. "列")
    end
    for b = 1, 9 do
        local cells = {}
        local baseR = math.floor((b - 1) / 3) * 3
        local baseC = ((b - 1) % 3) * 3
        for dr = 0, 2 do
            for dc = 0, 2 do
                cells[#cells + 1] = (baseR + dr) * 9 + (baseC + dc) + 1
            end
        end
        pushUnit(cells, "box", "第" .. b .. "宫")
    end
end
Rating.UNITS = UNITS

local ROW_UNITS, COL_UNITS, BOX_UNITS = {}, {}, {}
for _, u in ipairs(UNITS) do
    if u.kind == "row" then
        ROW_UNITS[#ROW_UNITS + 1] = u
    elseif u.kind == "col" then
        COL_UNITS[#COL_UNITS + 1] = u
    else
        BOX_UNITS[#BOX_UNITS + 1] = u
    end
end

local PEERS = {}
for i = 1, 81 do
    local list, seen = {}, {}
    for j = 1, 81 do
        if j ~= i and (ROW[j] == ROW[i] or COL[j] == COL[i] or BOX[j] == BOX[i]) then
            if not seen[j] then
                seen[j] = true
                list[#list + 1] = j
            end
        end
    end
    PEERS[i] = list
end

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------

local State = {}
State.__index = State

--- 由盘面构建状态（cands 用位掩码表示候选）
function Rating.state(puzzle)
    local s = setmetatable({ vals = {}, cands = {} }, State)
    for i = 1, 81 do
        s.vals[i] = puzzle[i] or 0
    end
    for i = 1, 81 do
        if s.vals[i] ~= 0 then
            s.cands[i] = 0
        else
            local used = 0
            for _, j in ipairs(PEERS[i]) do
                local v = s.vals[j]
                if v ~= 0 then
                    used = used | bit(v)
                end
            end
            s.cands[i] = FULL & ~used
        end
    end
    return s
end

function State:clone()
    local s = setmetatable({ vals = {}, cands = {} }, State)
    for i = 1, 81 do
        s.vals[i] = self.vals[i]
        s.cands[i] = self.cands[i]
    end
    return s
end

function State:emptyCount()
    local n = 0
    for i = 1, 81 do
        if self.vals[i] == 0 then
            n = n + 1
        end
    end
    return n
end

function State:place(idx, v)
    self.vals[idx] = v
    self.cands[idx] = 0
    local b = bit(v)
    for _, j in ipairs(PEERS[idx]) do
        if self.vals[j] == 0 then
            self.cands[j] = self.cands[j] & ~b
        end
    end
end

--- 位掩码转数字列表
function Rating.digitsOf(mask)
    local t = {}
    for v = 1, 9 do
        if has(mask, v) then
            t[#t + 1] = v
        end
    end
    return t
end

-- ---------------------------------------------------------------------------
-- 技巧：L1 唯一候选
-- ---------------------------------------------------------------------------

local function tryNakedSingle(s)
    for i = 1, 81 do
        if s.vals[i] == 0 and popcount(s.cands[i]) == 1 then
            local v = Rating.digitsOf(s.cands[i])[1]
            s:place(i, v)
            return { idx = i, value = v, level = Rating.LEVEL.NAKED,
                reason = "这一格只剩 " .. v .. " 可以填" }
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- 技巧：L2 唯一位置
-- ---------------------------------------------------------------------------

local function tryHiddenSingle(s)
    for _, unit in ipairs(UNITS) do
        for v = 1, 9 do
            local only, count, placed = nil, 0, false
            for _, i in ipairs(unit.cells) do
                if s.vals[i] == v then
                    placed = true
                    break
                end
                if s.vals[i] == 0 and has(s.cands[i], v) then
                    count = count + 1
                    only = i
                end
            end
            if not placed and count == 1 and only then
                s:place(only, v)
                return { idx = only, value = v, level = Rating.LEVEL.HIDDEN,
                    reason = unit.label .. "只剩一格能填 " .. v }
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- 技巧：L3 区块排除（指向 + 声明）
-- ---------------------------------------------------------------------------

local function eliminate(s, idx, v)
    if s.vals[idx] ~= 0 then
        return false
    end
    if not has(s.cands[idx], v) then
        return false
    end
    s.cands[idx] = s.cands[idx] & ~bit(v)
    return true
end

local function tryLockedCandidates(s)
    -- 指向（pointing）：宫内某数只出现在同一行/列 → 该行/列宫外可排除
    for _, box in ipairs(BOX_UNITS) do
        for v = 1, 9 do
            local cells, placed = {}, false
            for _, i in ipairs(box.cells) do
                if s.vals[i] == v then
                    placed = true
                    break
                end
                if s.vals[i] == 0 and has(s.cands[i], v) then
                    cells[#cells + 1] = i
                end
            end

            if not placed and #cells >= 2 then
                local r0, c0 = ROW[cells[1]], COL[cells[1]]
                local sameRow, sameCol = true, true
                for k = 2, #cells do
                    if ROW[cells[k]] ~= r0 then
                        sameRow = false
                    end
                    if COL[cells[k]] ~= c0 then
                        sameCol = false
                    end
                end

                if sameRow then
                    local changed = false
                    for c = 1, 9 do
                        local i = (r0 - 1) * 9 + c
                        if BOX[i] ~= BOX[cells[1]] and eliminate(s, i, v) then
                            changed = true
                        end
                    end
                    if changed then
                        return true
                    end
                elseif sameCol then
                    local changed = false
                    for r = 1, 9 do
                        local i = (r - 1) * 9 + c0
                        if BOX[i] ~= BOX[cells[1]] and eliminate(s, i, v) then
                            changed = true
                        end
                    end
                    if changed then
                        return true
                    end
                end
            end
        end
    end

    -- 声明（claiming）：行/列内某数只落在同一宫 → 该宫内行/列外可排除
    for _, unit in ipairs(UNITS) do
        if unit.kind ~= "box" then
            for v = 1, 9 do
                local cells, placed = {}, false
                for _, i in ipairs(unit.cells) do
                    if s.vals[i] == v then
                        placed = true
                        break
                    end
                    if s.vals[i] == 0 and has(s.cands[i], v) then
                        cells[#cells + 1] = i
                    end
                end

                if not placed and #cells >= 2 then
                    local b0 = BOX[cells[1]]
                    local sameBox = true
                    for k = 2, #cells do
                        if BOX[cells[k]] ~= b0 then
                            sameBox = false
                        end
                    end

                    if sameBox then
                        local changed = false
                        for _, i in ipairs(BOX_UNITS[b0].cells) do
                            if not unit.set[i] and eliminate(s, i, v) then
                                changed = true
                            end
                        end
                        if changed then
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- 技巧：L4 数对
-- ---------------------------------------------------------------------------

local function tryNakedPair(s)
    for _, unit in ipairs(UNITS) do
        for a = 1, #unit.cells - 1 do
            local ia = unit.cells[a]
            if s.vals[ia] == 0 and popcount(s.cands[ia]) == 2 then
                for b = a + 1, #unit.cells do
                    local ib = unit.cells[b]
                    if s.vals[ib] == 0 and s.cands[ib] == s.cands[ia] then
                        local changed = false
                        local digits = Rating.digitsOf(s.cands[ia])
                        for _, i in ipairs(unit.cells) do
                            if i ~= ia and i ~= ib then
                                for _, v in ipairs(digits) do
                                    if eliminate(s, i, v) then
                                        changed = true
                                    end
                                end
                            end
                        end
                        if changed then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- 对外接口
-- ---------------------------------------------------------------------------

--- 逐层推进，返回这道题的技巧等级
---@param puzzle table
---@param opts table|nil { onStall = fun(state) } 卡住时回调，便于诊断
---@return table { solved=boolean, level=integer, remaining=integer, steps=integer }
function Rating.analyze(puzzle, opts)
    local s = Rating.state(puzzle)
    local level, steps = 0, 0

    while s:emptyCount() > 0 and steps < 400 do
        steps = steps + 1
        local info = tryNakedSingle(s)
        if info then
            level = math.max(level, Rating.LEVEL.NAKED)
        else
            info = tryHiddenSingle(s)
            if info then
                level = math.max(level, Rating.LEVEL.HIDDEN)
            elseif tryLockedCandidates(s) then
                level = math.max(level, Rating.LEVEL.LOCKED)
            elseif tryNakedPair(s) then
                level = math.max(level, Rating.LEVEL.PAIR)
            else
                if opts and opts.onStall then
                    opts.onStall(s)
                end
                break -- 基础技巧到此为止
            end
        end
    end

    return {
        solved = s:emptyCount() == 0,
        level = level,
        remaining = s:emptyCount(),
        steps = steps,
        vals = s.vals, -- 解出来的盘面，供自检核对是否填错
    }
end

--- 给出当前盘面的「下一步」：只找唯一候选 / 唯一位置（不猜、不填）
---@return table|nil { idx, value, level, reason }
function Rating.nextStep(puzzle)
    local s = Rating.state(puzzle)
    local info = tryNakedSingle(s)
    if info then
        return info
    end
    info = tryHiddenSingle(s)
    if info then
        return info
    end
    return nil
end

--- 候选数列表（供 UI 自动显示用）
function Rating.candidates(puzzle)
    local s = Rating.state(puzzle)
    local out = {}
    for i = 1, 81 do
        if s.vals[i] == 0 then
            out[i] = Rating.digitsOf(s.cands[i])
        else
            out[i] = {}
        end
    end
    return out
end

return Rating
