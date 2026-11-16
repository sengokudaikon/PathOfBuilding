describe("Imbued support import and selection", function()
	before_each(function()
		newBuild()
	end)

	local function importImbuedSupport(name)
		build.importTab:ImportItemsAndSkills({
			level = 20,
			equipment = { {
				id = "imbued-helmet",
				frameType = 0,
				name = "",
				typeLine = "Iron Hat",
				inventoryId = "Helm",
				ilvl = 10,
				properties = {},
				sockets = { { group = 0, sColour = "B" } },
				socketedItems = { {
					socket = 0,
					support = false,
					typeLine = "Fireball",
					properties = { { name = "Level", values = { { "1", 0 } } } },
					builtInSupport = name,
				} },
			} },
		}, true, true, true)
		runCallback("OnFrame")
		build.skillsTab.controls.groupList:SelectIndex(1)
		return build.skillsTab.socketGroupList[1]
	end

	local function assertImmolate(slot)
		local skills = build.skillsTab
		assert.equals("Immolate", skills.displayGroup.imbuedSupport)
		assert.equals("Immolate", skills.controls.imbuedSupport.buf)
		assert.equals("SupportImmolate", skills.imbuedSupportBySlot[slot].id)
		local gemId = skills.controls.imbuedSupport.gemId
		assert.equals("Default:", gemId:sub(1, 8))
		assert.equals("Immolate", skills.controls.imbuedSupport.gems[gemId].name)
		local found
		for _, support in ipairs(build.calcsTab.mainEnv.player.mainSkill.supportList) do
			if support.grantedEffect.id == "SupportImmolate" then
				found = true
				assert.equals(1, support.level)
			end
		end
		assert.is_true(found)
	end

	for _, name in ipairs({ "Supported by Level 1 [SupportImmolate|Immolate]", "Supported by Level 1 Immolate", "Supported by Level 1 Immolate Support" }) do
		it("imports and selects " .. name, function()
			local group = importImbuedSupport(name)
			assert.equals("Immolate", group.imbuedSupport)
			assertImmolate("Helmet")
		end)
	end

	it("repairs tagged support names in an already saved build", function()
		importImbuedSupport("Supported by Level 1 Immolate")
		local xml = build:SaveDB("code"):gsub('imbuedSupport="Immolate"', 'imbuedSupport="[SupportImmolate|Immolate]"')
		loadBuildFromXML(xml)
		build.skillsTab.controls.groupList:SelectIndex(1)
		assertImmolate("Helmet")
		assert.is_truthy(build:SaveDB("code"):find('imbuedSupport="Immolate"', 1, true))
	end)

	it("can select an existing group with a tagged support before rebuilding the slot map", function()
		local group = importImbuedSupport("Supported by Level 1 Immolate")
		group.imbuedSupport = "[SupportImmolate|Immolate]"
		build.skillsTab:SetDisplayGroup(group)
		assertImmolate("Helmet")
	end)

	it("keeps an unknown saved support editable without applying a different support", function()
		local group = importImbuedSupport("Supported by Level 1 Immolate")
		group.imbuedSupport = "[UnknownSupport|Unknown Support]"
		build.skillsTab:RebuildImbuedSupportBySlot()
		build.skillsTab:SetDisplayGroup(group)
		assert.is_nil(build.skillsTab.controls.imbuedSupport.gemId)
		assert.equals("[UnknownSupport|Unknown Support]", build.skillsTab.controls.imbuedSupport.buf)
		assert.is_nil(build.skillsTab.imbuedSupportBySlot.Helmet)
		build.skillsTab.controls.imbuedSupportClear:Click()
		assert.is_nil(group.imbuedSupport)
	end)

	it("loads an unknown saved support without failing when the group is selected", function()
		importImbuedSupport("Supported by Level 1 Immolate")
		local xml = build:SaveDB("code"):gsub('imbuedSupport="Immolate"', 'imbuedSupport="No Such Support"')
		loadBuildFromXML(xml)
		build.skillsTab.controls.groupList:SelectIndex(1)
		assert.is_nil(build.skillsTab.controls.imbuedSupport.gemId)
		assert.is_nil(build.skillsTab.imbuedSupportBySlot.Helmet)
		assert.equals("No Such Support", build.skillsTab.controls.imbuedSupport.buf)
	end)

	it("does not resolve an active skill as an imbued support", function()
		assert.is_nil(build.skillsTab:ResolveImbuedSupport("Fireball"))
	end)
end)
