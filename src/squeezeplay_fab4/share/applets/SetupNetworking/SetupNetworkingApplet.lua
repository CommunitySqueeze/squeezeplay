

-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------



-- stuff we use
local assert, getmetatable, ipairs, pairs, pcall, setmetatable, tonumber, tostring, type = assert, getmetatable, ipairs, pairs, pcall, setmetatable, tonumber, tostring, type

local oo                     = require("loop.simple")

local io                     = require("io")
local os                     = require("os")
local string                 = require("string")
local table                  = require("jive.utils.table")
local debug                  = require("jive.utils.debug")

local Applet                 = require("jive.Applet")
local Event                  = require("jive.ui.Event")
local Framework              = require("jive.ui.Framework")
local Icon                   = require("jive.ui.Icon")
local Label                  = require("jive.ui.Label")
local Button                 = require("jive.ui.Button")
local Group                  = require("jive.ui.Group")
local Keyboard               = require("jive.ui.Keyboard")
local Tile                   = require("jive.ui.Tile")
local RadioButton            = require("jive.ui.RadioButton")
local RadioGroup             = require("jive.ui.RadioGroup")
local SimpleMenu             = require("jive.ui.SimpleMenu")
local Surface                = require("jive.ui.Surface")
local Task                   = require("jive.ui.Task")
local Textarea               = require("jive.ui.Textarea")
local Textinput              = require("jive.ui.Textinput")
local Window                 = require("jive.ui.Window")
local Popup                  = require("jive.ui.Popup")

local Networking             = require("jive.net.Networking")

local log                    = require("jive.utils.log").logger("applets.setup")

local appletManager          = appletManager
local jnt                    = jnt

local LAYER_FRAME            = jive.ui.LAYER_FRAME
local LAYER_CONTENT_ON_STAGE = jive.ui.LAYER_CONTENT_ON_STAGE

local LAYOUT_NORTH           = jive.ui.LAYOUT_NORTH
local LAYOUT_EAST            = jive.ui.LAYOUT_EAST
local LAYOUT_SOUTH           = jive.ui.LAYOUT_SOUTH
local LAYOUT_WEST            = jive.ui.LAYOUT_WEST
local LAYOUT_CENTER          = jive.ui.LAYOUT_CENTER
local LAYOUT_NONE            = jive.ui.LAYOUT_NONE


-- configuration
local CONNECT_TIMEOUT = 30
local WPS_WALK_TIMEOUT = 120		-- WPS walk timeout


module(..., Framework.constants)
oo.class(_M, Applet)


function init(self)
	self.wlanIface = Networking:wirelessInterface(jnt)
	self.ethIface = Networking:wiredInterface(jnt)

	self.scanResults = {}
end


function _helpAction(self, window, titleText, bodyText)
	window:addActionListener("help", self, function()
		local window = Window("help_info", self:string(titleText), "helptitle")
		window:setAllowScreensaver(false)

		window:setButtonAction("rbutton", "more_help")
		window:addActionListener("more_help", self, function()
			appletManager:callService("supportMenu")
		end)

		local textarea = Textarea("text", self:string(bodyText))
		window:addWidget(textarea)
		self:tieAndShowWindow(window)
	end)

	window:setButtonAction("rbutton", "help")
end


-- start network setup flow
function setupNetworking(self, setupNext)
	self.mode = "setup"

	self.setupNext = setupNext

	_wirelessRegion(self, self.wlanIface)
end


-- start network settings flow
function settingsNetworking(self)
	self.mode = "settings"

	local topWindow = Framework.windowStack[1]
	self.setupNext = function()
		local stack = Framework.windowStack
		for i=1,#stack do
			if stack[i] == topWindow then
				for j=i-1,1,-1 do
					stack[j]:hide(Window.transitionPushLeft)
				end
			end
		end
	end

	_wirelessRegion(self, self.wlanIface)
end


-------- CONNECTION TYPE --------

-- connection type (ethernet or wireless)
function _connectionType(self)
	log:debug('_connectionType')

	assert(self.wlanIface or self.ethIface)

	-- short cut if only one interface is available
	if not self.wlanIface then
		_networkScan(self, self.ethIface)
	elseif not self.ethIface then
		_wirelessRegion(self, self.wlanIface)
	end

	-- ask the user to choose
	local window = Window("text_list", self:string("NETWORK_CONNECTION_TYPE"), "setup")
	window:setAllowScreensaver(false)

	local connectionMenu = SimpleMenu("menu")

	connectionMenu:addItem({
		iconStyle = 'wlan',
		text = (self:string("NETWORK_CONNECTION_TYPE_WIRELESS")),
		sound = "WINDOWSHOW",
		callback = function()
			_networkScan(self, self.wlanIface)
		end,
		weight = 1
	})
	
	connectionMenu:addItem({
		iconStyle = 'wired',
		text = (self:string("NETWORK_CONNECTION_TYPE_WIRED")),
		sound = "WINDOWSHOW",
		callback = function()
			_networkScan(self, self.ethIface)
		end,
		weight = 2
	})

	window:addWidget(connectionMenu)

	_helpAction(self, window, "NETWORK_CONNECTION_HELP", "NETWORK_CONNECTION_HELP_BODY")

	self:tieAndShowWindow(window)
