-- ============================================================================
-- 视觉常量：配色、字号、尺寸
-- 想换皮只改这里，逻辑层与控件层都不写死颜色
-- ============================================================================

local Theme = {}

-- 数值型配色用 RGBA 数组，Label/Panel 的字体色与背景色都接受这种格式
Theme.COLORS = {
    -- 底色
    background = { 241, 245, 249, 255 },
    surface = { 255, 255, 255, 255 },
    surfaceMuted = { 246, 248, 251, 255 },

    -- 文字
    textPrimary = { 30, 41, 59, 255 },
    textSecondary = { 100, 116, 139, 255 },
    textMuted = { 148, 163, 184, 255 },

    -- 主色
    accent = { 37, 99, 235, 255 },
    accentPressed = { 29, 78, 216, 255 },
    accentSoft = { 219, 234, 254, 255 },

    -- 棋盘格状态
    cellSelected = { 191, 219, 254, 255 },
    cellPeer = { 238, 244, 252, 255 },
    cellSameDigit = { 219, 234, 254, 255 },
    cellError = { 254, 226, 226, 255 },

    -- 格线：细线画格，粗线画 3x3 宫界
    gridThin = { 203, 213, 225, 255 },
    gridBold = { 100, 116, 139, 255 },

    -- 数字
    digitGiven = { 30, 41, 59, 255 },
    digitUser = { 37, 99, 235, 255 },
    digitError = { 220, 38, 38, 255 },
    digitNote = { 100, 116, 139, 255 },

    -- 浮层
    overlay = { 15, 23, 42, 150 },
}

Theme.FONT = {
    cell = 26,
    note = 10,
    keypad = 22,
    title = 20,
    body = 14,
    small = 12,
    tiny = 10,
}

Theme.SIZE = {
    boardMax = 560, -- 棋盘最大边长（基准像素）；手机上会被 100% 宽度限制住
    gridLineThin = 1,
    gridLineBold = 2,
    keypadHeight = 52,
    toolHeight = 42,
    hudHeight = 44,
    radius = 10,
}

return Theme
