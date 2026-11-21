-- 探测：真机容器注入的社会/跳转/广告能力清单
-- 用法：构建测试版 → 真机扫码进入 → 读 runtime.log 里的 [Probe] 行
local okSdk, sdk = pcall(function()
    return rawget(_G, "sdk")
end)
print("[Probe] sdk exists:", tostring(okSdk), type(sdk))
if type(sdk) == "table" then
    for name, fn in pairs(sdk) do
        print("[Probe] sdk." .. tostring(name) .. ":", type(fn))
    end
end

local okTap, tap = pcall(function()
    return rawget(_G, "tap")
end)
print("[Probe] tap exists:", tostring(okTap), type(tap))
if type(tap) == "table" then
    for name, fn in pairs(tap) do
        print("[Probe] tap." .. tostring(name) .. ":", type(fn))
    end
end

-- REP 跳转候选方法逐一探测（用于确认「打开链接」能力是否存在）
local JUMP_CANDIDATES = { "OpenUrl", "openUrl", "OpenWithUrl", "OpenLink", "openLink",
    "RepOpen", "openRep", "OpenTapTap", "openTapTap", "JumpToTapTap" }
if type(sdk) == "table" then
    for _, name in ipairs(JUMP_CANDIDATES) do
        print("[Probe] sdk jump candidate " .. name .. ":", type(sdk[name]))
    end
end

print("[Probe] done")
