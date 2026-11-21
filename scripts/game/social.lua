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

-- 平台好友榜的榜单 ID（在开发者中心「游戏服务 → 游戏排行」创建后填入；空 = 不启用）
Social.PLATFORM_LEADERBOARD_ID = ""

--- 是否有平台排行榜能力（好友榜依赖它；本地/未知环境返回 false）
function Social.hasPlatformLeaderboard()
    if not Social.PLATFORM_LEADERBOARD_ID or Social.PLATFORM_LEADERBOARD_ID == "" then
        return false
    end
    local ok, tap = pcall(function()
        return rawget(_G, "tap")
    end)
    if not ok or type(tap) ~= "table" then
        return false
    end
    local okMgr, mgr = pcall(function()
        return tap:getLeaderboardManager()
    end)
    return okMgr and mgr ~= nil
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

--- 打开平台排行榜面板（好友榜：collection = "friends"）
---@return boolean 是否成功调起
function Social.showPlatformLeaderboard(collection)
    if not Social.hasPlatformLeaderboard() then
        return false
    end
    local tap = rawget(_G, "tap")
    local ok, mgr = pcall(function()
        return tap:getLeaderboardManager()
    end)
    if not ok or type(mgr) ~= "table" then
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
