-- ============================================================================
-- 激励视频广告封装（engine-docs/recipes/sdk.md 契约）
--   sdk:ShowRewardVideoAd(callback) -> boolean
--   · 返回 true 仅代表请求被受理，最终结果以回调 result.success 为准
--   · 返回 false 时失败回调可能同步触发、也可能不触发
--   → 因此必须同时处理返回值与回调，并用一次性完成状态防止重复发奖
-- ============================================================================

local Ad = {}

local watching_ = false -- 已有广告请求进行中（引擎侧还有 3 秒防抖/冷却，这里先挡一层）

--- 当前环境是否具备广告能力（sdk 全局与激励视频接口是否存在）
function Ad.isSupported()
    local ok, sdk = pcall(function()
        return rawget(_G, "sdk")
    end)
    if not ok or type(sdk) ~= "table" then
        return false
    end
    return type(sdk.ShowRewardVideoAd) == "function"
end

--- 请求播放激励视频
---@param onDone function|nil function(success, msg)
---@return boolean accepted 是否受理（false = 未受理，回调可能已同步触发或不触发）
function Ad.showRewarded(onDone)
    if watching_ then
        return false
    end
    if not Ad.isSupported() then
        return false
    end

    watching_ = true
    local finished = false
    local function finish(success, msg)
        if finished then
            return -- 回调与返回值兜底只生效一次
        end
        finished = true
        watching_ = false
        if onDone then
            pcall(onDone, success, msg)
        end
    end

    local sdk = rawget(_G, "sdk")
    local accepted = false
    local okCall = pcall(function()
        accepted = sdk:ShowRewardVideoAd(function(result)
            -- msg: "embed success" / "embed manual close" / "unsupported platform" / 错误描述
            local success = result and result.success == true
            finish(success, result and tostring(result.msg or "") or "")
        end)
    end)

    if not okCall then
        finish(false, "广告接口调用失败")
        return false
    end
    if not accepted and not finished then
        -- 受理失败且回调没有同步触发：自己兜底结束，避免 UI 卡死
        finish(false, "广告暂不可用")
        return false
    end
    return accepted
end

return Ad