end


-------- WIRELESS REGION --------

-- select wireless region
function _wirelessRegion(self, wlan)
	-- skip region if already set and not in setup mode
	if self:getSettings()['region'] and self.mode ~= "setup" then
		return _connectionType(self)
	end

	local window = Window("text_list", self:string("NETWORK_REGION"), "setup")
	window:setAllowScreensaver(false)

	local region = wlan:getRegion()

	local menu = SimpleMenu("menu")

	for name in wlan:getRegionNames() do
		log:debug("region=", region, " name=", name)
		local item = {
			text = self:string("NETWORK_REGION_" .. name),
			iconStyle = "region_" .. name,
			sound = "WINDOWSHOW",
			callback = function()
					if region ~= name then
						wlan:setRegion(name)
					end
					self:getSettings()['region'] = name
                       			self:storeSettings()

					_connectionType(self)
				   end
		}

		menu:addItem(item)
		if region == name then
			menu:setSelectedItem(item)
		end
	end

	window:addWidget(menu)

	_helpAction(self, window, "NETWORK_REGION_HELP", "NETWORK_REGION_HELP_BODY")

	self:tieAndShowWindow(window)
end


-------- NETWORK SCANNING --------

-- scan menu: update currect SSID
function _setCurrentSSID(self, ssid)
	if self.currentSSID == ssid then
		return
	end

	if self.currentSSID and self.scanResults[self.currentSSID] then
		local item = self.scanResults[self.currentSSID].item
		item.style = nil
		if self.scanMenu then
			self.scanMenu:updatedItem(item)
		end
	end

	self.currentSSID = ssid
end


-- scan menu: add network
function _addNetwork(self, iface, ssid)
	local item = {
		text = iface:isWireless() and ssid or tostring(self:string("NETWORK_ETHERNET")),
		arrow = Icon("icon"),
		sound = "WINDOWSHOW",
		callback = function()
			_enterPassword(self, iface, ssid)
		end,
		weight = iface:isWireless() and 1 or 2
	}
		      
	self.scanResults[ssid] = {
		item = item,            -- menu item
		iface = iface,		-- interface
		-- flags = nil,         -- beacon flags
		-- bssid = nil,         -- bssid if know from scan
		-- id = nil             -- wpa_ctrl id if configured
	}

	if self.scanMenu then
		self.scanMenu:addItem(item)
	end
end


-- perform scan on the network interface
function _networkScan(self, iface)
	local popup = Popup("waiting_popup")
	popup:setAllowScreensaver(false)
	popup:ignoreAllInputExcept({"back"})

        popup:addWidget(Icon("icon_connecting"))
        popup:addWidget(Label("text", self:string("NETWORK_FINDING_NETWORKS")))

	local status = Label("subtext", self:string("NETWORK_FOUND_NETWORKS", 0))
	popup:addWidget(status)

        popup:addTimer(1000, function()
			local numNetworks = 0

			local results = iface:scanResults()
			for k, v in pairs(results) do
				numNetworks = numNetworks + 1
			end

			status:setValue(self:string("NETWORK_FOUND_NETWORKS", tostring(numNetworks) ) )
		end)

	-- start network scan
	iface:scan(function()
		_networkScanComplete(self, iface)
	end)

	-- or timeout after 10 seconds if no networks are found
	popup:addTimer(10000,
		function()
			ifaceCount = 0
			_networkScanComplete(self, iface)
		end)

	self:tieAndShowWindow(popup)
end


-- network scan is complete, show results
function _networkScanComplete(self, iface)
	self.scanResults = {}

	-- for ethernet, automatically connect
	if not iface:isWireless() then
		_scanResults(self, iface)

		return _connect(self, iface, iface:getName(), true)
	end

	local window = Window("text_list", self:string("NETWORK_WIRELESS_NETWORKS"), 'setuptitle')
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu")
	menu:setComparator(SimpleMenu.itemComparatorWeightAlpha)

	-- add hidden ssid menu
	menu:addItem({
		text = self:string("NETWORK_ENTER_ANOTHER_NETWORK"),
		sound = "WINDOWSHOW",
		callback = function()
			_chooseEnterSSID(self, iface)
		end,
		weight = 3
	})

	window:addWidget(menu)

	self.scanWindow = window
	self.scanMenu = menu

	-- process existing scan results
	_scanResults(self, iface)

	-- schedule network scan 
	self.scanMenu:addTimer(5000,
		function()
			iface:scan(function()
				_scanResults(self, iface)
			end)
		end)

	_helpAction(self, window, "NETWORK_LIST_HELP", "NETWORK_LIST_HELP_BODY")

	self:tieAndShowWindow(window)
end


-- collapse windows and reopen network scan
function _networkScanAgain(self, iface, isComplete)
	self.scanWindow:hideToTop()

	if isComplete then
		_networkScanComplete(self, iface)
	else
		_networkScan(self, iface)
	end
end


