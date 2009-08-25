
local pairs = pairs

local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")
local LocalPlayer   = require("jive.slim.LocalPlayer")
local SlimServer    = require("jive.slim.SlimServer")

local Sample        = require("squeezeplay.sample")

local SqueezeboxMeta = require("applets.Squeezebox.SqueezeboxMeta")

local appletManager = appletManager
local jiveMain      = jiveMain
local jive          = jive
local jnt           = jnt


module(...)
oo.class(_M, SqueezeboxMeta)


function jiveVersion(meta)
	return 1, 1
end


function defaultSettings(meta)
	return { 
		alsaPlaybackDevice = "default",
		alsaPlaybackBufferTime = 20000,
		alsaPlaybackPeriodCount = 2,
		alsaEffectsDevice = "plughw:2,0",
		alsaEffectsBufferTime = 20000,
		alsaEffectsPeriodCount = 2,
		alsaSampleSize = 24,
	}
end


function upgradeSettings(meta, settings)
	-- fill in any blanks
	local defaults = defaultSettings(meta)
	for k, v in pairs(defaults) do
		if not settings[k] then
			settings[k] = v
		end
	end

	-- fix buffer time
	settings.alsaPlaybackBufferTime = 20000
	settings.alsaEffectsBufferTime = 20000

	return settings
end


function registerApplet(meta)
	-- profile functions, 1 second warn, 10 second die
	jive.perfhook(1000, 10000)

	SqueezeboxMeta.registerApplet(meta)

	-- Set player device type
	LocalPlayer:setDeviceType("fab4", "Squeezebox Touch")

	-- Set the minimum support server version
	SlimServer:setMinimumVersion("7.4")

	-- System sound effects attenuation
	Sample:setEffectAttenuation(Sample.MAXVOLUME)

	-- Bug 9900
	-- Use SN test during development
	jnt:setSNHostname("fab4.squeezenetwork.com")

	-- BSP is a resident Applet
	appletManager:loadApplet("SqueezeboxFab4")


	-- audio playback defaults
	appletManager:addDefaultSetting("Playback", "enableAudio", 1)

	jiveMain:setDefaultSkin("WQVGAsmallSkin")

	-- settings
	jiveMain:addItem(meta:menuItem('brightnessSetting', 'settingsBrightness', "BSP_BRIGHTNESS", function(applet, ...) applet:settingsBrightnessShow(...) end))
	jiveMain:addItem(meta:menuItem('brightnessSettingControl', 'settingsBrightness', "BSP_BRIGHTNESS_CTRL", function(applet, ...) applet:settingsBrightnessControlShow(...) end))

	-- services
	meta:registerService("getBrightness")
	meta:registerService("setBrightness")
end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]

