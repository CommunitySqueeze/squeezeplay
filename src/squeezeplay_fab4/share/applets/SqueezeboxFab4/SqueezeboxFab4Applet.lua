
local tonumber, tostring = tonumber, tostring

-- board specific driver
local fab4_bsp               = require("fab4_bsp")

local oo                     = require("loop.simple")
local os                     = require("os")
local io                     = require("io")
local string                 = require("string")
local math                   = require("math")

local Applet                 = require("jive.Applet")
local System                 = require("jive.System")

local Framework              = require("jive.ui.Framework")
local Group                  = require("jive.ui.Group")
local Icon                   = require("jive.ui.Icon")
local Button                 = require("jive.ui.Button")
local Event                  = require("jive.ui.Event")
local Popup                  = require("jive.ui.Popup")
local Textarea               = require("jive.ui.Textarea")
local Timer                  = require("jive.ui.Timer")
local SimpleMenu             = require("jive.ui.SimpleMenu")
local Slider                 = require("jive.ui.Slider")
local RadioGroup             = require("jive.ui.RadioGroup")
local RadioButton            = require("jive.ui.RadioButton")
local Window                 = require("jive.ui.Window")

local debug                  = require("jive.utils.debug")

local jnt                    = jnt
local iconbar                = iconbar
local jiveMain               = jiveMain
local settings	             = nil

module(..., Framework.constants)
oo.class(_M, Applet)


function init(self)
	local uuid, mac

	settings = self:getSettings()

	-- read device uuid
	local f = io.open("/proc/cpuinfo")
	if f then
		for line in f:lines() do
			if string.match(line, "UUID") then
				uuid = string.match(line, "UUID%s+:%s+([%x-]+)")
				uuid = string.gsub(uuid, "[^%x]", "")
			end
		end
		f:close()
	end

	System:init({
		uuid = uuid,
		machine = "fab4",
	})

	mac = System:getMacAddress()
	uuid = System:getUUID()

	if not uuid or string.match(mac, "^00:40:20")
		or uuid == "00000000-0000-0000-0000-000000000000"
		or mac == "00:04:20:ff:ff:01" then
		local window = Window("help_list", self:string("INVALID_MAC_TITLE"))

		window:setAllowScreensaver(false)
		window:setAlwaysOnTop(true)
		window:setAutoHide(false)

		local text = Textarea("help_text", self:string("INVALID_MAC_TEXT"))
		local menu = SimpleMenu("menu", {
			{
				text = self:string("INVALID_MAC_CONTINUE"),
				sound = "WINDOWHIDE",
				callback = function()
						   window:hide()
					   end
			},
		})

		menu:setHeaderWidget(text)
		window:addWidget(menu)
		window:show()
	end


	settings.brightness = settings.brightness or 100
	settings.ambient = settings.ambient or 0
	settings.brightnessControl = settings.brightnessControl or "manual"

	self:initBrightness()
	local brightnessTimer = Timer( 2000,
		function()
			if settings.brightnessControl == "manual" then
				self:doManualBrightnessTimer()
			else
				self:doAutomaticBrightnessTimer()
			end
		end)
	brightnessTimer:start()
	
	Framework:addActionListener("soft_reset", self, _softResetAction, true)

	-- find out when we connect to player
	jnt:subscribe(self)

	self:storeSettings()
end

-----------------------------
-- Ambient Light Stuff Start
-----------------------------
-- Ambient SysFS Path
local AMBIENT_SYSPATH = "/sys/bus/i2c/devices/0-0039/"

-- Default/Start Values
local brightCur = 100
local brightMax = 100
local brightTarget = 100
local brightSettings = 0;

local brightOverride = 0

-- Minimum Brightness - Default:1, calculated using settings.brightness
-- 	- This variable should probably be configurable by the users
local brightMinMax = 50
local brightMin = 1

-- Maximum number of brightness levels up/down per run of the timer
local AMBIENT_RAMPSTEPS = 7

-- Initialize Brightness Stuff (Factor)
function initBrightness(self)
	self.brightPrev = self:getBrightness()
	if self.brightPrev and self.brightPrev == 0 then
		--don't ever fallback to off
		self.brightPrev = 50
	end
	-- Initialize the Ambient Sensor with a factor of 30
	local f = io.open(AMBIENT_SYSPATH .. "factor", "w")
	f:write("30")
	f:close()
		
	-- Set Initial Settings Brightness
	if not settings.brightness then
		settings.brightness = brightMax
	end

	brightSettings = settings.brightness
	brightMax = (settings.brightness/2) + brightMinMax
		
	-- Create a global listener to set 
	Framework:addListener(ACTION | EVENT_SCROLL | EVENT_MOUSE_ALL | EVENT_MOTION | EVENT_IR_ALL,
		function(event)
			if settings.brightnessControl == "manual" then 
				return
			end
					
			-- if this is a new 'touch' event set brightness to max
			if brightOverride == 0 then
				self:setBrightness( math.floor(brightCur) )
			end
			
			brightOverride = 2	
			return EVENT_UNUSED
		end
		,true)		
end

