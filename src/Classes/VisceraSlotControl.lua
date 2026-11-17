-- Path of Building
--
-- Class: Viscera Slot
-- Equipment dropdown with compatible parts from the Viscera catalogue.
--
local VisceraSlotClass = newClass("VisceraSlotControl", "ItemSlotControl")

local function partName(item)
	return item.title and item.title ~= "" and item.title or item.name
end

function VisceraSlotClass:VisceraSlotControl(anchor, x, y, itemsTab, slotName)
	self:ItemSlotControl(anchor, x, y, itemsTab, slotName)
	self.db = main.visceraDB
	self.catalogueItems = { }
	self.catalogueLoaded = false
	self.maxDroppedWidth = 500
	local itemTooltip = self.tooltipFunc
	self.tooltipFunc = function(tooltip, mode, index, value)
		if mode == "BODY" and self.items[index] == 0 and not main.popups[1] then
			tooltip:Clear()
			tooltip:AddLine(14, "Choose compatible Viscera here. Type to search; hover over a part to compare its stats.")
		else
			itemTooltip(tooltip, mode, index, value)
		end
	end
	return self
end

function VisceraSlotClass:GetItemForIndex(index)
	local itemId = self.items[index]
	return self.itemsTab.items[itemId] or self.catalogueItems[itemId]
end

function VisceraSlotClass:Populate()
	self.ItemSlotControl.Populate(self)
	for index = 2, #self.items do
		local item = self.itemsTab.items[self.items[index]]
		self.list[index] = colorCodes[item.rarity]..partName(item)
	end
	wipeTable(self.catalogueItems)
	self.catalogueLoaded = not self.db.loading
	if self.db.loading then return end

	local owned = { }
	for _, item in pairs(self.itemsTab.items) do
		owned[item.raw] = true
	end
	local candidates = { }
	for _, item in pairs(self.db.list) do
		if not owned[item.raw] and self.itemsTab:IsItemValidForSlot(item, self.slotName) then
			table.insert(candidates, item)
		end
	end
	table.sort(candidates, function(a, b) return partName(a):lower() < partName(b):lower() end)
	for index, item in ipairs(candidates) do
		-- Catalogue keys never become equipped IDs; selection creates a build-owned copy.
		local key = -index
		self.catalogueItems[key] = item
		table.insert(self.items, key)
		table.insert(self.list, { label = colorCodes[item.rarity]..partName(item), detail = "^8Catalogue" })
	end
	self:CheckDroppedWidth(true)
	if self:IsSearchActive() then
		self:UpdateSearch()
	end
end

function VisceraSlotClass:SelectItem(index)
	local itemId = self.items[index]
	local candidate = self.catalogueItems[itemId]
	if candidate then
		if not self.itemsTab.undo[1] then
			self.itemsTab:ResetUndo()
		end
		local item = new("Item"):Item(candidate.raw)
		self.itemsTab:AddItem(item, true)
		self:EquipItem(item.id)
	else
		self.ItemSlotControl.SelectItem(self, index)
	end
end

function VisceraSlotClass:Draw(viewPort)
	if not self.catalogueLoaded and not self.db.loading then
		self:Populate()
	end
	self.ItemSlotControl.Draw(self, viewPort)
end
