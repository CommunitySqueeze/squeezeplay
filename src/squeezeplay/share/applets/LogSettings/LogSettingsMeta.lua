
--[[
=head1 NAME

applets.LogSettings.LogSettingsMeta - LogSettings meta-info

=head1 DESCRIPTION

See L<applets.LogSettings.LogSettingsApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")
local System        = require("jive.System")

local appletManager = appletManager
local jiveMain      = jiveMain
local lfs           = require("lfs")


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
	return 1, 1
end


function registerApplet(meta)
	-- only make this available if an SD card is slotted in and
	-- a /media/*/log directory is present
	local media = false
	if lfs.attributes("/media", "mode") ~= nil then
		for dir in lfs.dir("/media") do
			if lfs.attributes("/media/" .. dir .. "/log", "mode") == "directory" then
				media = true
				break
			end
		end
	end

	local desktop = not System:isHardware()

	if desktop or media then
		jiveMain:addItem(meta:menuItem('appletLogSettings', 'advancedSettings', 'DEBUG_LOG', function(applet, ...) applet:logSettings(...) end))
	end
end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]

