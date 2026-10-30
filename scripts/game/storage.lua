-- ============================================================================
-- 存档层
--   · 主链路：clientCloud 云变量（按账号隔离，跨设备）
--   · 兜底：进程内内存快照（云端不可用时不丢当前会话；跨启动不保留）
--   · 为什么不用本地文件：本引擎沙箱禁止 FileSystem:GetAppPreferencesDir
--     （会抛 "not allowed" 并被校验判为错误），项目目录在正式包里也未必可写
-- ============================================================================

local Storage = {}

Storage.SCHEMA = 1
Storage.CLOUD_KEY = "sudoku_save_v1"

local memory_ = nil
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
-- 对外接口
-- ---------------------------------------------------------------------------

--- 保存。data 为纯数据 table，onDone(ok, source) 可选
function Storage.save(data, onDone)
    if type(data) ~= "table" then
        if onDone then
            onDone(false, "none")
        end
        return false
    end

    memory_ = data -- 无论如何先放内存，保证同一进程内可回滚

    local c = cloud()
    if c then
        local dispatched = pcall(function()
            c:Set(Storage.CLOUD_KEY, data, {
                ok = function()
                    lastSource_ = "cloud"
                    if onDone then
                        onDone(true, "cloud")
                    end
                end,
                error = function(_, reason)
                    lastSource_ = "memory"
                    print("[Storage] 云存档失败，退回内存：" .. tostring(reason))
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

--- 读取。onLoaded(data, source) 仅在拿到合法存档时回调
function Storage.load(onLoaded)
    if type(onLoaded) ~= "function" then
        return
    end

    local c = cloud()
    if c then
        local dispatched = pcall(function()
            c:Get(Storage.CLOUD_KEY, {
                ok = function(values)
                    local data = type(values) == "table" and values[Storage.CLOUD_KEY] or nil
                    if type(data) == "table" then
                        lastSource_ = "cloud"
                        memory_ = data
                        onLoaded(data, "cloud")
                    elseif memory_ then
                        lastSource_ = "memory"
                        onLoaded(memory_, "memory")
                    end
                end,
                error = function(_, reason)
                    print("[Storage] 云存档读取失败：" .. tostring(reason))
                    if memory_ then
                        lastSource_ = "memory"
                        onLoaded(memory_, "memory")
                    end
                end,
                timeout = function()
                    if memory_ then
                        lastSource_ = "memory"
                        onLoaded(memory_, "memory")
                    end
                end,
            })
        end)
        if dispatched then
            return
        end
    end

    if memory_ then
        lastSource_ = "memory"
        onLoaded(memory_, "memory")
    end
end

--- 清空存档（通关后调用，避免下次进来直接是已完成的盘）
function Storage.clear()
    memory_ = nil
    local c = cloud()
    if c then
        pcall(function()
            c:BatchSet():Delete(Storage.CLOUD_KEY):Save("clear sudoku save", {})
        end)
    end
end

return Storage