function doBrightnessRamping(self, target)
	local diff = 0
	diff = (target - brightCur)
	
	--log:info("Diff: " .. diff)

	if math.abs(diff) > AMBIENT_RAMPSTEPS then
		diff = AMBIENT_RAMPSTEPS
			
		-- is there an easier solution for this?
		if brightCur > target then
			diff = diff * -1.0
		end
	end
		
	brightCur = brightCur + diff	

	if brightCur > 100 then
		brightCur = 100
	elseif brightCur < 1 then
		brightCur = 1	
	end
	
	--log:info("Cur: " .. brightCur)
end

-- Fully Automatic Brigthness

-- 3500 Is about the value I've seen in my room during full daylight
-- so set it somewhere below that
local staticLuxMax = 2000

function doAutomaticBrightnessTimer(self)

	-- As long as the user is touching the screen don't do anything more
	if brightOverride > 0 then
		-- count down once per cycle
		brightOverride = brightOverride - 1
		return
	end
	
	-- Now continue with the real ambient code 
	local f = io.open(AMBIENT_SYSPATH .. "lux")
	local lux = f:read("*all")
	f:close()
	
	local luxvalue = tonumber(string.sub(lux, 0, string.len(lux)-1))
	
	if luxvalue > staticLuxMax then
		-- Fix calculation for very high lux values
		luxvalue = staticLuxMax
	end
	
	local brightTarget = (100.0 / staticLuxMax) * luxvalue
	
	self:doBrightnessRamping(brightTarget);
	
	-- Set Brightness
	self:setBrightness( math.floor(brightCur) )
	
	--log:info("LuxValue: " .. tostring(luxvalue))
	--log:info("CurTarMax: " .. tostring(brightCur) .. " - ".. tostring(brightTarget))
	
end

-- Valid Brightness goes from 1 - 100, 0 = display off
function doManualBrightnessTimer(self)
	-- First Check if it is automatic or manual brightness control
	if settings.brightnessControl == "manual" then
		if settings.brightness != brightSettings then
			self:setBrightness(settings.brightness)
			brightSettings = settings.brightness
		end
		return
	end
end

---
-- END BRIGHTNESS
---


--disconnect from player and server and re-set "clean (no server)" LocalPlayer as current player
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

	iconbar:update()
end


function getBrightness (self)
	local f = io.open("/sys/class/backlight/mxc_ipu_bl.0/brightness", "r")
	local level = f:read("*a")
	f:close()

	--opposite of setBrigtness translation
	return math.floor(100 * math.pow(tonumber(level)/255, 1/1.38)) -- gives 0 to 100
end


function setBrightness (self, level)
	if level == "off" or level == 0 then
		level = 0
	elseif level == "on" then
		level = self.brightPrev
	else
		self.brightPrev = level
	end

	--ceil((percentage_bright)^(1.58)*255)
	local deviceLevel = math.ceil(math.pow((level/100.0), 1.38) * 255) -- gives 1 to 1 for first 6, and 255 for max (100)
	if deviceLevel > 255 then -- make sure we don't exceed
		deviceLevel = 255 --max
	end


	local f = io.open("/sys/class/backlight/mxc_ipu_bl.0/brightness", "w")
	f:write(tostring(deviceLevel))
	f:close()
	if log:isDebug() then
		log:debug(" level: ", level, " deviceLevel:", deviceLevel, " getBrightness: ", self:getBrightness())
	end
end


function settingsBrightnessShow (self, menuItem)
	local window = Window("text_list", self:string("BSP_BRIGHTNESS"), squeezeboxjiveTitleStyle)

	local settings = self:getSettings()
	local level = settings.brightness

	local slider = Slider('brightness_slider', 1, 100, level,
				function(slider, value, done)
					
					if settings.brightnessControl != "manual" then
						settings.brightnessControl = "manual"
					end
					
					settings.brightness = value

					local bright = settings.brightness + settings.ambient
					if bright > 100 then
						bright = 100
					end

					if settings.brightnessControl == "manual" then
						self:setBrightness( bright)
					end
					--
					-- Quick fix to avoid error
					if settings.ambient == nil then
						settings.ambient = 0
					end

					if done then
						window:playSound("WINDOWSHOW")
						window:hide(Window.transitionPushLeft)
					end
				end)
	slider.jumpOnDown = false
	slider.dragThreshold = 5

--	window:addWidget(Textarea("help_text", self:string("BSP_BRIGHTNESS_ADJUST_HELP")))
	window:addWidget(Group('brightness_group', {
				div6 = Icon('div6'),
				div7 = Icon('div7'),


				down  = Button(
					Icon('down'),
					function()
						local e = Event:new(EVENT_SCROLL, -1)
						Framework:dispatchEvent(slider, e)
						return EVENT_CONSUME
					end
				),
				up  = Button(
					Icon('up'),
					function()
						local e = Event:new(EVENT_SCROLL, 1)
						Framework:dispatchEvent(slider, e)
						return EVENT_CONSUME
					end
				),
				slider = slider,
			}))

	window:addActionListener("page_down", self,
				function()
					local e = Event:new(EVENT_SCROLL, 1)
					Framework:dispatchEvent(self.volSlider, e)
					return EVENT_CONSUME
				end)
	window:addActionListener("page_up", self,
				function()
					local e = Event:new(EVENT_SCROLL, -1)
					Framework:dispatchEvent(self.volSlider, e)
					return EVENT_CONSUME
				end)

--	window:addWidget(slider) - for focus purposes (todo: get style right for this so slider can be focused)


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