function _scanResults(self, iface)
	local now = Framework:getTicks()

	local scanTable = iface:scanResults()

	local associated = self.currentSSID
	for ssid, entry in pairs(scanTable) do
		-- hide squeezebox ad-hoc networks
		if not string.match(ssid, "logitech[%-%+%*]squeezebox[%-%+%*](%x+)") then

			if not self.scanResults[ssid] then
				_addNetwork(self, iface, ssid)
			end

			-- always update the id, bssid and flags
			self.scanResults[ssid].id = entry.id
			self.scanResults[ssid].bssid = entry.bssid
			self.scanResults[ssid].flags = entry.flags

			if entry.associated then
				associated = ssid
			end

			local itemStyle
			if iface:isWireless() then
				itemStyle = "wirelessLevel" .. (entry.quality or 0)
			else
				itemStyle = entry.link and "wiredEthernetLink" or "wiredEthernetNoLink"
			end

			local item = self.scanResults[ssid].item
			item.arrow:setStyle(itemStyle)

			if self.scanMenu then
				self.scanMenu:updatedItem(item)
			end
		end
	end

	-- remove old networks
	for ssid, entry in pairs(self.scanResults) do
		if entry.iface == iface and not scanTable[ssid] then
			if self.scanMenu then
				self.scanMenu:removeItem(entry.item)
			end
			self.scanResults[ssid] = nil
		end
	end

	-- update current ssid 
	_setCurrentSSID(self, associated)
end


-------- WIRELESS SSID AND PASSWORD --------


function _chooseEnterSSID(self, iface)
	local window = Window("help_list", self:string("NETWORK_DONT_SEE_YOUR_NETWORK"), 'setuptitle')
	window:setAllowScreensaver(false)

	local textarea = Textarea("help_text", self:string("NETWORK_ENTER_SSID_HINT"))

	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_SEARCH_FOR_MY_NETWORK"),
			sound = "WINDOWSHOW",
			callback = function()
				_networkScanAgain(self, iface, false)
			end
		},
		{
			text = self:string("NETWORK_ENTER_SSID"),
			sound = "WINDOWSHOW",
			callback = function()
				_enterSSID(self, iface, ssid)
			end
		},
	})

	window:addWidget(textarea)
	window:addWidget(menu)

	_helpAction(self, window, "NETWORK_LIST_HELP", "NETWORK_LIST_HELP_BODY")

	self:tieAndShowWindow(window)
end


function _enterSSID(self, iface)
	assert(iface, debug.traceback())

	local window = Window("input", self:string("NETWORK_NETWORK_NAME"), 'setuptitle')
	window:setAllowScreensaver(false)

	local textinput = Textinput("textinput", "",
				    function(widget, value)
					    if #value == 0 then
						    return false
					    end

					    widget:playSound("WINDOWSHOW")

					    _enterPassword(self, iface, value)

					    return true
				    end
			    )

	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )

        window:addWidget(group)
	window:addWidget(Keyboard("keyboard", 'qwerty'))
        window:focusWidget(group)

	_helpAction(self, window, 'NETWORK_NETWORK_NAME_HELP', 'NETWORK_NETWORK_NAME_HELP_BODY') 

	self:tieAndShowWindow(window)
end


-- wireless network choosen, we need the password
function _enterPassword(self, iface, ssid, nocheck)
	assert(iface and ssid, debug.traceback())

	-- check if we know about this ssid
	if self.scanResults[ssid] == nil then
		return _chooseEncryption(self, iface, ssid)
	end

	-- is the ssid already configured
	if nocheck ~= "config" and self.scanResults[ssid].id ~= nil then
		return _connect(self, iface, ssid, false)
	end

	local flags = self.scanResults[ssid].flags
	log:debug("ssid is: ", ssid, " flags are: ", flags)

	if flags == "" then
		self.encryption = "none"
		return _connect(self, iface, ssid, true)

	elseif string.find(flags, "ETH") then
		self.encryption = "none"
		return _connect(self, iface, ssid, true)

	elseif nocheck ~= "wps" and string.find(flags, "WPS") then
		self.encryption = "wpa2"
		return _chooseWPS(self, iface, ssid)

	elseif string.find(flags, "WPA2%-PSK") then
		self.encryption = "wpa2"
		return _enterPSK(self, iface, ssid)

	elseif string.find(flags, "WPA%-PSK") then
		self.encryption = "wpa"
		return _enterPSK(self, iface, ssid)

	elseif string.find(flags, "WEP") then
		return _chooseWEPLength(self, iface, ssid)

	elseif string.find(flags, "WPA%-EAP") or string.find(flags, "WPA2%-EAP") then
		return _enterEAP(self, iface, ssid)

	else
		return _chooseEncryption(self, iface, ssid)

	end
end


