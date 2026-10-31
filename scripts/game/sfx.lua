-- ============================================================================
-- 音效：短促反馈音（落子 / 填错 / 通关 / 失败）
--   · UI-only 工程没有场景，这里自建一个 Scene 挂 SoundSource
--   · 全部 pcall 包裹：没有音频设备或资源缺失时静默降级，绝不影响玩法
--   · 每个音效独立 SoundSource，避免通关音被落子音打断
-- ============================================================================

local Sfx = {}

Sfx.FILES = {
    place = "audio/place.wav",
    error = "audio/error.wav",
    win = "audio/win.wav",
    fail = "audio/fail.wav",
}

-- 各音效音量与最短触发间隔（秒），避免连点时糊成一片
local MIX = {
    place = { gain = 0.55, gap = 0.035 },
    error = { gain = 0.70, gap = 0.12 },
    win = { gain = 0.80, gap = 1.00 },
    fail = { gain = 0.80, gap = 1.00 },
}

local scene_ = nil
local sources_ = {}
local sounds_ = {}
local lastTime_ = {}
local ready_ = false
local tried_ = false
local enabled_ = true
local clock_ = 0

--- 初始化（可重复调用；失败只尝试一次）
function Sfx.init()
    if tried_ then
        return ready_
    end
    tried_ = true

    local ok = pcall(function()
        scene_ = Scene()
        local root = scene_:CreateChild("SfxRoot")

        for key, path in pairs(Sfx.FILES) do
            local sound = cache:GetResource("Sound", path)
            if sound == nil then
                error("missing sound: " .. path)
            end
            local node = root:CreateChild(key)
            local source = node:CreateComponent("SoundSource")
            source:SetSoundType(SOUND_EFFECT)
            source:SetGain(MIX[key] and MIX[key].gain or 0.7)
            sounds_[key] = sound
            sources_[key] = source
        end
    end)

    ready_ = ok
    if not ok then
        print("[Sfx] 音频不可用，已降级为静音")
    else
        local n = 0
        for _ in pairs(sources_) do
            n = n + 1
        end
        print("[Sfx] 音效已就绪：" .. tostring(n) .. " 个")
    end
    return ready_
end

--- 总开关（设置里控制）
function Sfx.setEnabled(on)
    enabled_ = on ~= false
end

function Sfx.isEnabled()
    return enabled_
end

--- 播放一个音效；不存在的 key 直接忽略
---@param key string "place" | "error" | "win" | "fail"
function Sfx.play(key)
    if not enabled_ then
        return false
    end
    if not ready_ and not Sfx.init() then
        return false
    end

    local source = sources_[key]
    local sound = sounds_[key]
    if not source or not sound then
        return false
    end

    local spec = MIX[key] or {}
    local gap = spec.gap or 0
    local now = clock_
    if gap > 0 and lastTime_[key] and (now - lastTime_[key]) < gap then
        return false
    end
    lastTime_[key] = now

    local ok = pcall(function()
        if key == "place" then
            -- 落子带一点随机音高，连填时不至于像机器
            local pitch = 0.965 + math.random() * 0.07
            source:Play(sound, sound:GetFrequency() * pitch, spec.gain or 0.6)
        else
            source:Play(sound, 0, spec.gain or 0.7)
        end
    end)
    if not ok then
        ready_ = false
        print("[Sfx] 播放失败，后续降级为静音")
    end
    return ok
end

--- 每帧推进内部时钟（节流用自累加的帧时间，不依赖 os.clock 精度）
function Sfx.tick(dt)
    clock_ = clock_ + (dt or 0)
end

return Sfx
