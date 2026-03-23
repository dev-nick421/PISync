----------------------------------------------------------------------
-- PISync - Power Infusion Coordinator for WoW Midnight (12.0)
-- made for the best priest justin, my baby and the greatest windwalker of all time OMEGALUL
--
-- FLOW:
--   1. DPS macro:    /pi           → whispers "PI me!" to priest
--   2. Priest macro: /pi active    → whispers "PI activated" to DPS
--
-- PRIEST MACRO EXAMPLE:
--   #showtooltip Power Infusion
--   /cast [@mouseover,help,nodead][@target,help,nodead] Power Infusion
--   /pi active
----------------------------------------------------------------------

local PI_BUFF_DURATION = 15
local PI_COOLDOWN_TOTAL = 120
local PI_COOLDOWN_REMAINING = PI_COOLDOWN_TOTAL - PI_BUFF_DURATION  -- 105s

local WHISPER_REQUEST   = "PI me!"
local WHISPER_ACTIVATED = "PI activated"

----------------------------------------------------------------------
-- Addon-channel messaging (12.0 fix: works in combat / instances)
----------------------------------------------------------------------
local ADDON_PREFIX = "PISync"
local ADDON_MSG_REQUEST   = "REQ"
local ADDON_MSG_ACTIVATED = "ACT"

-- States
local STATE_IDLE      = "IDLE"
local STATE_REQUESTED = "REQUESTED"
local STATE_ACTIVE    = "ACTIVE"
local STATE_COOLDOWN  = "COOLDOWN"
local STATE_READY     = "READY"

----------------------------------------------------------------------
-- Addon Frame
----------------------------------------------------------------------
local PISync = CreateFrame("Frame", "PISyncFrame", UIParent)
PISync.state = STATE_IDLE
PISync.partner = nil
PISync.partnerDisplay = nil
PISync.buffEndTime = 0
PISync.cdEndTime = 0
PISync.blinkElapsed = 0
PISync.blinkVisible = true

local BAR_INNER_WIDTH = 212

