-- ============================================================================
-- 成绩记录：每档难度的最佳用时（用时更短即刷新，记录该局错误次数）
-- 纯数据逻辑，不碰 UI / 存储，便于自检
-- ============================================================================

local Records = {}

Records.VERSION = 1

--- 新建一份空记录
function Records.new()
    return { v = Records.VERSION, best = {} }
end

--- 把云端/存档里读回来的任意数据整理成合法结构，脏字段一律丢弃
function Records.sanitize(data)
    local out = Records.new()
    if type(data) ~= "table" or type(data.best) ~= "table" then
        return out
    end

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
    return out
end

--- 取某档的最佳成绩，没有则返回 nil
function Records.bestOf(records, difficulty)
    if type(records) ~= "table" or type(records.best) ~= "table" then
        return nil
    end
    return records.best[difficulty]
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

return Records
