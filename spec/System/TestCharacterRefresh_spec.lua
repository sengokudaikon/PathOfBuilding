describe("Character refresh", function()
	local dkjson = require "dkjson"
	local original = {}
	local tab, controls, listRequests, characterRequests, confirmation
	local now

	local function character(name, league, level)
		return { name = name, league = league or "Standard", level = level or 10, class = "Witch", realm = "pc" }
	end

	local function fetchList(characters)
		controls.accountRealmFetchButton:Click()
		listRequests[#listRequests].callback({ characters = characters })
	end

	before_each(function()
		for _, key in ipairs({ "api", "SaveSettings", "OpenConfirmPopup", "lastRealm", "lastLeague", "lastCharacterHash", "lastToken", "lastRefreshToken", "tokenExpiry" }) do
			original[key] = main[key]
		end
		original.time = os.time
		original.downloadPage = launch.DownloadPage
		now = os.time()
		os.time = function() return now end
		main.lastRealm, main.lastLeague, main.lastCharacterHash = nil, nil, nil
		main.SaveSettings = function() end
		main.api = new("PoEAPI"):PoEAPI("access-token", "refresh-token", now + 3600)
		listRequests, characterRequests, confirmation = {}, {}, nil
		main.api.DownloadCharacterList = function(_, realm, callback)
			table.insert(listRequests, { realm = realm, callback = callback })
		end
		main.api.DownloadCharacter = function(_, realm, name, callback)
			table.insert(characterRequests, { realm = realm, name = name, callback = callback })
		end
		main.OpenConfirmPopup = function(_, title, message, label, callback)
			confirmation = { title = title, message = message, label = label, callback = callback }
		end
		newBuild()
		tab, controls = build.importTab, build.importTab.controls
	end)

	after_each(function()
		for _, key in ipairs({ "api", "SaveSettings", "OpenConfirmPopup", "lastRealm", "lastLeague", "lastCharacterHash", "lastToken", "lastRefreshToken", "tokenExpiry" }) do
			main[key] = original[key]
		end
		os.time = original.time
		launch.DownloadPage = original.downloadPage
	end)

	it("refreshes a fetched list and preserves the current league and character", function()
		fetchList({ character("Alpha"), character("Bravo", "Challenge"), character("Charlie", "Challenge") })
		controls.charSelectLeague:SetSel(1) -- Challenge
		controls.charSelect:SelByValue("Charlie", "label")
		main.lastLeague = "Standard"
		tab.lastCharacterHash = common.sha1("Alpha")
		assert.equals("Refresh Characters", controls.accountRealmFetchButton:GetProperty("label"))
		assert.is_true(controls.accountRealmFetchButton:IsEnabled())

		fetchList({ character("Alpha"), character("Bravo", "Challenge"), character("Charlie", "Challenge", 30), character("Delta", "Challenge") })

		assert.equals(2, #listRequests)
		assert.equals("Challenge", controls.charSelectLeague:GetSelValue())
		assert.equals("Charlie", controls.charSelect:GetSelValue().label)
		assert.equals(30, controls.charSelect:GetSelValue().char.level)
		assert.equals(3, #controls.charSelect.list)
		assert.equals("access-token", main.api.authToken)
	end)

	it("allows an empty account to be fetched again when a character is created", function()
		fetchList({})
		assert.is_false(controls.charRefresh:IsEnabled())
		fetchList({ character("NewCharacter") })
		assert.equals("NewCharacter", controls.charSelect:GetSelValue().label)
		assert.is_true(controls.charRefresh:IsEnabled())
	end)

	it("keeps the old list on errors and permits retry without logging in", function()
		fetchList({ character("Alpha") })
		controls.accountRealmFetchButton:Click()
		listRequests[2].callback(nil, "SSL connect error")
		assert.equals("SSL connect error", tab.oauthErrCode)
		assert.equals("Alpha", controls.charSelect:GetSelValue().label)
		assert.is_false(tab.oauthLoading)
		assert.is_true(controls.accountRealmFetchButton:IsEnabled())
		fetchList({ character("Alpha", "Standard", 20) })
		assert.is_nil(tab.oauthErrCode)
		assert.equals(20, controls.charSelect:GetSelValue().char.level)
	end)

	it("handles malformed list responses without losing the selection or staying busy", function()
		fetchList({ character("Alpha") })
		controls.accountRealmFetchButton:Click()
		listRequests[2].callback({})
		assert.equals("Could not fetch characters", tab.oauthErrCode)
		assert.equals("Alpha", controls.charSelect:GetSelValue().label)
		assert.is_true(controls.charRefresh:IsEnabled())
	end)

	it("prevents overlapping fetches, imports and realm changes", function()
		fetchList({ character("Alpha") })
		controls.charRefresh:Click()
		for _, name in ipairs({ "accountRealmFetchButton", "charRefresh", "charImportTree", "charImportItems" }) do
			assert.is_false(controls[name]:IsEnabled())
			controls[name]:Click()
		end
		for _, name in ipairs({ "accountRealm", "charSelectLeague", "charSelect", "logoutApiButton", "charImportTreeClearJewels", "charImportItemsClearItems", "charImportItemsClearSkills", "charImportItemsIgnoreWeaponSwap" }) do
			assert.is_false(controls[name]:IsEnabled())
		end
		assert.equals(1, #listRequests)
		assert.equals(1, #characterRequests)
		characterRequests[1].callback(nil, "Connection failed")
		assert.is_true(controls.charRefresh:IsEnabled())
	end)

	it("shows fetching while refreshing a previously fetched list", function()
		fetchList({ character("Alpha") })
		controls.accountRealmFetchButton:Click()
		assert.matches("Fetching%.%.%.", controls.charImportStatusLabel:GetProperty("label"))
		assert.equals("Fetching...", controls.accountRealmFetchButton:GetProperty("label"))
		assert.is_false(controls.charRefresh:IsEnabled())
		listRequests[2].callback({ characters = { character("Alpha") } })
		assert.is_false(tab.oauthFetchingCharacters)
	end)

	for _, action in ipairs({ "list", "character" }) do
		it("respects rate limits when refreshing the " .. action .. " and recovers after the cooldown", function()
			fetchList({ character("Alpha") })
			local button = action == "list" and controls.accountRealmFetchButton or controls.charRefresh
			local requests = action == "list" and listRequests or characterRequests
			button:Click()
			requests[#requests].callback(nil, "Response code: 429", now + 30)
			assert.is_false(tab.oauthLoading)
			assert.is_false(button:IsEnabled())
			local count = #requests
			button:Click()
			assert.equals(count, #requests)
			now = now + 30
			assert.is_true(button:IsEnabled())
			button:Click()
			assert.equals(count + 1, #requests)
		end)
	end

	it("imports tree and items from one fresh response using the selected import options", function()
		fetchList({ character("Alpha") })
		controls.charImportTreeClearJewels.state = false
		controls.charImportItemsClearItems.state = false
		controls.charImportItemsClearSkills.state = true
		controls.charImportItemsIgnoreWeaponSwap.state = true
		local importedTree, importedItems
		tab.ImportPassiveTreeAndJewels = function(_, data, deleteJewels)
			importedTree = data
			assert.is_false(deleteJewels)
		end
		tab.ImportItemsAndSkills = function(_, data, clearItems, clearSkills, ignoreWeaponSwap)
			importedItems = data
			assert.is_false(clearItems)
			assert.is_true(clearSkills)
			assert.is_true(ignoreWeaponSwap)
		end
		controls.charRefresh:Click()
		assert.equals(1, #characterRequests)
		assert.equals("pc", characterRequests[1].realm)
		assert.equals("Alpha", characterRequests[1].name)
		local freshData = character("Alpha", "Standard", 20)
		characterRequests[1].callback({ character = freshData })
		assert.is_true(importedTree == freshData)
		assert.is_true(importedItems == freshData)
		assert.equals(common.sha1("Alpha"), tab.lastCharacterHash)
		assert.is_false(tab.oauthLoading)
	end)

	it("refreshes the actual build again after the character levels up", function()
		local file = assert(io.open("../spec/System/SampleCharacter.json", "r"))
		local data = dkjson.decode(file:read("*a")).character
		file:close()
		fetchList({ data })
		controls.charRefresh:Click()
		characterRequests[1].callback({ character = data })
		runCallback("OnFrame")
		assert.equals(99, build.characterLevel)
		assert.equals("Hierophant", build.spec.curAscendClassName)
		assert.is_true(#build.itemsTab.itemOrderList > 0)
		assert.is_true(#build.skillsTab.socketGroupList > 0)

		controls.charRefresh:Click()
		assert.is_not_nil(confirmation)
		assert.equals(1, #characterRequests)
		confirmation.callback()
		data = copyTable(data)
		data.level = 100
		characterRequests[2].callback({ character = data })
		runCallback("OnFrame")
		assert.equals(100, build.characterLevel)
		assert.equals("access-token", main.api.authToken)
	end)

	it("does not change a populated build if the overwrite confirmation is cancelled", function()
		fetchList({ character("Alpha") })
		build.spec.allocNodes[4492] = build.spec.tree.nodes[4492]
		controls.charRefresh:Click()
		assert.is_not_nil(confirmation)
		assert.equals(0, #characterRequests)
		assert.is_false(tab.oauthLoading)
	end)

	it("leaves the build untouched on a failed character download", function()
		fetchList({ character("Alpha") })
		tab.ImportPassiveTreeAndJewels = function() error("must not import tree") end
		tab.ImportItemsAndSkills = function() error("must not import items") end
		controls.charRefresh:Click()
		characterRequests[1].callback(nil, "Response code: 503")
		assert.equals("Response code: 503", tab.oauthErrCode)
		assert.is_true(controls.charRefresh:IsEnabled())
		assert.equals("access-token", main.api.authToken)
	end)

	it("discards a refresh response if another build has been opened", function()
		fetchList({ character("Alpha") })
		controls.charRefresh:Click()
		local callback = characterRequests[1].callback
		newBuild()
		build.importTab.ImportPassiveTreeAndJewels = function() error("must not change the new build") end
		build.importTab.ImportItemsAndSkills = function() error("must not change the new build") end
		callback({ character = character("Alpha") })
		assert.is_false(tab.oauthLoading)
		assert.equals(1, build.characterLevel)
	end)

	it("offers authorization again when the server rejects the refreshed credentials", function()
		fetchList({ character("Alpha") })
		controls.charRefresh:Click()
		characterRequests[1].callback(nil, "Response code: 401")
		assert.is_nil(main.api.authToken)
		assert.is_true(controls.authenticateButton:IsShown())
		assert.is_false(controls.charRefresh:IsEnabled())
		assert.matches("Please login again", tab.oauthErrCode)
	end)

	it("refreshes an expired access token before downloading the character", function()
		fetchList({ character("Alpha") })
		main.api.DownloadCharacter = nil -- Exercise the real API/auth path.
		main.api.tokenExpiry = now - 1
		local urls = {}
		launch.DownloadPage = function(_, url, callback, options)
			table.insert(urls, url)
			if #urls == 1 then
				assert.equals("https://www.pathofexile.com/oauth/token", url)
				assert.matches("grant_type=refresh_token", options.body)
				callback({ body = dkjson.encode({ access_token = "renewed-token", refresh_token = "renewed-refresh", expires_in = 3600 }) })
			else
				assert.equals("Authorization: Bearer renewed-token", options.header)
				callback({ body = dkjson.encode({ character = character("Alpha") }), header = "HTTP/1.1 200 OK\n" })
			end
		end
		local imports = 0
		tab.ImportPassiveTreeAndJewels = function() imports = imports + 1 end
		tab.ImportItemsAndSkills = function() imports = imports + 1 end
		controls.charRefresh:Click()
		assert.equals(2, #urls)
		assert.equals("https://api.pathofexile.com/character/Alpha", urls[2])
		assert.equals(2, imports)
		assert.equals("renewed-token", main.api.authToken)
		assert.is_false(tab.oauthLoading)
	end)
end)
