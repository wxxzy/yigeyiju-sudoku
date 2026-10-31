-- ============================================================================
-- 设置：音效、自动清笔记、候选字号、错误上限
-- 纯数据 + 循环切换逻辑，不碰 UI，便于自检
-- ============================================================================

local Settings = {}

Settings.VERSION = 1

Settings.FONT_STEPS = { 10, 11, 12 }
Settings.LIMIT_STEPS = { 0, 3, 5 } -- 0 表示不限

Settings.DEFAULTS = {
    sound = true,
    autoClean = true,
    candidateFont = 11,
    mistakeLimit = 0,
}

--- 新建一份默认设置
function Settings.new()
    local out = {}
    for k, v in pairs(Settings.DEFAULTS) do
        out[k] = v
    end
    out.v = Settings.VERSION
    return out
end

local function cycle(list, cur)
    for i, v in ipairs(list) do
        if v == cur then
            return list[(i % #list) + 1]
        end
    end
    return list[1]
end

--- 清洗存档里的设置：非法值一律回落到默认
function Settings.sanitize(data)
    local out = Settings.new()
    if type(data) ~= "table" then
        return out
    end

    if type(data.sound) == "boolean" then
        out.sound = data.sound
    end
    if type(data.autoClean) == "boolean" then
        out.autoClean = data.autoClean
    end

    local font = tonumber(data.candidateFont)
    for _, v in ipairs(Settings.FONT_STEPS) do
        if font == v then
            out.candidateFont = v
        end
    end

    local limit = tonumber(data.mistakeLimit)
    for _, v in ipairs(Settings.LIMIT_STEPS) do
        if limit == v then
            out.mistakeLimit = v
        end
    end

    return out
end

function Settings.toggleSound(s)
    s.sound = not s.sound
    return s.sound
end

function Settings.toggleAutoClean(s)
    s.autoClean = not s.autoClean
    return s.autoClean
end

--- 候选字号循环：10 → 11 → 12 → 10
function Settings.cycleCandidateFont(s)
    s.candidateFont = cycle(Settings.FONT_STEPS, tonumber(s.candidateFont) or 11)
    return s.candidateFont
end

--- 错误上限循环：不限 → 3 次 → 5 次 → 不限
function Settings.cycleMistakeLimit(s)
    s.mistakeLimit = cycle(Settings.LIMIT_STEPS, tonumber(s.mistakeLimit) or 0)
    return s.mistakeLimit
end

--- 展示用文案
function Settings.limitLabel(limit)
    limit = tonumber(limit) or 0
    if limit <= 0 then
        return "不限"
    end
    return tostring(limit) .. " 次"
end

return Settings
