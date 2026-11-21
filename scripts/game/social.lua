-- ============================================================================
-- 排行与好友能力封装
--   · 全服榜：clientCloud iscores（Lua 原生，确定可用）；用时越小排名越靠前
--   · 好友榜：平台 tap.getLeaderboardManager（JS 容器能力，UrhoX/Lua 侧未确认
--     暴露）→ 运行时探测，可用才启用入口，不可用则整体隐藏，绝不报错
-- ============================================================================

local Storage = require "game.storage"

local Social = {}

-- 各难度的全服榜 iscore key（存通关用时秒数，升序）
Social.RANK_KEYS = {
    easy = "sudoku_best_easy",
    normal = "sudoku_best_normal",
    hard = "sudoku_best_hard",
    expert = "sudoku_best_expert",
}

-- 平台好友榜的榜单 ID（空 = 不启用）
Social.PLATFORM_LEADERBOARD_ID = ""
-- 平台每日一题榜 ID（开发者中心「游戏排行」创建；榜单需配置为升序 + 按日重置 + 保留历史最好成绩）
Social.DAILY_LEADERBOARD_ID = ""

-- 每日榜罚分系数：有效成绩 = 用时 + 错误×30s + 提示×60s（可调）
Social.PENALTY_MISTAKE = 30
Social.PENALTY_HINT = 60

-- REP 游戏跳转：真机 sdk 打开链接的候选方法名（容器未文档化，运行时探测）
Social.JUMP_METHODS = { "OpenUrl", "openUrl", "OpenWithUrl", "OpenLink", "openLink",
    "RepOpen", "openRep", "OpenTapTap", "openTapTap" }
Social.lastJumpMethod_ = nil

--- 每日榜综合成绩（秒，越小越好）
function Social.dailyScore(seconds, mistakes, hints)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local m = math.max(0, math.floor(tonumber(mistakes) or 0))
    local h = math.max(0, math.floor(tonumber(hints) or 0))
    return seconds + m * Social.PENALTY_MISTAKE + h * Social.PENALTY_HINT
end

--- 平台排行榜能力探测（好友榜与每日榜共用；tap 全局由真机容器注入）
local function tapManager()
    local ok, tap = pcall(function()
        return rawget(_G, "tap")
    end)
    if not ok or type(tap) ~= "table" then
        return nil
    end
    local okMgr, mgr = pcall(function()
        return tap:getLeaderboardManager()
    end)
    if okMgr and mgr ~= nil then
        return mgr
    end
    -- 兼容点调用封装
    local okDot, mgrDot = pcall(function()
        return tap.getLeaderboardManager(tap)
    end)
    if okDot and mgrDot ~= nil then
        return mgrDot
    end
    return nil
end

--- 是否有平台好友榜能力
function Social.hasPlatformLeaderboard()
    if not Social.PLATFORM_LEADERBOARD_ID or Social.PLATFORM_LEADERBOARD_ID == "" then
        return false
    end
    return tapManager() ~= nil
end

--- 是否有平台每日一题榜能力
function Social.hasDailyBoard()
    if not Social.DAILY_LEADERBOARD_ID or Social.DAILY_LEADERBOARD_ID == "" then
        return false
    end
    return tapManager() ~= nil
end

--- 打开 REP 监测链接（跳转 TapTap）。
--- 容器未文档化「打开链接」API，逐个探测 sdk 的候选方法；都没有则返回 false
---@param url string 完整 https 链接
---@return boolean ok 是否成功调起
---@return string via 命中的方法名或失败原因
function Social.openJumpUrl(url)
    local okSdk, sdk = pcall(function()
        return rawget(_G, "sdk")
    end)
    if not okSdk or type(sdk) ~= "table" then
        return false, "nosdk"
    end
    if type(url) ~= "string" or url == "" then
        return false, "nourl"
    end
    for _, name in ipairs(Social.JUMP_METHODS) do
        local fn = sdk[name]
        if type(fn) == "function" then
            local okCall = pcall(function()
                fn(sdk, url)
            end)
            if okCall then
                Social.lastJumpMethod_ = name
                print("[Rep] 跳转已受理，via sdk." .. name)
                return true, name
            end
        end
    end
    return false, "nomethod"
end

local function cloud()
    return rawget(_G, "clientCloud")
end

--- 提交成绩到全服榜（iscores 覆盖写；调用方只在破纪录时提交，天然保持最优）
---@param difficulty string
---@param seconds number 通关用时
---@return boolean 是否已提交
function Social.submitBest(difficulty, seconds)
    local key = Social.RANK_KEYS[difficulty]
    local c = cloud()
    if not key or type(c) ~= "table" or not Storage.isFiniteNumber(seconds) then
        return false
    end
    local ok = pcall(function()
        c:SetInt(key, math.max(0, math.floor(seconds)))
    end)
    return ok == true
end

