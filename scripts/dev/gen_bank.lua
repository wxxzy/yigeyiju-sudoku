-- 临时工具：离线生成题库（严格筛选后把结果贴进 scripts/game/puzzle_bank.lua）
-- 跑法：taptap-maker preview validate --entry dev/gen_bank.lua --mode validate --validate-timeout 560

local Sudoku = require "game.sudoku"
local Rating = require "game.rating"

local PER_TIER = 20

-- 每档的挖洞下限 + 验收条件
local TIERS = {
    { key = "easy", floor = 46, maxGivens = 52, accept = function(r) return r.solved and r.level == 1 end },
    { key = "normal", floor = 38, maxGivens = 44, accept = function(r) return r.solved and r.level == 2 end },
    { key = "hard", floor = 31, maxGivens = 36, accept = function(r) return r.solved and r.level == 3 end },
    -- 专家：基础技巧（唯一候选/唯一位置/区块排除/数对）解不完，属于需要进阶技巧的题
    { key = "expert", floor = 25, maxGivens = 30, accept = function(r) return (not r.solved) and r.level >= 2 end },
}

local function toText(puzzle)
    local buf = {}
    for i = 1, 81 do
        buf[#buf + 1] = tostring(puzzle[i] or 0)
    end
    return table.concat(buf)
end

function Start()
    local lines = {}
    lines[#lines + 1] = "[BANK] -- 复制下面内容到 scripts/game/puzzle_bank.lua"

    for _, tier in ipairs(TIERS) do
        local got, attempts = {}, 0
        local givensSum = 0

        while #got < PER_TIER and attempts < 1800 do
            attempts = attempts + 1
            local puzzle, _solution, givens = Sudoku.generateRaw(tier.floor)
            if givens <= tier.maxGivens then
                local r = Rating.analyze(puzzle)
                if tier.accept(r) then
                    got[#got + 1] = toText(puzzle)
                    givensSum = givensSum + givens
                end
            end
        end

        lines[#lines + 1] = "[BANK] " .. tier.key .. " 收集 " .. #got .. "/" .. PER_TIER
            .. "，尝试 " .. attempts .. " 次"
            .. "，平均已知 " .. (#got > 0 and math.floor(givensSum / #got + 0.5) or 0)

        for _, s in ipairs(got) do
            lines[#lines + 1] = '[BANK]     "' .. s .. '",'
        end
    end

    print(table.concat(lines, "\n"))
end

function Stop() end
