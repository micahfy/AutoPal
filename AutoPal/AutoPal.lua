if not UnitClass then
    return
end

local _, playerClass = UnitClass("player")
if playerClass ~= "PALADIN" then
    return
end

AutoPal = AutoPal or {}
AutoPalSaved = AutoPalSaved or {}

local AP = AutoPal

AP.Version = "1.03"
AP.UI = {}
AP.Monitor = nil
AP.MinimapButton = nil

BINDING_HEADER_AUTOPAL_HEADER = "AutoPal"
BINDING_NAME_AUTOPAL_ONEKEY = "圣骑一键治疗"

local SPELL = {
    Flash = "圣光闪现",
    Holy = "圣光术",
    HolyShock = "神圣震击",
    HolyStrike = "神圣打击",
    CrusaderStrike = "十字军打击",
    SealWisdom = "智慧圣印",
    Judgement = "审判",
    JudgementWisdom = "智慧审判",
    LayHands = "圣疗术"
}

AP.FlashCost = { 35, 50, 70, 90, 115, 140, 180 }
AP.FlashBase = { 72, 109, 162, 219, 295, 365, 460 }
AP.HolyCost = { 35, 60, 110, 190, 275, 365, 465, 580, 660 }
AP.HolyBase = { 46, 89, 184, 350, 538, 758, 1018, 1342, 1680 }
AP.FlashFactor = 0.7
AP.HolyFactor = 1.4
AP.FlashEffect = {}
AP.HolyEffect = {}
AP.SpellIDCache = {}
AP.HealDelay = {}
AP.LastHealTarget = nil
AP.LastHealCastTime = 0
AP.InCombat = false
AP.FlashMaxRank = 0
AP.HolyMaxRank = 0

AP.Defaults = {
    Enabled = 1,
    UseMelee = 1,
    UseHolyStrike = 1,
    UseCrusaderStrike = 1,
    UseHolyShock = 1,
    UseHolyLight = 1,
    UseFlash = 1,
    UseLayHands = 1,
    UseSealWisdom = 1,
    UseJudgeWisdom = 1,
    Monitor = 1,
    Minimap = 1,
    MinimapPos = 225,
    FocusFirst = 1,
    TargetFirst = 1,
    TargetTarget = 1,
    ScanGroup = 1,
    OverflowFocus = 0,
    HolyStrikeHealOnly = 1,
    BeginValue = 99,
    HolyLightValue = 80,
    FlashValue = 95,
    HolyShockValue = 40,
    LayHandsValue = 15,
    HolyLightMaxRank = 9,
    FlashMaxRank = 7,
    IdleSpell = 1 -- 1=圣光闪现1级, 2=圣光术2级
}

local APTooltip = CreateFrame("GameTooltip", "AutoPalTooltip", UIParent, "GameTooltipTemplate")