--- 昵称批量查询的防御性解析：回调形态未在文档细化，兼容 map / list 两种
local function applyNicknames(rows, ids, result)
    local byId = nil
    if type(result) == "table" then
        if result.userIds ~= nil or result.nicknames ~= nil then
            byId = result.nicknames or result
        elseif #result > 0 then
            -- 列表形态：[{userId, name/nickname}, ...]
            byId = {}
            for _, it in ipairs(result) do
                if type(it) == "table" and it.userId ~= nil then
                    byId[tostring(it.userId)] = it.name or it.nickname
                end
            end
        else
            byId = result -- 直接当 map
        end
    end
    for _, row in ipairs(rows) do
        local name = nil
        if type(byId) == "table" then
            name = byId[row.userId] or byId[tonumber(row.userId)]
        end
        if type(name) == "string" and name ~= "" then
            row.name = name
        end
    end
end

--- 拉取全服榜 Top N（升序 = 用时最短优先），附带昵称
---@param difficulty string
---@param count integer 默认 10
---@param onDone function(rows, status) rows 为 nil 表示不可用/失败
function Social.loadTop(difficulty, count, onDone)
    local key = Social.RANK_KEYS[difficulty]
    local c = cloud()
    if not key or type(c) ~= "table" or type(onDone) ~= "function" then
        onDone(nil, "unavailable")
        return
    end

    local dispatched = pcall(function()
        c:GetRankList(key, 0, count or 10, true, {
            ok = function(rankList)
                local rows = {}
                local ids = {}
                for i, item in ipairs(rankList or {}) do
                    local t = item.iscore and item.iscore[key]
                    local uid = tostring(item.userId or "")
                    rows[#rows + 1] = { rank = i, userId = uid, seconds = tonumber(t), name = nil }
                    ids[#ids + 1] = uid
                end

                -- 昵称查询失败不影响榜单主体
                local okNick = pcall(function()
                    GetUserNickname({
                        userIds = ids,
                        onSuccess = function(result)
                            applyNicknames(rows, ids, result)
                            onDone(rows, "ok")
                        end,
                        onError = function()
                            onDone(rows, "ok")
                        end,
                    })
                end)
                if not okNick then
                    onDone(rows, "ok")
                end
            end,
            error = function(_, reason)
                onDone(nil, tostring(reason))
            end,
            timeout = function()
                onDone(nil, "timeout")
            end,
        })
    end)
    if not dispatched then
        onDone(nil, "unavailable")
    end
end

--- 我的排名（全服榜）
function Social.loadMyRank(difficulty, onDone)
    local key = Social.RANK_KEYS[difficulty]
    local c = cloud()
    if not key or type(c) ~= "table" or type(onDone) ~= "function" then
        onDone(nil)
        return
    end
    local myId = nil
    pcall(function() myId = c.userId end)
    if myId == nil or myId == "" or myId == 0 then
        onDone(nil)
        return
    end
    local dispatched = pcall(function()
        c:GetUserRank(myId, key, {
            ok = function(rank, scoreValue)
                onDone({ rank = tonumber(rank), seconds = tonumber(scoreValue) })
            end,
            error = function() onDone(nil) end,
            timeout = function() onDone(nil) end,
        })
    end)
    if not dispatched then
        onDone(nil)
    end
end

--- 提交每日一题成绩到平台榜（综合成绩秒数，越小越好）
---@return boolean accepted 是否被受理
function Social.submitDailyScore(seconds, mistakes, hints)
    local mgr = tapManager()
    if not mgr or not Social.hasDailyBoard() then
        return false
    end
    local score = Social.dailyScore(seconds, mistakes, hints)
    local ok = pcall(function()
        mgr:submitScores({
            scores = {
                { leaderboardId = Social.DAILY_LEADERBOARD_ID, score = score },
            },
            callback = {
                onSuccess = function() end,
                onFailure = function() end,
            },
        })
    end)
    return ok == true
end

--- 调起平台每日一题榜官方 UI 面板
---@return boolean 是否成功调起
function Social.showDailyBoard()
    local mgr = tapManager()
    if not mgr or not Social.hasDailyBoard() then
        return false
    end
    local ok = pcall(function()
        mgr:openLeaderboard({
            leaderboardId = Social.DAILY_LEADERBOARD_ID,
            callback = {
                onSuccess = function() end,
                onFailure = function() end,
            },
        })
    end)
    return ok == true
end

--- 打开平台排行榜面板（好友榜：collection = "friends"）
---@return boolean 是否成功调起
function Social.showPlatformLeaderboard(collection)
    local mgr = tapManager()
    if not mgr or not Social.hasPlatformLeaderboard() then
        return false
    end
    return pcall(function()
        mgr:openLeaderboard({
            leaderboardId = Social.PLATFORM_LEADERBOARD_ID,
            collection = collection or "friends",
            callback = {
                onSuccess = function() end,
                onFailure = function() end,
            },
        })
    end) == true
end

return Social