function _chooseEncryption(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local window = Window("text_list", self:string("NETWORK_WIRELESS_ENCRYPTION"), 'setuptitle')
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_NO_ENCRYPTION"),
			sound = "WINDOWSHOW",
			callback = function()
				self.encryption = "none"
				_connect(self, iface, ssid, true)
			end
		},
		{
			text = self:string("NETWORK_WEP_64"),
			sound = "WINDOWSHOW",
			callback = function()
				self.encryption = "wep40"
				_enterWEPKey(self, iface, ssid)
			end
		},
		{
			text = self:string("NETWORK_WEP_128"),
			sound = "WINDOWSHOW",
			callback = function()
				self.encryption = "wep104"
				_enterWEPKey(self, iface, ssid)
			end
		},
		{
			text = self:string("NETWORK_WPA"),
			sound = "WINDOWSHOW",
			callback = function()
				self.encryption = "wpa"
				_enterPSK(self, iface, ssid)
			end
		},
		{
			text = self:string("NETWORK_WPA2"),
			sound = "WINDOWSHOW",
			callback = function()
				self.encryption = "wpa2"
				_enterPSK(self, iface, ssid)
			end
		},
	})
	window:addWidget(menu)

	--_helpAction(self, window, "NETWORK_WIRELESS_ENCRYPTION", "NETWORK_WIRELESS_ENCRYPTION_HELP")

	self:tieAndShowWindow(window)
end


function _chooseWEPLength(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local window = Window("text_list", self:string("NETWORK_PASSWORD_TYPE"), 'setuptitle')
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_WEP_64"),
			sound = "WINDOWSHOW",
			callback = function()
				self.encryption = "wep40"
				_enterWEPKey(self, iface, ssid)
			end
		},
		{
			text = self:string("NETWORK_WEP_128"),
			sound = "WINDOWSHOW",
			callback = function()
				self.encryption = "wep104"
				_enterWEPKey(self, iface, ssid)
			end
		},
	})
	window:addWidget(menu)

	--_helpAction(self, window, "NETWORK_WIRELESS_ENCRYPTION", "NETWORK_WIRELESS_ENCRYPTION_HELP")

	self:tieAndShowWindow(window)
end


function _enterWEPKey(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local window = Window("input", self:string("NETWORK_WIRELESS_KEY"), 'setuptitle')
	window:setAllowScreensaver(false)

	local v
	-- set the initial value
	if self.encryption == "wep40" then
		v = Textinput.hexValue("", 10, 10)
	else
		v = Textinput.hexValue("", 26, 26)
	end

	local textinput = Textinput("textinput", v,
				    function(widget, value)
					    self.key = value:getValue()

					    widget:playSound("WINDOWSHOW")

					    _connect(self, iface, ssid, true)
					    return true
				    end
			    )

	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )
	local keyboard = Keyboard('keyboard', 'hex')

        window:addWidget(group)
	window:addWidget(keyboard)
        window:focusWidget(group)

	_helpAction(self, window, 'NETWORK_WIRELESS_PASSWORD_HELP', 'NETWORK_WIRELESS_PASSWORD_HELP_BODY')

	self:tieAndShowWindow(window)
end


function _enterPSK(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local window = Window("input", self:string("NETWORK_WIRELESS_PASSWORD"), 'setuptitle')
	window:setAllowScreensaver(false)

	local v = Textinput.textValue(self.psk, 8, 63)
	local textinput = Textinput("textinput", v,
				    function(widget, value)
					    self.psk = tostring(value)

					    widget:playSound("WINDOWSHOW")

					    _connect(self, iface, ssid, true)
					    return true
				    end,
				    self:string("ALLOWEDCHARS_WPA")
			    )
	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )

        window:addWidget(group)
	window:addWidget(Keyboard('keyboard', 'qwerty'))
        window:focusWidget(group)

	_helpAction(self, window, 'NETWORK_WIRELESS_PASSWORD_HELP', 'NETWORK_WIRELESS_PASSWORD_HELP_BODY')

	self:tieAndShowWindow(window)
end


function _enterEAP(self, iface, ssid)
	local window = Window("error", self:string('NETWORK_ERROR'), 'setuptitle')
	window:setAllowScreensaver(false)

	window:addWidget(Textarea("text", self:string("NETWORK_UNSUPPORTED_TYPES_HELP")))

	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_UNSUPPORTED_OTHER_NETWORK"),
			sound = "WINDOWSHOW",
			callback = function()
				_networkScanAgain(self, iface, true)
			end
		},
	})
	window:addWidget(menu)

	self:tieAndShowWindow(window)		
end


-------- WIRELESS PROTECTED SETUP --------


function _chooseWPS(self, iface, ssid)
	log:debug('chooseWPS')

	-- ask the user to choose
	local window = Window("text_list", self:string("NETWORK_WPS_METHOD"), 'setuptitle')
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu")

	menu:addItem({
		text = (self:string("NETWORK_WPS_METHOD_PBC")),
		sound = "WINDOWSHOW",
		callback = function()
			_chooseWPSPbc(self, iface, ssid)
		end,
	})

	menu:addItem({
		text = (self:string("NETWORK_WPS_METHOD_PIN")),
		sound = "WINDOWSHOW",
		callback = function()
			_chooseWPSPin(self, iface, ssid)
		end,
	})

	menu:addItem({
		text = (self:string("NETWORK_WPS_METHOD_PSK")),
		sound = "WINDOWSHOW",
		callback = function()
			-- Calling regular enter password function (which determinds the
			--  encryption) but do not check flags for WPS anymore to prevent
			--  ending up in this function again
			_enterPassword(self, iface, ssid, "wps")
		end,
	})

	window:addWidget(menu)

	_helpAction(self, window, "NETWORK_WPS_HELP", "NETWORK_WPS_HELP_BODY")

	self:tieAndShowWindow(window)
