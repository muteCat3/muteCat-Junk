local addonName, addonTable = ...

-----------------------------------------------------------
-- Core Variables & Event Frame
-------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")

local lower = string.lower
local find = string.find
local floor = math.floor
local maxBagIndex = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5 -- Modern WoW standard
local sellRunId = 0
local lastEvalError = ""
local lastEvalErrorAt = 0
local CALLER_ID = "muteCat Junk"
local MIN_PROFIT_COPPER = 10000
local AH_NET_FACTOR = 0.95

local itemIDs = addonTable.itemIDs or {}
local forceKeepItemIDs = itemIDs.forceKeepItemIDs or {}
local forceSellItemIDs = itemIDs.forceSellItemIDs or {}
local midnightConsumableKeepIDs = itemIDs.midnightConsumableKeepIDs or {}
local midnightCraftingMatsByID = itemIDs.midnightCraftingMatsByID or {}

local consumableClassID = Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0
local tradeGoodsClassID = (Enum and Enum.ItemClass and (Enum.ItemClass.Tradegoods or Enum.ItemClass.TradeGoods)) or 7
local reagentClassID = (Enum and Enum.ItemClass and Enum.ItemClass.Reagent) or 5
local professionClassID = (Enum and Enum.ItemClass and Enum.ItemClass.Profession) or 19

local nativeSoulbound = _G.ITEM_SOULBOUND and lower(_G.ITEM_SOULBOUND) or nil
local nativeWarbound = _G.ITEM_BIND_TO_WAR_ACCOUNT and lower(_G.ITEM_BIND_TO_WAR_ACCOUNT) or nil
local nativeBoA = _G.ITEM_BIND_TO_ACCOUNT and lower(_G.ITEM_BIND_TO_ACCOUNT) or nil
local nativeBoN = _G.ITEM_BIND_TO_BNETACCOUNT and lower(_G.ITEM_BIND_TO_BNETACCOUNT) or nil
local nativeItemLevelPrefix = _G.ITEM_LEVEL and lower(_G.ITEM_LEVEL) or "item level"
local nativeCraftingReagent = _G.PROFESSIONS_USED_IN_COOKING and lower(_G.PROFESSIONS_USED_IN_COOKING) or nil

local scanningTip = CreateFrame("GameTooltip", "muteCatJunkScanningTip", nil, "GameTooltipTemplate")
scanningTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function SafeLowerText(value)
    if type(value) == "string" then
        return lower(value)
    end
    return ""
end

local function GetBagTooltipLinesFromScanningTip(bag, slot)
    scanningTip:ClearLines()
    scanningTip:SetBagItem(bag, slot)

    local lines = {}
    for i = 1, scanningTip:NumLines() do
        local left = _G["muteCatJunkScanningTipTextLeft" .. i]
        local right = _G["muteCatJunkScanningTipTextRight" .. i]
        lines[#lines + 1] = {
            leftText = left and left:GetText() or nil,
            rightText = right and right:GetText() or nil,
        }
    end
    return lines
end

