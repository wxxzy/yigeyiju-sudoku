-- ============================================================================
-- 数独核心逻辑（纯 Lua，不依赖引擎，可单独跑测试）
--   · 生成完整解 → 挖洞 → 每次挖洞用「解数计数」保证唯一解
--   · 位掩码 + MRV（最小候选优先）搜索，挖洞校验足够快
-- ============================================================================

local Rating = require "game.rating"

local Sudoku = {}

Sudoku.SIZE = 9
Sudoku.CELLS = 81

-- 挖洞最多尝试几轮（取最优结果），轮数越多越接近目标难度，代价是生成耗时
Sudoku.GENERATE_ATTEMPTS = 24
-- 单次生成的软时间上限（秒），超时就用当前最优，避免卡住 UI
Sudoku.GENERATE_TIME_BUDGET = 0.9

-- 难度表
--   givens      期望已知数（用于评分的中心值）
--   minGivens   生成时挖到的下限（不低于它）
--   maxGivens   可接受的上限
--   minLevel    至少需要到哪层技巧（1 唯一候选 / 2 唯一位置 / 3 区块排除 / 4 数对）
--   maxLevel    最多到哪层（超过就太难，不要）
Sudoku.DIFFICULTIES = {
    {
        key = "easy", label = "简单",
        givens = 48, minGivens = 45, maxGivens = 52,
        minLevel = 1, maxLevel = 1,
        desc = "只看候选就能填，不需要任何技巧",
    },
    {
        key = "normal", label = "普通",
        givens = 40, minGivens = 36, maxGivens = 43,
        minLevel = 2, maxLevel = 2,
        desc = "需要找「某数只有一个位置」",
    },
    {
        key = "hard", label = "困难",
        givens = 33, minGivens = 29, maxGivens = 36,
        minLevel = 3, maxLevel = 3,
        desc = "需要区块排除（指向/声明）",
    },
    {
        key = "expert", label = "专家",
        givens = 28, minGivens = 24, maxGivens = 31,
        minLevel = 4, maxLevel = 4,
        desc = "需要数对等进阶排除",
    },
}

--- 取难度配置（找不到就回落到普通）
function Sudoku.configOf(difficulty)
    for _, d in ipairs(Sudoku.DIFFICULTIES) do
        if d.key == difficulty then
            return d
        end
    end
    return Sudoku.DIFFICULTIES[2]
end

-- ---------------------------------------------------------------------------
-- 索引与位掩码的基础设施
-- ---------------------------------------------------------------------------

local FULL = 0x1FF -- 9 位全 1，表示 1..9 全部候选

local ROW, COL, BOX = {}, {}, {}
for i = 1, Sudoku.CELLS do
    local r = math.floor((i - 1) / 9)
    local c = (i - 1) % 9
    ROW[i] = r + 1
    COL[i] = c + 1
    BOX[i] = math.floor(r / 3) * 3 + math.floor(c / 3) + 1
end
Sudoku.ROW, Sudoku.COL, Sudoku.BOX = ROW, COL, BOX

local function bitOf(v)
    return 1 << (v - 1)
end

local function popcount(m)
    local n = 0
    while m ~= 0 do
        m = m & (m - 1)
        n = n + 1
    end
    return n
end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function copyGrid(grid)
    local t = {}
    for i = 1, Sudoku.CELLS do
        t[i] = grid[i] or 0
    end
    return t
end

--- 由盘面构建行/列/宫位掩码；盘面本身不合法时返回 nil
local function buildMasks(grid)
    local rm, cm, bm = {}, {}, {}
    for i = 1, 9 do
        rm[i], cm[i], bm[i] = 0, 0, 0
    end
    for i = 1, Sudoku.CELLS do
        local v = grid[i]
        if v and v ~= 0 then
            local r, c, b = ROW[i], COL[i], BOX[i]
            local m = bitOf(v)
            if (rm[r] & m) ~= 0 or (cm[c] & m) ~= 0 or (bm[b] & m) ~= 0 then
                return nil
            end
            rm[r] = rm[r] | m
            cm[c] = cm[c] | m
            bm[b] = bm[b] | m
        end
    end
    return rm, cm, bm
end

--- 选出候选最少的空格；返回 idx, 候选掩码, 候选数
local function pickCell(grid, rm, cm, bm)
    local bestIdx, bestCand, bestCount = nil, nil, 10
    for i = 1, Sudoku.CELLS do
        if (grid[i] or 0) == 0 then
            local cand = FULL & ~(rm[ROW[i]] | cm[COL[i]] | bm[BOX[i]])
            local n = popcount(cand)
            if n == 0 then
                return nil, 0, 0 -- 死路
            end
            if n < bestCount then
                bestIdx, bestCand, bestCount = i, cand, n
                if n == 1 then
                    break
                end
            end
        end
    end
    return bestIdx, bestCand, bestCount
end

