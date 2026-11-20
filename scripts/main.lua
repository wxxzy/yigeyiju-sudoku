-- ============================================================================
-- 数独 · 入口脚本
-- 结构：
--   scripts/game/sudoku.lua   纯逻辑（生成 / 求解 / 唯一解校验）
--   scripts/game/board.lua    棋盘会话状态（选中 / 填数 / 笔记 / 撤销 / 计时 / 序列化）
--   scripts/game/records.lua  每档难度的最佳成绩
--   scripts/game/storage.lua  存档（云变量优先，内存兜底）
--   scripts/ui/*              表现层（主题 / 棋盘 / 键盘 / HUD）
-- 本地校验：
--   taptap-maker preview validate --entry main.lua --mode validate
-- ============================================================================

local UI = require("urhox-libs/UI")
local Board = require "game.board"
local Sudoku = require "game.sudoku"
local Records = require "game.records"
local Daily = require "game.daily"
local Settings = require "game.settings"
local Sfx = require "game.sfx"
local Storage = require "game.storage"
local Ad = require "game.ad"
local BoardView = require "ui.board_view"
local Keypad = require "ui.keypad"
local HUD = require "ui.hud"
local TitleView = require "ui.title_view"
local Theme = require "ui.theme"

local CONFIG = {
    Title = "一格一局",
    Difficulty = "normal",
    LayoutCheckInterval = 0.25, -- 秒：多久重测一次可用空间
    AutosaveInterval = 10, -- 秒：有改动后多久落一次存档
    StatsReserve = 42, -- 棋盘下方成绩条占用（22 高 + 10 间距 + 边框余量）
}

-- 长生命周期引用（Start/Stop 是全局函数，状态只能放模块级）
local board_ = nil
local boardView_ = nil
local keypad_ = nil
local hud_ = nil
local titleView_ = nil
local root_ = nil
local boardArea_ = nil
local resultShown_ = false
local pendingDaily_ = false -- 确认框点「开新局」时，是否要开每日一题
local scene_ = "title" -- 当前场景："title" 主菜单 / "game" 对局界面

-- 待开局难度（难度按钮改的是它，真正开局要按「新局」并确认）
local pendingDifficulty_ = CONFIG.Difficulty
local records_ = Records.new()
local settings_ = Settings.new()
local failShown_ = false

-- 自适应与存档
local layoutTimer_ = 0
local autosaveTimer_ = 0
local saveDirty_ = false
local layoutWarned_ = false

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = CONFIG.Title

    -- 三步走：Init → 建控件树 → SetRoot
    UI.Init {
        theme = "default-taptap",
        scale = UI.Scale.DEFAULT,
    }

    board_ = Board.new(CONFIG.Difficulty)
    pendingDifficulty_ = CONFIG.Difficulty
    records_ = Records.new()

    BuildUI()
    ApplySettings(false)

    -- 历史成绩（同步/异步都可能，读到即更新）
    Storage.loadStats(function(data)
        records_ = Records.sanitize(data)
        settings_ = records_.settings
        ApplySettings(false)
        local n = 0
        for _ in pairs(records_.best) do
            n = n + 1
        end
        RefreshDailyButton()
        RefreshTitleInfo()
        print("=== 已载入历史成绩：" .. n .. " 档，累计通关 "
            .. tostring(Records.clearedCount(records_)) .. " 局 ===")
    end)

    -- 再尝试续上次进度（本地/云端回调可能同步，因此放在建完 UI 之后）
    Storage.load(function(data)
        -- 玩家已经开始动了就不覆盖，避免异步回调把当前进度冲掉
        if saveDirty_ or board_.started then
            return
        end
        -- 每日一题只在当天有效：隔天的存档不续（避免玩家以为今天做过了）
        local dk = data and data.daily
        if type(dk) == "string" and #dk == 10 and dk ~= Daily.today() then
            print("=== 每日一题已过期（" .. dk .. "），本次开普通局 ===")
            return
        end
        if board_:restore(data) then
            ApplySettings(false)
            failShown_ = false
            pendingDifficulty_ = board_.difficulty
            hud_:setDifficulty(pendingDifficulty_)
            hud_:setPendingMismatch(false)
            resultShown_ = board_.solved
            RefreshAll()
            RefreshTitleInfo()
            print("=== 续上次进度：" .. board_.difficulty
                .. "，空格 " .. board_:emptyCount() .. "，用时 " .. board_:timeText() .. " ===")
        end
    end)

    hud_:setDifficulty(pendingDifficulty_)
    RefreshDailyButton()
    RefreshAll()
    FitBoard()
    ShowTitle() -- 开局先进主菜单，点难度 / 继续才进对局

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    print("=== " .. CONFIG.Title .. " 启动，难度 " .. board_.difficulty
        .. "，空格 " .. board_:emptyCount() .. " ===")
end

function Stop()
    if saveDirty_ and not board_.solved then
        Storage.save(board_:serialize())
    end
    UI.Shutdown()
end

-- ============================================================================
-- 界面组装
-- ============================================================================

function BuildUI()
    boardView_ = BoardView.new(function(idx)
        if hud_ and hud_:isModalOpen() then
            return
        end
        board_:select(idx)
        RefreshAll()
    end)

    keypad_ = Keypad.new {
        onDigit = InputDigit,
        onErase = function()
            if hud_:isModalOpen() then
                return
            end
            board_:erase()
            RefreshAll()
        end,
        onNotes = function()
            if hud_:isModalOpen() then
                return
            end
            board_:toggleNotesMode()
            RefreshAll()
        end,
        onHint = function()
            DoHint()
        end,
        onCandidates = function()
            if hud_:isModalOpen() then
                return
            end
            board_:toggleCandidatesMode()
            RefreshAll()
        end,
        onUndo = function()
            if hud_:isModalOpen() then
                return
            end
            board_:undo()
            RefreshAll()
        end,
    }

    hud_ = HUD.new {
        onNewGame = function()
            RequestNewGame()
        end,
        onCycleDifficulty = function()
            CycleDifficulty()
        end,
        onConfirmNewGame = function()
            if pendingDaily_ then
                pendingDaily_ = false
                local key = Daily.today()
                if key then
                    BeginDaily(key)
                    return
                end
            end
            StartNewGame(pendingDifficulty_)
        end,
        onDaily = function()
            StartDaily()
        end,
        onPause = function()
            TogglePause()
        end,
        onResume = function()
            TogglePause()
        end,
        onSettings = function()
            hud_:showSettings()
        end,
        onToggleSound = function()
            Settings.toggleSound(settings_)
            ApplySettings()
        end,
        onToggleAutoClean = function()
            Settings.toggleAutoClean(settings_)
            ApplySettings()
        end,
        onCycleFont = function()
            Settings.cycleCandidateFont(settings_)
            ApplySettings()
        end,
        onCycleLimit = function()
            Settings.cycleMistakeLimit(settings_)
            ApplySettings()
        end,
        onRetry = function()
            StartNewGame(pendingDifficulty_)
        end,
        onHome = function()
            GoHome()
        end,
    }

    titleView_ = TitleView.new {
        onStart = function(difficulty)
            StartNewGame(difficulty)
        end,
        onContinue = function()
            EnterGame()
        end,
        onDaily = function()
            StartDaily()
        end,
        onSettings = function()
            hud_:showSettings()
        end,
    }

    -- 棋盘容器：占满顶栏与键盘之间的剩余空间，实际边长由 FitBoard 按空间算出
    -- 棋盘与其下方的成绩条作为一个整体垂直居中，避免两者被拉开
    boardArea_ = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
        gap = 10,
        children = { boardView_.root, hud_.statsBar },
    }

    root_ = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.background,
        children = {
            -- 可交互内容放进安全区，避开刘海 / 圆角 / Tap 胶囊
            UI.SafeAreaView {
                width = "100%",
                height = "100%",
                children = {
                    UI.Panel {
                        width = "100%",
                        height = "100%",
                        flexDirection = "column",
                        padding = 12,
                        gap = 10,
                        children = {
                            hud_.root,
                            boardArea_,
                            keypad_.root,
                        },
                    },
                },
            },
            -- 主菜单全屏覆盖层：在设置弹层之下，从主菜单可直接打开设置
            titleView_.root,
            hud_.overlay,
            hud_.confirmOverlay,
            hud_.pauseOverlay,
            hud_.settingsOverlay,
            hud_.failOverlay,
            hud_.toastPanel,
        },
    }

    UI.SetRoot(root_)
end

--- 统一刷新入口：棋盘 + 键盘 + HUD 一次同步
function RefreshAll()
    boardView_:refresh(board_)
    keypad_:update(board_)
    hud_:update(board_)
    RefreshStatsBar()
    saveDirty_ = true
end

--- 棋盘下方成绩条：连续打卡 · 累计通关 · 当前难度最佳
function RefreshStatsBar()
    if not hud_ then
        return
    end

    local parts = {}
    local streak = records_.daily and tonumber(records_.daily.streak) or 0
    if streak and streak > 0 then
        parts[#parts + 1] = "连续 " .. tostring(streak) .. " 天"
    end
    parts[#parts + 1] = "累计 " .. tostring(Records.clearedCount(records_)) .. " 局"

    local best = records_.best[board_.difficulty]
    if best and tonumber(best.time) then
        -- 这里不能用后面才声明的局部函数 difficultyLabel（作用域取不到），就地查表
        local label = board_.difficulty
        for _, d in ipairs(Sudoku.DIFFICULTIES) do
            if d.key == board_.difficulty then
                label = d.label
                break
            end
        end
        parts[#parts + 1] = label .. "最佳 " .. HUD.fmtTime(best.time)
    end

    hud_:setStats(table.concat(parts, " · "))
end

--- 把设置应用到音效 / 棋盘 / 视图 / 弹层显示，并按需落盘
---@param persist boolean|nil 传 false 时只应用不写档
function ApplySettings(persist)
    settings_ = Settings.sanitize(settings_)

    Sfx.setEnabled(settings_.sound)
    if settings_.sound then
        Sfx.init()
    end

    if board_ then
        board_.autoCleanNotes = settings_.autoClean
        board_:setMistakeLimit(settings_.mistakeLimit)
    end
    if boardView_ then
        boardView_:setCandidateFont(settings_.candidateFont)
    end
    if hud_ then
        hud_:setSettingsView {
            sound = settings_.sound,
            autoClean = settings_.autoClean,
            fontText = tostring(settings_.candidateFont),
            limitText = Settings.limitLabel(settings_.mistakeLimit),
        }
    end

    if persist ~= false then
        records_.settings = settings_
        Storage.saveStats(records_)
    end
end

--- 统一的落子入口：填数 + 音效 + 反馈动画 + 刷新
---@param n integer 1..9
function InputDigit(n)
    if hud_ and hud_:isModalOpen() then
        return
    end
    local idx = board_.selected
    board_:input(n)

    local act = board_.lastAction
    if act == "wrong" then
        boardView_:flash(idx, "error")
        Sfx.play("error")
    elseif act == "place" then
        boardView_:flash(idx, "place")
        Sfx.play("place")
    end

    RefreshAll()
end

-- ============================================================================
-- 自适应：按可用空间决定棋盘边长（横屏 / 平板 / 大屏都不会挤到键盘）
-- ============================================================================

--- 长度值是否可用：排除 nan / inf（引擎里 nan 的数值比较不可靠）
local function isUsableLength(v)
    return Storage.isFiniteNumber(v) and v > 0
end

function FitBoard()
    if not boardArea_ then
        return
    end

    -- 自适应只是视觉优化，任何异常都不该影响玩法
    local ok = pcall(function()
        local w, h = boardArea_:GetComputedSize()
        -- 首帧 Yoga 还没算出尺寸时会返回 nan / inf；
        -- 本引擎里 nan 的数值比较不可靠（nan > 0 可能为真），必须用字符串挡
        if not isUsableLength(w) or not isUsableLength(h) then
            return
        end

        -- 棋盘容器里还有成绩条，算边长时要把它的高度预留出来，否则会顶到键盘
        local reserve = CONFIG.StatsReserve
        local availH = h - reserve
        if not isUsableLength(availH) then
            availH = h
        end

        -- 正方形：取可用宽高的较小值，再受主题上限约束
        local size = math.floor(math.min(w, availH, Theme.SIZE.boardMax))
        if not isUsableLength(size) or size < 80 then
            return -- 空间过小时保持默认布局，避免把棋盘压没
        end

        if boardView_:setSize(size) then
            -- 注意：引擎重写了 string.format，%d 遇到浮点会抛错，这里只用拼接
            print("=== 棋盘尺寸 " .. tostring(size)
                .. "（可用 " .. tostring(math.floor(w)) .. "x" .. tostring(math.floor(h)) .. "）===")
        end
    end)

    if not ok and not layoutWarned_ then
        layoutWarned_ = true
        print("[Layout] 棋盘自适应失败，回退默认布局")
    end
end

-- ============================================================================
-- 存档
-- ============================================================================

--- 立即落盘（有改动才有意义）
function SaveProgress(onDone)
    if board_.solved then
        saveDirty_ = false
        return
    end
    saveDirty_ = false
    autosaveTimer_ = 0

    Storage.save(board_:serialize(), function(ok, source)
        if ok then
            if onDone then
                onDone(true, source)
            end
        else
            saveDirty_ = true -- 失败就保持脏标记，下次继续尝试
            print("[Save] 存档写入失败，稍后重试")
            if onDone then
                onDone(false, source)
            end
        end
    end)
end

-- ============================================================================
-- 流程控制
-- ============================================================================

local function difficultyLabel(key)
    for _, d in ipairs(Sudoku.DIFFICULTIES) do
        if d.key == key then
            return d.label
        end
    end
    return "普通"
end

--- 当前盘面是否值得保护（已经开始且没通关 / 没判负）
local function HasProgress()
    return board_.started and not board_.solved and not board_.failed
end

--- 提示入口（键盘 H 与工具键共用）：先讲理由，再点一次落笔。
--- 次数按难度限额（sudoku.DIFFICULTIES 的 hintLimit），用完可看广告补充
function DoHint()
    if hud_ and hud_:isModalOpen() then
        return
    end

    if board_:hintsLeft() <= 0 then
        ShowHintAdOffer()
        return
    end

    -- 第一次点：标出可确定的格并说明理由；再点一次才填入
    if board_.hintIdx then
        local idx = board_.hintIdx
        board_:applyHint()
        boardView_:flash(idx, "hint")
        Sfx.play("place")
        RefreshAll()
        return
    end

    local step = board_:requestHint()
    if step then
        hud_:toast("提示：" .. step.reason .. "（再点一次「提示」直接填入）", 3.5)
    else
        hud_:toast("当前盘面没有能一步确定的格子，试试打开候选数或换个角度", 3.5)
    end
    RefreshAll()
end

--- 提示用尽时：提供「看广告 +1」入口；环境不支持广告则退回纯提示
function ShowHintAdOffer()
    if not Ad.isSupported() then
        hud_:toast("「" .. difficultyLabel(board_.difficulty) .. "」的提示已用完（"
            .. tostring(board_.hintLimit) .. " 次）", 3)
        return
    end

    hud_:showConfirm("观看一段视频广告，可获得 1 次提示。", {
        title = "提示用完了",
        confirmText = "看广告 +1",
        cancelText = "先不用",
        onConfirm = function()
            WatchAdForHint()
        end,
    })
end

--- 播放激励视频：完整观看才 +1 次提示（成功后直接给出这一步的指引）
function WatchAdForHint()
    local accepted = Ad.showRewarded(function(success, msg)
        if not success then
            -- "embed manual close"：iOS 嵌入式下未看完就手动关闭，不发奖
            if msg == "embed manual close" then
                hud_:toast("需完整观看广告才能获得提示", 3)
            else
                hud_:toast("广告未完成："
                    .. (type(msg) == "string" and msg ~= "" and msg or "稍后再试"), 3)
            end
            RefreshAll()
            return
        end

        board_:grantBonusHint()
        local step = board_:requestHint()
        if step then
            hud_:toast("提示 +1：" .. step.reason .. "（再点一次「提示」直接填入）", 4)
        else
            hud_:toast("提示 +1（当前盘面暂时没有能一步确定的格子）", 3)
        end
        saveDirty_ = true
        RefreshAll()
    end)

    if not accepted then
        hud_:toast("广告暂不可用，稍后再试", 2.5)
    end
end

--- 回到主菜单（暂停 / 结算 / 失败弹层共用）：先落盘，再清理弹层与暂停态
function GoHome()
    if HasProgress() then
        SaveProgress()
    end
    hud_:hideResult()
    hud_:hideConfirm()
    hud_:hideFail()
    if board_:isPaused() then
        board_:togglePause()
    end
    hud_:setPaused(false, board_:timeText())
    ShowTitle()
end

--- 显示主菜单
function ShowTitle()
    scene_ = "title"
    RefreshTitleInfo()
    titleView_:show()
end

--- 进入对局界面（幂等：已在对局中重复调用无副作用）
function EnterGame()
    scene_ = "game"
    titleView_:hide()
end

--- 主菜单信息：继续按钮 / 打卡状态 / 成绩概览
function RefreshTitleInfo()
    if not titleView_ then
        return
    end

    if HasProgress() then
        titleView_:setContinueInfo(true, "继续上局 · " .. difficultyLabel(board_.difficulty)
            .. " · 用时 " .. board_:timeText())
    else
        titleView_:setContinueInfo(false)
    end

    local key = Daily.today()
    local daily = records_.daily
    local streak = (type(daily) == "table" and tonumber(daily.streak)) or 0
    titleView_:setDailyInfo(streak, key ~= nil and Daily.doneToday(daily, key) or false)
    titleView_:setStats(Records.clearedCount(records_), streak, records_.best)
end

--- 难度按钮：只切换待开局难度，不碰当前盘
function CycleDifficulty()
    pendingDifficulty_ = NextDifficulty(pendingDifficulty_)
    hud_:setDifficulty(pendingDifficulty_)
    hud_:setPendingMismatch(pendingDifficulty_ ~= board_.difficulty)
end

--- 新局入口：有进度时先确认，避免手快点掉
function RequestNewGame()
    if HasProgress() then
        hud_:showConfirm("将以「" .. difficultyLabel(pendingDifficulty_)
            .. "」开始新局，当前这局（" .. board_:timeText() .. "）的进度会被放弃。")
        return
    end
    StartNewGame(pendingDifficulty_)
end

--- 每日一题入口：同一天固定同一题、同一难度
function StartDaily()
    local key = Daily.today()
    if not key then
        hud_:toast("当前环境拿不到日期，每日一题暂不可用", 3)
        return
    end

    -- 已经在做今天的每日题：不重开，直接回到那一局
    if board_.dailyKey == key and HasProgress() then
        EnterGame()
        return
    end

    if HasProgress() then
        pendingDaily_ = true
        hud_:showConfirm("将开始今天的每日一题，当前这局（" .. board_:timeText() .. "）的进度会被放弃。")
        return
    end

    BeginDaily(key)
end

---@param key string "YYYY-MM-DD"
function BeginDaily(key)
    local difficulty = Daily.difficultyFor(key)
    pendingDifficulty_ = difficulty
    board_:reset(difficulty, { daily = key })
    ApplySettings(false)
    failShown_ = false
    hud_:hideFail()

    resultShown_ = false
    saveDirty_ = true
    autosaveTimer_ = 0

    hud_:setPaused(false, board_:timeText())
    hud_:hideResult()
    hud_:hideConfirm()
    hud_:setDifficulty(pendingDifficulty_)
    hud_:setPendingMismatch(false)
    RefreshDailyButton()
    RefreshAll()
    EnterGame()

    if Daily.doneToday(records_.daily, key) then
        hud_:toast("今天的每日已打卡，这局不计入连续天数", 3.5)
    else
        hud_:toast("每日一题 · 今天难度「" .. difficultyLabel(difficulty) .. "」", 3)
    end
    print("=== 每日一题：" .. key .. "，难度 " .. difficulty
        .. "，空格 " .. board_:emptyCount() .. " ===")
end

--- 每日入口按钮：显示今天是否已打卡、连续天数
function RefreshDailyButton()
    local key = Daily.today()
    local daily = records_.daily
    local streak = (type(daily) == "table" and tonumber(daily.streak)) or 0
    hud_:setDaily(key, streak, Daily.doneToday(daily, key))
end

--- 暂停 / 继续
function TogglePause()
    if board_.solved then
        return
    end
    if not board_.started then
        hud_:toast("先点一格开始计时，再暂停", 2)
        return
    end
    local paused = board_:togglePause()
    hud_:setPaused(paused, board_:timeText())
end

---@param difficulty string
function StartNewGame(difficulty)
    pendingDaily_ = false
    pendingDifficulty_ = difficulty or pendingDifficulty_
    board_:reset(pendingDifficulty_)
    hud_:setPaused(false, board_:timeText())
    resultShown_ = false
    saveDirty_ = true
    autosaveTimer_ = 0
    hud_:hideResult()
    hud_:hideConfirm()
    hud_:setDifficulty(pendingDifficulty_)
    hud_:setPendingMismatch(false)
    RefreshAll()
    EnterGame()
    print("=== 新局：" .. pendingDifficulty_ .. "，空格 " .. board_:emptyCount() .. " ===")
end

--- 难度循环：简单 → 普通 → 困难 → 专家 → 简单
---@param current string
function NextDifficulty(current)
    local list = Sudoku.DIFFICULTIES
    for i, d in ipairs(list) do
        if d.key == current then
            return list[(i % #list) + 1].key
        end
    end
    return list[2].key
end

-- ============================================================================
-- 每帧与键盘
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 主菜单场景下不计时：棋盘被盖住，也没有任何输入
    if scene_ == "game" then
        board_:tick(dt)
    end
    boardView_:update(dt)
    Sfx.tick(dt)
    hud_:update(board_, dt)

    -- 布局自适应：窗口尺寸变了（转屏 / 拖动窗口）就重算棋盘边长
    layoutTimer_ = layoutTimer_ + dt
    if layoutTimer_ >= CONFIG.LayoutCheckInterval then
        layoutTimer_ = 0
        FitBoard()
    end

    -- 自动存档：有改动才计时，避免每帧写
    if saveDirty_ then
        autosaveTimer_ = autosaveTimer_ + dt
        if autosaveTimer_ >= CONFIG.AutosaveInterval then
            SaveProgress()
        end
    end

    -- 错误次数用尽：本局结束（设置里可关闭上限）
    if board_.failed and not failShown_ then
        failShown_ = true
        Sfx.play("fail")
        hud_:showFail(board_)
        saveDirty_ = false
        Storage.clearProgress() -- 失败局不再续，避免下次进来卡在死局
        print("=== 本局失败：错误 " .. board_.mistakes .. " 次，用时 " .. board_:timeText() .. " ===")
    end

    if board_.solved and not resultShown_ then
        resultShown_ = true
        boardView_:markSolved()

        local isRecord, prevBest = false, nil
        local extra = ""

        Records.markCleared(records_)

        if board_.dailyKey then
            -- 每日一题：计入连续打卡，不参与各档最佳（避免一次简单局刷掉记录）
            local streak, firstToday = Records.markDaily(records_, board_.dailyKey)
            extra = (firstToday and "每日一题完成 · 连续 " or "今日已打卡 · 连续 ")
                .. tostring(streak) .. " 天"
            RefreshDailyButton()
            RefreshStatsBar()
        else
            -- 普通局：用时更短才刷新，记录该局的错误次数
            isRecord, prevBest = Records.submit(records_, board_.difficulty, board_.elapsed, board_.mistakes)
            RefreshStatsBar()
        end

        Storage.saveStats(records_)

        extra = extra .. (extra ~= "" and " · " or "")
            .. "累计通关 " .. tostring(Records.clearedCount(records_)) .. " 局"

        Sfx.play("win")
        hud_:showResult(board_, { isRecord = isRecord, prevBest = prevBest, extra = extra })
        saveDirty_ = false
        Storage.clearProgress() -- 进度清掉，成绩保留
        print("=== 通关：" .. board_:timeText() .. "，错误 " .. board_.mistakes
            .. " 次" .. (isRecord and "，刷新记录" or "")
            .. (board_.dailyKey and "，每日 " .. board_.dailyKey or "") .. " ===")
    end
end

local DIGIT_KEYS = {
    [KEY_1] = 1,
    [KEY_2] = 2,
    [KEY_3] = 3,
    [KEY_4] = 4,
    [KEY_5] = 5,
    [KEY_6] = 6,
    [KEY_7] = 7,
    [KEY_8] = 8,
    [KEY_9] = 9,
}

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    -- 主菜单场景：键盘快捷键全部不响应，避免误触开局
    if scene_ == "title" then
        return
    end

    if hud_ and hud_:isModalOpen() then
        -- 暂停遮罩下仍然允许键盘继续，避免只能用鼠标/手指
        if board_ and board_:isPaused() and (key == KEY_P or key == KEY_SPACE) then
            TogglePause()
        end
        return
    end

    local digit = DIGIT_KEYS[key]
    if digit then
        InputDigit(digit)
        return
    end

    if key == KEY_BACKSPACE or key == KEY_DELETE then
        board_:erase()
    elseif key == KEY_LEFT then
        board_:moveSelection(0, -1)
    elseif key == KEY_RIGHT then
        board_:moveSelection(0, 1)
    elseif key == KEY_UP then
        board_:moveSelection(-1, 0)
    elseif key == KEY_DOWN then
        board_:moveSelection(1, 0)
    elseif key == KEY_N then
        board_:toggleNotesMode()
    elseif key == KEY_H then
        DoHint()
        return
    elseif key == KEY_U then
        board_:undo()
    elseif key == KEY_R then
        RequestNewGame()
        return
    elseif key == KEY_P then
        TogglePause()
        return
    elseif key == KEY_D then
        StartDaily()
        return
    else
        return
    end

    RefreshAll()
end
