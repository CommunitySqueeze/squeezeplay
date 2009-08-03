
--[[
=head1 NAME

applets.ScreenSavers.ScreenSaversApplet - Screensaver manager.

=head1 DESCRIPTION

This applets hooks itself into Jive to provide a screensaver
service, complete with settings.

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 
ScreenSaversApplet overrides the following methods:

=cut
--]]


-- stuff we use
local ipairs, pairs, tostring = ipairs, pairs, tostring

local oo               = require("loop.simple")

local Applet           = require("jive.Applet")
local Timer            = require("jive.ui.Timer")
local Framework        = require("jive.ui.Framework")
local Window           = require("jive.ui.Window")
local RadioGroup       = require("jive.ui.RadioGroup")
local RadioButton      = require("jive.ui.RadioButton")
local Label            = require("jive.ui.Label")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local System           = require("jive.System")
local Textarea         = require("jive.ui.Textarea")
local string           = require("string")
local table            = require("jive.utils.table")
local debug            = require("jive.utils.debug")

local appletManager    = appletManager

local jnt = jnt
local jiveMain = jiveMain


module(..., Framework.constants)
oo.class(_M, Applet)


function init(self, ...)
	self.screensavers = {}
	self.screensaverSettings = {}
	self:addScreenSaver(self:string("SCREENSAVER_NONE"), false, false, _, _, 100)

	self.timeout = self:getSettings()["timeout"]

	self.active = {}
	self.demoScreensaver = nil

	-- wait for at least a minute after we start before activating a screensaver,
	-- otherwise the screensaver may have started when you exit the bootscreen
	self.timer = Timer(60000, function() self:_activate() end, true)
	self.timer:start()

	-- listener to restart screensaver timer
	Framework:addListener(ACTION | EVENT_SCROLL | EVENT_MOUSE_ALL | EVENT_MOTION | EVENT_IR_ALL,
		function(event)
			if (event:getType() & EVENT_IR_ALL) > 0 then
				if (not Framework:isValidIRCode(event)) then
					return EVENT_UNUSED
				end
			end
			
			-- restart timer if it is running
			self.timer:setInterval(self.timeout)
			return EVENT_UNUSED
		end,
		true
	)

	Framework:addListener(ACTION | EVENT_KEY_PRESS | EVENT_KEY_HOLD | EVENT_SCROLL | EVENT_MOUSE_PRESS | EVENT_MOUSE_HOLD | EVENT_MOUSE_DRAG,
		function(event)

			-- screensaver is not active
			if #self.active == 0 then
				return EVENT_UNUSED
			end

			if Framework:isAnActionTriggeringKeyEvent(event, EVENT_KEY_ALL ) then
				--will come back as an ACTION, let's respond to it then to give other action listeners a chance
				return 	EVENT_UNUSED
			end

			log:debug("Closing screensaver event=", event:tostring())

			self:deactivateScreensaver()

			-- keys should close the screensaver, and not
			-- perform an action
			if event:getType() == ACTION then
				if event:getAction() == "back" or event:getAction() == "go" then
					return EVENT_CONSUME
				end

				-- make sure when exiting a screensaver we
				-- really go home.
				if event:getAction() == "home" then
					appletManager:callService("goHome")
					return EVENT_CONSUME
				end
			end
			return EVENT_UNUSED
		end,
		100 -- process after all other event handlers
	)

	jnt:subscribe(self)

	return self
end


--[[

=head2 applets.ScreenSavers.ScreenSaversApplet:free()

Overridden to return always false, this ensure the applet is
permanently loaded.

=cut
--]]
function free(self)
	-- ScreenSavers cannot be freed
	return false
end


