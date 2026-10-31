-- ============================================================================
-- 每日一题：按日期确定性选题 + 连续打卡
--   · 同一天不管重启几次都是同一题、同一难度
--   · 不写随机种子，靠字符串哈希，纯函数，便于自检
-- ============================================================================

local Daily = {}

Daily.VERSION = 1

local WEEKDAY_DIFFICULTY = {
    [1] = "easy", -- 周日
    [2] = "easy", -- 周一（工作日开头给个轻松局）
    [3] = "normal",
    [4] = "hard",
    [5] = "normal",
    [6] = "hard",
    [7] = "expert", -- 周六
}

local function pad2(n)
    n = math.floor(tonumber(n) or 0)
    if n < 10 then
        return "0" .. n
    end
    return tostring(n)
end

--- 今天的日期键 "YYYY-MM-DD"；引擎不给时间时返回 nil（调用方降级为普通局）
function Daily.today()
    local ok, v = pcall(function()
        return os.date("%Y-%m-%d")
    end)
    if ok and type(v) == "string" and #v == 10 then
        return v
    end
    return nil
end

--- "YYYY-MM-DD" → 当天 12 点的 time 值；格式非法返回 nil
function Daily.dayTime(key)
    if type(key) ~= "string" then
        return nil
    end
    local y, m, d = key:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then
        return nil
    end
    local ok, t = pcall(function()
        return os.time { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
    end)
    if not ok or type(t) ~= "number" then
        return nil
    end
    return t
end

--- 日期键对应的难度（按星期几轮换）
function Daily.difficultyFor(key)
    local t = Daily.dayTime(key)
    if not t then
        return "normal"
    end
    local ok, wday = pcall(function()
        return os.date("*t", t).wday
    end)
    if not ok or type(wday) ~= "number" then
        return "normal"
    end
    return WEEKDAY_DIFFICULTY[wday] or "normal"
end

--- 字符串 → 稳定整数（djb2 变体，去掉大数乘法避免浮点误差）
function Daily.hash(text)
    text = tostring(text or "")
    local h = 5381
    for i = 1, #text do
        h = (h * 33 + text:byte(i)) % 2147483647
    end
    return h
end

--- 日期 + 难度 → 题库下标（1..count）
function Daily.indexFor(key, count)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then
        return 1
    end
    return (Daily.hash(tostring(key)) % count) + 1
end

--- 是否是紧邻的上一天（用于连续打卡判断）
function Daily.isPreviousDay(prevKey, curKey)
    local a = Daily.dayTime(prevKey)
    local b = Daily.dayTime(curKey)
    if not a or not b then
        return false
    end
    return math.floor((b - a) / 86400 + 0.5) == 1
end

--- 新建一份空的每日状态
function Daily.newState()
    return { last = "", streak = 0, cleared = 0 }
end

--- 清洗存档里的每日状态
function Daily.sanitize(state)
    local out = Daily.newState()
    if type(state) ~= "table" then
        return out
    end
    if type(state.last) == "string" and #state.last == 10 then
        out.last = state.last
    end
    out.streak = math.max(0, math.floor(tonumber(state.streak) or 0))
    out.cleared = math.max(0, math.floor(tonumber(state.cleared) or 0))
    return out
end

--- 完成当天每日一题，更新连续天数
---@return integer streak 更新后的连续天数
---@return boolean firstToday 今天是否是第一次完成（重复完成不重复计数）
function Daily.markCleared(state, key)
    if type(state) ~= "table" then
        return 0, false
    end
    key = key or Daily.today()
    if not key then
        return math.max(0, math.floor(tonumber(state.streak) or 0)), false
    end

    state.cleared = math.max(0, math.floor(tonumber(state.cleared) or 0)) + 1
    if state.last == key then
        -- 一天内多次完成：只算一次连续
        return math.max(1, math.floor(tonumber(state.streak) or 0)), false
    end

    local streak = math.max(0, math.floor(tonumber(state.streak) or 0))
    if Daily.isPreviousDay(state.last, key) then
        streak = streak + 1
    else
        streak = 1
    end
    state.streak = streak
    state.last = key
    return streak, true
end

--- 今天是否已完成过每日一题
function Daily.doneToday(state, key)
    if type(state) ~= "table" then
        return false
    end
    key = key or Daily.today()
    return key ~= nil and state.last == key
end

--- 用来展示的日期短标签 "10/31"
function Daily.shortLabel(key)
    if type(key) ~= "string" then
        return ""
    end
    local m, d = key:match("^%d%d%d%d%-(%d%d)%-(%d%d)$")
    if not m then
        return key
    end
    return tostring(tonumber(m)) .. "/" .. tostring(tonumber(d))
end

return Daily
