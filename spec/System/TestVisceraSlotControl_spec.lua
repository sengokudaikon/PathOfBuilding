describe("Viscera slot picker", function()
	local originalPopups

	before_each(function()
		originalPopups = main.popups
		newBuild()
		main.popups = { }
	end)

	after_each(function()
		main.popups = originalPopups
	end)

	local function findItem(slot, name)
		for index in ipairs(slot.items) do
			local item = slot:GetItemForIndex(index)
			if item and (item.title or item.name) == name then
				return index, item
			end
		end
		error("Missing slot candidate: "..name)
	end

	it("offers only compatible catalogue parts in all four empty slots", function()
		for _, name in ipairs({ "Head", "Body", "Arm", "Leg" }) do
			local slot = build.itemsTab.slots[name]
			assert.is_true(slot:IsEnabled())
			assert.equals(0, slot.selItemId)
			assert.equals("None", slot.list[1])
			local previous = ""
			for index = 2, #slot.items do
				local item = slot:GetItemForIndex(index)
				assert.equals("Viscera", item.type)
				assert.is_true(build.itemsTab:IsItemValidForSlot(item, name))
				assert.is_true(previous <= item.title:lower())
				previous = item.title:lower()
			end
		end
		assert.equals(0, #build.itemsTab.itemOrderList)
		assert.is_false(build.itemsTab.slots.Helmet:IsEnabled())
	end)

	it("equips a private copy of the selected catalogue part and applies its stats", function()
		local tab, slot = build.itemsTab, build.itemsTab.slots.Arm
		local index, candidate = findItem(slot, "Lesser Warden's Arm")
		local raw, id = candidate.raw, candidate.id
		local before = build.calcsTab.mainOutput.Life
		slot:SetSel(index)
		runCallback("OnFrame")
		assert.equals(1, #tab.itemOrderList)
		assert.is_true(slot.selItemId > 0)
		local equipped = tab.items[slot.selItemId]
		assert.is_false(equipped == candidate)
		assert.equals(candidate.name, equipped.name)
		assert.equals(id, candidate.id)
		assert.equals(raw, candidate.raw)
		assert.equals(slot.selItemId, tab.activeItemSet.Arm.selItemId)
		assert.is_true(build.calcsTab.mainOutput.Life > before)
	end)

	it("previews the stat comparison without adding or equipping a part", function()
		local tab, slot = build.itemsTab, build.itemsTab.slots.Arm
		local index, candidate = findItem(slot, "Lesser Warden's Arm")
		local calculate, baseline = build.calcsTab:GetMiscCalculator()
		local preview = calculate({ repSlotName = "Arm", repItem = candidate })
		assert.is_true(preview.Life > baseline.Life)
		local tooltip = new("Tooltip"):Tooltip()
		slot.dropped = true
		slot.tooltipFunc(tooltip, "HOVER", index, slot.list[index])
		local text = ""
		for _, line in ipairs(tooltip.lines) do
			text = text..(line.text or "").."\n"
		end
		assert.is_truthy(text:find("Equipping this item in Arm", 1, true))
		assert.equals(0, #tab.itemOrderList)
		assert.equals(0, slot.selItemId)
		slot:SetSel(index)
		runCallback("OnFrame")
		assert.equals(preview.Life, build.calcsTab.mainOutput.Life)
	end)

	it("reuses an owned part instead of offering or creating a duplicate", function()
		local tab, slot = build.itemsTab, build.itemsTab.slots.Arm
		local index = findItem(slot, "Lesser Warden's Arm")
		slot:SetSel(index)
		local itemId = slot.selItemId
		tab.items[itemId].uniqueID = "imported-character-part"
		slot:SetSel(1)
		local found = 0
		for row in ipairs(slot.items) do
			local item = slot:GetItemForIndex(row)
			if item and item.title == "Lesser Warden's Arm" then
				found = found + 1
				assert.equals(itemId, slot.items[row])
			end
		end
		assert.equals(1, found)
		slot:SetSel((findItem(slot, "Lesser Warden's Arm")))
		assert.equals(itemId, slot.selItemId)
		assert.equals("imported-character-part", tab.items[itemId].uniqueID)
		assert.equals(1, #tab.itemOrderList)
	end)

	it("supports undo and redo including the new item", function()
		local tab, slot = build.itemsTab, build.itemsTab.slots.Arm
		slot:SetSel((findItem(slot, "Lesser Warden's Arm")))
		local itemId = slot.selItemId
		tab:Undo()
		assert.equals(0, slot.selItemId)
		assert.equals(0, #tab.itemOrderList)
		assert.is_true(slot:IsEnabled())
		tab:Redo()
		assert.equals(itemId, slot.selItemId)
		assert.equals("Lesser Warden's Arm", tab.items[itemId].title)
	end)

	it("persists the chosen item using ordinary positive item IDs", function()
		local slot = build.itemsTab.slots.Arm
		slot:SetSel((findItem(slot, "Lesser Warden's Arm")))
		local itemId = slot.selItemId
		local xml = build:SaveDB("code")
		loadBuildFromXML(xml)
		assert.equals(itemId, build.itemsTab.slots.Arm.selItemId)
		assert.equals("Lesser Warden's Arm", build.itemsTab.items[itemId].title)
		assert.equals(1, #build.itemsTab.itemOrderList)
		assert.is_true(build.itemsTab.slots.Head:IsEnabled())
	end)

	it("changes only the active item set", function()
		local tab, slot = build.itemsTab, build.itemsTab.slots.Arm
		tab:NewItemSet(2)
		tab:SetActiveItemSet(2)
		slot:SetSel((findItem(slot, "Lesser Warden's Arm")))
		assert.equals(0, tab.itemSets[1].Arm.selItemId)
		assert.is_true(tab.itemSets[2].Arm.selItemId > 0)
		tab:SetActiveItemSet(1)
		assert.equals(0, slot.selItemId)
		assert.is_true(slot:IsEnabled())
	end)

	it("filters by typing and selects the correct filtered catalogue row", function()
		local slot = build.itemsTab.slots.Arm
		slot.dropped = true
		slot:OnChar("Warden")
		assert.is_true(slot:GetDropCount() > 0)
		assert.is_true(slot:GetDropCount() < #slot.items)
		local index = findItem(slot, "Lesser Warden's Arm")
		slot:SetSel(slot:ListIndexToDropIndex(index))
		assert.equals("Lesser Warden's Arm", build.itemsTab.items[slot.selItemId].title)
	end)

	it("enables an empty slot when the catalogue finishes loading", function()
		local slot = build.itemsTab.slots.Arm
		local _, candidate = findItem(slot, "Lesser Warden's Arm")
		slot.db = { loading = true, list = { candidate } }
		slot:Populate()
		assert.is_false(slot:IsEnabled())
		slot.db.loading = nil
		slot:Draw({ x = 0, y = 0, width = 1920, height = 1080 })
		assert.is_true(slot:IsEnabled())
		assert.equals(2, #slot.items)
	end)
end)