--_activate(the_screensaver)
--Activates the screensaver C<the_screensaver>. If <the_screensaver> is nil then the
--screensaver set for the current mode is activated.
-- the force arg is set to true for preview, allowing screensavers that might be not shown in certain circumstances to still be previewed
-- see ClockApplet for example
function _activate(self, the_screensaver, force)
	log:debug("Screensaver activate")

	-- check if the top window will allow screensavers, if not then
	-- set the screensaver to activate 10 seconds after the window
	-- is closed, assuming we still don't have any activity
	if not Framework.windowStack[1]:canActivateScreensaver() and self:isSoftPowerOn() then
		Framework.windowStack[1]:addListener(EVENT_WINDOW_INACTIVE,
			function()
				if not self.timer:isRunning() then
					self.timer:restart(10000)
				end
			end)
		return
	end

	-- what screensaver, check the playmode of the current player
	if the_screensaver == nil then
		the_screensaver = self:_getDefaultScreensaver()
	end

	local screensaver = self.screensavers[the_screensaver]
	if not screensaver or not screensaver.applet then
		-- no screensaver, do nothing
		return
	end

	-- activate the screensaver. it should register any windows with
	-- screensaverWindow, and open then itself
	local instance = appletManager:loadApplet(screensaver.applet)
	if instance[screensaver.method](instance, force) ~= false then
		log:info("activating " .. screensaver.applet .. " screensaver")
	end
end



--service method
function activateScreensaver(self)
	self:_activate(nil)
end


function isSoftPowerOn(self)
	return jiveMain:getSoftPowerState() == "on"
end


function _closeAnyPowerOnWindow(self)
	if self.powerOnWindow then
		self.powerOnWindow:hide(Window.transitionNone)
		self.powerOnWindow = nil

		local ss = self:_getOffScreensaver()

		if ss then
			local screensaver = self.screensavers[ss]
			if not screensaver or not screensaver.applet then
				-- no screensaver, do nothing
				return
			end

			local instance = appletManager:loadApplet(screensaver.applet)
			if instance.onOverlayWindowHidden then
				instance:onOverlayWindowHidden()
			end
		end
	end

end


function _getOffScreensaver(self)
	return self:getSettings()["whenOff"] or "BlankScreen:openScreensaver" --hardcode for backward compatability
end


function _getDefaultScreensaver(self)
	local ss

	if not self:isSoftPowerOn() then
		ss = self:_getOffScreensaver()
		log:debug("whenOff")
	else
		local player = appletManager:callService("getCurrentPlayer")
		if player and player:getPlayMode() == "play" then
			ss = self:getSettings()["whenPlaying"]
			log:debug("whenPlaying")
		else
			ss = self:getSettings()["whenStopped"]
			log:debug("whenStopped")
		end
	end

	return ss
end

-- screensavers can have methods that are executed on close
function _deactivate(self, window, the_screensaver)
	log:debug("Screensaver deactivate")

	self:_closeAnyPowerOnWindow()

	if not the_screensaver then
		the_screensaver = self:_getDefaultScreensaver()
	end
	local screensaver = self.screensavers[the_screensaver]

	if screensaver and screensaver.applet and screensaver.closeMethod then
		local instance = appletManager:loadApplet(screensaver.applet)
		instance[screensaver.closeMethod](instance)
	end
	window:hide(Window.transitionNone)
	self.demoScreensaver = nil

end

-- switch screensavers on a player mode change
function notify_playerModeChange(self, player, mode)
	if not self:isSoftPowerOn() then
		return
	end

	local oldActive = self.active

	if #oldActive == 0 then
		-- screensaver is not active
		return
	end

	self.active = {}
	self:_activate(nil)

	-- close active screensaver
	for i, window in ipairs(oldActive) do
		_deactivate(self, window, self.demoScreensaver)
	end
end


local _powerAllowedActions = {
			["play_preset_0"] = 1,
			["play_preset_1"] = 1,
			["play_preset_2"] = 1,
			["play_preset_3"] = 1,
			["play_preset_4"] = 1,
			["play_preset_5"] = 1,
			["play_preset_6"] = 1,
			["play_preset_7"] = 1,
			["play_preset_8"] = 1,
			["play_preset_9"] = 1,
			["play"]            = "pause",
		}

function _powerActionHandler(self, actionEvent)
	local action = actionEvent:getAction()

	if _powerAllowedActions[action] then
		--for special allowed actions, turn on power and forward the action
		jiveMain:setSoftPowerState("on")

		local translatedAction = action
		if _powerAllowedActions[action] ~= 1 then
			--certain actions like play during poweroff translate to other actions
			translatedAction = _powerAllowedActions[action]
		end
		Framework:pushAction(translatedAction)
		return
	end

	--action not used, so bring up "power on" window if isn't already to let user know device is in off state-- not for baby though for bug 12541  
	if System:getMachine() ~= "baby" then
		self:_showPowerOnWindow()
	end