end


function _chooseWPSPin(self, iface, ssid)
	local wpspin = iface:generateWPSPin()

	local window = Window("error", self:string('NETWORK_ENTER_PIN'), 'setuptitle')
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	window:addWidget(Textarea("text", self:string("NETWORK_ENTER_PIN_HINT", tostring(wpspin))))

	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_START_TIMER"),
			sound = "WINDOWSHOW",
			callback = function()
				_processWPS(self, iface, ssid, "pin", wpspin)
			end
		},
	})
	window:addWidget(menu)

	self:tieAndShowWindow(window)		
end


function _chooseWPSPbc(self, iface, ssid)
	local window = Window("error", self:string('NETWORK_ENTER_PBC'), 'setuptitle')
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	window:addWidget(Textarea("text", self:string("NETWORK_ENTER_PBC_HINT")))

	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_START_TIMER"),
			sound = "WINDOWSHOW",
			callback = function()
				_processWPS(self, iface, ssid, "pbc")
			end
		},
	})
	window:addWidget(menu)

	self:tieAndShowWindow(window)		
end


function _processWPS(self, iface, ssid, wpsmethod, wpspin)
	assert(iface and ssid and wpsmethod, debug.traceback())

	self.processWPSTimeout = 0

	-- Stop wpa_supplicant - cannot run while wpsapp is running
	iface:stopWPASupplicant()
	-- Remove wps.conf, (re-)start wpsapp
	iface:startWPSApp(wpsmethod, wpspin)

	-- Progress window
	local popup = Popup("waiting_popup")
	popup:setAllowScreensaver(false)

	popup:addWidget(Icon("icon_connecting"))
	if wpsmethod == "pbc" then
		popup:addWidget(Label("text", self:string("NETWORK_WPS_PROGRESS_PBC")))
	else
		popup:addWidget(Label("text", self:string("NETWORK_WPS_PROGRESS_PIN", tostring(wpspin))))
	end

	local status = Label("subtext", self:string("NETWORK_WPS_REMAINING_WALK_TIME", tostring(WPS_WALK_TIMEOUT)))
	popup:addWidget(status)

	popup:addTimer(1000, function()
			_timerWPS(self, iface, ssid, wpsmethod, wpspin)

			local remaining_walk_time = WPS_WALK_TIMEOUT - self.processWPSTimeout
			status:setValue(self:string("NETWORK_WPS_REMAINING_WALK_TIME", tostring(remaining_walk_time)))
		end)

	local _stopWPSAction = function(self, event)
		iface:stopWPSApp()
		iface:startWPASupplicant()
		popup:hide()
	end

	popup:addActionListener("back", self, _stopWPSAction)
	popup:addActionListener("soft_reset", self, _stopWPSAction)
	popup:ignoreAllInputExcept({"back"})

	self:tieAndShowWindow(popup)
	return popup
end


function _timerWPS(self, iface, ssid, wpsmethod, wpspin)
	assert(iface and ssid, debug.traceback())

	Task("networkWPS", self,
		function()
			log:debug("processWPSTimeout=", self.processWPSTimeout)

			local status = iface:t_wpsStatus()
			if not (status.wps_state == "COMPLETED") then
				self.processWPSTimeout = self.processWPSTimeout + 1
				if self.processWPSTimeout ~= WPS_WALK_TIMEOUT then
					return
				end

				-- WPS walk timeout
				processWPSFailed(self, iface, ssid, wpsmethod, wpspin)
				return
			else
				-- Make sure wpa supplicant is running again
				iface:startWPASupplicant()

				-- Set credentials from WPS
				self.encryption = status.wps_encryption
				self.psk = status.wps_psk
				self.key = status.wps_key

				_connect(self, iface, ssid, true)
			end

		end):addTask()
end


function processWPSFailed(self, iface, ssid, wpsmethod, wpspin)
	assert(iface and ssid, debug.traceback())

	log:debug("processWPSFailed")

-- TODO: Remove later (should not be necessary)
	iface:stopWPSApp()

	iface:startWPASupplicant()

	-- popup failure
	local window = Window("error", self:string("NETWORK_WPS_PROBLEM"), 'setuptitle')
	window:setAllowScreensaver(false)


	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_TRY_AGAIN"),
			sound = "WINDOWHIDE",
			callback = function()
				window:hide()
				_processWPS(self, iface, ssid, wpsmethod, wpspin)
			end
		},
		{
			text = self:string("NETWORK_WPS_DIFFERENT_METHOD"),
			sound = "WINDOWHIDE",
			callback = function()
				window:hide()
				Framework.windowStack[1]:hide()
			end
		},
	})

	window:addWidget(Textarea("help_text", self:string("NETWORK_WPS_PROBLEM_HINT")))
	window:addWidget(menu)

	self:tieAndShowWindow(window)
