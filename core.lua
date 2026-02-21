local addonName, addonTable = ...

-----------------------------------------------------------
-- Core Variables & Event Frame
-----------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")

local lower = string.lower
local find = string.find
local maxBagIndex = _G.NUM_BAG_SLOTS or 4
local sellRunId = 0

local nativeSoulbound = _G.ITEM_SOULBOUND and lower(_G.ITEM_SOULBOUND) or nil
local nativeWarbound = _G.ITEM_BIND_TO_WAR_ACCOUNT and lower(_G.ITEM_BIND_TO_WAR_ACCOUNT) or nil
local nativeBoA = _G.ITEM_BIND_TO_ACCOUNT and lower(_G.ITEM_BIND_TO_ACCOUNT) or nil
local nativeBoN = _G.ITEM_BIND_TO_BNETACCOUNT and lower(_G.ITEM_BIND_TO_BNETACCOUNT) or nil
local nativeItemLevelPrefix = _G.ITEM_LEVEL and lower(_G.ITEM_LEVEL) or "item level"

-----------------------------------------------------------
-- Helper: Scrape Item Tooltip Data
-- Parses tooltip lines for localized "Soulbound" and "Item Level" numbers
-----------------------------------------------------------
local function ParseTooltip(bag, slot)
    local bind, bound, lvl = false, false, nil
    local t = C_TooltipInfo.GetBagItem(bag, slot)
    
    if t and t.lines then
        for _, l in ipairs(t.lines) do
            local txt = lower(l.leftText or "")
            
            -- Detect bindings using native strings (with english fallback).
            if nativeWarbound and find(txt, nativeWarbound, 1, true) then bound = true end
            if nativeBoA and find(txt, nativeBoA, 1, true) then bound = true end
            if nativeBoN and find(txt, nativeBoN, 1, true) then bound = true end
            if find(txt, "warbound", 1, true) or find(txt, "warband", 1, true) or find(txt, "account", 1, true) then
                bound = true
            end

            if nativeSoulbound and find(txt, nativeSoulbound, 1, true) then bind = true end
            if find(txt, "soulbound", 1, true) then bind = true end
            
            -- Extract item level from native token or english fallback.
            local foundLvl = txt:match(nativeItemLevelPrefix .. "%s*(%d+)") or txt:match("item level%s*(%d+)")
            if foundLvl then lvl = tonumber(foundLvl) end
        end
    end
    
    return bind, bound, lvl
end

-----------------------------------------------------------
-- Core Filter: Determine if a Bag Item is Junk
-----------------------------------------------------------
local function IsJunk(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or info.hasNoValue then return false end
    
    -- Exclude equipment sets
    if C_Container.GetContainerItemEquipmentSetInfo(bag, slot) then return false end
    
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if not C_Item.DoesItemExist(loc) then return false end

    local name, _, rarity, baseLvl, minLvl, _, _, _, equipLoc, _, _, classID, _, bindType = C_Item.GetItemInfo(info.hyperlink)
    if not name or rarity == 5 or rarity == 6 then return false end
    
    -- 1. True Gray Junk
    if rarity == 0 then return true end

    -- 2. Bound Gear Checks (Armor/Weapons)
    if equipLoc and equipLoc ~= "" and (classID == 2 or classID == 4) then
        local bind, bound, tLvl = ParseTooltip(bag, slot)
        if bindType == 8 then bound = true end
        if info.isBound then bind = true end
        
        -- BoE Gear is strictly kept
        if not bind and not bound then return false end
        
        -- Special: Low requirement account gear
        if bound and minLvl and minLvl < 90 then return true end

        -- Level Thresholds (Midnight Values)
        local pcallOk, cLvl = pcall(C_Item.GetCurrentItemLevel, loc)
        local lvl = tLvl or (pcallOk and cLvl) or baseLvl
        
        local pLvl = UnitLevel("player")
        if pLvl >= 80 and lvl < 101 then return true end
        if pLvl >= 90 and lvl < 130 then return true end
    end
    
    return false
end

-----------------------------------------------------------
-- Auto-Repair Functionality
-----------------------------------------------------------
local function AutoRepair()
    if CanMerchantRepair() then
        local cost, canRepair = GetRepairAllCost()
        if canRepair and cost > 0 then
            local guild = CanGuildBankRepair() and GetGuildBankMoney() >= cost and (GetGuildBankWithdrawMoney() == -1 or GetGuildBankWithdrawMoney() >= cost)
            RepairAllItems(guild)
            print("|cffff00ffmuteCat Junk:|r Repair (" .. (guild and "Guild" or "Player") .. "): " .. GetCoinTextureString(cost))
        end
    end
end

local isMerchantOpen = false

frame:SetScript("OnEvent", function(self, event)
    if event == "MERCHANT_CLOSED" then
        isMerchantOpen = false
        sellRunId = sellRunId + 1
    elseif event == "MERCHANT_SHOW" then
        isMerchantOpen = true
        sellRunId = sellRunId + 1
        local thisRunId = sellRunId
        if IsShiftKeyDown() then return end
        AutoRepair()
        
        local queue, sold, gold = {}, 0, 0
        for bag = 0, maxBagIndex do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local ok, junk = pcall(IsJunk, bag, slot)
                if ok and junk then 
                    table.insert(queue, {bag=bag, slot=slot})
                end
            end
        end

        local function SellNext()
            if thisRunId ~= sellRunId or not isMerchantOpen or #queue == 0 then
                if sold > 0 then
                    print("|cffff00ffmuteCat Junk:|r Sold " .. sold .. " item(s) for " .. GetCoinTextureString(gold) .. ".")
                end
                return
            end
            
            -- Batch 4 items
            for i = 1, math.min(4, #queue) do
                local item = table.remove(queue, 1)
                local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
                if info and not info.hasNoValue then
                    gold = gold + (select(11, C_Item.GetItemInfo(info.hyperlink)) or 0) * info.stackCount
                    sold = sold + 1
                    C_Container.UseContainerItem(item.bag, item.slot)
                end
            end
            -- Call itself recursively to act as a thread
            C_Timer.After(0.15, SellNext)
        end
        SellNext()
    end
end)

-----------------------------------------------------------
-- Integration: Baganator Plugin
-----------------------------------------------------------
local bFrame = CreateFrame("Frame")
bFrame:RegisterEvent("PLAYER_LOGIN")
bFrame:SetScript("OnEvent", function()
    if Baganator and Baganator.API and Baganator.API.RegisterJunkPlugin then
        Baganator.API.RegisterJunkPlugin("muteCat Junk", "mutecatjunk", function(bag, slot)
            local ok, junk = pcall(IsJunk, bag, slot)
            return ok and junk
        end)
    end
end)
