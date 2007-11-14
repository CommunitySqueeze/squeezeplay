
--[[
=head1 NAME

applets.SetupDateTime.SetupDateTime - Add a main menu option for setting up date and time formats

=head1 DESCRIPTION

Allows user to select different date and time settings

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local ipairs, pairs, io, string, tostring = ipairs, pairs, io, string, tostring
local os = os

local oo               = require("loop.simple")

local Applet           = require("jive.Applet")
local Choice	       = require("jive.ui.Choice")
local RadioButton      = require("jive.ui.RadioButton")
local RadioGroup       = require("jive.ui.RadioGroup")
local Framework        = require("jive.ui.Framework")
local Label            = require("jive.ui.Label")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Textarea         = require("jive.ui.Textarea")
local Window           = require("jive.ui.Window")

local log              = require("jive.utils.log").logger("applets.setup")
local locale           = require("jive.utils.locale")
local datetime         = require("jive.utils.datetime")
local table            = require("jive.utils.table")

local appletManager    = appletManager
local EVENT_KEY_PRESS  = jive.ui.EVENT_KEY_PRESS
local EVENT_SCROLL     = jive.ui.EVENT_SCROLL
local EVENT_CONSUME    = jive.ui.EVENT_CONSUME
local EVENT_ACTION     = jive.ui.EVENT_ACTION
local EVENT_WINDOW_POP = jive.ui.EVENT_WINDOW_POP
local KEY_PLAY         = jive.ui.KEY_PLAY

local datetimeTitleStyle = 'settingstitle'

module(...)
oo.class(_M, Applet)

function settingsShow(self, menuItem)
	local window = Window("window", menuItem.text, datetimeTitleStyle)

	local curHours = ""
	if self:getSettings()["hours"] == 12 then
		curHours = 1
	else
		curHours = 2
	end

	local curWeekStart
	if self:getSettings()["weekstart"] == "Monday" then
		curWeekStart = 2
	else
		curWeekStart = 1
	end

	window:addWidget(SimpleMenu("menu",
		{
			{	
				text = self:string("DATETIME_TIMEFORMAT"),
				sound = "WINDOWSHOW",
				callback = function(obj, selectedIndex)
						self:timeSetting(menuItem)
					end
			},
			{
				text = self:string("DATETIME_DATEFORMAT"),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
						self:dateFormatSetting(menuItem)
						return EVENT_CONSUME
					end
			},
			{
				text = self:string("DATETIME_WEEKSTART"),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
						self:weekstartSetting(menuItem)
					end
			},
		}
	))


	window:addListener(EVENT_WINDOW_POP, 
		function()
			self:storeSettings()
		end
	)

	self:tieAndShowWindow(window)
	return window
end

function timeSetting(self, menuItem)
	local window = Window("window", menuItem.text, datetimeTitleStyle)
	local group = RadioGroup()

	local current = self:getSettings()["hours"]

	local menu = SimpleMenu("menu", {
		{
			text = self:string("DATETIME_TIMEFORMAT_12H"),
			icon = RadioButton("radio", group, function(event, menuItem)
					self:setHours("12")
				end,
			current == "12")
		},
		{
			text = self:string("DATETIME_TIMEFORMAT_24H"),
			icon = RadioButton("radio", group, function(event, menuItem)
					self:setHours("24")
				end,
			current == "24")
		},
	})

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window;
end

function dateFormatSetting(self, menuItem)
	local window = Window("window", menuItem.text, datetimeTitleStyle)
	local group = RadioGroup()

	local current = self:getSettings()["dateformat"]

	local menu = SimpleMenu("menu", {})

	for k,v in pairs(datetime:getAllDateFormats()) do
		local _text = os.date(v)
		if string.match(v, '%%d') or string.match(v, '%%m') then
			local _help = _getDateHelpString(v)
			_text = _text .. " (" .. _help .. ")"
		end
--[[		if tostring(v) == '%D' then
			_text = _text .. " (mm/dd/yy)"
		end
--]]
		menu:addItem({
				text = _text,
				icon = RadioButton("radio", group, function(event, menuItem)
						self:setDateFormat(v)
					end,
				current == v)
		})
	end

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end

function _getDateHelpString(dateString)
	dateString = string.gsub(dateString, '%%d', 'DD')
	dateString = string.gsub(dateString, '%%m', 'MM')
	dateString = string.gsub(dateString, '%%Y', 'YYYY')
	dateString = string.gsub(dateString, '%%y', 'YY')
	dateString = string.gsub(dateString, '%%a', 'WWW')
	dateString = string.gsub(dateString, '%%A', 'WWWW')
	dateString = string.gsub(dateString, '%%b', 'MMM')
	dateString = string.gsub(dateString, '%%B', 'MMMM')
	return dateString
end

function weekstartSetting(self, menuItem)
	local window = Window("window", menuItem.text, datetimeTitleStyle)
	local group = RadioGroup()

	local current = self:getSettings()["weekstart"]

	local menu = SimpleMenu("menu", {
		{
			text = self:string("DATETIME_SUNDAY"),
			icon = RadioButton("radio", group, function(event, menuItem)
					self:setWeekStart("Sunday")
				end,
			current == "Sunday")
		},
		{
			text = self:string("DATETIME_MONDAY"),
			icon = RadioButton("radio", group, function(event, menuItem)
					self:setWeekStart("Monday")
				end,
			current == "Monday")
		},
	})

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window;
end

function setDateFormat(self, format)
	self:getSettings()["dateformat"] = format
	datetime:setDateFormat(format)
end

function setWeekStart(self, day)
	self:getSettings()["weekstart"] = day
	datetime:setWeekstart(day)
end

function setHours(self, hours)
	self:getSettings()["hours"] = hours
	datetime:setHours(hours)
end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]

