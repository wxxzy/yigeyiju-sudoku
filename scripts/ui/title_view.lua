-- ============================================================================
-- 主菜单：标题 / 继续上局 / 难度选择 / 每日一题 / 设置 / 成绩概览
--   · 全屏覆盖层，叠在游戏界面之上；进入对局时整体隐藏
--   · 设置弹层复用 HUD 的 settingsOverlay（层级在主菜单之上，可直接打开）
--   · 按钮只发回调，业务（二次确认 / 存档 / 计时）全部由 main 处理
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require "ui.theme"
local Sudoku = require "game.sudoku"
local HUD = require "ui.hud" -- 只借用 fmtTime

local TitleView = {}
TitleView.__index = TitleView

local C = Theme.COLORS
local F = Theme.FONT

---@param handlers table { onStart(difficulty), onContinue(), onDaily(), onSettings() }
function TitleView.new(handlers)
    local self = setmetatable({}, TitleView)

    -- 继续上局：有未完成的存档时才显示，文案由 main 动态设置
    self.continueButton = UI.Button {
        text = "继续上局",
        width = "100%",
        height = 46,
        fontSize = F.body,
        variant = "primary",
        backgroundColor = C.accent,
        hoverBackgroundColor = C.accentPressed,
        pressedBackgroundColor = C.accentPressed,
        textColor = C.surface,
        borderRadius = 10,
        visible = false,
        onClick = function()
            handlers.onContinue()
        end,
    }

    -- 四档难度 2x2：点了直接开局（有进度时 main 会走二次确认）
    local function difficultyButton(d)
        return UI.Button {
            text = d.label,
            flex = 1,
            height = 46,
            fontSize = F.body,
            backgroundColor = C.surface,
            hoverBackgroundColor = C.accentSoft,
            pressedBackgroundColor = C.accentSoft,
            textColor = C.textPrimary,
            borderRadius = 10,
            onClick = function()
                handlers.onStart(d.key)
            end,
        }
    end

    local diffs = Sudoku.DIFFICULTIES
    self.difficultyRows = {}
    for row = 1, 2 do
        self.difficultyRows[row] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 10,
            children = {
                difficultyButton(diffs[(row - 1) * 2 + 1]),
                difficultyButton(diffs[(row - 1) * 2 + 2]),
            },
        }
    end

    self.dailyButton = UI.Button {
        text = "每日一题",
        width = "100%",
        height = 44,
        fontSize = F.body,
        backgroundColor = C.surface,
        hoverBackgroundColor = C.accentSoft,
        pressedBackgroundColor = C.accentSoft,
        textColor = C.textPrimary,
        borderRadius = 10,
        onClick = function()
            handlers.onDaily()
        end,
    }

    self.settingsButton = UI.Button {
        text = "设置",
        width = "100%",
        height = 40,
        fontSize = F.small,
        backgroundColor = C.surfaceMuted,
        hoverBackgroundColor = C.accentSoft,
        pressedBackgroundColor = C.accentSoft,
        textColor = C.textSecondary,
        borderRadius = 10,
        onClick = function()
            handlers.onSettings()
        end,
    }

    self.leaderboardButton = UI.Button {
        text = "排行榜",
        width = "100%",
        height = 40,
        fontSize = F.small,
        backgroundColor = C.surfaceMuted,
        hoverBackgroundColor = C.accentSoft,
        pressedBackgroundColor = C.accentSoft,
        textColor = C.textSecondary,
        borderRadius = 10,
        onClick = function()
            handlers.onLeaderboard()
        end,
    }

    self.statsLabel = UI.Label {
        text = "",
        fontSize = F.tiny,
        fontColor = C.textMuted,
        textAlign = "center",
        whiteSpace = "normal",
        width = "100%",
    }

    self.saveInfoLabel = UI.Label {
        text = "",
        fontSize = F.tiny,
        fontColor = C.textMuted,
        textAlign = "center",
        width = "100%",
    }

    -- ---------------------------------------------------------------------
    -- 排行榜面板：难度 tab + Top10 列表 + 我的排名 + 好友榜入口（能力探测）
    -- ---------------------------------------------------------------------
    self.rankTitleLabel = UI.Label {
        text = "排行榜",
        fontSize = 26,
        fontColor = C.textPrimary,
    }

    self.rankTabs = {}
    local tabRow = UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 8,
        children = {},
    }
    for _, d in ipairs(Sudoku.DIFFICULTIES) do
        local btn = UI.Button {
            text = d.label,
            flex = 1,
            height = 34,
            fontSize = F.small,
            backgroundColor = C.surfaceMuted,
            hoverBackgroundColor = C.accentSoft,
            pressedBackgroundColor = C.accentSoft,
            textColor = C.textSecondary,
            borderRadius = 8,
            onClick = function()
                handlers.onRankTab(d.key)
            end,
        }
        self.rankTabs[d.key] = btn
        tabRow.children[#tabRow.children + 1] = btn
    end

    self.rankRows = {}
    local rowCells = {}
    for i = 1, 10 do
        local row = UI.Label {
            text = "",
            fontSize = F.small,
            fontColor = C.textSecondary,
            width = "100%",
        }
        self.rankRows[i] = row
        rowCells[#rowCells + 1] = row
    end

    self.rankListPanel = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexDirection = "column",
        gap = 6,
        children = rowCells,
    }

    self.rankMyLabel = UI.Label {
        text = "",
        fontSize = F.small,
        fontColor = C.accent,
        width = "100%",
    }

    self.friendsBoardButton = UI.Button {
        text = "好友榜",
        width = "100%",
        height = 40,
        fontSize = F.small,
        backgroundColor = C.surface,
        hoverBackgroundColor = C.accentSoft,
        pressedBackgroundColor = C.accentSoft,
        textColor = C.textPrimary,
        borderRadius = 10,
        visible = false, -- 有平台能力时才显示（main 决定）
        onClick = function()
            handlers.onFriendsBoard()
        end,
    }

    self.rankBackButton = UI.Button {
        text = "返回",
        width = "100%",
        height = 40,
        fontSize = F.small,
        backgroundColor = C.surfaceMuted,
        hoverBackgroundColor = C.accentSoft,
        pressedBackgroundColor = C.accentSoft,
        textColor = C.textSecondary,
        borderRadius = 10,
        onClick = function()
            handlers.onRankBack()
        end,
    }

    self.rankPanel = UI.Panel {
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        backgroundColor = C.background,
        padding = 16,
        gap = 10,
        visible = false,
        children = {
            self.rankTitleLabel,
            tabRow,
            self.rankListPanel,
            self.rankMyLabel,
            self.friendsBoardButton,
            self.rankBackButton,
        },
    }

    self.root = UI.Panel {
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        backgroundColor = C.background,
        alignItems = "center",
        justifyContent = "center",
        visible = false,
        children = {
            -- 主菜单页（home）与排行榜页（rank）互斥切换
            UI.Panel {
                position = "absolute",
                top = 0,
                left = 0,
                right = 0,
                bottom = 0,
                alignItems = "center",
                justifyContent = "center",
                children = {
                    UI.Panel {
                        width = 300,
                        flexDirection = "column",
                        alignItems = "center",
                        gap = 12,
                children = {
                    UI.Panel { height = 12 },
                    UI.Label {
                        text = "一格一局",
                        fontSize = 40,
                        fontColor = C.textPrimary,
                    },
                    UI.Label {
                        text = "每格只有一个答案",
                        fontSize = F.small,
                        fontColor = C.textMuted,
                    },
                    UI.Panel { height = 10 },
                    self.continueButton,
                    UI.Label {
                        text = "开始新局",
                        fontSize = F.tiny,
                        fontColor = C.textMuted,
                    },
                    self.difficultyRows[1],
                    self.difficultyRows[2],
                    self.dailyButton,
                    self.settingsButton,
                    self.leaderboardButton,
                    UI.Panel { height = 6 },
                    self.statsLabel,
                    self.saveInfoLabel,
                    UI.Label {
                        text = "无弹窗打扰 · 竖屏单手可玩",
                        fontSize = F.tiny,
                        fontColor = C.textMuted,
                    },
                },
            },
        },
        },
            self.rankPanel,
        },
    }

    -- root 的第一个子面板就是主菜单页（home），切页时隐藏/显示它
    self.homeScreen = self.root.children[1]

    return self
end

--- 继续按钮：can 为 false 时整颗隐藏（主菜单没有可续进度）
function TitleView:setContinueInfo(can, text)
    if can then
        self.continueButton:SetText(text or "继续上局")
        self.continueButton:SetVisible(true)
    else
        self.continueButton:SetVisible(false)
    end
end

--- 每日按钮文案：随打卡状态变化
function TitleView:setDailyInfo(streak, doneToday)
    local text = "每日一题"
    if doneToday then
        text = "每日一题 · 今日已打卡"
    elseif (tonumber(streak) or 0) > 0 then
        text = "每日一题 · 连续 " .. tostring(streak) .. " 天"
    end
    self.dailyButton:SetText(text)
end

--- 成绩概览：累计通关 / 连续打卡 / 各档最佳
---@param cleared integer 累计通关局数
---@param streak integer 连续打卡天数
---@param best table records.best（difficulty → {time, mistakes}）
function TitleView:setStats(cleared, streak, best)
    cleared = math.floor(tonumber(cleared) or 0)
    streak = math.floor(tonumber(streak) or 0)

    local lines = {}
    if streak > 0 then
        lines[#lines + 1] = "连续打卡 " .. streak .. " 天"
    end
    lines[#lines + 1] = "累计通关 " .. cleared .. " 局"

    local cells = {}
    for _, d in ipairs(Sudoku.DIFFICULTIES) do
        local entry = type(best) == "table" and best[d.key] or nil
        local t = "--"
        if entry and tonumber(entry.time) then
            t = HUD.fmtTime(entry.time)
        end
        cells[#cells + 1] = d.label .. " " .. t
    end
    lines[#lines + 1] = cells[1] .. " · " .. cells[2]
    lines[#lines + 1] = cells[3] .. " · " .. cells[4]

    self.statsLabel:SetText(table.concat(lines, "\n"))
end

--- 存档模式说明：云同步状态对玩家可见
---@param text string 空字符串时隐藏
function TitleView:setSaveInfo(text)
    local t = text or ""
    self.saveInfoLabel:SetText(t)
    self.saveInfoLabel:SetVisible(t ~= "")
end

--- 打开排行榜面板（切到排行页）
function TitleView:showRankPanel()
    self.root:SetVisible(true)
    self.homeScreen:SetVisible(false)
    self.rankPanel:SetVisible(true)
end

--- 回到主菜单页
function TitleView:showHomePanel()
    self.rankPanel:SetVisible(false)
    self.homeScreen:SetVisible(true)
end

--- 难度 tab 高亮
function TitleView:setRankTab(difficulty)
    for key, btn in pairs(self.rankTabs) do
        local active = (key == difficulty)
        btn:SetStyle {
            backgroundColor = active and C.accentSoft or C.surfaceMuted,
            textColor = active and C.accent or C.textSecondary,
        }
    end
end

--- 填充榜单行（rows: {rank, name, seconds}；nil/空时清空）
function TitleView:setRankRows(rows)
    for i = 1, 10 do
        local label = self.rankRows[i]
        local r = rows and rows[i]
        if r and r.seconds then
            local name = (r.name and r.name ~= "") and r.name
                or ("玩家" .. string.sub(r.userId or "", -6))
            local text = "#" .. tostring(r.rank) .. "  " .. name .. "  "
                .. HUD.fmtTime(r.seconds)
            label:SetText(text)
            label:SetVisible(true)
        else
            label:SetText("")
            label:SetVisible(false)
        end
    end
end

--- 榜单占位/提示行（加载中 / 暂无数据）
function TitleView:setRankPlaceholder(text)
    if text and text ~= "" then
        self.rankRows[1]:SetText(text)
        self.rankRows[1]:SetVisible(true)
        for i = 2, 10 do
            self.rankRows[i]:SetText("")
            self.rankRows[i]:SetVisible(false)
        end
    end
end

--- 我的排名行（text 空 = 隐藏）
function TitleView:setMyRank(text)
    local t = text or ""
    self.rankMyLabel:SetText(t)
    self.rankMyLabel:SetVisible(t ~= "")
end

--- 好友榜入口：仅平台能力可用时显示（main 决定）
function TitleView:setFriendsBoardVisible(visible)
    self.friendsBoardButton:SetVisible(visible == true)
end

function TitleView:show()
    self.root:SetVisible(true)
end

function TitleView:hide()
    self.root:SetVisible(false)
end

return TitleView