end


-------- CONNECT TO NETWORK --------


-- start to connect
function _connect(self, iface, ssid, createNetwork)
	assert(iface and ssid, debug.traceback())

	if not iface:isWireless() then
		local status = iface:t_wpaStatus()
		if not status.link then
			return _attachEthernet(self, iface, ssid, createNetwork)
		end
	end

	self.connectTimeout = 0
	self.dhcpTimeout = 0

	-- progress window
	local popup = Popup("waiting_popup")

	local icon  = Icon("icon_connecting")
	icon:addTimer(1000,
		function()
			_connectTimer(self, iface, ssid)
		end)
	popup:addWidget(icon)
	popup:ignoreAllInputExcept({"back"})

	-- XXXX popup text, including dhcp detection text

	popup:addWidget(Label("text", self:string("NETWORK_CONNECTING_TO_SSID", ssid)))

	self:tieAndShowWindow(popup)

	-- Select/create the network in a background task
	Task("networkSelect", self, _selectNetworkTask):addTask(iface, ssid, createNetwork)
end


-- task to modify network configuration
function _selectNetworkTask(self, iface, ssid, createNetwork)
	assert(iface and ssid, debug.traceback())

	-- disconnect from existing network
	iface:t_disconnectNetwork()

	-- remove any existing network config
	if createNetwork then
		_removeNetworkTask(self, iface, ssid)
	end

	-- ensure the network state exists
	_setCurrentSSID(self, nil)
	if self.scanResults[ssid] == nil then
		_addNetwork(self, iface, ssid)
	end

	local id = self.scanResults[ssid].id

	-- create the network config (if necessary)
	if id == nil then
		local option = {
			encryption = self.encryption,
			psk = self.psk,
			key = self.key
		}

		local id = iface:t_addNetwork(ssid, option)

		self.createdNetwork = true
		if self.scanResults[ssid] then
			self.scanResults[ssid].id = id
		end
	end

	-- select new network
	iface:t_selectNetwork(ssid)
end


-- remove the network configuration
function _removeNetworkTask(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	iface:t_removeNetwork(ssid)

	if self.scanResults[ssid] then
		-- remove from menu
		local item = self.scanResults[ssid].item
		if self.scanMenu then
			self.scanMenu:removeItem(item)
		end

		-- clear entry
		self.scanResults[ssid] = nil
	end
end


-- warning if ethernet cable is not connected
function _attachEthernet(self, iface, ssid, createNetwork)
	local window = Window("help_list", self:string("NETWORK_ATTACH_CABLE"))
        window:setAllowScreensaver(false)

	window:setButtonAction("rbutton", nil)

	local textarea = Textarea('help_text', self:string("NETWORK_ATTACH_CABLE_DETAILED"))
	window:addWidget(textarea)

	window:addTimer(500,
		function(event)
			log:debug("Checking Link")
			Task("ethernetConnect", self,
				function()
					local status = iface:t_wpaStatus()
					log:debug("link=", status.link)
					if status.link then
						log:debug("connected")
						window:hide()
						_connect(self, iface, ssid, createNetwork)
					end
             			end
			):addTask()
		end
	)

	self:tieAndShowWindow(window)
end


-- timer to check connection state
function _connectTimer(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local completed = false

	Task("networkConnect", self, function()
		log:debug("connectTimeout=", self.connectTimeout, " dhcpTimeout=", self.dhcpTimeout)

		local status = iface:t_wpaStatus()

		log:debug("wpa_state=", status.wpa_state)
		log:debug("ip_address=", status.ip_address)

		if status.wpa_state == "COMPLETED" then
			completed = true
		end

		if not (completed and status.ip_address) then
			-- not connected yet

			self.connectTimeout = self.connectTimeout + 1
			if self.connectTimeout ~= CONNECT_TIMEOUT then
				return
			end

			-- connection timed out
			_connectFailed(self, iface, ssid, "timeout")
			return
		end
			    
		if string.match(status.ip_address, "^169.254.") then
			-- auto ip
			self.dhcpTimeout = self.dhcpTimeout + 1
			if self.dhcpTimeout ~= CONNECT_TIMEOUT then
				return
			end

			-- dhcp timed out
			_failedDHCP(self, iface, ssid)
		else
			-- dhcp completed
			_connectSuccess(self, iface, ssid)
		end
	end):addTask()
end


function _connectFailedTask(self, iface, ssid)
	-- Stop trying to connect to the network
	iface:t_disconnectNetwork()

	if self.createdNetwork then
		-- Remove failed network
		_removeNetworkTask(self, iface, ssid)
		self.createdNetwork = nil
	end
end


function _connectSuccess(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	if ssid == nil then
		-- make sure we are still trying to connect
		return
	end

	log:debug("connection OK ", ssid)

	_setCurrentSSID(self, ssid)

	-- forget connection state
	self.encryption = nil
	self.psk = nil
	self.key = nil

	-- send notification we're on a new network
	jnt:notify("networkConnected")

	-- popup confirmation
	local popup = Popup("waiting_popup")
	popup:addWidget(Icon("icon_connected"))
	popup:ignoreAllInputExcept({"back"})

	local name = self.scanResults[ssid].item.text
	local text = Label("text", self:string("NETWORK_CONNECTED_TO", name))
	popup:addWidget(text)

	popup:addTimer(2000,
			function(event)
				self.setupNext()
			end,
			true)

	popup:addListener(EVENT_KEY_PRESS | EVENT_MOUSE_PRESS, --todo IR should work too, but not so simple - really window:hideOnAllButtonInput should allow for a callback on hide for "next" type situations such as this
			   function(event)
				self.setupNext()
				return EVENT_CONSUME
			   end)

	self:tieAndShowWindow(popup)
end


function _connectFailed(self, iface, ssid, reason)
	assert(iface and ssid, debug.traceback())

	log:debug("connection failed")

	-- Stop trying to connect to the network, if this network is
	-- being added this will also remove the network configuration
	Task("networkFailed", self, _connectFailedTask):addTask(iface, ssid)

	-- Message based on failure type
	local helpText = self:string("NETWORK_CONNECTION_PROBLEM_HELP", tostring(self.psk))

	-- popup failure
	local window = Window("error", self:string('NETWORK_CANT_CONNECT'), 'setuptitle')
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_TRY_PASSWORD"),
			sound = "WINDOWHIDE",
			callback = function()
				_networkScanAgain(self, iface, true)
				_enterPassword(self, iface, ssid, "config")
			end
		},
		{
			text = self:string("NETWORK_TRY_DIFFERENT"),
			sound = "WINDOWSHOW",
			callback = function()
				_networkScanAgain(self, iface, true)
			end
		},
	})


	window:addWidget(Textarea("help_text", helpText))
	window:addWidget(menu)

	self:tieAndShowWindow(window)
