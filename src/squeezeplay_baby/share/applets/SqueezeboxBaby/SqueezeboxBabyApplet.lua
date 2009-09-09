
local pcall, unpack, tonumber, tostring = pcall, unpack, tonumber, tostring

-- board specific driver
local bsp                    = require("baby_bsp")

local oo                     = require("loop.simple")
local os                     = require("os")
local io                     = require("io")
local string                 = require("jive.utils.string")
local table                  = require("jive.utils.table")
local math                   = require("math")

local Applet                 = require("jive.Applet")
local Decode                 = require("squeezeplay.decode")
local System                 = require("jive.System")

local Networking             = require("jive.net.Networking")

local Player                 = require("jive.slim.Player")
local LocalPlayer            = require("jive.slim.LocalPlayer")

local Checkbox               = require("jive.ui.Checkbox")
local Framework              = require("jive.ui.Framework")
local Group                  = require("jive.ui.Group")
local Icon                   = require("jive.ui.Icon")
local Event                  = require("jive.ui.Event")
local Label                  = require("jive.ui.Label")
local Popup                  = require("jive.ui.Popup")
local Task                   = require("jive.ui.Task")
local Textarea               = require("jive.ui.Textarea")
local Timer                  = require("jive.ui.Timer")
local SimpleMenu             = require("jive.ui.SimpleMenu")
local Slider                 = require("jive.ui.Slider")
local Window                 = require("jive.ui.Window")
local RadioGroup             = require("jive.ui.RadioGroup")
local RadioButton            = require("jive.ui.RadioButton")

local debug                  = require("jive.utils.debug")

local SqueezeboxApplet       = require("applets.Squeezebox.SqueezeboxApplet")

local EVENT_IR_DOWN          = jive.ui.EVENT_IR_DOWN
local EVENT_IR_REPEAT        = jive.ui.EVENT_IR_REPEAT

local jnt                    = jnt
local iconbar                = iconbar
local jiveMain               = jiveMain
local appletManager          = appletManager

local brightnessTable        = {}


module(..., Framework.constants)
oo.class(_M, SqueezeboxApplet)


--[[

Power states:

ACTIVE
  The user is interacting with the system, everything is on.

IDLE
  The user has stopped interating with the system, the lcd is dimmed.

SLEEP
  A low power mode, the power amp is off.

HIBERNATE
  Suspend to ram. Not currently supported on baby.


State transitions (with default times):

* -> ACTIVE
  Any user activity changes to the active state.

ACTIVE -> IDLE
  After 30 seconds of inactivity, player power is on

ACTIVE -> SLEEP
  After 30 seconds of inactivity, player power is off

IDLE -> SLEEP
  After 10 minutes of inactivity, when not playing

SLEEP -> HIBERNATE
  After 1 hour of inactivity

--]]



local brightnessTimer = nil

