-- ============================================================================
-- 存档层（两路 key：当前进度 / 历史成绩）
--   · 主链路：clientCloud 云变量（按账号隔离，跨设备）
--   · 兜底：进程内内存快照（云端不可用时不丢当前会话；跨启动不保留）
--   · 为什么不用本地文件：本引擎沙箱禁止 FileSystem:GetAppPreferencesDir
--     （会抛 "not allowed" 并被校验判为错误），项目目录在正式包里也未必可写
-- ============================================================================

local Storage = {}

Storage.SCHEMA = 1
Storage.CLOUD_KEY = "sudoku_save_v1" -- 当前进度
Storage.STATS_KEY = "sudoku_stats_v1" -- 历史最佳成绩（清进度时不动它）

local memory_ = {}
local lastSource_ = "none"
local warned_ = false

--- 最近一次读/写命中的后端："cloud" | "memory" | "none"
function Storage.lastSource()
    return lastSource_
end

--- 云端是否可用：本地预览里 clientCloud 存在但 userId 是占位值
local function cloud()
    local c = rawget(_G, "clientCloud")
    if c == nil then
        return nil
    end
    local ok, uid = pcall(function()
        return c.userId
    end)
    if ok and uid ~= nil and uid ~= "" and uid ~= 0 then
        return c
    end
    return nil
end

--- 只接受数字，且排除 nan / inf（本引擎 nan 的比较行为不可靠，用字符串判定）
local function isFiniteNumber(v)
    if type(v) ~= "number" then
        return false
    end
    local s = tostring(v)
    return not (s:find("nan") or s:find("inf"))
end

Storage.isFiniteNumber = isFiniteNumber

-- ---------------------------------------------------------------------------
-- 通用读写
-- ---------------------------------------------------------------------------

local function write(key, data, onDone)
    if type(data) ~= "table" then
        if onDone then
            onDone(false, "none")
        end
        return false
    end

    memory_[key] = data -- 无论如何先放内存，保证同一进程内可回滚

    local c = cloud()
    if c then
        local dispatched = pcall(function()
            c:Set(key, data, {
                ok = function()
                    lastSource_ = "cloud"
                    if onDone then
                        onDone(true, "cloud")
                    end
                end,
                error = function(_, reason)
                    lastSource_ = "memory"
                    print("[Storage] 云写入失败，退回内存：" .. tostring(reason))
                    if onDone then
                        onDone(false, "memory")
                    end
                end,
            })
        end)
        if dispatched then
            return true
        end
    elseif not warned_ then
        warned_ = true
        print("[Storage] 云端不可用，本次仅保存在内存中")
    end

    lastSource_ = "memory"
    if onDone then
        onDone(false, "memory")
    end
    return false
end

local function read(key, onLoaded)
    if type(onLoaded) ~= "function" then
        return
    end

    local c = cloud()
    if c then
        local dispatched = pcall(function()
            c:Get(key, {
                ok = function(values)
                    local data = type(values) == "table" and values[key] or nil
                    if type(data) == "table" then
                        lastSource_ = "cloud"
                        memory_[key] = data
                        onLoaded(data, "cloud")
                    elseif memory_[key] then
                        lastSource_ = "memory"
                        onLoaded(memory_[key], "memory")
                    end
                end,
                error = function(_, reason)
                    print("[Storage] 云读取失败：" .. tostring(reason))
                    if memory_[key] then
                        lastSource_ = "memory"
                        onLoaded(memory_[key], "memory")
                    end
                end,
                timeout = function()
                    if memory_[key] then
                        lastSource_ = "memory"
                        onLoaded(memory_[key], "memory")
                    end
                end,
            })
        end)
        if dispatched then
            return
        end
    end

    if memory_[key] then
        lastSource_ = "memory"
        onLoaded(memory_[key], "memory")
    end
end

-- ---------------------------------------------------------------------------
-- 对外接口
-- ---------------------------------------------------------------------------

--- 保存当前进度
function Storage.save(data, onDone)
    return write(Storage.CLOUD_KEY, data, onDone)
end

--- 读取当前进度
function Storage.load(onLoaded)
    return read(Storage.CLOUD_KEY, onLoaded)
end

--- 保存历史成绩
function Storage.saveStats(stats, onDone)
    return write(Storage.STATS_KEY, stats, onDone)
end

--- 读取历史成绩
function Storage.loadStats(onLoaded)
    return read(Storage.STATS_KEY, onLoaded)
end

--- 清空进度（通关后调用，避免下次进来直接是已完成的盘）；成绩记录保留
function Storage.clearProgress()
    memory_[Storage.CLOUD_KEY] = nil
    local c = cloud()
    if c then
        pcall(function()
            c:BatchSet():Delete(Storage.CLOUD_KEY):Save("clear sudoku save", {})
        end)
    end
end

--- 兼容旧名字
Storage.clear = Storage.clearProgress

return Storage