----------------------------------------------------------------------
-- Saved Variables
----------------------------------------------------------------------
local defaults = {
    partner = nil,
    locked = false,
    point = "CENTER",
    relPoint = "CENTER",
    xOfs = 0,
    yOfs = 150,
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function FormatTime(seconds)
    if seconds <= 0 then return "0:00" end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%d:%02d", m, s)
end

local function ShortName(fullName)
    if not fullName then return nil end
    return Ambiguate(fullName, "short")
end

local function SetPartner(fullName)
    PISync.partner = fullName
    PISync.partnerDisplay = ShortName(fullName)
    PISyncDB.partner = fullName
end

local function DisplayName()
    return PISync.partnerDisplay or PISync.partner or "???"
end

----------------------------------------------------------------------
-- Cross-realm safe name for whispers (v3 fix)
-- UnitName("target") alone wouldnt include realm for xrealm players
----------------------------------------------------------------------
local function GetFullName(unit)
    local name, realm = UnitName(unit)
    if not name then return nil end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    local myRealm = GetNormalizedRealmName()
    return myRealm and (name .. "-" .. myRealm) or name
end

----------------------------------------------------------------------
-- message sending (v3 fix)
-- Primary:  C_ChatInfo.SendAddonMessage  (hidden, works in combat)
-- Fallback: C_ChatInfo.SendChatMessage   (visible whisper, may fail
--           in combat due to taint / encounter restrictions)
----------------------------------------------------------------------
local function SendPIMessage(addonMsg, whisperText)
    local partner = PISync.partner
    if not partner then return false end

    -- Primary: addon channel — try RAID/PARTY first (no xrealm name issues),
    -- fall back to WHISPER target for addon msg if not grouped
    local sent = false
    if IsInRaid() then
        sent = C_ChatInfo.SendAddonMessage(ADDON_PREFIX, addonMsg, "RAID")
    elseif IsInGroup() then
        sent = C_ChatInfo.SendAddonMessage(ADDON_PREFIX, addonMsg, "PARTY")
    else
        -- Outside group: addon whisper (needs full Name-Realm)
        sent = C_ChatInfo.SendAddonMessage(ADDON_PREFIX, addonMsg, "WHISPER", partner)
    end

    -- Fallback: visible whisper via the NEW 12.0 API (not the deprecated global)
    -- This is best-effort; may silently fail in combat/instances
    pcall(function()
        C_ChatInfo.SendChatMessage(whisperText, "WHISPER", nil, partner)
    end)

    return sent
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
local function CreateUI()
    local f = PISync

    f:SetSize(220, 60)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)

    f:SetScript("OnDragStart", function(self)
        if not PISyncDB.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, xOfs, yOfs = self:GetPoint()
        PISyncDB.point = point
        PISyncDB.relPoint = relPoint
        PISyncDB.xOfs = xOfs
        PISyncDB.yOfs = yOfs
    end)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.75)

    f.border = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.border:SetAllPoints()
    f.border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })

    f.glow = f:CreateTexture(nil, "OVERLAY")
    f.glow:SetPoint("TOPLEFT", -3, 3)
    f.glow:SetPoint("BOTTOMRIGHT", 3, -3)
    f.glow:SetColorTexture(1, 0.84, 0, 0.5)
    f.glow:SetBlendMode("ADD")
    f.glow:Hide()

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(40, 40)
    f.icon:SetPoint("LEFT", f, "LEFT", 8, 0)
    f.icon:SetTexture(135939)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.iconBorder = f:CreateTexture(nil, "OVERLAY")
    f.iconBorder:SetSize(44, 44)
    f.iconBorder:SetPoint("CENTER", f.icon, "CENTER")
    f.iconBorder:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    f.iconBorder:SetDrawLayer("ARTWORK", -1)

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.status:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -2)
    f.status:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    f.status:SetJustifyH("LEFT")
    f.status:SetText("PI Sync")
    f.status:SetTextColor(1, 1, 1)

    f.timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.timer:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 8, 2)
    f.timer:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    f.timer:SetJustifyH("LEFT")
    f.timer:SetText("")
    f.timer:SetTextColor(0.8, 0.8, 0.8)

    f.barBg = f:CreateTexture(nil, "ARTWORK")
    f.barBg:SetHeight(4)
    f.barBg:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 4)
    f.barBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    f.barBg:SetColorTexture(0.15, 0.15, 0.15, 1)

    f.bar = f:CreateTexture(nil, "OVERLAY")
    f.bar:SetHeight(4)
    f.bar:SetPoint("BOTTOMLEFT", f.barBg, "BOTTOMLEFT")
    f.bar:SetColorTexture(1, 0.84, 0, 1)
    f.bar:SetWidth(BAR_INNER_WIDTH)

    f.closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.closeBtn:SetSize(20, 20)
    f.closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    f.closeBtn:SetScript("OnClick", function()
        f:Hide()
        print("|cff00ccff[PISync]|r Hidden. /pi show to restore.")
    end)

    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            PISyncDB.locked = not PISyncDB.locked
            print("|cff00ccff[PISync]|r Frame " .. (PISyncDB.locked and "|cff00ff00locked|r." or "|cffff6600unlocked|r."))
        end
    end)

    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("PISync - Power Infusion Coordinator", 1, 0.84, 0)
        GameTooltip:AddLine(" ")
        if PISync.partnerDisplay then
            GameTooltip:AddLine("Partner: " .. PISync.partnerDisplay, 0.5, 1, 0.5)
        else
            GameTooltip:AddLine("No partner. /pi set", 1, 0.5, 0.5)
        end
        GameTooltip:AddLine("State: " .. PISync.state, 0.7, 0.7, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Left-drag", "Move", 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
        GameTooltip:AddDoubleLine("Right-click", "Lock/Unlock", 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

----------------------------------------------------------------------
-- STATE VISUALS
----------------------------------------------------------------------
local function SetState(newState)
    PISync.state = newState
    local f = PISync

    f.glow:Hide()
    f.blinkElapsed = 0
    f.blinkVisible = true

    if newState == STATE_IDLE then
        f.status:SetText("PI Sync")
        f.status:SetTextColor(0.6, 0.6, 0.6)
        f.timer:SetText(PISync.partnerDisplay and ("Partner: " .. PISync.partnerDisplay) or "/pi set")
        f.timer:SetTextColor(0.5, 0.5, 0.5)
        f.bar:SetWidth(0.01)
        f.bar:SetColorTexture(0.3, 0.3, 0.3, 1)
        f.icon:SetDesaturated(true)
        f.icon:SetAlpha(0.6)

    elseif newState == STATE_REQUESTED then
        f.status:SetText("PI Requested!")
        f.status:SetTextColor(1, 0.6, 0)
        f.timer:SetText("Waiting...")
        f.timer:SetTextColor(1, 0.8, 0.4)
        f.bar:SetWidth(0.01)
        f.bar:SetColorTexture(1, 0.6, 0, 1)
        f.icon:SetDesaturated(false)
        f.icon:SetAlpha(1)

    elseif newState == STATE_ACTIVE then
        f.status:SetText("PI ACTIVE")
        f.status:SetTextColor(0, 1, 0.4)
        f.icon:SetDesaturated(false)
        f.icon:SetAlpha(1)
        f.bar:SetColorTexture(0.2, 1, 0.4, 1)
        PlaySound(888)

    elseif newState == STATE_COOLDOWN then
        f.status:SetText("PI Cooldown")
        f.status:SetTextColor(1, 0.3, 0.3)
        f.icon:SetDesaturated(true)
        f.icon:SetAlpha(0.8)
        f.bar:SetColorTexture(0.8, 0.2, 0.2, 1)

    elseif newState == STATE_READY then
        f.status:SetText("PI READY!")
        f.status:SetTextColor(0, 1, 0.6)
        f.timer:SetText("Send /pi to request!")
        f.timer:SetTextColor(0.5, 1, 0.7)
        f.icon:SetDesaturated(false)
        f.icon:SetAlpha(1)
        f.bar:SetWidth(BAR_INNER_WIDTH)
        f.bar:SetColorTexture(0, 1, 0.5, 1)
        StartBlinking()
        PlaySound(8959)
    end
end

----------------------------------------------------------------------
-- start 15s active + 105s cooldown (both)
----------------------------------------------------------------------
local function StartActiveTimer()
    local now = GetTime()
    PISync.buffEndTime = now + PI_BUFF_DURATION
    PISync.cdEndTime = now + PI_BUFF_DURATION + PI_COOLDOWN_REMAINING
    SetState(STATE_ACTIVE)
end

----------------------------------------------------------------------
-- blinking in UI
----------------------------------------------------------------------
function StartBlinking()
    PISync.blinkElapsed = 0
    PISync.blinkVisible = true
    PISync.glow:Show()
end

local function UpdateBlink(elapsed)
    -- Don't blink in READY for priest -> only DPS should get the alert
    if PISync.state ~= STATE_REQUESTED and PISync.state ~= STATE_READY then
        PISync.glow:Hide()
        return
    end
    if PISync.state == STATE_READY and PISync.lastRole ~= "DPS" then
        PISync.glow:Hide()
        return
    end
    PISync.blinkElapsed = PISync.blinkElapsed + elapsed
    if PISync.blinkElapsed >= 0.5 then
        PISync.blinkElapsed = 0
        PISync.blinkVisible = not PISync.blinkVisible
        if PISync.blinkVisible then
            PISync.glow:Show()
            PISync.bg:SetColorTexture(0.15, 0.12, 0, 0.85)
        else
            PISync.glow:Hide()
            PISync.bg:SetColorTexture(0, 0, 0, 0.75)
        end
    end
end

----------------------------------------------------------------------
-- ON UPDATE
----------------------------------------------------------------------
local updateThrottle = 0
PISync:SetScript("OnUpdate", function(self, elapsed)
    UpdateBlink(elapsed)

    updateThrottle = updateThrottle + elapsed
    if updateThrottle < 0.05 then return end
    updateThrottle = 0

    local now = GetTime()

    if self.state == STATE_ACTIVE then
        local remaining = self.buffEndTime - now
        if remaining <= 0 then
            SetState(STATE_COOLDOWN)
        else
            self.timer:SetText(string.format("Active: %.1fs", remaining))
            self.bar:SetWidth(math.max(1, BAR_INNER_WIDTH * (remaining / PI_BUFF_DURATION)))
        end

    elseif self.state == STATE_COOLDOWN then
        local remaining = self.cdEndTime - now
        if remaining <= 0 then
            SetState(STATE_READY)
        else
            self.timer:SetText("Cooldown: " .. FormatTime(remaining))
            self.bar:SetWidth(math.max(1, BAR_INNER_WIDTH * (remaining / PI_COOLDOWN_REMAINING)))
        end
    end
end)

----------------------------------------------------------------------
-- EVENTS
----------------------------------------------------------------------
PISync:RegisterEvent("PLAYER_LOGIN")
PISync:RegisterEvent("CHAT_MSG_WHISPER")
PISync:RegisterEvent("CHAT_MSG_ADDON")

PISync:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if not PISyncDB then PISyncDB = {} end
        for k, v in pairs(defaults) do
            if PISyncDB[k] == nil then PISyncDB[k] = v end
        end

        CreateUI()
        self:ClearAllPoints()
        self:SetPoint(PISyncDB.point, UIParent, PISyncDB.relPoint, PISyncDB.xOfs, PISyncDB.yOfs)

        if PISyncDB.partner then
            PISync.partner = PISyncDB.partner
            PISync.partnerDisplay = ShortName(PISyncDB.partner)
        end

        SetState(STATE_IDLE)
        C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
        print("|cff00ccff[PISync]|r loaded! /pi help for commands.")

    elseif event == "CHAT_MSG_WHISPER" then
        local msg, sender = ...
        local senderShort = Ambiguate(sender, "short")
        local msgLower = msg and msg:lower() or ""

        -- "PI me!" incoming = DPS wants PI (we are priest, blink!)
        if msgLower == "pi me!" or msgLower == "pi me" then
            if not self.partner then
                SetPartner(sender)
                print("|cff00ccff[PISync]|r Auto-set partner: |cffffff00" .. senderShort .. "|r")
            end
            SetState(STATE_REQUESTED)
            StartBlinking()
            PlaySound(37881)
            print("|cff00ccff[PISync]|r |cffff8800" .. senderShort .. "|r wants PI!")

        -- "PI activated" incoming = priest cast PI (we are DPS, start timer!)
        elseif msgLower == "pi activated" then
            if not self.partner then
                SetPartner(sender)
                print("|cff00ccff[PISync]|r Auto-set partner: |cffffff00" .. senderShort .. "|r")
            end
            StartActiveTimer()
            print("|cff00ccff[PISync]|r PI active! 15s buff timer started.")
        end

    -------------------------------------------------------------------
    -- ADDON CHANNEL (v3 fix: more reliable in combat / instances)
    -------------------------------------------------------------------
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefix ~= ADDON_PREFIX then return end

        -- Ignore our own messages
        local me = UnitName("player")
        local myRealm = GetNormalizedRealmName()
        local myFull = myRealm and (me .. "-" .. myRealm) or me
        if sender == myFull or Ambiguate(sender, "short") == me then return end

        local senderShort = Ambiguate(sender, "short")

        if msg == ADDON_MSG_REQUEST then
            if not self.partner then
                SetPartner(sender)
                print("|cff00ccff[PISync]|r Auto-set partner: |cffffff00" .. senderShort .. "|r")
            end
            SetState(STATE_REQUESTED)
            StartBlinking()
            PlaySound(37881)
            print("|cff00ccff[PISync]|r |cffff8800" .. senderShort .. "|r wants PI! (addon ch)")

        elseif msg == ADDON_MSG_ACTIVATED then
            if not self.partner then
                SetPartner(sender)
                print("|cff00ccff[PISync]|r Auto-set partner: |cffffff00" .. senderShort .. "|r")
            end
            StartActiveTimer()
            print("|cff00ccff[PISync]|r PI active! 15s buff timer started. (addon ch)")
        end
    end
end)

----------------------------------------------------------------------
-- SLASH COMMANDS
----------------------------------------------------------------------
SLASH_PISYNC1 = "/pi"
SLASH_PISYNC2 = "/pisync"

SlashCmdList["PISYNC"] = function(input)
    local cmd, arg = input:match("^(%S+)%s*(.*)$")
    if not cmd then cmd = input end
    cmd = cmd:lower()

    if cmd == "set" then
        if not arg or arg == "" then
            if UnitExists("target") and UnitIsPlayer("target") then
                arg = GetFullName("target")
            else
                print("|cff00ccff[PISync]|r Target a player, or: /pi set Name-Realm")
                return
            end
        end
        SetPartner(arg)
        print("|cff00ccff[PISync]|r Partner: |cffffff00" .. DisplayName() .. "|r (" .. arg .. ")")
        if PISync.state == STATE_IDLE then
            PISync.timer:SetText("Partner: " .. DisplayName())
        end

    elseif cmd == "active" then
        -----------------------------------------------------------------
        -- PRIEST: put this in PI macro!
        -- Whispers "PI activated" to partner → starts your own timer
        --
        -- Example macro:
        --   #showtooltip Power Infusion
        --   /cast [@mouseover,help,nodead][@target] Power Infusion
        --   /pi active
        -----------------------------------------------------------------
        if not PISync.partner then
            print("|cff00ccff[PISync]|r No partner set! /pi set first.")
            return
        end
        SendPIMessage(ADDON_MSG_ACTIVATED, WHISPER_ACTIVATED)
        StartActiveTimer()
        print("|cff00ccff[PISync]|r PI activated! Notified " .. DisplayName() .. ", timer started.")

    elseif cmd == "show" then
        PISync:Show()
        print("|cff00ccff[PISync]|r Shown.")

    elseif cmd == "hide" then
        PISync:Hide()
        print("|cff00ccff[PISync]|r Hidden. /pi show to restore.")

    elseif cmd == "lock" then
        PISyncDB.locked = true
        print("|cff00ccff[PISync]|r |cff00ff00Locked.|r")

    elseif cmd == "unlock" then
        PISyncDB.locked = false
        print("|cff00ccff[PISync]|r |cffff6600Unlocked.|r")

    elseif cmd == "reset" then
        SetState(STATE_IDLE)
        print("|cff00ccff[PISync]|r Reset.")

    elseif cmd == "help" then
        print("|cff00ccff[PISync]|r ---- Commands ----")
        print("  |cffffff00/pi|r - Whisper 'PI me!' to partner (DPS macro)")
        print("  |cffffff00/pi active|r - Whisper 'PI activated' + start timer (Priest macro)")
        print("  |cffffff00/pi set|r - Set partner from target")
        print("  |cffffff00/pi set Name-Realm|r - Set partner manually")
        print("  |cffffff00/pi show / hide / lock / unlock / reset|r")
        print("|cff00ccff[PISync]|r ---- Macros ----")
        print("  DPS:    |cffffff00/pi|r")
        print("  Priest: |cffffff00#showtooltip Power Infusion|r")
        print("          |cffffff00/cast [@mouseover,help,nodead][@target] Power Infusion|r")
        print("          |cffffff00/pi active|r")

    elseif cmd == "" or cmd == "request" then
        if not PISync.partner then
            print("|cff00ccff[PISync]|r No partner! /pi set first.")
            return
        end
        SendPIMessage(ADDON_MSG_REQUEST, WHISPER_REQUEST)
        SetState(STATE_REQUESTED)
        PISync.timer:SetText("Waiting for " .. DisplayName() .. "...")
        PISync.timer:SetTextColor(1, 0.8, 0.4)
        print("|cff00ccff[PISync]|r Requested PI from |cffffff00" .. DisplayName() .. "|r!")

    else
        SetPartner(input:match("^%s*(.-)%s*$"))
        print("|cff00ccff[PISync]|r Partner: |cffffff00" .. DisplayName() .. "|r. /pi to request!")
        if PISync.state == STATE_IDLE then
            PISync.timer:SetText("Partner: " .. DisplayName())
        end
    end
end
