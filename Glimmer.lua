-- Glimmer 2: sparkle + own icons on ore, herbs, chests; paw icon on skinnable corpses;
-- keeps the game's quest-item loot sparkle on. WoW: Forever.
local ADDON = ...
local PREFIX = "|cffffd200Glimmer|r "

---------------------------------------------------------------------------
-- Game settings (CVars)
---------------------------------------------------------------------------
local QUEST_SPARKLE = {               -- game's own sparkle on lootable quest items
  outlineModeShowLootEffectWhenDisabled = "1",
  graphicsOutlineMode = "0",
  OutlineEngineMode = "0",
  raidGraphicsOutlineMode = "0",
  RAIDOutlineEngineMode = "0",
}
local TARGETING = {                   -- lets the game tell us the nearest object; no game icons
  SoftTargetInteract = "3",
  SoftTargetInteractRange = "30",
  SoftTargetInteractArc = "2",
  SoftTargetInteractOnlyInRange = "0",
  SoftTargetIconGameObject = "1",     -- needed so objects get a screen anchor; Glimmer hides the icon itself
  SoftTargetIconInteract = "0",       -- no game icons on NPCs / corpses (no double "?")
  SoftTargetIconEnemy = "0",          -- no sword over enemies
  SoftTargetIconFriend = "0",
  SoftTargetLowPriorityIcons = "1",   -- keeps objects anchored; Glimmer hides their icons
}

local defaults = {
  questSparkle = true,
  oreSparkle = true,  oreIcon = true,
  herbSparkle = true, herbIcon = true,
  chestSparkle = true, chestIcon = true,
  skinIcon = true,
  sparkleSize = 1.0, iconSize = 1.0, offset = -55,
  saved = {},
}
local db
local applying, pending = false, false

local function Get(k) return C_CVar and C_CVar.GetCVar(k) or GetCVar(k) end
local function Set(k, v)
  if Get(k) == nil then return end
  local ok, err = pcall(function() if C_CVar then C_CVar.SetCVar(k, v) else SetCVar(k, v) end end)
  if not ok then print(PREFIX .. "couldn't set " .. k .. ": " .. tostring(err)) end
end

local function AnyObjectFeature()
  return db.oreSparkle or db.oreIcon or db.herbSparkle or db.herbIcon
      or db.chestSparkle or db.chestIcon or db.skinIcon
end

local function Apply()
  if InCombatLockdown() then pending = true; return end
  pending = false
  applying = true
  if db.questSparkle then
    for k, v in pairs(QUEST_SPARKLE) do if Get(k) ~= v then Set(k, v) end end
  end
  if AnyObjectFeature() then
    for k, v in pairs(TARGETING) do
      if db.saved[k] == nil then db.saved[k] = Get(k) end
      if Get(k) ~= v then Set(k, v) end
    end
  else
    for k, v in pairs(db.saved) do Set(k, v) end   -- give the game its own settings back
    wipe(db.saved)
  end
  applying = false
end

local timer
local function ApplySoon()
  if timer then timer:Cancel() end
  timer = C_Timer.NewTimer(1, function() timer = nil; Apply() end)
end

---------------------------------------------------------------------------
-- What is the nearest thing?
---------------------------------------------------------------------------
local HERBS = {
  "peacebloom", "silverleaf", "earthroot", "mageroyal", "briarthorn", "stranglekelp", "bruiseweed",
  "wild steelbloom", "grave moss", "kingsblood", "liferoot", "fadeleaf", "goldthorn", "khadgar's whisker",
  "wintersbite", "firebloom", "purple lotus", "arthas' tears", "sungrass", "blindweed", "ghost mushroom",
  "gromsblood", "golden sansam", "dreamfoil", "mountain silversage", "plaguebloom", "icecap", "black lotus",
  "swiftthistle", "bloodthistle",
}
local CHESTS = { "chest", "strongbox", "footlocker", "coffer" }
local ORES = { " vein", " deposit" }

local function Has(str, list)
  for _, w in ipairs(list) do if str:find(w, 1, true) then return true end end
  return false
end

local function ClassifyName(name)        -- "chest" / "ore" / "herb" / nil
  if not name then return nil end
  local n = " " .. name:lower()
  if Has(n, CHESTS) then return "chest" end
  if Has(n, ORES) then return "ore" end
  if Has(n, HERBS) then return "herb" end
  return nil
end

