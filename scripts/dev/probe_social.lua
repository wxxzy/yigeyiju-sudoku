-- 临时探测：容器是否向 Lua 暴露平台排行榜（tap 全局）与好友能力
-- 用法: preview validate --entry dev/probe_social.lua --mode validate
local ok, tapObj = pcall(function()
    return rawget(_G, "tap")
end)
print("[Probe] _G.tap exists:", tostring(ok), type(tapObj))

if type(tapObj) == "table" then
    print("[Probe] tap.getLeaderboardManager:", type(tapObj.getLeaderboardManager))
    local okMgr, mgr = pcall(function()
        return tapObj:getLeaderboardManager()
    end)
    print("[Probe] leaderboardManager:", tostring(okMgr), type(mgr))
    if type(mgr) == "table" then
        for _, name in ipairs({ "submitScores", "openLeaderboard", "loadLeaderboardScores", "loadCurrentPlayerLeaderboardScore" }) do
            print("[Probe] mgr." .. name .. ":", type(mgr[name]))
        end
    end
end

-- 顺带探测其他可能的社会能力入口
for _, name in ipairs({ "sdk", "clientCloud", "lobby", "tapSdk", "social" }) do
    local v = rawget(_G, name)
    print("[Probe] _G." .. name .. ":", type(v))
end

print("[Probe] done")
