-- ============================================================================
-- 逻辑自检脚本（不参与正式游戏入口）
-- 跑法：
--   taptap-maker preview validate --entry dev/selftest.lua --mode validate
-- 覆盖：四档难度的唯一解、已知数个数、求解一致性、完整填盘判定、错误计数
-- ============================================================================

local Sudoku = require "game.sudoku"
local Board = require "game.board"

local failures = 0
local checks = 0

local function check(ok, msg)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        print("[SELFTEST][FAIL] " .. msg)
    end
end

local function givensOf(puzzle)
    local n = 0
    for i = 1, Sudoku.CELLS do
        if puzzle[i] ~= 0 then
            n = n + 1
        end
    end
    return n
end

local function run()
    -- 1) 每档难度：题目合法 + 唯一解 + 解与 solution 一致
    for _, d in ipairs(Sudoku.DIFFICULTIES) do
        local puzzle, solution = Sudoku.generate(d.key)
        local givens = givensOf(puzzle)
        -- 目标个数是期望值，多轮取最优后允许有 1 个偏差
        check(givens <= d.givens + 1, d.key .. " 已知数 " .. givens .. " 超过目标 " .. d.givens)
        print("[SELFTEST][INFO] " .. d.key .. " 已知数 " .. givens .. "（目标 " .. d.givens .. "）")
        check(Sudoku.countSolutions(puzzle, 2) == 1, d.key .. " 题目不是唯一解")

        local solved = Sudoku.solve(puzzle)
        check(solved ~= nil, d.key .. " 求解失败")
        if solved then
            local same = true
            for i = 1, Sudoku.CELLS do
                if solved[i] ~= solution[i] then
                    same = false
                    break
                end
            end
            check(same, d.key .. " 求解结果与生成解不一致")
        end

        -- 题目本身不能违反规则
        for i = 1, Sudoku.CELLS do
            local v = puzzle[i]
            if v ~= 0 then
                for j = 1, Sudoku.CELLS do
                    if j ~= i and puzzle[j] == v and Sudoku.isPeer(i, j) then
                        check(false, string.format("%s 题目冲突：格 %d 与 %d", d.key, i, j))
                    end
                end
            end
        end
    end

    -- 2) 会话状态：填错计数、撤销、提示、通关
    local board = Board.new("easy")
    check(board.values[1] ~= nil, "reset 后 values 未初始化")

    local empty = board:emptyCells()
    check(#empty > 0, "开局没有空格")

    local first = empty[1]
    board:select(first)

    -- 填错：选一个与答案不同的数字
    local wrongDigit = 1
    for n = 1, 9 do
        if n ~= board.solution[first] then
            wrongDigit = n
            break
        end
    end
    board:input(wrongDigit)
    check(board.mistakes == 1, "填错没有累计错误次数")
    check(board.wrong[first] == true, "填错没有标记 wrong")
    check(not board.solved, "填错不应判通关")

    -- 撤销应恢复原状
    board:undo()
    check(board.values[first] == 0, "撤销没有还原空格")
    check(board.mistakes == 0, "撤销没有还原错误次数")

    -- 提示应填对
    board:select(first)
    board:hint()
    check(board.values[first] == board.solution[first], "提示没有填入正确答案")

    -- 全部填满 → 通关
    for _, idx in ipairs(board:emptyCells()) do
        board:select(idx)
        board:input(board.solution[idx])
    end
    check(board.solved == true, "全部填对后没有判定通关")
    check(board:emptyCount() == 0, "通关后仍有空格")

    -- 通关后不可再编辑
    board:select(first)
    check(board:canEdit(first) == false, "通关后仍可编辑")

    -- 3) 存档序列化 / 还原
    local fresh = Board.new("hard")
    local e1 = fresh:emptyCells()[1]
    fresh:select(e1)
    fresh:input(fresh.solution[e1]) -- 填对一个
    local e2 = fresh:emptyCells()[2]
    fresh:select(e2)
    fresh:toggleNotesMode()
    fresh:input(2)
    fresh:input(7)
    fresh:toggleNotesMode()
    fresh.elapsed = 123.6

    local snap = fresh:serialize()
    check(#snap.puzzle == Sudoku.CELLS and #snap.values == Sudoku.CELLS, "序列化盘面长度不对")

    local restored = Board.new("easy") -- 故意用别的难度，验证 restore 会覆盖
    local okRestore = restored:restore(snap)
    check(okRestore == true, "restore 失败")
    check(restored.difficulty == "hard", "restore 没有还原难度")
    check(restored.values[e1] == fresh.values[e1], "restore 没有还原已填数字")
    check(restored.notes[e2][2] == true and restored.notes[e2][7] == true, "restore 没有还原笔记")
    check(restored.notes[e2][5] == nil, "restore 多出了不该有的笔记")
    check(math.floor(restored.elapsed) == 123, "restore 没有还原用时")
    check(restored.solution[e1] == fresh.solution[e1], "restore 反解出的答案不一致")
    check(restored:emptyCount() == fresh:emptyCount(), "restore 后空格数不一致")

    -- 非法存档必须被拒绝，而不是污染棋盘
    check(restored:restore({ puzzle = { 1, 2, 3 } }) == false, "非法存档没有被拒绝")
    check(restored:restore({ puzzle = { 5, 5 } }) == false, "残缺存档没有被拒绝")

    -- 4) 存档层：有可用后端时应能存取一致
    local Storage = require "game.storage"
    local saved, source = false, "none"
    Storage.save(snap, function(ok, src)
        saved, source = ok, src
    end)
    if saved then
        local loaded = nil
        Storage.load(function(data)
            loaded = data
        end)
        check(type(loaded) == "table", "存了却读不回来（" .. source .. "）")
        if type(loaded) == "table" then
            check(loaded.puzzle[e1] == snap.puzzle[e1], "存档读回后盘面不一致")
            check(loaded.difficulty == "hard", "存档读回后难度不一致")

            -- 完整回路：存档数据 → Board.restore
            local resumed = Board.new("easy")
            check(resumed:restore(loaded) == true, "存档数据无法还原成棋盘")
            check(resumed.values[e1] == fresh.values[e1], "还原后已填数字丢失")
            check(resumed.notes[e2][7] == true, "还原后笔记丢失")
            check(math.floor(resumed.elapsed) == 123, "还原后用时丢失")
        end
    else
        print("[SELFTEST][INFO] 当前环境无存档后端，跳过存取校验")
    end

    print(string.format("[SELFTEST] checks=%d failures=%d", checks, failures))
    print(failures == 0 and "[SELFTEST] RESULT=OK" or "[SELFTEST] RESULT=FAILED")
end

function Start()
    local ok, err = pcall(run)
    if not ok then
        print("[SELFTEST][FAIL] 运行异常: " .. tostring(err))
    end
end

function Stop() end