function init(self)
	local settings = self:getSettings()

	self.isLowBattery = false

	-- read uuid, serial and revision
	parseCpuInfo(self)

	System:init({
		machine = "baby",
		uuid = self._uuid,
		revision = self._revision,
	})

	-- warn if uuid or mac are invalid
	verifyMacUUID(self)

	if not self._serial then
		log:warn("Serial not found")
	end

	if self._revision < 1 then
		betaHardware(self, true) -- euthanize
	elseif self._revision < 3 then
		betaHardware(self, false) -- warning
	end

	-- sys interface
	sysOpen(self, "/sys/class/backlight/mxc_lcdc_bl.0/", "brightness", "rw")
	sysOpen(self, "/sys/class/backlight/mxc_lcdc_bl.0/", "bl_power", "rw")
	sysOpen(self, "/sys/bus/i2c/devices/1-0010/", "ambient")
	sysOpen(self, "/sys/devices/platform/i2c-adapter:i2c-1/1-0010/", "power_mode")
	sysOpen(self, "/sys/devices/platform/i2c-adapter:i2c-1/1-0010/", "battery_charge")
	sysOpen(self, "/sys/devices/platform/i2c-adapter:i2c-1/1-0010/", "battery_capacity")
	sysOpen(self, "/sys/devices/platform/i2c-adapter:i2c-1/1-0010/", "charger_state")

	-- register wakeup/sleep functions
	Framework:registerWakeup(function() wakeup(self) end)
	Framework:addListener(EVENT_ALL_INPUT,
		function(event)
			Framework.wakeup()
		end, true)

	self.powerTimer = Timer(settings.initTimeout,
		function() sleep(self) end)

	-- initial power settings
	self:_initBrightnessTable()
	if settings.brightness > #brightnessTable then
		settings.brightness = #brightnessTable
		self:storeSettings()
	end

	self.lcdBrightness = settings.brightness

	self:initBrightness()

	self:setPowerState("ACTIVE")

	brightnessTimer = Timer( 2000,
		function()
			if settings.brightnessControl != "manual" then
				if not self:isScreenOff() then
					self:doAutomaticBrightnessTimer()
				end
			end
		end)
	brightnessTimer:start()

	-- status bar updates
	local updateTask = Task("statusbar", self, _updateTask)
	updateTask:addTask()
	iconbar.iconWireless:addTimer(5000, function()  -- every five seconds
		updateTask:addTask()
	end)

	Framework:addActionListener("soft_reset", self, _softResetAction, true)

        Framework:addActionListener("shutdown", self, function()
		appletManager:callService("poweroff")
	end)

	-- for testing:
	self.testLowBattery = false
	--Framework:addActionListener("start_demo", self, function()
	--	self.testLowBattery = not self.testLowBattery
	--	log:warn("battery low test ", self.testLowBattery)
	--end, true)

	Framework:addListener(EVENT_SWITCH, function(event)
		local sw,val = event:getSwitch()

		if sw == 1 then
			-- headphone
			self:_headphoneJack(val == 1)

		elseif sw == 2 then
			-- line in
			self:_lineinJack(val == 1)

		elseif sw == 3 then
			-- power event
			self:_updatePower()
		end
	end)

	-- open audio device
	local isHeadphone = (bsp:getMixer("Headphone Switch") > 0)
	if isHeadphone then
		-- set endpoint before the device is opened
		bsp:setMixer("Endpoint", "Headphone")
	end

	Decode:open(settings)

	-- disable crossover after the device is opened
	self:_headphoneJack(isHeadphone)

	-- find out when we connect to player
	jnt:subscribe(self)

	if bsp:getMixer("Line In Switch") then
		self:_lineinJack(true)
	end

	playSplashSound(self)
end

local MAX_BRIGHTNESS_LEVEL = -1
-- Minium Brightness is 11 because IDLE powerstate subtracts 10 form the value passed to setBrightness

local MIN_BRIGHTNESS_LEVEL = 11
local STATIC_AMBIENT_MIN = -1

-- Maximum number of brightness levels up/down per run of the timer
local AMBIENT_RAMPSTEPS = -1

local wasDimmed = false
local brightCur = -1

function initBrightness(self)
	-- Static Variables
	MAX_BRIGHTNESS_LEVEL = #brightnessTable
	STATIC_AMBIENT_MIN = 10000
	AMBIENT_RAMPSTEPS = 4

	-- Init some values to a default value
	brightCur = MAX_BRIGHTNESS_LEVEL

	self.brightPrev = self:getBrightness()
	if self.brightPrev and self.brightPrev == 0 then
		--don't ever fallback to off
		self.brightPrev = 70
	end

end


function isScreenOff(self)
	return self:getBrightness() == 0
end


function doBrightnessRamping(self, target)
	local diff = 0
	diff = (target - brightCur)
	log:warn("ramp: target(" .. target .. "), brightCur(" .. brightCur ..")")
	--log:info("Diff: " .. diff)

	if math.abs(diff) > AMBIENT_RAMPSTEPS then
		diff = AMBIENT_RAMPSTEPS

		-- is there an easier solution for this?
		if brightCur > target then
			diff = diff * -1.0
		end
	end

	brightCur = brightCur + diff

	-- make sure brighCur is a integer
	brightCur = math.floor(brightCur)

	if brightCur > MAX_BRIGHTNESS_LEVEL then
		brightCur = MAX_BRIGHTNESS_LEVEL
	elseif brightCur < MIN_BRIGHTNESS_LEVEL then
		brightCur = MIN_BRIGHTNESS_LEVEL
	end

end

function doAutomaticBrightnessTimer(self)

	-- As long as the power state is active don't do anything
	if self.powerState ==  "ACTIVE" then
		if wasDimmed == true then
			log:info("SWITCHED TO ACTIVE: " .. self.powerState)
			-- set brightness so that the ACTIVE power state removes the 60% dimming
			self:setBrightness( brightCur )
			wasDimmed = false
		end
		return
	else
		wasDimmed = true
	end

	local settings = self:getSettings()

	-- Now continue with the real ambient code
	local ambient = sysReadNumber(self, "ambient")

	--[[
	log:info("Ambient:      " .. tostring(ambient))
	log:info("MaxBright:    " .. tostring(MAX_BRIGHTNESS_LEVEL))
	log:info("Brightness:   " .. tostring(settings.brightness))
	]]--

	-- switch around ambient value
	ambient = STATIC_AMBIENT_MIN - ambient
	if ambient < 0 then
		ambient = 0
	end
	--log:info("AmbientFixed: " .. tostring(ambient))


	local brightTarget = (MAX_BRIGHTNESS_LEVEL / STATIC_AMBIENT_MIN) * ambient

	self:doBrightnessRamping(brightTarget);

	-- Set Brightness
	self:setBrightness( brightCur )

	--log:info("CurTarMax:    " .. tostring(brightCur) .. " - ".. tostring(brightTarget))