local function GetBagTooltipInfo(bag, slot)
    local t = C_TooltipInfo.GetBagItem(bag, slot)
    if t then
        -- Retail tooltips can require arg surfacing before left/right text is present.
        if TooltipUtil and TooltipUtil.SurfaceArgs then
            TooltipUtil.SurfaceArgs(t)
            if t.lines then
                for _, line in ipairs(t.lines) do
                    TooltipUtil.SurfaceArgs(line)
                end
            end
        end
    end

    if not (t and t.lines and #t.lines > 0) then
        return { lines = GetBagTooltipLinesFromScanningTip(bag, slot) }
    end

    local hasText = false
    for _, line in ipairs(t.lines) do
        if line and (line.leftText or line.rightText) then
            hasText = true
            break
        end
    end
    if not hasText then
        return { lines = GetBagTooltipLinesFromScanningTip(bag, slot) }
    end

    return t
end

local function GetItemIDFromLink(itemLink)
    if not itemLink then return nil end
    local itemID = C_Item.GetItemInfoInstant(itemLink)
    if type(itemID) == "number" and itemID > 0 then
        return itemID
    end
    return nil
end

local function GetAuctionPrice(itemLink, itemID)
    if not (Auctionator and Auctionator.API and Auctionator.API.v1) then
        return nil
    end

    local api = Auctionator.API.v1

    if itemLink and api.GetAuctionPriceByItemLink then
        local ok, price = pcall(api.GetAuctionPriceByItemLink, CALLER_ID, itemLink)
        if ok and type(price) == "number" then
            return price
        end
    end

    if itemID and api.GetAuctionPriceByItemID then
        local ok, price = pcall(api.GetAuctionPriceByItemID, CALLER_ID, itemID)
        if ok and type(price) == "number" then
            return price
        end
    end

    return nil
end

local function GetProfitCopper(itemLink, itemID, vendorUnitPrice, bag, slot)
    local vendor = type(vendorUnitPrice) == "number" and vendorUnitPrice or 0
    if vendor <= 0 and bag and slot then
        -- Try sync price API for bag items if GetItemInfo failed
        local price = C_Item.GetItemPrice(ItemLocation:CreateFromBagAndSlot(bag, slot))
        if price and price > 0 then vendor = price end
    end

    local auction = GetAuctionPrice(itemLink, itemID)
    local netAuction = vendor -- Vendor fallback when no AH data is available.
    if type(auction) == "number" then
        netAuction = floor(auction * AH_NET_FACTOR)
    end
    return netAuction - vendor
end

local function ReportEvalError(err)
    local msg = tostring(err or "unknown")
    local now = GetTime and GetTime() or 0
    if msg ~= lastEvalError or (now - lastEvalErrorAt) > 2 then
        lastEvalError = msg
        lastEvalErrorAt = now
        print("|cffff5555muteCat Junk error:|r " .. msg)
    end
end

local function IsCraftingReagentInTooltip(bag, slot)
    local t = GetBagTooltipInfo(bag, slot)
    if not (t and t.lines) then
        return false
    end

    for _, l in ipairs(t.lines) do
        local txt = SafeLowerText(l.leftText)
        local rtxt = SafeLowerText(l.rightText)
        if nativeCraftingReagent and find(txt, nativeCraftingReagent, 1, true) then
            return true
        end
        if nativeCraftingReagent and find(rtxt, nativeCraftingReagent, 1, true) then
            return true
        end
        if find(txt, "crafting reagent", 1, true) or find(txt, "classic crafting reagent", 1, true) then
            return true
        end
        if find(txt, "handwerksreagenz", 1, true) then
            return true
        end
        if find(rtxt, "crafting reagent", 1, true) or find(rtxt, "classic crafting reagent", 1, true) then
            return true
        end
        if find(rtxt, "handwerksreagenz", 1, true) then
            return true
        end
    end

    return false
end

local function IsCraftingMat(bag, slot, classID, isCraftingReagent, subTypeText)
    if isCraftingReagent then return true end
    
    local subType = SafeLowerText(subTypeText)
    local hasReagentSubType = false
    if subType ~= "" then
        if nativeCraftingReagent and find(subType, nativeCraftingReagent, 1, true) then
            hasReagentSubType = true
        end
        if find(subType, "reagent", 1, true) or find(subType, "reagenz", 1, true) then
            hasReagentSubType = true
        end
        if find(subType, "handwerksreagenz", 1, true) then
            hasReagentSubType = true
        end
    end

    -- Match based on Class IDs or names in Tooltip
    return classID == tradeGoodsClassID
        or classID == reagentClassID
        or hasReagentSubType
        or IsCraftingReagentInTooltip(bag, slot)
end

-----------------------------------------------------------
-- Helper: Scrape Item Tooltip Data
-- Parses tooltip lines for localized "Soulbound" and "Item Level" numbers
-----------------------------------------------------------
local function ParseTooltip(bag, slot)
    local bind, bound, lvl = false, false, nil
    local t = GetBagTooltipInfo(bag, slot)
    
    if t and t.lines then
        for _, l in ipairs(t.lines) do
            local txt = SafeLowerText(l.leftText)
            
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

    local itemID = info.itemID or GetItemIDFromLink(info.hyperlink)
    local itemKey = itemID or info.hyperlink
    
    -- Use Instant IDs to avoid cache misses
    local _, _, _, _, _, instantClassID = C_Item.GetItemInfoInstant(itemKey)
    
    -- Get more info, but handle nil (async)
    local _, _, rarity, baseLvl, minLvl, _, subType, _, equipLoc, _, sellPrice, classID, _, bindType, _, _, isCraftingReagent = C_Item.GetItemInfo(itemKey)
    
    local resolvedClassID = classID or instantClassID
    local resolvedRarity = rarity or info.quality

    if resolvedRarity == 5 or resolvedRarity == 6 then return false end

    -- Manual hard overrides.
    if itemID and forceKeepItemIDs[itemID] then return false end
    if itemID and forceSellItemIDs[itemID] then return true end
    
    -- 1. True Gray Junk
    if resolvedRarity == 0 then return true end

    -- 2. Bound Gear Checks (Armor/Weapons/Profession Gear)
    if equipLoc and equipLoc ~= "" and (resolvedClassID == 2 or resolvedClassID == 4 or resolvedClassID == 19) then
        local bind, bound, tLvl = ParseTooltip(bag, slot)
        if bindType == 8 then bound = true end
        if info.isBound then bind = true end
        
        -- BoE Gear is strictly kept
        if not bind and not bound then return false end
        
        -- Special: Low requirement account gear
        if bound and minLvl and minLvl < 90 then return true end

        -- Level Thresholds (Midnight Values)
        -- TWW BiS is ~170 after squish. Midnight S1 starts at 230+.
        local pcallOk, cLvl = pcall(C_Item.GetCurrentItemLevel, loc)
        local lvl = tLvl or (pcallOk and cLvl) or baseLvl
        
        local pLvl = UnitLevel("player")
        -- Sell old expansion gear when reaching Midnight levels (Squish-adjusted for 12.0)
        -- TWW BiS is ~170 after squish. Midnight S1 starts at 230+.
        if pLvl >= 80 and lvl < 80 then return true end -- Legacy junk
        if pLvl >= 90 and lvl < 150 then return true end -- Old/Low TWW gear
        if pLvl >= 100 and lvl < 200 then return true end -- Early Midnight bridge gear
    end

    -- 3. Consumables: always keep listed Midnight consumables, otherwise profit based.
    if resolvedClassID == consumableClassID then
        if itemID and midnightConsumableKeepIDs[itemID] then
            return false
        end

        local profit = GetProfitCopper(info.hyperlink, itemID, sellPrice, bag, slot)
        return profit < MIN_PROFIT_COPPER
    end

    -- 4. Crafting mats: keep Midnight mats, sell non-Midnight mats below profit threshold.
    if IsCraftingMat(bag, slot, resolvedClassID, isCraftingReagent, subType) then
        if itemID and midnightCraftingMatsByID[itemID] then
            return false
        end

        local profit = GetProfitCopper(info.hyperlink, itemID, sellPrice, bag, slot)
        return profit < MIN_PROFIT_COPPER
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
        -- Iterate through all possible player bags (Backpack to Reagent Bag)
        for bag = 0, maxBagIndex do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            if numSlots > 0 then
                for slot = 1, numSlots do
                    local ok, junk = pcall(IsJunk, bag, slot)
                    if ok and junk then 
                        table.insert(queue, {bag=bag, slot=slot})
                    elseif not ok then
                        ReportEvalError(junk)
                    end
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
            if not ok then
                ReportEvalError(junk)
            end
            return ok and junk
        end)
    end
end)
