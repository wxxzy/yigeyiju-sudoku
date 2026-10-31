-- ============================================================================
-- 成绩与统计：每档最佳用时 + 累计通关数 + 每日一题连续打卡
-- 纯数据逻辑，不碰 UI / 存储，便于自检
-- ============================================================================

local Daily = require "game.daily"
local Settings = require "game.settings"

local Records = {}

Records.VERSION = 3

--- 新建一份空记录
function Records.new()
    return {
        v = Records.VERSION,
        best = {},
        cleared = 0,
        daily = Daily.newState(),
        settings = Settings.new(),
    }
end

--- 把云端/存档里读回来的任意数据整理成合法结构，脏字段一律丢弃
--- 兼容 v1（只有 best）
function Records.sanitize(data)
    local out = Records.new()
    if type(data) ~= "table" then
        return out
    end

    if type(data.best) == "table" then
        for key, entry in pairs(data.best) do
            if type(key) == "string" and type(entry) == "table" then
                local t = tonumber(entry.time)
                if t and t > 0 then
                    out.best[key] = {
                        time = math.floor(t),
                        mistakes = math.max(0, math.floor(tonumber(entry.mistakes) or 0)),
                    }
                end
            end
        end
    end

    out.cleared = math.max(0, math.floor(tonumber(data.cleared) or 0))
    out.daily = Daily.sanitize(data.daily)
    out.settings = Settings.sanitize(data.settings)
    return out
end

--- 取某档的最佳成绩，没有则返回 nil
function Records.bestOf(records, difficulty)
    if type(records) ~= "table" or type(records.best) ~= "table" then
        return nil
    end
    return records.best[difficulty]
end

--- 已通关总次数（不含每日一题）
function Records.clearedCount(records)
    if type(records) ~= "table" then
        return 0
    end
    return math.max(0, math.floor(tonumber(records.cleared) or 0))
end

--- 提交一局成绩
---@return boolean isRecord 是否刷新记录
---@return table|nil prevBest 刷新前的旧记录
function Records.submit(records, difficulty, seconds, mistakes)
    if type(records) ~= "table" then
        return false, nil
    end
    records.best = records.best or {}
    records.v = Records.VERSION

    local prev = records.best[difficulty]
    local secs = math.floor(tonumber(seconds) or 0)
    if secs <= 0 then
        return false, prev
    end

    -- 首次通关也算记录；之后只在用时更短时刷新
    if prev == nil or secs < prev.time then
        records.best[difficulty] = {
            time = secs,
            mistakes = math.max(0, math.floor(tonumber(mistakes) or 0)),
        }
        return true, prev
    end
    return false, prev
end

--- 普通局通关：累计数 +1
function Records.markCleared(records)
    if type(records) ~= "table" then
        return 0
    end
    records.cleared = Records.clearedCount(records) + 1
    return records.cleared
end

--- 每日一题通关：更新连续打卡
---@return integer streak
---@return boolean firstToday
function Records.markDaily(records, key)
    if type(records) ~= "table" then
        return 0, false
    end
    records.daily = Daily.sanitize(records.daily)
    return Daily.markCleared(records.daily, key)
end

return Records