end

--service method
function performHalfDuplexBugTest(self)
	return self._revision < 5
end


--service method
function getDefaultWallpaper(self)
	local wallpaper = "bb_encore.png" -- default, if none found examining serial
	if self._serial then
		local colorCode = self._serial:sub(11,12)

		if colorCode == "00" then
			log:debug("case is black")
			wallpaper = "bb_encore.png"
		elseif colorCode == "01" then
			log:debug("case is red")
			wallpaper = "bb_encorered.png"
		else
			log:warn("No case color found (assuming black) examining serial: ", self._serial )
		end
	end

	return wallpaper
end


function _setEndpoint(self)
	if self.isHeadphone == nil then
		-- don't change state during initialization
		return
	end

	local endpoint
	if self.isHeadphone then
		endpoint = "Headphone"
	elseif self.powerState == "ACTIVE" or self.powerState == "IDLE" then
		endpoint = "Speaker"
	else
		-- only power off when using the power amp to prevent
		-- pops on headphones
		endpoint = "Off"
	end

	if self.endpoint == endpoint then
		return
	end
	self.endpoint = endpoint

	if endpoint == "Speaker" then
		bsp:setMixer("Crossover", true)
		bsp:setMixer("Endpoint", endpoint)
	else
		bsp:setMixer("Endpoint", endpoint)
		bsp:setMixer("Crossover", false)
	end
end


function _headphoneJack(self, val)
	self.isHeadphone = val
	self:_setEndpoint()
end


function _lineinJack(self, val)
	if val then
		appletManager:callService("addLineInMenuItem")
	else
		appletManager:callService("removeLineInMenuItem")
	end
end


function _softResetAction(self, event)
	LocalPlayer:disconnectServerAndPreserveLocalPlayer()
	jiveMain:goHome()
end


function notify_playerCurrent(self, player)
	-- if not passed a player, or if player hasn't change, exit
	if not player or not player:isConnected() then
		return
	end

	if self.player == player then
		return
	end
	self.player = player

	local sink = function(chunk, err)
		if err then
			log:warn(err)
			return
		end
		log:debug('date sync: ', chunk.data.date)
                self:setDate(chunk.data.date)
 	end

	-- setup a once/hour
        player:subscribe(
		'/slim/datestatus/' .. player:getId(),
		sink,
		player:getId(),
		{ 'date', 'subscribe:3600' }
	)
end


function notify_playerDelete(self, player)
	if self.player ~= player then
		return
	end
	self.player = false

	log:debug('unsubscribing from datestatus/', player:getId())
	player:unsubscribe('/slim/datestatus/' .. player:getId())
end


function setDate(self, date)
	-- matches date format 2007-09-08T20:40:42+00:00
	local CCYY, MM, DD, hh, mm, ss, TZ = string.match(date, "(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)([-+]%d%d:%d%d)")

	log:debug("CCYY=", CCYY, " MM=", MM, " DD=", DD, " hh=", hh, " mm=", mm, " ss=", ss, " TZ=", TZ)

	-- set system date
	os.execute("/bin/date " .. MM..DD..hh..mm..CCYY.."."..ss)

	-- set RTC to system time
	os.execute("hwclock -w")

	iconbar:update()
end


local function _updateWireless(self)
	local iface = Networking:activeInterface()
	local player = Player:getLocalPlayer()

	if not iface then
		iconbar:setWirelessSignal(nil)
	else
		if iface:isWireless() then
			-- wireless strength
			local quality, strength = iface:getLinkQuality()
			iconbar:setWirelessSignal(quality ~= nil and quality or "ERROR")

			if player then
				player:setSignalStrength(strength)
			end
		else
			-- wired
			local status = iface:t_wpaStatus()
			iconbar:setWirelessSignal(not status.link and "ERROR" or nil)

			if player then
				player:setSignalStrength(nil)
			end
		end
	end
end


