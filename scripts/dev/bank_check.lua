-- 临时校验：题库里每道题是否真的符合该档难度（唯一解 + 技巧等级 + 已知数）
local Bank = require "game.puzzle_bank"
local Sudoku = require "game.sudoku"
local Rating = require "game.rating"

local EXPECT = {
    easy = { minL = 1, maxL = 1, minG = 44, maxG = 54 },
    normal = { minL = 2, maxL = 2, minG = 34, maxG = 46 },
    hard = { minL = 3, maxL = 3, minG = 27, maxG = 38 },
    expert = { minL = 2, maxL = 9, minG = 22, maxG = 32, allowUnsolved = true },
}

local function givensOf(p)
    local n = 0
    for i = 1, 81 do
        if p[i] ~= 0 then
            n = n + 1
        end
    end
    return n
end

function Start()
    local out = {}
    for _, key in ipairs(Bank.TIERS) do
        local exp = EXPECT[key]
        local n, bad, minG, maxG = 0, 0, 99, 0
        local hist = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
        local unsolved = 0

        for _, str in ipairs(Bank.DATA[key]) do
            n = n + 1
            local puzzle = {}
            for i = 1, 81 do
                puzzle[i] = tonumber(str:sub(i, i)) or 0
            end
            local g = givensOf(puzzle)
            if g < minG then minG = g end
            if g > maxG then maxG = g end

            local solutions = Sudoku.countSolutions(puzzle, 2)
            local r = Rating.analyze(puzzle)

            local okGivens = g >= exp.minG and g <= exp.maxG
            local okLevel
            if exp.allowUnsolved then
                okLevel = (not r.solved) or (r.level >= exp.minL and r.level <= exp.maxL)
            else
                okLevel = r.solved and r.level >= exp.minL and r.level <= exp.maxL
            end

            if not r.solved then
                unsolved = unsolved + 1
            else
                hist[r.level] = (hist[r.level] or 0) + 1
            end

            if solutions ~= 1 or not okGivens or not okLevel then
                bad = bad + 1
                out[#out + 1] = "[BANKCHK] 不合格 " .. key .. " givens=" .. g
                    .. " solutions=" .. solutions
                    .. " level=" .. r.level .. " solved=" .. tostring(r.solved)
            end
        end

        out[#out + 1] = "[BANKCHK] " .. key .. " 共 " .. n
            .. " 题，不合格 " .. bad
            .. "，已知数 " .. minG .. "-" .. maxG
            .. "，L1 " .. hist[1] .. " L2 " .. hist[2] .. " L3 " .. hist[3] .. " L4 " .. hist[4]
            .. "，基础技巧解不完 " .. unsolved
    end
    print(table.concat(out, "\n"))
end

function Stop() end