local function IsGameObject()
  local isObj = false
  local ok = pcall(function() isObj = UnitGUID("softinteract"):find("^GameObject") ~= nil end)
  if not ok then isObj = false end
  pcall(function()
    if UnitCreatureType("softinteract") or UnitIsPlayer("softinteract") then isObj = false end
  end)
  return isObj
end

local function KnowsSkinning()
  local ok, known = pcall(function()
    for _, idx in ipairs({ GetProfessions() }) do
      if idx then
        local _, icon, _, _, _, _, skillLine = GetProfessionInfo(idx)
        if skillLine == 393 or (icon and tostring(icon):lower():find("skin", 1, true)) then return true end
      end
    end
    return false
  end)
  return ok and known
end

local function IsSkinnableCorpse()
  local ok, yes = pcall(function()
    if not UnitIsDead("softinteract") then return false end
    local data = C_TooltipInfo and C_TooltipInfo.GetUnit("softinteract")
    if not data or not data.lines then return false end
    for _, line in ipairs(data.lines) do
      local t = line.leftText
      if t and tostring(t):lower():find("skinnable", 1, true) then return true end
    end
    return false
  end)
  return ok and yes
end

---------------------------------------------------------------------------
-- Drawing: sparkle + icon
---------------------------------------------------------------------------
local holder = CreateFrame("Frame", nil, WorldFrame)
holder:SetSize(130, 90); holder:SetFrameStrata("HIGH"); holder:Hide()

local spark = CreateFrame("Frame", nil, holder)
spark:SetSize(130, 60); spark:SetPoint("CENTER")
local stars = {}
for i = 1, 10 do
  local t = spark:CreateTexture(nil, "OVERLAY")
  t:SetTexture("Interface\\Cooldown\\star4")
  t:SetBlendMode("ADD")
  stars[i] = { tex = t, phase = math.random() * 6.28, speed = 0.6 + math.random(),
               x = math.random(-55, 55), y = math.random(-16, 16), size = math.random(6, 10) }
end
local glow = spark:CreateTexture(nil, "ARTWORK")
glow:SetTexture("Interface\\Cooldown\\starburst")
glow:SetBlendMode("ADD"); glow:SetSize(110, 40); glow:SetPoint("CENTER")

local t0 = 0
spark:SetScript("OnUpdate", function(_, dt)
  t0 = t0 + dt
  for _, s in ipairs(stars) do
    local p = (t0 * s.speed + s.phase) % 2
    local a = (p < 1) and p or (2 - p)
    s.tex:SetAlpha(a * 0.7)
    local sz = s.size * (0.5 + a * 0.6)
    s.tex:SetSize(sz, sz)
    s.tex:ClearAllPoints()
    s.tex:SetPoint("CENTER", spark, "CENTER", s.x, s.y + p * 4)
    if p > 1.98 then s.x = math.random(-55, 55); s.y = math.random(-16, 16) end
  end
  glow:SetAlpha(0.12 + 0.08 * math.sin(t0 * 2))
end)

local icon = CreateFrame("Frame", nil, holder)
icon:SetSize(26, 26); icon:SetPoint("BOTTOM", spark, "TOP", 0, 4)
local iconTex = icon:CreateTexture(nil, "ARTWORK")
iconTex:SetAllPoints()
iconTex:SetTexCoord(0.1, 1, 0.1, 1)               -- trim the pointer corner
local iconMask = icon:CreateMaskTexture()          -- round mask hides the cursor's little arrow
iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
iconMask:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
iconMask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 3, -3)
iconTex:AddMaskTexture(iconMask)

local ICONS = {                      -- sharp crosshair versions first, classic cursor as fallback
  ore   = { "Interface\\Cursor\\Crosshair\\Mine",        "Interface\\Cursor\\Mine" },
  herb  = { "Interface\\Cursor\\Crosshair\\GatherHerbs", "Interface\\Cursor\\Gatherherbs" },
  chest = { "Interface\\Cursor\\Crosshair\\Interact",    "Interface\\Cursor\\Interact" },
  skin  = { "Interface\\Cursor\\Crosshair\\Skin",        "Interface\\Cursor\\Skin" },
}
local function SetIcon(kind)
  local hiRes = iconTex:SetTexture(ICONS[kind][1])
  if hiRes == false then iconTex:SetTexture(ICONS[kind][2]) end
  local usedHi = (hiRes ~= false)
  -- the sharp versions have no pointer arrow, so no trim/mask needed
  iconTex:SetTexCoord(usedHi and 0 or 0.1, 1, usedHi and 0 or 0.1, 1)
  if usedHi then iconTex:RemoveMaskTexture(iconMask) else iconTex:AddMaskTexture(iconMask) end
  Glimmer_iconRes = usedHi and "sharp" or "classic"