-- return true to prevent firmware updates
function isBatteryLow(self)
	local chargerState = sysReadNumber(self, "charger_state")

	if chargerState == 3 then
		local batteryCharge = sysReadNumber(self, "battery_charge")
		local batteryCapacity = sysReadNumber(self, "battery_capacity")

		local batteryRemain = (batteryCharge / batteryCapacity) * 100

		return batteryRemain < 10

	elseif chargerState == 4 then
		return true
	else
		return false
	end
end


function _updatePower(self)
	local isLowBattery = false
	local chargerState = sysReadNumber(self, "charger_state")

	if chargerState == 1 then
		-- no battery is installed, we must be on ac!
		log:debug("no battery")
		iconbar:setBattery(nil)

	elseif chargerState == 2 then
		log:debug("on ac, fully charged")
		iconbar:setBattery("AC")

	elseif chargerState == 3 then
		-- running on battery
		local batteryCharge = sysReadNumber(self, "battery_charge")
		local batteryCapacity = sysReadNumber(self, "battery_capacity")

		local batteryRemain = (batteryCharge / batteryCapacity) * 100
		log:debug("on battery power ", batteryRemain, "%")

		iconbar:setBattery(math.min(math.floor(batteryRemain / 25) + 1, 4))

	elseif chargerState == 4 then
		log:debug("low battery")
		isLowBattery = true
		iconbar:setBattery(0)

	elseif chargerState & 8 then
		log:debug("on ac, charging")
		iconbar:setBattery("CHARGING")

	else
		log:warn("invalid chargerState")
		iconbar:setBattery(nil)
	end

	self:_lowBattery(isLowBattery or self.testLowBattery)
end


function _lowBattery(self, isLowBattery)
	if self.isLowBattery == isLowBattery then
		return
	end

	self.isLowBattery = isLowBattery

	if not isLowBattery then
		appletManager:callService("lowBatteryCancel")
	else
		appletManager:callService("lowBattery")
	end
end


function _updateTask(self)
	while true do
		_updatePower(self)
		_updateWireless(self)

		-- suspend task
		Task:yield(false)
	end
end


function sleep(self)
	local state = self.powerState
	local player = Player:getLocalPlayer()

	log:debug("sleep: ", state)

	if state == "ACTIVE" then
		if player then
			local poweron = player:isPowerOn()

			if not poweron then
				return self:setPowerState("SLEEP")
			end
		end

		return self:setPowerState("IDLE")

	elseif state == "IDLE" then
		if player then
			local playmode = player:getPlayMode()

			if playmode == "play" then
				return self.powerTimer:stop()
			end
		end

		return self:setPowerState("SLEEP")

	elseif state == "SLEEP" then
		return self:setPowerState("HIBERNATE")
	end
end


function wakeup(self)
	log:debug("wakeup: ", self.powerState)

	self:setPowerState("ACTIVE")
end


function notify_playerPower(self, player, power)
	if not player:isLocal() then
		return
	end

	if power then
		self:wakeup()
	else
		self:setPowerState(self.powerState)
	end
end


function notify_playerModeChange(self, player, mode)
	if not player:isLocal() then
		return
	end

	if mode == 'play' then
		self:wakeup()
	else
		self:setPowerState(self.powerState)
	end
end


function setPowerState(self, state)
	local settings = self:getSettings()

	if state == "ACTIVE" then
		self.powerTimer:restart(settings.idleTimeout)

	elseif state == "IDLE" then
		self.powerTimer:restart(settings.sleepTimeout)

	elseif state == "SLEEP" then
		self.powerTimer:restart(settings.hibernateTimeout)

	elseif state == "HIBERNATE" then
		self.powerTimer:stop()
	end

	if self.powerState == state then
		return
	end

	log:debug("powerState: ", self.powerState, "->", state)

	self.powerState = state

	_setEndpoint(self)
	_setBrightness(self, self.lcdBrightness)
end


function _initBrightnessTable( self)
	local pwm_steps = 256
	local brightness_step_percent = 10
	local k = 1

	--first value is "off" value
	brightnessTable[k] = {0, 0}
	k = k + 1

	if self._revision >= 3 then
		-- Brightness table for PB3 and newer
		-- First parameter can be 1 to achieve very low brightness
		brightnessTable[k] = {1, 1}
		for step = 1, pwm_steps, 1 do
			if 100 * ( step - brightnessTable[k][2]) / brightnessTable[k][2] >= brightness_step_percent then
				k = k + 1
				brightnessTable[k] = {1, step}
			end
		end
		k = k + 1
		brightnessTable[k] = {0, 33}
		for step = 33, pwm_steps, 1 do
			if 100 * ( step - brightnessTable[k][2]) / brightnessTable[k][2] >= brightness_step_percent then
				k = k + 1
				brightnessTable[k] = {0, step}
			end
		end
	else
		-- Brightness table for PB1 and PB2
		-- First parameter need to be 0 at all times, else brightness is really dark
		brightnessTable[k] = {0, 1}
		for step = 1, pwm_steps, 1 do
			if 100 * ( step - brightnessTable[k][2]) / brightnessTable[k][2] >= brightness_step_percent then
				k = k + 1
				brightnessTable[k] = {0, step}
			end
		end
	end