local function APPrint(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00AutoPal|r: " .. msg)
    end
end

local function APApplyDefaults()
    if not AutoPalSaved then
        AutoPalSaved = {}
    end
    for k, v in pairs(AP.Defaults) do
        if AutoPalSaved[k] == nil then
            AutoPalSaved[k] = v
        end
    end
end

local function APGetHealingPower()
    if type(GetSpellBonusHealing) == "function" then
        local bonus = GetSpellBonusHealing()
        if bonus then
            return bonus
        end
    end
    return 0
end

local function APTableLen(t)
    if not t then
        return 0
    end
    if table and table.getn then
        return table.getn(t)
    end
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

local function APFindSpellID(name, rank)
    if not name or not GetSpellName then
        return nil
    end
    local i = 1
    local spellName, spellRank = GetSpellName(i, "spell")
    while spellName do
        if spellName == name then
            if not rank or spellRank == rank then
                return i
            end
        end
        i = i + 1
        spellName, spellRank = GetSpellName(i, "spell")
    end
    return nil
end

local function APCacheSpellID(name)
    local id = APFindSpellID(name)
    if id then
        AP.SpellIDCache[name] = id
    end
    return id
end

local function APGetHighestRank(name)
    if not name or not GetSpellName then
        return 0
    end
    local highest = 0
    local i = 1
    local spellName, spellRank = GetSpellName(i, "spell")
    while spellName do
        if spellName == name then
            local rank = tonumber(string.match(spellRank or "", "(%d+)")) or 0
            if rank > highest then
                highest = rank
            end
        end
        i = i + 1
        spellName, spellRank = GetSpellName(i, "spell")
    end
    return highest
end

local function APUpdateSpellData()
    AP.SpellIDCache = {}
    AP.FlashMaxRank = APGetHighestRank(SPELL.Flash)
    AP.HolyMaxRank = APGetHighestRank(SPELL.Holy)
    APCacheSpellID(SPELL.Flash)
    APCacheSpellID(SPELL.Holy)
    APCacheSpellID(SPELL.HolyShock)
    APCacheSpellID(SPELL.HolyStrike)
    APCacheSpellID(SPELL.CrusaderStrike)
    APCacheSpellID(SPELL.SealWisdom)
    APCacheSpellID(SPELL.Judgement)
    APCacheSpellID(SPELL.LayHands)

    local healPower = APGetHealingPower()
    for i = 1, APTableLen(AP.FlashBase) do
        AP.FlashEffect[i] = AP.FlashBase[i] + healPower * AP.FlashFactor
    end
    for i = 1, APTableLen(AP.HolyBase) do
        AP.HolyEffect[i] = AP.HolyBase[i] + healPower * AP.HolyFactor
    end
end

local function APGetSpellCooldownRemaining(name)
    local id = AP.SpellIDCache[name] or APCacheSpellID(name)
    if not id or not GetSpellCooldown then
        return 999
    end
    local start, duration = GetSpellCooldown(id, "spell")
    if not start or start == 0 then
        return 0
    end
    local remaining = duration - (GetTime() - start)
    if remaining < 0 then
        remaining = 0
    end
    return remaining
end

local function APSpellReady(name, offset)
    offset = offset or 0
    return APGetSpellCooldownRemaining(name) <= offset
end

local function APIsCasting()
    if CastingBarFrame and CastingBarFrame.IsShown and CastingBarFrame:IsShown() then
        return true
    end
    if SpellIsTargeting and SpellIsTargeting() then
        return true
    end
    return false
end

local function APTryStopOverheal()
    if AutoPalSaved.OverflowFocus == 1 then
        return
    end
    if not AP.LastHealTarget then
        return
    end
    if not UnitExists or not UnitExists(AP.LastHealTarget) then
        return
    end
    local maxHealth = UnitHealthMax(AP.LastHealTarget)
    if not maxHealth or maxHealth == 0 then
        return
    end
    local percent = UnitHealth(AP.LastHealTarget) / maxHealth * 100
    if percent >= AutoPalSaved.BeginValue and SpellStopCasting then
        SpellStopCasting()
    end
end

local function APIsFriendly(unit)
    if not unit or not UnitExists or not UnitExists(unit) then
        return false
    end
    if UnitCanAssist then
        return UnitCanAssist("player", unit)
    end
    if UnitCanAttack then
        return not UnitCanAttack("player", unit)
    end
    return false
end

local function APFindAura(unit, name, isDebuff)
    if not unit or not name then
        return false
    end
    local i = 1
    while true do
        local tex = isDebuff and UnitDebuff(unit, i) or UnitBuff(unit, i)
        if not tex then
            break
        end
        APTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        if isDebuff then
            APTooltip:SetUnitDebuff(unit, i)
        else
            APTooltip:SetUnitBuff(unit, i)
        end
        local text = _G["AutoPalTooltipTextLeft1"] and _G["AutoPalTooltipTextLeft1"]:GetText()
        if text == name then
            return true
        end
        i = i + 1
    end
    return false
end

local function APHasBuff(unit, name)
    return APFindAura(unit, name, false)
end

local function APHasDebuff(unit, name)
    return APFindAura(unit, name, true)
end

local function APUnitDistance(unit)
    if type(UnitXP) == "function" then
        local ok, dist = pcall(UnitXP, "distanceBetween", "player", unit)
        if ok and dist then
            return dist
        end
    end
    return nil
end

local function APIsInRange(unit, maxRange, spellName)
    if not unit or not UnitExists or not UnitExists(unit) then
        return false
    end
    local dist = APUnitDistance(unit)
    if dist and dist > 0 then
        return dist <= maxRange
    end
    if spellName and IsSpellInRange then
        local inRange = IsSpellInRange(spellName, unit)
        if inRange == 1 then
            return true
        elseif inRange == 0 then
            return false
        end
    end
    if CheckInteractDistance then
        if maxRange <= 10 then
            return CheckInteractDistance(unit, 3) == 1
        elseif maxRange <= 28 then
            return CheckInteractDistance(unit, 4) == 1
        end
    end
    return true
end

local function APEnemyInMeleeRange()
    if not UnitExists or not UnitExists("target") then
        return false
    end
    if UnitCanAttack and not UnitCanAttack("player", "target") then
        return false
    end
    if IsSpellInRange then
        local inRange = IsSpellInRange(SPELL.HolyStrike, "target")
        if inRange == 1 then
            return true
        elseif inRange == 0 then
            return false
        end
    end
    return APIsInRange("target", 5)
end

local function APCastSpell(spellName)
    if not spellName or not CastSpellByName then
        return false
    end
    CastSpellByName(spellName)
    return true
end

local function APCastSpellOnUnit(spellName, unit)
    if not spellName or not unit then
        return false
    end
    if not UnitExists or not UnitExists(unit) then
        return false
    end
    CastSpellByName(spellName)
    if SpellIsTargeting and SpellIsTargeting() then
        SpellTargetUnit(unit)
        return true
    end
    return false
end

local function APBuildRankName(spellName, rank)
    if not rank or rank <= 0 then
        return spellName
    end
    return spellName .. "(等级 " .. rank .. ")"
end

local function APStartAttack()
    if AttackTarget and UnitExists and UnitExists("target") and UnitCanAttack and UnitCanAttack("player", "target") then
        AttackTarget()
    end
end

local function APUnitVisible(unit)
    if UnitIsVisible then
        return UnitIsVisible(unit)
    end
    return true
end

local function APGetGroupHealthList()
    local members = {}
    local numRaidMembers = GetNumRaidMembers and GetNumRaidMembers() or 0
    if numRaidMembers > 0 then
        for i = 1, numRaidMembers do
            local unit = "raid" .. i
            if UnitExists(unit) and APUnitVisible(unit) then
                local maxHealth = UnitHealthMax(unit)
                if maxHealth and maxHealth > 0 and (not UnitIsDeadOrGhost(unit)) then
                    table.insert(members, {
                        unit = unit,
                        health = UnitHealth(unit),
                        maxHealth = maxHealth
                    })
                end
            end
        end
    else
        local maxHealth = UnitHealthMax("player")
        if maxHealth and maxHealth > 0 then
            table.insert(members, {
                unit = "player",
                health = UnitHealth("player"),
                maxHealth = maxHealth
            })
        end

        local numPartyMembers = GetNumPartyMembers and GetNumPartyMembers() or 0
        if numPartyMembers > 0 then
            for i = 1, numPartyMembers do
                local unit = "party" .. i
                if UnitExists(unit) and APUnitVisible(unit) then
                    local maxPartyHealth = UnitHealthMax(unit)
                    if maxPartyHealth and maxPartyHealth > 0 and (not UnitIsDeadOrGhost(unit)) then
                        table.insert(members, {
                            unit = unit,
                            health = UnitHealth(unit),
                            maxHealth = maxPartyHealth
                        })
                    end
                end
            end
        end
    end
    return members
end

local function APGetSortedGroupByHealth()
    local members = APGetGroupHealthList()
    table.sort(members, function(a, b)
        local aPercent = a.health / a.maxHealth
        local bPercent = b.health / b.maxHealth
        return aPercent < bPercent
    end)
    return members
end

local function APSelectRank(effectTable, costTable, maxRank, missingHealth, mana)
    if maxRank <= 0 then
        return nil
    end
    for i = maxRank, 2, -1 do
        if effectTable[i] and missingHealth >= effectTable[i] then
            if not mana or mana >= costTable[i] then
                return i
            end
        end
    end
    return 1
end

local function APIsAnyFriendMissingInRange(maxRange)
    local members = APGetGroupHealthList()
    for _, member in ipairs(members) do
        if APIsFriendly(member.unit) and member.maxHealth > 0 and member.health < member.maxHealth then
            if APIsInRange(member.unit, maxRange) then
                return true
            end
        end
    end
    return false
end

local function APTryHealUnit(unit, allowOverheal)
    if not APIsFriendly(unit) then
        return false
    end
    local health = UnitHealth(unit)
    local maxHealth = UnitHealthMax(unit)
    if not maxHealth or maxHealth == 0 then
        return false
    end
    local percent = health / maxHealth * 100
    local missing = maxHealth - health
    if not allowOverheal and percent >= AutoPalSaved.BeginValue then
        return false
    end
    if not APIsInRange(unit, 40, SPELL.Flash) then
        return false
    end

    local name = UnitName(unit)
    if name and AP.HealDelay[name] and (GetTime() - AP.HealDelay[name] < 1.2) then
        return false
    end

    if AutoPalSaved.UseLayHands == 1 and percent <= AutoPalSaved.LayHandsValue and APSpellReady(SPELL.LayHands, 0.1) then
        AP.LastHealTarget = unit
        if name then
            AP.HealDelay[name] = GetTime()
        end
        return APCastSpellOnUnit(SPELL.LayHands, unit)
    end

    if AutoPalSaved.UseHolyShock == 1 and percent <= AutoPalSaved.HolyShockValue and APSpellReady(SPELL.HolyShock, 0.1) then
        if APIsInRange(unit, 20, SPELL.HolyShock) then
            AP.LastHealTarget = unit
            if name then
                AP.HealDelay[name] = GetTime()
            end
            return APCastSpellOnUnit(SPELL.HolyShock, unit)
        end
    end

    local mana = UnitMana("player")
    local holyMaxRank = AP.HolyMaxRank
    if AutoPalSaved.HolyLightMaxRank < holyMaxRank then
        holyMaxRank = AutoPalSaved.HolyLightMaxRank
    end
    if AutoPalSaved.UseHolyLight == 1 and holyMaxRank > 0 and percent <= AutoPalSaved.HolyLightValue then
        local rank = APSelectRank(AP.HolyEffect, AP.HolyCost, holyMaxRank, missing, mana)
        if rank then
            AP.LastHealTarget = unit
            if name then
                AP.HealDelay[name] = GetTime()
            end
            return APCastSpellOnUnit(APBuildRankName(SPELL.Holy, rank), unit)
        end
    end

    local flashMaxRank = AP.FlashMaxRank
    if AutoPalSaved.FlashMaxRank < flashMaxRank then
        flashMaxRank = AutoPalSaved.FlashMaxRank
    end
    if AutoPalSaved.UseFlash == 1 and flashMaxRank > 0 and percent <= AutoPalSaved.FlashValue then
        local rank = APSelectRank(AP.FlashEffect, AP.FlashCost, flashMaxRank, missing, mana)
        if rank then
            AP.LastHealTarget = unit
            if name then
                AP.HealDelay[name] = GetTime()
            end
            return APCastSpellOnUnit(APBuildRankName(SPELL.Flash, rank), unit)
        end
    end

    if allowOverheal then
        if AutoPalSaved.IdleSpell == 2 and AutoPalSaved.UseHolyLight == 1 and AP.HolyMaxRank >= 2 then
            AP.LastHealTarget = unit
            if name then
                AP.HealDelay[name] = GetTime()
            end
            return APCastSpellOnUnit(APBuildRankName(SPELL.Holy, 2), unit)
        end
        if AutoPalSaved.UseFlash == 1 and AP.FlashMaxRank >= 1 then
            AP.LastHealTarget = unit
            if name then
                AP.HealDelay[name] = GetTime()
            end
            return APCastSpellOnUnit(APBuildRankName(SPELL.Flash, 1), unit)
        end
        if AutoPalSaved.UseHolyLight == 1 and AP.HolyMaxRank >= 1 then
            AP.LastHealTarget = unit
            if name then
                AP.HealDelay[name] = GetTime()
            end
            return APCastSpellOnUnit(APBuildRankName(SPELL.Holy, 1), unit)
        end
    end

    return false
end

local function APTryPriorityHeals()
    if AutoPalSaved.FocusFirst == 1 and UnitExists("focus") then
        if APTryHealUnit("focus", false) then
            return true
        end
    end

    if AutoPalSaved.TargetFirst == 1 and UnitExists("target") and APIsFriendly("target") then
        if APTryHealUnit("target", false) then
            return true
        end
    end

    if AutoPalSaved.TargetTarget == 1 and UnitExists("target") and UnitCanAttack and UnitCanAttack("player", "target") then
        if UnitExists("targettarget") then
            if APTryHealUnit("targettarget", false) then
                return true
            end
        end
    end

    if AutoPalSaved.ScanGroup == 1 then
        local members = APGetSortedGroupByHealth()
        for _, member in ipairs(members) do
            if APTryHealUnit(member.unit, false) then
                return true
            end
        end
    end

    if AutoPalSaved.OverflowFocus == 1 and UnitExists("focus") then
        if APTryHealUnit("focus", true) then
            return true
        end
    end

    return false
end

local function APTrySealAndJudge()
    if AutoPalSaved.UseSealWisdom ~= 1 and AutoPalSaved.UseJudgeWisdom ~= 1 then
        return false
    end
    if AutoPalSaved.UseSealWisdom == 1 and not APHasBuff("player", SPELL.SealWisdom) then
        return APCastSpell(SPELL.SealWisdom)
    end
    if AutoPalSaved.UseJudgeWisdom == 1 and UnitExists("target") and UnitCanAttack and UnitCanAttack("player", "target") then
        if not APHasDebuff("target", SPELL.JudgementWisdom) and APSpellReady(SPELL.Judgement, 0.1) then
            return APCastSpell(SPELL.Judgement)
        end
    end
    return false
end

local function APTryMeleeRotation()
    if AutoPalSaved.UseMelee ~= 1 then
        return false
    end
    if not UnitExists("target") or not UnitCanAttack or not UnitCanAttack("player", "target") then
        return false
    end
    if not APEnemyInMeleeRange() then
        return false
    end

    APStartAttack()

    if APTrySealAndJudge() then
        return true
    end

    local holyReady = AutoPalSaved.UseHolyStrike == 1 and APSpellReady(SPELL.HolyStrike, 0.1)
    local crusaderReady = AutoPalSaved.UseCrusaderStrike == 1 and APSpellReady(SPELL.CrusaderStrike, 0.1)

    if holyReady and (AutoPalSaved.HolyStrikeHealOnly ~= 1 or APIsAnyFriendMissingInRange(8)) then
        return APCastSpell(SPELL.HolyStrike)
    end
    if crusaderReady then
        return APCastSpell(SPELL.CrusaderStrike)
    end
    if holyReady then
        return APCastSpell(SPELL.HolyStrike)
    end

    return false
end

local function APBoolText(value)
    return value == 1 and "开" or "关"
end

local function APBuildStatusText()
    return "状态:" .. APBoolText(AutoPalSaved.Enabled)
        .. "  近战:" .. APBoolText(AutoPalSaved.UseMelee)
        .. "  过量:" .. APBoolText(AutoPalSaved.OverflowFocus)
        .. "\n圣印:" .. APBoolText(AutoPalSaved.UseSealWisdom)
        .. "  审判:" .. APBoolText(AutoPalSaved.UseJudgeWisdom)
        .. "  监控:" .. APBoolText(AutoPalSaved.Monitor)
        .. "  小地图:" .. APBoolText(AutoPalSaved.Minimap)
end

local function APBuildMonitorText()
    return "状态:" .. APBoolText(AutoPalSaved.Enabled)
        .. "  近战:" .. APBoolText(AutoPalSaved.UseMelee)
        .. "  过量:" .. APBoolText(AutoPalSaved.OverflowFocus)
        .. "\n圣印:" .. APBoolText(AutoPalSaved.UseSealWisdom)
        .. "  审判:" .. APBoolText(AutoPalSaved.UseJudgeWisdom)
end

local function APUIUpdateSliderText(slider, label, value)
    local text = _G[slider:GetName() .. "Text"]
    if text then
        text:SetText(label .. ": " .. value .. "%")
    end
end

local function APUpdateDisplay()
    if AP.UI and AP.UI.Frame then
        AP.UI.InRefresh = true
        if AP.UI.Checks then
            for key, btn in pairs(AP.UI.Checks) do
                btn:SetChecked(AutoPalSaved[key] == 1)
            end
        end
        if AP.UI.Sliders then
            for key, slider in pairs(AP.UI.Sliders) do
                slider:SetValue(AutoPalSaved[key] or 0)
                APUIUpdateSliderText(slider, slider.APLabel or "", AutoPalSaved[key] or 0)
            end
        end
        AP.UI.InRefresh = false
        if AP.UI.StatusText then
            AP.UI.StatusText:SetText(APBuildStatusText())
        end
    end

    if AP.Monitor and AP.Monitor.Text then
        AP.Monitor.Text:SetText(APBuildMonitorText())
        if AutoPalSaved.Monitor == 1 then
            AP.Monitor:Show()
        else
            AP.Monitor:Hide()
        end
    end

    if AP.MinimapButton then
        if AutoPalSaved.Minimap == 1 then
            AP.MinimapButton:Show()
        else
            AP.MinimapButton:Hide()
        end
        if AP.MinimapButton.UpdatePosition then
            AP.MinimapButton:UpdatePosition()
        end
    end
end

local function APCreateMonitor()
    if AP.Monitor then
        return
    end

    local frame = CreateFrame("Frame", "AutoPalMonitorFrame", UIParent)
    frame:SetWidth(210)
    frame:SetHeight(48)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = 1,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.85)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)
    text:SetWidth(194)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetText("")
    frame.Text = text

    AP.Monitor = frame
    APUpdateDisplay()