end


function _failedDHCP(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	log:debug("self.encryption=", self.encryption)

	if self.encryption and string.match(self.encryption, "^wep.*") then
		-- use different error screen for WEP, the failure may
		-- be due to a bad WEP passkey, not DHCP.
		return _failedDHCPandWEP(self, iface, ssid)
	else
		return _failedDHCPandWPA(self, iface, ssid)
	end
end


function _failedDHCPandWPA(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local window = Window("error", self:string("NETWORK_DHCP_ERROR"), 'setuptitle')
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)
	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_DHCP_AGAIN"),
			sound = "WINDOWHIDE",
			callback = function()
				-- poke udhcpto try again
				_sigusr1("udhcpc")
				_connect(self, iface, ssid, false)
				window:hide(Window.transitionNone)
			end
		},
		{
			text = self:string("STATIC_ADDRESS"),
			sound = "WINDOWSHOW",
			callback = function()
				_enterIP(self, iface, ssid)
			end
		},
		{
			text = self:string("ZEROCONF_ADDRESS"),
			sound = "WINDOWSHOW",
			callback = function()
				-- already have a self assigned address, we're done
				_connectSuccess(self, iface, ssid)
			end
		},
	})

	window:addWidget(Textarea("help_text", self:string("NETWORK_DHCP_ERROR_HINT")))
	window:addWidget(menu)

	self:tieAndShowWindow(window)
end


function _failedDHCPandWEP(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local window = Window("error", self:string("NETWORK_ERROR"), 'setuptitle')
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_TRY_AGAIN"),
			sound = "WINDOWHIDE",
			callback = function()
				-- poke udhcpto try again
				_sigusr1("udhcpc")
				_connect(self, iface, ssid, false)
				window:hide(Window.transitionNone)
			end
		},
		{
			text = self:string("NETWORK_TRY_DIFFERENT"),
			sound = "WINDOWSHOW",
			callback = function()
				_networkScanAgain(self, iface, true)
			end
		},
		{
			text = self:string("NETWORK_WEP_DHCP"),
			sound = "WINDOWHIDE",
			callback = function()
				_failedDHCPandWPA(self, iface, ssid)
			end
		},
	})

	window:addWidget(Textarea("help_text", self:string("NETWORK_ADDRESS_HELP_WEP", tostring(self.key))))
	window:addWidget(menu)

	self:tieAndShowWindow(window)
end


-------- STATIC-IP --------


function _parseip(str)
	local ip = 0
	for w in string.gmatch(str, "%d+") do
		ip = ip << 8
		ip = ip | tonumber(w)
	end
	return ip
end


function _ipstring(ip)
	local str = {}
	for i = 4,1,-1 do
		str[i] = string.format("%d", ip & 0xFF)
		ip = ip >> 8
	end
	str = table.concat(str, ".")
	return str
end


function _validip(str)
	local ip = _parseip(str)
	if ip == 0x00000000 or ip == 0xFFFFFFFF then
		return false
	else
		return true
	end
end


function _subnet(self)
	local ip = _parseip(self.ipAddress or "0.0.0.0")

	if ((ip & 0xC0000000) == 0xC0000000) then
		return "255.255.255.0"
	elseif ((ip & 0x80000000) == 0x80000000) then
		return "255.255.0.0"
	elseif ((ip & 0x80000000) == 0) then
		return "255.0.0.0"
	else
		return "0.0.0.0";
	end
end