-- This is debugging stuff, Caleb, isn't it?
--	local a
--	for k = 1, #brightnessTable, 1 do
--		a = brightnessTable[k][1]
--		a = brightnessTable[k][2]
--	end
end


function _setBrightness(self, level)
	log:debug("_setBrightness: ", level)

	self.lcdBrightness = level

	level = level + 1 -- adjust 0 based to one based for the brightnessTable

	if level > MAX_BRIGHTNESS_LEVEL  then
		level = MAX_BRIGHTNESS_LEVEL
	end

	-- 60% brightness in idle power mode
	if self.powerState == "IDLE" then
		if level > 11 then
			level = level - 10
		else
			level = 2 --(lowest visible setting)
		end
	end

	brightness = brightnessTable[level][2]
	bl_power   = brightnessTable[level][1]

	sysWrite(self, "brightness", brightness)
	sysWrite(self, "bl_power",   bl_power)
end


function getBrightness (self)
	return self.lcdBrightness
end


function setBrightness (self, level)
	-- FIXME a quick hack to prevent the display from dimming
	if level == "off" then
		level = 0
	elseif level == "on" then
		level = self.brightPrev
	elseif level == nil then
		return
	else
		self.brightPrev = level
	end

	_setBrightness(self, level)
end


function settingsBrightnessShow (self, menuItem)
	local window = Window("text_list", self:string("BSP_BRIGHTNESS"), squeezeboxjiveTitleStyle)

	local settings = self:getSettings()
	local level = settings.brightness

	local slider = Slider("slider", 1, #brightnessTable, level,
		function(slider, value, done)
			settings.brightness = value

			-- If the user modifies the slider - automatically switch to manaul brightness
			settings.brightnessControl = "manual"

			local bright = value

			self:setBrightness(bright)

			-- done is true for 'go' and 'play' but we do not want to leave
			if done then
				window:playSound("BUMP")
				window:bumpRight()
			end
	end)

	-- Allow IR to move brightness slider up and down
	slider:addListener(EVENT_IR_DOWN | EVENT_IR_REPEAT,
		function(event)
			if event:isIRCode("arrow_down") then
				local e = Event:new(EVENT_SCROLL, -1)
				Framework:dispatchEvent(slider, e)
				return EVENT_CONSUME
			elseif event:isIRCode("arrow_up") then
				local e = Event:new(EVENT_SCROLL, 1)
				Framework:dispatchEvent(slider, e)
				return EVENT_CONSUME
			end
		end)

	window:addWidget(Textarea("help_text", self:string("BSP_BRIGHTNESS_ADJUST_HELP")))
	window:addWidget(Group("sliderGroup", {
		min = Icon("button_slider_min"),
		slider = slider,
		max = Icon("button_slider_max"),
	}))

	-- If we are here already, eat this event to avoid piling up this screen over and over
	window:addActionListener("go_brightness", self,
				function()
					return EVENT_CONSUME
				end)

	window:addListener(EVENT_WINDOW_POP,
		function()
			self:storeSettings()
		end
	)

	window:show()
	return window
end

function settingsBrightnessControlShow(self, menuItem)
	local window = Window("text_list", self:string("BSP_BRIGHTNESS_CTRL"), squeezeboxjiveTitleStyle)
	local settings = self:getSettings()

	local group = RadioGroup()
	--log:info("Setting: " .. settings.brightnessControl)
	local menu = SimpleMenu("menu", {
		{
			text = self:string("BSP_BRIGHTNESS_AUTOMATIC"),
			style = "item_choice",
			check = RadioButton("radio", group, function(event, menuItem)
						settings.brightnessControl = "automatic"
					end,
					settings.brightnessControl == "automatic")
		},
		{
			text = self:string("BSP_BRIGHTNESS_MANUAL"),
			style = "item_choice",
			check = RadioButton("radio", group, function(event, menuItem)
						settings.brightnessControl = "manual"
						self:setBrightness(settings.brightness)
					end,
					settings.brightnessControl == "manual")
		}
	})

	window:addListener(EVENT_WINDOW_POP,
		function()
			self:storeSettings()
		end
	)

	window:addWidget(menu)
	self:tieAndShowWindow(window)

end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]