end


function _showPowerOnWindow(self)
	if self.powerOnWindow then
		return EVENT_UNUSED
	end

	local ss = self:_getOffScreensaver()

	if ss then
		local screensaver = self.screensavers[ss]
		if not screensaver or not screensaver.applet then
			-- no screensaver, do nothing
			return
		end

		local instance = appletManager:loadApplet(screensaver.applet)
		if instance.onOverlayWindowShown then
			instance:onOverlayWindowShown()
		end
	end

	self.powerOnWindow = Window("power_on_window")
	self.powerOnWindow:setButtonAction("lbutton", "power")
	self.powerOnWindow:setButtonAction("rbutton", nil)
	self.powerOnWindow:setTransparent(true)
	self.powerOnWindow:setAlwaysOnTop(true)
	self.powerOnWindow:setAllowScreensaver(false)
	self.powerOnWindow:ignoreAllInputExcept({ "power", "power_on", "power_off" },
						function(actionEvent)
							return self:_powerActionHandler(actionEvent)
						end)
	self.powerOnWindow:show(Window.transitionNone)

	self.powerOnWindow:addTimer(    5000,
					function ()
						self:_closeAnyPowerOnWindow()
					end,
					true)
end


--[[

=head2 screensaverWindow(window)

Register the I<window> as a screensaver window. This is used to maintain the
the screensaver activity, and adds some default listeners for screensaver
behaviour.

=cut
--]]
function screensaverWindow(self, window)
	-- the screensaver is active when this window is pushed to the window stack
	window:addListener(EVENT_WINDOW_PUSH,
			   function(event)
				   log:debug("screensaver opened ", #self.active)

				   table.insert(self.active, window)
				   self.timer:stop()
				   return EVENT_UNUSED
			   end)

	-- the screensaver is inactive when this window is poped from the window stack
	window:addListener(EVENT_WINDOW_POP,
			   function(event)
				   table.delete(self.active, window)
				   if #self.active == 0 then
					   log:debug("screensaver inactive")
					   self.timer:start()
				   end

				   log:debug("screensaver closed ", #self.active)
				   return EVENT_UNUSED
			   end)

	if not self:isSoftPowerOn() then

		window:ignoreAllInputExcept(    { "power", "power_on", "power_off" },
		                                function(actionEvent)
		                                        self:_powerActionHandler(actionEvent)
		                                end)
		window:addListener(     EVENT_MOUSE_PRESS | EVENT_MOUSE_HOLD,
		                        function (event)
			                        self:_showPowerOnWindow()
			                        return EVENT_CONSUME
		                        end)
		window:addListener(     EVENT_SCROLL,
					function ()
						self:_showPowerOnWindow()
					end)

	end

	log:debug("Overriding the default window action 'bump' handling to allow action to fall through to framework listeners")
	window:removeDefaultActionListeners()
	
end


--service method
function restartScreenSaverTimer(self)
	self.timer:restart()
end


--service method
function isScreensaverActive(self)
	return self.active and #self.active > 0
end

--service method
function deactivateScreensaver(self)
	-- close all screensaver windows
	for i,w in ipairs(self.active) do
		_deactivate(self, w, self.demoScreensaver)
	end
end


function addScreenSaver(self, displayName, applet, method, settingsName, settings, weight, closeMethod )
	local key = tostring(applet) .. ":" .. tostring(method)
	self.screensavers[key] = {
		applet = applet,
		method = method,
		displayName = displayName,
		settings = settings,
		weight = weight,
		closeMethod = closeMethod
	}

	if settingsName then
		self.screensaverSettings[settingsName] = self.screensavers[key]
	end
end


function setScreenSaver(self, mode, key)
	self:getSettings()[mode] = key
end


function setTimeout(self, timeout)
	self:getSettings()["timeout"] = timeout

	self.timeout = timeout
	self.timer:setInterval(self.timeout)
end


function screensaverSetting(self, menuItem, mode)
	local menu = SimpleMenu("menu")
        menu:setComparator(menu.itemComparatorWeightAlpha)

	local activeScreensaver = self:getSettings()[mode]

	local group = RadioGroup()
	for key, screensaver in pairs(self.screensavers) do
		local button = RadioButton(
			"radio", 
			group, 
			function()
				self:setScreenSaver(mode, key)
			end,
			key == activeScreensaver
		)
		local testScreensaverAction = function (self)
			self.demoScreensaver = key
			self:_activate(key, true)
			return EVENT_CONSUME
		end

		-- pressing play should play the screensaver, so we need a handler
		button:addActionListener("play", self, testScreensaverAction)

		-- set default weight to 100
		if not screensaver.weight then screensaver.weight = 100 end
		menu:addItem({
				text = screensaver.displayName,
				style = 'item_choice',
				check = button,
				weight = screensaver.weight
			     })
	end

	local window = Window("text_list", menuItem.text, 'settingstitle')
--	window:addWidget(Textarea("help_text", self:string("SCREENSAVER_SELECT_HELP")))
	window:addWidget(menu)

	window:addListener(EVENT_WINDOW_POP, function() self:storeSettings() end)

	self:tieAndShowWindow(window)
	return window
end


function timeoutSetting(self, menuItem)
	local group = RadioGroup()

	local timeout = self:getSettings()["timeout"]
	
	local window = Window("text_list", menuItem.text, 'settingstitle')
	window:addWidget(SimpleMenu("menu",
		{
			{
				text = self:string('DELAY_10_SEC'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(10000) end, timeout == 10000),
			},
			{
				text = self:string('DELAY_20_SEC'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(20000) end, timeout == 20000),
			},
			{
				text = self:string('DELAY_30_SEC'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(30000) end, timeout == 30000),
			},
			{
				text = self:string('DELAY_1_MIN'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(60000) end, timeout == 60000),
			},
			{ 
				text = self:string('DELAY_2_MIN'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(120000) end, timeout == 120000),
			},
			{
				text = self:string('DELAY_5_MIN'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(300000) end, timeout == 300000),
			},
			{ 
				text = self:string('DELAY_10_MIN'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(600000) end, timeout == 600000),
			},
			{ 
				text = self:string('DELAY_30_MIN'),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setTimeout(1800000) end, timeout == 1800000),
			},
		}))

	window:addListener(EVENT_WINDOW_POP, function() self:storeSettings() end)

	self:tieAndShowWindow(window)
	return window
end


function openSettings(self, menuItem)

	local menu = SimpleMenu("menu",
		{
			{ 
				text = self:string('SCREENSAVER_PLAYING'),
				weight = 1,
				sound = "WINDOWSHOW",
				callback = function(event, menu_item)
						   self:screensaverSetting(menu_item, "whenPlaying")
					   end
			},
			{
				text = self:string("SCREENSAVER_STOPPED"),
				weight = 1,
				sound = "WINDOWSHOW",
				callback = function(event, menu_item)
						   self:screensaverSetting(menu_item, "whenStopped")
					   end
			},
			{
				text = self:string("SCREENSAVER_OFF"),
				weight = 2,
				sound = "WINDOWSHOW",
				callback = function(event, menu_item)
						   self:screensaverSetting(menu_item, "whenOff")
					   end
			},
			{
				text = self:string("SCREENSAVER_DELAY"),
				weight = 5,
				sound = "WINDOWSHOW",
				callback = function(event, menu_item)
						   self:timeoutSetting(menu_item)
					   end
			},
		})

	menu:setComparator(menu.itemComparatorWeightAlpha)
	for setting_name, screensaver in pairs(self.screensaverSettings) do
		menu:addItem({
				     text = setting_name,
				     weight = 3,
				     sound = "WINDOWSHOW",
				     callback =
					     function(event, menuItem)
							local instance = appletManager:loadApplet(screensaver.applet)
							instance[screensaver.settings](instance, menuItem)
					     end
			     })
	end

	local window = Window("text_list", menuItem.text, 'settingstitle')
	window:addWidget(menu)

	-- Store the applet settings when the window is closed
	window:addListener(EVENT_WINDOW_POP,
		function()
			self:storeSettings()
		end
	)

	self:tieAndShowWindow(window)
	return window
end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]