end

-- hide the game's own icon on the object's anchor (object anchors only hold that icon)
local hidden = {}
local function RestoreGameIcons()
  for r in pairs(hidden) do pcall(r.SetAlpha, r, 1) end
  wipe(hidden)
end
local function HideGameIcons(frame, depth)
  if not frame or depth > 4 then return end
  for _, r in ipairs({ frame:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "Texture" then r:SetAlpha(0); hidden[r] = true end
  end
  for _, c in ipairs({ frame:GetChildren() }) do HideGameIcons(c, depth + 1) end
end

local last = {}
local function Update()
  RestoreGameIcons()
  last.kind, last.why = nil, nil
  holder:Hide()
  if not db then return end

  local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit("softinteract")
  if not plate or not UnitGUID("softinteract") then last.why = "no target / no anchor"; return end

  local kind, showSpark, showIcon
  if IsGameObject() then
    pcall(HideGameIcons, plate, 0)          -- never show the game's object icons (chairs etc.)
    local name; pcall(function() name = UnitName("softinteract") end)
    kind = ClassifyName(name)
    if kind then
      showSpark = db[kind .. "Sparkle"]
      showIcon = db[kind .. "Icon"]
    end
  elseif db.skinIcon and IsSkinnableCorpse() and KnowsSkinning() then
    kind, showSpark, showIcon = "skin", false, true
  end
  last.kind = kind
  if not kind then last.why = "not a Glimmer type"; return end
  if not (showSpark or showIcon) then last.why = "turned off in settings"; return end

  local isChest = (kind == "chest")
  spark:SetScale(db.sparkleSize * (isChest and 1.15 or 1))
  for _, s in ipairs(stars) do s.tex:SetVertexColor(1, isChest and 0.8 or 0.9, isChest and 0.2 or 0.5) end
  glow:SetVertexColor(1, 0.8, 0.3, 0.6)
  spark:SetShown(showSpark and true or false)
  icon:SetScale(db.iconSize)
  pcall(SetIcon, kind)
  icon:SetShown(showIcon and true or false)

  holder:ClearAllPoints()
  -- corpses: icon floats above the name; objects: sparkle on the object, icon just above it
  local yOff = (kind == "skin") and -8 or db.offset
  local ok = pcall(holder.SetPoint, holder, "CENTER", plate, "CENTER", 0, yOff)
  if not ok then
    local ok2, x, y = pcall(plate.GetCenter, plate)
    if not (ok2 and x) then last.why = "anchor blocked"; return end
    local sc = plate:GetEffectiveScale() / holder:GetEffectiveScale()
    holder:SetPoint("CENTER", WorldFrame, "BOTTOMLEFT", x * sc, y * sc + yOff)
  end
  last.why = "drawn"
  holder:Show()
end
local function SafeUpdate()
  local ok, err = pcall(Update)
  if not ok then last.why = "error: " .. tostring(err); holder:Hide() end
end

---------------------------------------------------------------------------
-- Settings panel
---------------------------------------------------------------------------
local panel
local function BuildOptions()
  local p = CreateFrame("Frame")
  p.name = "Glimmer"
  local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16); title:SetText("Glimmer")
  local sub = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetText("Sparkle and icons on the nearest object in front of you (about 15 yards). All other game interact icons are hidden.")

  local function Header(text, x, y)
    local h = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    h:SetPoint("TOPLEFT", x, y); h:SetText(text)
  end
  local function Box(key, x, y)
    local c = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    c:SetPoint("TOPLEFT", x, y); c:SetSize(24, 24)
    if c.Text then c.Text:SetText("") end
    c:SetScript("OnShow", function(self) self:SetChecked(db[key]) end)
    c:SetScript("OnClick", function(self) db[key] = self:GetChecked() and true or false; Apply(); SafeUpdate() end)
    return c
  end
  local function Row(label, y, sparkKey, iconKey)
    local l = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    l:SetPoint("TOPLEFT", 20, y - 5); l:SetText(label)
    if sparkKey then Box(sparkKey, 300, y) end
    if iconKey then Box(iconKey, 370, y) end
  end

  Header("Type", 20, -64); Header("Sparkle", 292, -64); Header("Icon", 370, -64)
  Row("Quest objects (game's sparkle)", -80, "questSparkle", nil)
  Row("Ore veins", -108, "oreSparkle", "oreIcon")
  Row("Herbs", -136, "herbSparkle", "herbIcon")
  Row("Treasure chests", -164, "chestSparkle", "chestIcon")
  Row("Skinnable corpses (if you know Skinning)", -192, nil, "skinIcon")

  local function Slider(label, key, minV, maxV, step, y, fmt)
    local l = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    l:SetPoint("TOPLEFT", 20, y)
    local s = CreateFrame("Slider", nil, p)
    s:SetOrientation("HORIZONTAL"); s:SetSize(180, 16); s:SetPoint("TOPLEFT", 300, y + 2)
    local bg = s:CreateTexture(nil, "BACKGROUND"); bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    bg:SetPoint("LEFT"); bg:SetPoint("RIGHT"); bg:SetHeight(4)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
    local function Txt(v) l:SetText(label .. ": " .. string.format(fmt, v)) end
    s:SetScript("OnShow", function(self) self:SetValue(db[key]); Txt(db[key]) end)
    s:SetScript("OnValueChanged", function(_, v) db[key] = v; Txt(v); SafeUpdate() end)
  end
  Slider("Sparkle size", "sparkleSize", 0.5, 2, 0.1, -232, "%.1f")
  Slider("Icon size", "iconSize", 0.5, 2, 0.1, -262, "%.1f")
  Slider("Height on object", "offset", -120, 20, 5, -292, "%d")

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(p, "Glimmer")
    Settings.RegisterAddOnCategory(cat)
    p.categoryID = cat:GetID()
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(p)
  end
  return p
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
SLASH_GLIMMER1 = "/glimmer"
SlashCmdList.GLIMMER = function(msg)
  msg = (msg or ""):lower()
  if msg == "status" then
    SafeUpdate()
    local name; pcall(function() name = tostring(UnitName("softinteract")) end)
    print(PREFIX .. "target: " .. tostring(name) .. "  object: " .. tostring(IsGameObject())
      .. "  type: " .. tostring(last.kind) .. "  result: " .. tostring(last.why) .. "  icon: " .. tostring(Glimmer_iconRes))
    local bad = {}
    for k, v in pairs(QUEST_SPARKLE) do if db.questSparkle and Get(k) ~= v then bad[#bad + 1] = k end end
    for k, v in pairs(TARGETING) do if AnyObjectFeature() and Get(k) ~= v then bad[#bad + 1] = k end end
    print(PREFIX .. "game settings: " .. ((#bad == 0) and "|cff40ff40all ok|r" or ("|cffff4040wrong:|r " .. table.concat(bad, ", "))))
    return
  end
  if Settings and Settings.OpenToCategory and panel and panel.categoryID then
    Settings.OpenToCategory(panel.categoryID)
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("CVAR_UPDATE")
for _, e in ipairs({ "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
  pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, e, a1)
  if e == "ADDON_LOADED" and a1 == ADDON then
    GlimmerDB = GlimmerDB or {}
    if not GlimmerDB.v2 then                         -- fresh start for Glimmer 2, keep restore list + height
      local saved, offset = GlimmerDB.saved, GlimmerDB.offset
      GlimmerDB = { v2 = true, saved = saved or {}, offset = offset }
    end
    for k, v in pairs(defaults) do
      if GlimmerDB[k] == nil then GlimmerDB[k] = (type(v) == "table") and {} or v end
    end
    db = GlimmerDB
    panel = BuildOptions()
    C_Timer.NewTicker(0.25, SafeUpdate)
  elseif not db then
    return
  elseif e == "PLAYER_ENTERING_WORLD" then
    ApplySoon(); C_Timer.After(0, SafeUpdate)
  elseif e == "PLAYER_REGEN_ENABLED" then
    if pending then Apply() end
  elseif e == "CVAR_UPDATE" then
    if not applying and (QUEST_SPARKLE[a1] or TARGETING[a1] or a1 == "graphicsQuality" or a1 == "raidGraphicsQuality") then
      ApplySoon()
    end
  else
    C_Timer.After(0, SafeUpdate)
  end
end)