function _gateway(self)
	local ip = _parseip(self.ipAddress or "0.0.0.0")
	local subnet = _parseip(self.ipSubnet or "255.255.255.0")

	return _ipstring(ip & subnet | 1)
end


function _sigusr1(process)
	local pid

	local pattern = "%s*(%d+).*" .. process

	local cmd = io.popen("/bin/ps")
	for line in cmd:lines() do
		pid = string.match(line, pattern)
		if pid then break end
	end
	cmd:close()

	if pid then
		log:debug("kill -usr1 ", pid)
		os.execute("kill -usr1 " .. pid)
	else
		log:error("cannot sigusr1 ", process)
	end
end


function _enterIP(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local v = Textinput.ipAddressValue(self.ipAddress or "0.0.0.0")

	local window = Window("input", self:string("NETWORK_IP_ADDRESS"), 'setuptitle')
	window:setAllowScreensaver(false)

	local textinput = Textinput("textinput", v,
				   function(widget, value)
					   value = value:getValue()
					   if not _validip(value) then
						   return false
					   end

					   self.ipAddress = value
					   self.ipSubnet = _subnet(self)

					   widget:playSound("WINDOWSHOW")
					   _enterSubnet(self, iface, ssid)
					   return true
				   end)
	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )
	local keyboard = Keyboard("keyboard", "numeric")

        window:addWidget(group)
	window:addWidget(keyboard)
        window:focusWidget(group)

	_helpAction(self, window, 'NETWORK_IP_ADDRESS_HELP', 'NETWORK_IP_ADDRESS_HELP_BODY')

	self:tieAndShowWindow(window)
end


function _enterSubnet(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local v = Textinput.ipAddressValue(self.ipSubnet)

	local window = Window("input", self:string("NETWORK_SUBNET"), 'setuptitle')
	window:setAllowScreensaver(false)

	local textinput = Textinput("textinput", v,
				   function(widget, value)
					   value = value:getValue()

					   self.ipSubnet = value
					   self.ipGateway = _gateway(self)

					   widget:playSound("WINDOWSHOW")
					   _enterGateway(self, iface, ssid)
					   return true
				   end)
	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )
	local keyboard = Keyboard("keyboard", "numeric")

        window:addWidget(group)
	window:addWidget(keyboard)
        window:focusWidget(group)

	_helpAction(self, window, 'NETWORK_IP_ADDRESS_HELP', 'NETWORK_IP_ADDRESS_HELP_BODY')

	self:tieAndShowWindow(window)
end


function _enterGateway(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local v = Textinput.ipAddressValue(self.ipGateway)

	local window = Window("input", self:string("NETWORK_GATEWAY"), 'setuptitle')
	window:setAllowScreensaver(false)

	local textinput = Textinput("textinput", v,
				   function(widget, value)
					   value = value:getValue()

					   if not _validip(value) then
						   return false
					   end

					   self.ipGateway = value
					   self.ipDNS = self.ipGateway

					   widget:playSound("WINDOWSHOW")
					   _enterDNS(self, iface, ssid)
					   return true
				   end)
	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )
	local keyboard = Keyboard("keyboard", "numeric")

        window:addWidget(group)
	window:addWidget(keyboard)
        window:focusWidget(group)

	_helpAction(self, window, 'NETWORK_IP_ADDRESS_HELP', 'NETWORK_IP_ADDRESS_HELP_BODY')

	self:tieAndShowWindow(window)
end


function _enterDNS(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local v = Textinput.ipAddressValue(self.ipDNS)

	local window = Window("input", self:string("NETWORK_DNS"), 'setuptitle')
	window:setAllowScreensaver(false)

	local textinput = Textinput("textinput", v,
				   function(widget, value)
					   value = value:getValue()

					   if not _validip(value) then
						   return false
					   end

					   self.ipDNS = value

					   widget:playSound("WINDOWSHOW")
					   _setStaticIP(self, iface, ssid)
					   return true
				   end)
	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )
	local keyboard = Keyboard("keyboard", "numeric")

	window:addWidget(group)
	window:addWidget(keyboard)
        window:focusWidget(group)

	_helpAction(self, window, 'NETWORK_IP_ADDRESS_HELP', 'NETWORK_IP_ADDRESS_HELP_BODY')

	self:tieAndShowWindow(window)
end


function _setStaticIP(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	log:debug("setStaticIP addr=", self.ipAddress, " subnet=", self.ipSubnet, " gw=", self.ipGateway, " dns=", self.ipDNS)

	local popup = Popup("waiting_popup")
	popup:addWidget(Icon("icon_connecting"))
	popup:ignoreAllInputExcept({"back"})

	local name = self.scanResults[ssid].item.text
	popup:addWidget(Label("text", self:string("NETWORK_CONNECTING_TO_SSID", name)))

	self:tieAndShowWindow(popup)

	Task("networkStatic", self, function()
		iface:t_disconnectNetwork()

		iface:t_setStaticIP(ssid, self.ipAddress, self.ipSubnet, self.ipGateway, self.ipDNS)
		_connectSuccess(self, iface, ssid)
	end):addTask()
end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]