end

local function APAtan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    end
    if x == 0 then
        if y > 0 then
            return math.pi / 2
        elseif y < 0 then
            return -math.pi / 2
        else
            return 0
        end
    end
    local atan = math.atan(y / x)
    if x < 0 then
        atan = atan + math.pi
    end
    return atan
end

local function APCreateMinimapButton()
    if AP.MinimapButton or not Minimap then
        return
    end

    local button = CreateFrame("Button", "AutoPalMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetWidth(32)
    button:SetHeight(32)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:EnableMouse(true)
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", self.OnUpdatePosition)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UpdatePosition()
    end)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\Spell_Holy_HolyLight")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetAllPoints(button)
    button.Icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetAllPoints(button)

    button.UpdatePosition = function(self)
        local angle = AutoPalSaved.MinimapPos or 225
        local radius = 78
        local rad = math.rad(angle)
        local x = math.cos(rad) * radius
        local y = math.sin(rad) * radius
        self:ClearAllPoints()
        self:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    button.OnUpdatePosition = function(self)
        local x, y = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        local centerX, centerY = Minimap:GetCenter()
        x = x / scale - centerX
        y = y / scale - centerY
        local angle = math.deg(APAtan2(y, x))
        if angle < 0 then
            angle = angle + 360
        end
        AutoPalSaved.MinimapPos = angle
        self:UpdatePosition()
    end

    button:SetScript("OnClick", function(_, btn)
        if btn == "LeftButton" then
            APCreateUI()
            if AP.UI and AP.UI.Frame then
                if AP.UI.Frame:IsShown() then
                    AP.UI.Frame:Hide()
                else
                    AP.UI.Frame:Show()
                end
            end
        elseif btn == "RightButton" then
            AutoPalSaved.Enabled = AutoPalSaved.Enabled == 1 and 0 or 1
            APUpdateDisplay()
        end
    end)

    button:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("AutoPal")
        GameTooltip:AddLine("左键：打开/关闭设置", 1, 1, 1)
        GameTooltip:AddLine("右键：启用/禁用插件", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    AP.MinimapButton = button
    button:UpdatePosition()
    APUpdateDisplay()
end

local function APUI_CreateCheckButton(parent, name, label, x, y, key)
    local btn = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local text = _G[name .. "Text"]
    if text then
        text:SetText(label)
    end
    btn:SetScript("OnClick", function(self)
        AutoPalSaved[key] = self:GetChecked() and 1 or 0
        APUpdateDisplay()
    end)
    return btn
end

local function APUI_CreateSlider(parent, name, label, x, y, key)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:SetWidth(160)
    slider:SetMinMaxValues(1, 100)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end
    slider.APLabel = label

    local low = _G[name .. "Low"]
    local high = _G[name .. "High"]
    if low then
        low:SetText("1")
    end
    if high then
        high:SetText("100")
    end

    slider:SetScript("OnValueChanged", function(self, value)
        if AP.UI and AP.UI.InRefresh then
            return
        end
        value = math.floor(value + 0.5)
        AutoPalSaved[key] = value
        APUIUpdateSliderText(self, label, value)
        APUpdateDisplay()
    end)

    return slider
end

local function APCreateUI()
    if AP.UI and AP.UI.Frame then
        return
    end

    local frame = CreateFrame("Frame", "AutoPalConfigFrame", UIParent)
    frame:SetWidth(380)
    frame:SetHeight(360)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = 1,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
    title:SetText("AutoPal 圣骑治疗 v" .. AP.Version)

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
    status:SetWidth(356)
    status:SetJustifyH("LEFT")
    status:SetJustifyV("TOP")
    status:SetText("")

    AP.UI.Frame = frame
    AP.UI.StatusText = status
    AP.UI.Checks = {}
    AP.UI.Sliders = {}

    local leftChecks = {
        { key = "Enabled", label = "启用插件" },
        { key = "UseMelee", label = "近战模式" },
        { key = "OverflowFocus", label = "过量刷关注" },
        { key = "Monitor", label = "显示监控" },
        { key = "Minimap", label = "小地图图标" },
        { key = "FocusFirst", label = "关注优先" },
        { key = "TargetFirst", label = "目标优先" },
        { key = "TargetTarget", label = "目标的目标" },
        { key = "ScanGroup", label = "扫描队伍" }
    }

    local rightChecks = {
        { key = "UseSealWisdom", label = "智慧圣印" },
        { key = "UseJudgeWisdom", label = "智慧审判" },
        { key = "UseHolyStrike", label = "神圣打击" },
        { key = "UseCrusaderStrike", label = "十字军打击" },
        { key = "UseHolyShock", label = "神圣震击" },
        { key = "UseHolyLight", label = "圣光术" },
        { key = "UseFlash", label = "圣光闪现" },
        { key = "UseLayHands", label = "圣疗术" }
    }

    local startY = -72
    local rowHeight = 18
    local leftX = 12
    local rightX = 196

    for i, def in ipairs(leftChecks) do
        local btn = APUI_CreateCheckButton(frame, "AutoPalCheck" .. def.key, def.label, leftX, startY - (i - 1) * rowHeight, def.key)
        AP.UI.Checks[def.key] = btn
    end

    for i, def in ipairs(rightChecks) do
        local btn = APUI_CreateCheckButton(frame, "AutoPalCheck" .. def.key, def.label, rightX, startY - (i - 1) * rowHeight, def.key)
        AP.UI.Checks[def.key] = btn
    end

    local sliderStartY = -230
    local sliderRow = 40
    local sliderLeftX = 12
    local sliderRightX = 196

    local sliderLeft = {
        { key = "BeginValue", label = "起刷血线" },
        { key = "HolyLightValue", label = "圣光术" },
        { key = "FlashValue", label = "圣光闪现" }
    }

    local sliderRight = {
        { key = "HolyShockValue", label = "神圣震击" },
        { key = "LayHandsValue", label = "圣疗术" }
    }

    for i, def in ipairs(sliderLeft) do
        local slider = APUI_CreateSlider(frame, "AutoPalSlider" .. def.key, def.label, sliderLeftX, sliderStartY - (i - 1) * sliderRow, def.key)
        AP.UI.Sliders[def.key] = slider
    end

    for i, def in ipairs(sliderRight) do
        local slider = APUI_CreateSlider(frame, "AutoPalSlider" .. def.key, def.label, sliderRightX, sliderStartY - (i - 1) * sliderRow, def.key)
        AP.UI.Sliders[def.key] = slider
    end

    APUpdateDisplay()
    frame:Hide()
end

function AutoPal_OneKey()
    if AutoPalSaved.Enabled ~= 1 then
        return
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        return
    end
    if APIsCasting() then
        APTryStopOverheal()
        return
    end

    if APTryMeleeRotation() then
        return
    end

    APTryPriorityHeals()
end

local function APShowStatus()
    APPrint("版本: " .. AP.Version)
    APPrint("状态: " .. (AutoPalSaved.Enabled == 1 and "开启" or "关闭"))
    APPrint("近战模式: " .. (AutoPalSaved.UseMelee == 1 and "开启" or "关闭"))
    APPrint("过量刷关注: " .. (AutoPalSaved.OverflowFocus == 1 and "开启" or "关闭"))
    APPrint("监控显示: " .. (AutoPalSaved.Monitor == 1 and "开启" or "关闭"))
    APPrint("小地图图标: " .. (AutoPalSaved.Minimap == 1 and "开启" or "关闭"))
end

local function APShowHelp()
    APPrint("命令: /autopal on | off | status")
    APPrint("命令: /autopal melee on|off  /autopal overflow on|off")
    APPrint("命令: /autopal seal on|off   /autopal judge on|off")
    APPrint("命令: /autopal ui   /autopal monitor on|off")
    APPrint("命令: /autopal minimap on|off")
    APPrint("命令: /autopal idle flash|holy")
    APPrint("命令: /autopal set begin|holy|flash|shock|lay <百分比>")
end

local function APSetPercent(key, value)
    local num = tonumber(value)
    if not num then
        APPrint("数值无效")
        return
    end
    if num < 0 then
        num = 0
    elseif num > 100 then
        num = 100
    end
    AutoPalSaved[key] = num
    APPrint("已设置: " .. key .. " = " .. num .. "%")
    APUpdateDisplay()
end

local function APHandleSlash(msg)
    msg = msg or ""
    local cmd, rest = string.match(string.lower(msg), "^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "help" then
        APShowHelp()
        return
    end

    if cmd == "on" then
        AutoPalSaved.Enabled = 1
        APPrint("已开启")
        return
    elseif cmd == "off" then
        AutoPalSaved.Enabled = 0
        APPrint("已关闭")
        return
    elseif cmd == "status" then
        APShowStatus()
        return
    elseif cmd == "ui" then
        APCreateUI()
        if AP.UI and AP.UI.Frame then
            if AP.UI.Frame:IsShown() then
                AP.UI.Frame:Hide()
            else
                AP.UI.Frame:Show()
            end
        end
        return
    elseif cmd == "melee" then
        if rest == "on" then
            AutoPalSaved.UseMelee = 1
            APPrint("近战模式已开启")
        elseif rest == "off" then
            AutoPalSaved.UseMelee = 0
            APPrint("近战模式已关闭")
        end
        APUpdateDisplay()
        return
    elseif cmd == "overflow" then
        if rest == "on" then
            AutoPalSaved.OverflowFocus = 1
            APPrint("过量刷关注已开启")
        elseif rest == "off" then
            AutoPalSaved.OverflowFocus = 0
            APPrint("过量刷关注已关闭")
        end
        APUpdateDisplay()
        return
    elseif cmd == "seal" then
        if rest == "on" then
            AutoPalSaved.UseSealWisdom = 1
            APPrint("智慧圣印已开启")
        elseif rest == "off" then
            AutoPalSaved.UseSealWisdom = 0
            APPrint("智慧圣印已关闭")
        end
        APUpdateDisplay()
        return
    elseif cmd == "judge" then
        if rest == "on" then
            AutoPalSaved.UseJudgeWisdom = 1
            APPrint("智慧审判已开启")
        elseif rest == "off" then
            AutoPalSaved.UseJudgeWisdom = 0
            APPrint("智慧审判已关闭")
        end
        APUpdateDisplay()
        return
    elseif cmd == "monitor" then
        if rest == "on" then
            AutoPalSaved.Monitor = 1
            APPrint("监控已开启")
        elseif rest == "off" then
            AutoPalSaved.Monitor = 0
            APPrint("监控已关闭")
        end
        APUpdateDisplay()
        return
    elseif cmd == "minimap" then
        if rest == "on" then
            AutoPalSaved.Minimap = 1
            APPrint("小地图图标已开启")
        elseif rest == "off" then
            AutoPalSaved.Minimap = 0
            APPrint("小地图图标已关闭")
        end
        APUpdateDisplay()
        return
    elseif cmd == "idle" then
        if rest == "flash" then
            AutoPalSaved.IdleSpell = 1
            APPrint("过量刷关注使用：圣光闪现1级")
        elseif rest == "holy" then
            AutoPalSaved.IdleSpell = 2
            APPrint("过量刷关注使用：圣光术2级")
        end
        APUpdateDisplay()
        return
    elseif cmd == "set" then
        local key, value = string.match(rest, "^(%S+)%s+(%S+)$")
        if not key then
            APPrint("用法: /autopal set begin|holy|flash|shock|lay <百分比>")
            return
        end
        if key == "begin" then
            APSetPercent("BeginValue", value)
        elseif key == "holy" then
            APSetPercent("HolyLightValue", value)
        elseif key == "flash" then
            APSetPercent("FlashValue", value)
        elseif key == "shock" then
            APSetPercent("HolyShockValue", value)
        elseif key == "lay" then
            APSetPercent("LayHandsValue", value)
        else
            APPrint("未知参数")
        end
        APUpdateDisplay()
        return
    end

    APPrint("未知命令，输入 /autopal help")
end

local function APInit()
    APApplyDefaults()
    APUpdateSpellData()
    APCreateMonitor()
    APCreateMinimapButton()
    SLASH_AUTOPAL1 = "/autopal"
    SlashCmdList["AUTOPAL"] = APHandleSlash
    APUpdateDisplay()
    APPrint("已加载 v" .. AP.Version .. "，可在按键设置中绑定“圣骑一键治疗”")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("SPELLCAST_START")
frame:RegisterEvent("SPELLCAST_STOP")
frame:RegisterEvent("SPELLCAST_FAILED")
frame:RegisterEvent("SPELLCAST_INTERRUPTED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, ev)
    ev = ev or event
    if ev == "PLAYER_LOGIN" then
        APInit()
    elseif ev == "SPELLS_CHANGED" then
        APUpdateSpellData()
    elseif ev == "PLAYER_REGEN_DISABLED" then
        AP.InCombat = true
    elseif ev == "PLAYER_REGEN_ENABLED" then
        AP.InCombat = false
    elseif ev == "SPELLCAST_START" then
        AP.LastHealCastTime = GetTime()
    elseif ev == "SPELLCAST_STOP" or ev == "SPELLCAST_FAILED" or ev == "SPELLCAST_INTERRUPTED" then
        AP.LastHealCastTime = 0
    end
end)
