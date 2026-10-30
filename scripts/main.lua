-- ============================================================================
-- 数独 · 入口脚本
-- 结构：
--   scripts/game/sudoku.lua   纯逻辑（生成 / 求解 / 唯一解校验）
--   scripts/game/board.lua    棋盘会话状态（选中 / 填数 / 笔记 / 撤销 / 计时 / 序列化）
--   scripts/game/storage.lua  存档（云变量优先，本地文件兜底）
--   scripts/ui/*              表现层（主题 / 棋盘 / 键盘 / HUD）
-- 本地校验：
--   taptap-maker preview validate --entry main.lua --mode validate
-- ============================================================================

local UI = require("urhox-libs/UI")
local Board = require "game.board"
local Sudoku = require "game.sudoku"
local Storage = require "game.storage"
local BoardView = require "ui.board_view"
local Keypad = require "ui.keypad"
local HUD = require "ui.hud"
local Theme = require "ui.theme"

local CONFIG = {
    Title = "数独",
    Difficulty = "normal",
    LayoutCheckInterval = 0.25, -- 秒：多久重测一次可用空间
    AutosaveInterval = 10, -- 秒：有改动后多久落一次存档
}

-- 长生命周期引用（Start/Stop 是全局函数，状态只能放模块级）
local board_ = nil
local boardView_ = nil
local keypad_ = nil
local hud_ = nil
local root_ = nil
local boardArea_ = nil
local resultShown_ = false

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

    BuildUI()

    -- 先尝试续上次进度，再首次刷新（本地存档会同步回调，云端异步）
    Storage.load(function(data)
        -- 玩家已经开始动了就不覆盖，避免异步回调把当前进度冲掉
        if saveDirty_ or board_.started then
            return
        end
        if board_:restore(data) then
            resultShown_ = board_.solved
            RefreshAll()
            print(string.format("=== 续上次进度：%s，空格 %d，用时 %s ===",
                board_.difficulty, board_:emptyCount(), board_:timeText()))
        end
    end)

    RefreshAll()
    FitBoard()

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    print(string.format("=== %s 启动，难度 %s，空格 %d ===", CONFIG.Title, board_.difficulty, board_:emptyCount()))
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
        board_:select(idx)
        RefreshAll()
    end)

    keypad_ = Keypad.new {
        onDigit = function(n)
            board_:input(n)
            RefreshAll()
        end,
        onErase = function()
            board_:erase()
            RefreshAll()
        end,
        onNotes = function()
            board_:toggleNotesMode()
            RefreshAll()
        end,
        onHint = function()
            board_:hint()
            RefreshAll()
        end,
        onUndo = function()
            board_:undo()
            RefreshAll()
        end,
    }

    hud_ = HUD.new {
        onNewGame = function()
            NewGame(board_.difficulty)
        end,
        onCycleDifficulty = function()
            NewGame(NextDifficulty(board_.difficulty))
        end,
    }

    -- 棋盘容器：占满顶栏与键盘之间的剩余空间，实际边长由 FitBoard 按空间算出
    boardArea_ = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        alignItems = "center",
        justifyContent = "center",
        children = { boardView_.root },
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
            hud_.overlay,
        },
    }

    UI.SetRoot(root_)
end

--- 统一刷新入口：棋盘 + 键盘 + HUD 一次同步
function RefreshAll()
    boardView_:refresh(board_)
    keypad_:update(board_)
    hud_:update(board_)
    saveDirty_ = true
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

        -- 正方形：取可用宽高的较小值，再受主题上限约束
        local size = math.floor(math.min(w, h, Theme.SIZE.boardMax))
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

---@param difficulty string
function NewGame(difficulty)
    board_:reset(difficulty)
    resultShown_ = false
    saveDirty_ = true
    autosaveTimer_ = 0
    hud_:hideResult()
    RefreshAll()
    print(string.format("=== 新局：%s，空格 %d ===", difficulty, board_:emptyCount()))
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

    board_:tick(dt)
    hud_:update(board_)

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

    if board_.solved and not resultShown_ then
        resultShown_ = true
        boardView_:markSolved()
        hud_:showResult(board_)
        saveDirty_ = false
        Storage.clear() -- 通关后清档，下次进来直接开新局
        print(string.format("=== 通关：%s，错误 %d 次 ===", board_:timeText(), board_.mistakes))
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

    local digit = DIGIT_KEYS[key]
    if digit then
        board_:input(digit)
        RefreshAll()
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
        board_:hint()
    elseif key == KEY_U then
        board_:undo()
    elseif key == KEY_R then
        NewGame(board_.difficulty)
        return
    else
        return
    end

    RefreshAll()
end