--- 把候选掩码展开成打乱顺序的数字列表
local function candidatesOf(cand)
    local list = {}
    for v = 1, 9 do
        if (cand & bitOf(v)) ~= 0 then
            list[#list + 1] = v
        end
    end
    return shuffle(list)
end

--- 计数解的数量（最多数到 limit 个即返回）
local function countSearch(grid, rm, cm, bm, limit)
    local idx, cand = pickCell(grid, rm, cm, bm)
    if cand == 0 then
        return 0
    end
    if not idx then
        return 1 -- 全部填满，得到一个解
    end

    local r, c, b = ROW[idx], COL[idx], BOX[idx]
    local total = 0
    for _, v in ipairs(candidatesOf(cand)) do
        local m = bitOf(v)
        grid[idx] = v
        rm[r], cm[c], bm[b] = rm[r] | m, cm[c] | m, bm[b] | m
        total = total + countSearch(grid, rm, cm, bm, limit)
        rm[r], cm[c], bm[b] = rm[r] & ~m, cm[c] & ~m, bm[b] & ~m
        grid[idx] = 0
        if total >= limit then
            return total
        end
    end
    return total
end

--- 就地填出第一个解（成功返回 true，盘面被填满）
local function fillFirst(grid, rm, cm, bm)
    local idx, cand = pickCell(grid, rm, cm, bm)
    if cand == 0 then
        return false
    end
    if not idx then
        return true
    end

    local r, c, b = ROW[idx], COL[idx], BOX[idx]
    for _, v in ipairs(candidatesOf(cand)) do
        local m = bitOf(v)
        grid[idx] = v
        rm[r], cm[c], bm[b] = rm[r] | m, cm[c] | m, bm[b] | m
        if fillFirst(grid, rm, cm, bm) then
            return true
        end
        rm[r], cm[c], bm[b] = rm[r] & ~m, cm[c] & ~m, bm[b] & ~m
        grid[idx] = 0
    end
    return false
end

-- ---------------------------------------------------------------------------
-- 对外接口
-- ---------------------------------------------------------------------------

--- 统计一个盘面（可含 0 表示空格）有多少个解，最多数到 limit 个
function Sudoku.countSolutions(grid, limit)
    local g = copyGrid(grid)
    local rm, cm, bm = buildMasks(g)
    if not rm then
        return 0
    end
    return countSearch(g, rm, cm, bm, limit or 2)
end

--- 求解：返回完整解盘面，无解返回 nil（不修改入参）
function Sudoku.solve(grid)
    local g = copyGrid(grid)
    local rm, cm, bm = buildMasks(g)
    if not rm then
        return nil
    end
    if not fillFirst(g, rm, cm, bm) then
        return nil
    end
    return g
end

--- 生成一个随机完整解
function Sudoku.generateSolution()
    local g = {}
    for i = 1, Sudoku.CELLS do
        g[i] = 0
    end
    local rm, cm, bm = {}, {}, {}
    for i = 1, 9 do
        rm[i], cm[i], bm[i] = 0, 0, 0
    end
    fillFirst(g, rm, cm, bm)
    return g
end

--- 从一个完整解挖洞到目标数量，返回 puzzle 与实际保留数
local function dig(solution, target)
    local puzzle = copyGrid(solution)
    local order = {}
    for i = 1, Sudoku.CELLS do
        order[i] = i
    end
    shuffle(order)

    local kept = Sudoku.CELLS
    for _, idx in ipairs(order) do
        if kept <= target then
            break
        end
        local backup = puzzle[idx]
        if backup ~= 0 then
            puzzle[idx] = 0
            if Sudoku.countSolutions(puzzle, 2) == 1 then
                kept = kept - 1
            else
                puzzle[idx] = backup -- 破坏唯一解，撤销挖洞
            end
        end
    end
    return puzzle, kept
end

--- 随机生成一道挖到指定已知数的题（不做技巧校验，给上层筛选用）
---@param floorGivens integer 挖到不超过这个已知数就停
---@return table puzzle, table solution, integer givens
function Sudoku.generateRaw(floorGivens)
    local solution = Sudoku.generateSolution()
    local puzzle, kept = dig(solution, floorGivens)
    return puzzle, solution, kept
end

--- 按难度生成题目，返回 puzzle（0 表示空格）, solution
--- 先用已知数区间挖洞，再用技巧评分器校验「需要到哪一层」，
--- 达标才收；多轮拿不到就返回最接近的一题（保证不卡住 UI）
function Sudoku.generate(difficulty)
    local cfg = Sudoku.configOf(difficulty)

    local best, bestScore = nil, nil
    local deadline = os.clock() + Sudoku.GENERATE_TIME_BUDGET

    for _ = 1, Sudoku.GENERATE_ATTEMPTS do
        local puzzle, solution, kept = Sudoku.generateRaw(cfg.minGivens)
        local rate = Rating.analyze(puzzle)

        local score = 0
        -- 技巧等级落在区间内加 100；越界按距离扣分
        if rate.solved then
            if rate.level >= cfg.minLevel and rate.level <= cfg.maxLevel then
                score = score + 100
            else
                local dist
                if rate.level < cfg.minLevel then
                    dist = cfg.minLevel - rate.level
                else
                    dist = rate.level - cfg.maxLevel
                end
                score = score - dist * 25
            end
        else
            score = score - 60 -- 基础技巧解不完的题不参与评级（对玩家过难且不可解释）
        end

        -- 已知数落在 [minGivens, maxGivens] 再加 40
        if kept >= cfg.minGivens and kept <= cfg.maxGivens then
            score = score + 40
        else
            score = score - math.abs(kept - cfg.givens)
        end

        if bestScore == nil or score > bestScore then
            bestScore = score
            best = { puzzle = puzzle, solution = solution, givens = kept, rate = rate }
        end

        if score >= 140 then
            break -- 技巧与已知数都达标
        end
        if os.clock() > deadline then
            break -- 超时就用当前最优
        end
    end

    return best.puzzle, best.solution, best.givens, best.rate
end

--- 两个格子是否同行/同列/同宫
function Sudoku.isPeer(a, b)
    if a == b then
        return false
    end
    return ROW[a] == ROW[b] or COL[a] == COL[b] or BOX[a] == BOX[b]
end

--- 统计 1..9 每个数字已正确填入的个数，返回 { [1]=count, ... }
function Sudoku.correctCounts(values, solution)
    local counts = {}
    for v = 1, 9 do
        counts[v] = 0
    end
    for i = 1, Sudoku.CELLS do
        local v = values[i]
        if v and v ~= 0 and v == solution[i] then
            counts[v] = counts[v] + 1
        end
    end
    return counts
end

return Sudoku
