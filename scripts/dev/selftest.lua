-- ============================================================================
-- 逻辑自检脚本（不参与正式游戏入口）
-- 跑法：
--   taptap-maker preview validate --entry dev/selftest.lua --mode validate
-- 覆盖：四档难度的唯一解、已知数个数、求解一致性、完整填盘判定、错误计数
-- ============================================================================

local Sudoku = require "game.sudoku"
local Board = require "game.board"
local Daily = require "game.daily"
local Records = require "game.records"
local PuzzleBank = require "game.puzzle_bank"
local Settings = require "game.settings"

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

    -- 5) 成绩记录：首局算记录、更慢不覆盖、更快才刷新
    local Records = require "game.records"
    local recs = Records.new()

    local isRec, prev = Records.submit(recs, "easy", 500, 3)
    check(isRec == true and prev == nil, "首局通关没有记为记录")

    isRec, prev = Records.submit(recs, "easy", 600, 0)
    check(isRec == false, "更慢的成绩覆盖了记录")
    check(prev ~= nil and prev.time == 500, "更慢时没拿到旧记录")
    check(Records.bestOf(recs, "easy").time == 500, "记录被更慢的成绩改写")

    isRec, prev = Records.submit(recs, "easy", 420, 7)
    check(isRec == true, "更快的成绩没有刷新记录")
    local best = Records.bestOf(recs, "easy")
    check(best.time == 420 and best.mistakes == 7, "刷新后的记录内容不对")

    -- 难度之间互不影响
    check(Records.bestOf(recs, "hard") == nil, "不同难度记录串了")

    -- 脏数据必须被清掉
    local dirty = Records.sanitize({ best = { easy = { time = "abc" }, hard = { time = 300 } } })
    check(Records.bestOf(dirty, "easy") == nil, "脏成绩没有被丢弃")
    check(Records.bestOf(dirty, "hard") ~= nil, "合法成绩被误删")

    -- 成绩也能走存档层往返
    local statsSaved = false
    Storage.saveStats(recs, function(ok)
        statsSaved = ok
    end)
    if statsSaved then
        local loadedStats = nil
        Storage.loadStats(function(data)
            loadedStats = Records.sanitize(data)
        end)
        check(type(loadedStats) == "table", "成绩存了却读不回来")
        if type(loadedStats) == "table" then
            local e = Records.bestOf(loadedStats, "easy")
            check(e ~= nil and e.time == 420, "成绩读回后内容不一致")
        end
    end

    -- 6) 题库：每档题目必须真的符合该档技巧要求
    local PuzzleBank = require "game.puzzle_bank"
    local Rating = require "game.rating"

    local EXPECT_LEVEL = { easy = 1, normal = 2, hard = 3 }
    for _, key in ipairs(PuzzleBank.TIERS) do
        local list = PuzzleBank.DATA[key] or {}
        check(#list > 0, key .. " 题库为空")

        for i, str in ipairs(list) do
            check(#str == 81, key .. " 第" .. i .. "题长度不是 81")
            local puzzle = {}
            for k = 1, 81 do
                puzzle[k] = tonumber(str:sub(k, k)) or 0
            end
            check(Sudoku.countSolutions(puzzle, 2) == 1, key .. " 第" .. i .. "题不是唯一解")

            local r = Rating.analyze(puzzle)
            if key == "expert" then
                -- 专家：基础技巧（含数对）解不完
                check(not r.solved, key .. " 第" .. i .. "题其实基础技巧能解完")
            else
                check(r.solved, key .. " 第" .. i .. "题基础技巧解不完")
                check(r.level == EXPECT_LEVEL[key],
                    key .. " 第" .. i .. "题技巧等级 " .. r.level .. "，期望 " .. EXPECT_LEVEL[key])

                -- 解出来的盘面必须与真实解一致（防过度排除导致的错填）
                local truth = Sudoku.solve(puzzle)
                local same = truth ~= nil
                if truth then
                    for k = 1, 81 do
                        if r.vals[k] ~= truth[k] then
                            same = false
                            break
                        end
                    end
                end
                check(same, key .. " 第" .. i .. "题推导过程出错")
            end
        end
    end

    -- 7) 提示：给出的下一步必须是对的
    local hintBoard = Board.new("easy")
    hintBoard.showCandidates = true
    local step = hintBoard:requestHint()
    check(step ~= nil, "简单局求不出下一步提示")
    if step then
        check(step.value == hintBoard.solution[step.idx], "提示给的值不对")
        check(hintBoard.hintIdx == step.idx, "提示没有记录高亮格")
        check(hintBoard:applyHint() == true, "提示无法填入")
        check(hintBoard.values[step.idx] == step.value, "填入后数字不对")
        check(hintBoard.hintsUsed == 1, "提示次数没有累计")
        check(hintBoard.hintIdx == nil, "填入后没有清掉提示标记")
    end

    -- 7.5) 提示限额：次数用尽后两个入口都要拒绝
    check(hintBoard.hintLimit > 0, "easy 档应配置提示上限")
    hintBoard.hintsUsed = hintBoard.hintLimit
    check(hintBoard:hintsLeft() <= 0, "用尽后 hintsLeft 应为 0")
    check(hintBoard:requestHint() == nil, "用尽后 requestHint 应拒绝")
    check(hintBoard:hint() == false, "用尽后直接提示也应拒绝")
    hintBoard.hintsUsed = 0
    check(hintBoard:hintsLeft() == hintBoard.hintLimit, "重置已用次数后剩余额度应回满")

    -- 8) 自动候选：给的候选里不能包含与已填数字冲突的数
    local cands = hintBoard:autoCandidates()
    for i = 1, 81 do
        if hintBoard.values[i] == 0 then
            for _, v in ipairs(cands[i] or {}) do
                local conflict = false
                for j = 1, 81 do
                    if j ~= i and hintBoard.values[j] == v and Sudoku.isPeer(i, j) then
                        conflict = true
                        break
                    end
                end
                check(not conflict, "第" .. i .. "格候选 " .. v .. " 与同行列宫冲突")
            end
        end
    end

    -- 9) 自动清理笔记：填入正确数字后清掉同行列宫的笔记，且能整体撤销
    do
        local b = Board.new("easy")
        local idx, n
        for i = 1, 81 do
            if b.values[i] == 0 then
                idx = i
                n = b.solution[i]
                break
            end
        end
        local peer
        for i = 1, 81 do
            if i ~= idx and b.values[i] == 0 and Sudoku.isPeer(idx, i) then
                peer = i
                break
            end
        end

        if idx and peer and n then
            b:select(peer)
            b:toggleNotesMode()
            b:input(n)
            b:toggleNotesMode()
            check(b.notes[peer][n] == true, "笔记没有写进去，后续校验无意义")

            b:select(idx)
            b:input(n)
            check(b.values[idx] == n, "正确数字没有填上")
            check(b.notes[peer][n] == nil, "填入正确数字后没有清掉同行列宫的笔记")

            b:undo()
            check(b.values[idx] == 0, "撤销没有还原填的数")
            check(b.notes[peer][n] == true, "撤销没有恢复被清掉的笔记")
        else
            check(false, "没找到可用于清笔记校验的空格")
        end

        -- 关掉开关时不应清理
        local b2 = Board.new("easy")
        b2.autoCleanNotes = false
        local i2, n2, p2
        for i = 1, 81 do
            if b2.values[i] == 0 then
                i2 = i
                n2 = b2.solution[i]
                break
            end
        end
        for i = 1, 81 do
            if i ~= i2 and b2.values[i] == 0 and Sudoku.isPeer(i2, i) then
                p2 = i
                break
            end
        end
        if i2 and p2 and n2 then
            b2:select(p2)
            b2:toggleNotesMode()
            b2:input(n2)
            b2:toggleNotesMode()
            b2:select(i2)
            b2:input(n2)
            check(b2.notes[p2][n2] == true, "关掉自动清笔记后仍然被清掉了")
        end
    end

    -- 10) 暂停：暂停期间不计时，恢复后继续；未开始不能暂停；通关后不能暂停
    do
        local b = Board.new("easy")
        check(b:togglePause() == false, "还没开始就允许暂停")
        b.started = true
        b:tick(1)
        check(b.elapsed >= 0.9, "正常计时异常")

        check(b:togglePause() == true, "暂停失败")
        local frozen = b.elapsed
        b:tick(5)
        check(math.abs(b.elapsed - frozen) < 0.0001, "暂停期间仍在计时")
        check(b:isPaused() == true, "暂停状态没置上")

        check(b:togglePause() == false, "恢复失败")
        b:tick(1)
        check(b.elapsed > frozen + 0.9, "恢复后没有继续计时")

        b.solved = true
        check(b:togglePause() == false, "通关后仍允许暂停")
    end

    -- 11) 每日一题：日期解析、确定性选题、难度轮换
    do
        local key = Daily.today()
        check(type(key) == "string" and #key == 10, "拿不到今天的日期键")

        check(Daily.dayTime("2026-10-31") ~= nil, "合法日期解析失败")
        check(Daily.dayTime("2026/10/31") == nil, "非法日期没被拒绝")
        check(Daily.dayTime(nil) == nil, "nil 日期没被拒绝")

        check(Daily.isPreviousDay("2026-10-30", "2026-10-31") == true, "相邻两天识别失败")
        check(Daily.isPreviousDay("2026-10-29", "2026-10-31") == false, "隔一天误判为相邻")
        check(Daily.isPreviousDay("2026-10-31", "2026-10-31") == false, "同一天误判为前一天")

        check(Daily.indexFor("2026-10-31", 8) == Daily.indexFor("2026-10-31", 8), "同一天选题不稳定")
        local i1 = Daily.indexFor("2026-10-31", 8)
        check(i1 >= 1 and i1 <= 8, "选题下标越界")

        local d1 = Daily.difficultyFor("2026-10-31")
        check(type(d1) == "string" and d1 ~= "", "取不到当日难度")

        local count = PuzzleBank.count("easy")
        check(count > 0, "题库为空，每日一题无题可选")

        local bd = Board.new("easy")
        bd:reset("easy", { daily = "2026-10-31" })
        check(bd.dailyKey == "2026-10-31", "每日标记没有记上")

        local expect = PuzzleBank.pickAt("easy", Daily.indexFor("2026-10-31", count))
        local same = type(expect) == "table"
        if same then
            for i = 1, 81 do
                if bd.puzzle[i] ~= expect[i] then
                    same = false
                    break
                end
            end
        end
        check(same, "每日题与按日期算出的题不一致")

        local bd2 = Board.new("normal")
        bd2:reset("easy", { daily = "2026-10-31" })
        local samePuzzle = true
        for i = 1, 81 do
            if bd.puzzle[i] ~= bd2.puzzle[i] then
                samePuzzle = false
                break
            end
        end
        check(samePuzzle, "同一天两次开局拿到不同题")

        -- 每日标记要能存档 / 恢复
        local data = bd:serialize()
        check(data.daily == "2026-10-31", "每日标记没进存档")
        local bd3 = Board.new("easy")
        check(bd3:restore(data) == true, "每日存档恢复失败")
        check(bd3.dailyKey == "2026-10-31", "恢复后丢了每日标记")

        -- 普通局不该带每日标记
        local bp = Board.new("easy")
        bp:reset("easy")
        check(bp.dailyKey == nil, "普通局被误标成每日题")
    end

    -- 12) 连续打卡与累计通关
    do
        local st = Daily.newState()
        local s1, f1 = Daily.markCleared(st, "2026-10-29")
        check(s1 == 1 and f1 == true, "首日打卡没有从 1 开始")
        local s2, f2 = Daily.markCleared(st, "2026-10-30")
        check(s2 == 2 and f2 == true, "连续第二天没有 +1")
        local s3 = Daily.markCleared(st, "2026-10-30")
        check(s3 == 2, "同一天重复完成仍然加天数")
        local s4 = Daily.markCleared(st, "2026-11-02")
        check(s4 == 1, "中断后没有重置为 1")
        check(st.cleared == 4, "每日完成次数计数不对")

        local rec = Records.new()
        check(Records.clearedCount(rec) == 0, "新记录通关数不是 0")
        Records.markCleared(rec)
        Records.markCleared(rec)
        check(Records.clearedCount(rec) == 2, "累计通关数不对")

        -- 兼容 v1 存档（只有 best）
        local legacy = Records.sanitize({ v = 1, best = { hard = { time = 100, mistakes = 2 } } })
        check(legacy.best.hard and legacy.best.hard.time == 100, "v1 存档成绩没有读回来")
        check(Records.clearedCount(legacy) == 0, "v1 存档补默认通关数失败")
        check(legacy.daily.streak == 0, "v1 存档补默认每日状态失败")

        -- 脏数据清洗
        local dirty = Records.sanitize({ cleared = -5, daily = { streak = "x", last = 123, cleared = -1 } })
        check(Records.clearedCount(dirty) == 0, "负数通关数没被清掉")
        check(dirty.daily.streak == 0, "非法连续天数没被清掉")
        check(dirty.daily.last == "", "非法日期没被清掉")
        check(dirty.daily.cleared == 0, "负数每日次数没被清掉")
    end

    -- 13) 设置：默认值、非法值回落、循环切换、随存档往返
    do
        local st = Settings.sanitize({ sound = false, autoClean = false, candidateFont = 99, mistakeLimit = -1 })
        check(st.sound == false, "音效设置没有读回")
        check(st.autoClean == false, "自动清笔记设置没有读回")
        check(st.candidateFont == 11, "非法候选字号没有回落到默认 11")
        check(st.mistakeLimit == 0, "非法错误上限没有回落到默认 0")

        local empty = Settings.sanitize(nil)
        check(empty.sound == true and empty.autoClean == true, "空设置没有给默认值")
        check(empty.candidateFont == 11 and empty.mistakeLimit == 0, "空设置默认值不对")

        local s2 = Settings.new()
        check(Settings.cycleCandidateFont(s2) == 12, "字号循环 11→12 失败")
        check(Settings.cycleCandidateFont(s2) == 10, "字号循环 12→10 失败")
        check(Settings.cycleCandidateFont(s2) == 11, "字号循环 10→11 失败")

        local s3 = Settings.new()
        check(Settings.cycleMistakeLimit(s3) == 3, "上限循环 0→3 失败")
        check(Settings.cycleMistakeLimit(s3) == 5, "上限循环 3→5 失败")
        check(Settings.cycleMistakeLimit(s3) == 0, "上限循环 5→0 失败")

        check(Settings.limitLabel(0) == "不限", "不限文案不对")
        check(Settings.limitLabel(5) == "5 次", "错误上限文案不对")

        -- 设置随成绩存档往返（v3）
        local rec = Records.sanitize({ v = 2, cleared = 3 })
        check(type(rec.settings) == "table", "旧档没有补上设置字段")
        check(rec.settings.sound == true, "旧档补的设置默认值不对")

        local rec2 = Records.sanitize({ settings = { sound = false, autoClean = false, candidateFont = 12, mistakeLimit = 3 } })
        check(rec2.settings.sound == false, "设置音效没有随存档读回")
        check(rec2.settings.candidateFont == 12, "设置字号没有随存档读回")
        check(rec2.settings.mistakeLimit == 3, "设置上限没有随存档读回")
    end

    -- 14) 错误上限：达到上限判负、失败后不可编辑、新局恢复
    do
        local b = Board.new("easy")
        local idx, sol
        for i = 1, 81 do
            if b.values[i] == 0 then
                idx = i
                sol = b.solution[i]
                break
            end
        end

        check(idx ~= nil, "没找到空格，错误上限校验无意义")
        if idx then
            -- 收集 3 个与正确答案不同的数字
            local wrongs = {}
            for d = 1, 9 do
                if d ~= sol and #wrongs < 3 then
                    wrongs[#wrongs + 1] = d
                end
            end

            b:setMistakeLimit(3)
            check(b.mistakeLimit == 3, "错误上限没有设置成功")
            b:select(idx)

            b:input(wrongs[1])
            check(b.mistakes == 1, "第一次填错没有计数")
            check(b:isFailed() == false, "第一次填错就判负")

            b:input(wrongs[2])
            b:input(wrongs[3])
            check(b.mistakes == 3, "错误次数累计不对")
            check(b:isFailed() == true, "错误达到上限没有判负")
            check(b:canEdit(idx) == false, "判负后仍然可以编辑")

            -- 判负后不再计时
            local frozen = b.elapsed
            b:tick(2)
            check(math.abs(b.elapsed - frozen) < 0.0001, "判负后仍在计时")

            -- 新局要清掉失败态与错误数
            b:reset("easy")
            check(b:isFailed() == false, "新局没有清除失败态")
            check(b.mistakes == 0, "新局没有清空错误数")

            -- 不限时永远不判负
            b:setMistakeLimit(0)
            b:select(idx)
            for _ = 1, 6 do
                b:input(wrongs[1])
                b:input(wrongs[2])
            end
            check(b:isFailed() == false, "不限错误上限时仍被判负")
        end
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
