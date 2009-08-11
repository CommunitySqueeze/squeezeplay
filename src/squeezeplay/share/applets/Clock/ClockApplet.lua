
local ipairs, pairs, tonumber, setmetatable, type, tostring = ipairs, pairs, tonumber, setmetatable, type, tostring

local math             = require("math")
local table            = require("table")
local os	       = require("os")	
local string	       = require("jive.utils.string")
local debug	       = require("jive.utils.debug")

local oo               = require("loop.simple")

local Applet           = require("jive.Applet")
local Font             = require("jive.ui.Font")
local Framework        = require("jive.ui.Framework")
local Group            = require("jive.ui.Group")
local Icon             = require("jive.ui.Icon")
local Canvas           = require("jive.ui.Canvas")
local Choice           = require("jive.ui.Choice")
local Label            = require("jive.ui.Label")
local RadioButton      = require("jive.ui.RadioButton")
local RadioGroup       = require("jive.ui.RadioGroup")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Surface          = require("jive.ui.Surface")
local Tile             = require("jive.ui.Tile")
local Window           = require("jive.ui.Window")
                       
local datetime         = require("jive.utils.datetime")

local appletManager	= appletManager
local jiveMain          = jiveMain

local LAYER_FRAME            = jive.ui.LAYER_FRAME
local LAYER_CONTENT_ON_STAGE = jive.ui.LAYER_CONTENT_ON_STAGE

local LAYOUT_NORTH           = jive.ui.LAYOUT_NORTH
local LAYOUT_EAST            = jive.ui.LAYOUT_EAST
local LAYOUT_SOUTH           = jive.ui.LAYOUT_SOUTH
local LAYOUT_WEST            = jive.ui.LAYOUT_WEST
local LAYOUT_CENTER          = jive.ui.LAYOUT_CENTER
local LAYOUT_NONE            = jive.ui.LAYOUT_NONE

local WH_FILL                = jive.ui.WH_FILL


module(..., Framework.constants)
oo.class(_M, Applet)

-- Define useful variables for this skin
local fontpath = "fonts/"
local FONT_NAME = "FreeSans"
local BOLD_PREFIX = "Bold"

local function _imgpath(self)
	return "applets/" .. self.skinName .. "/images/"
end

local function _loadImage(self, file)
	return Surface:loadImage(self.imgpath .. file)
end

-- define a local function that makes it easier to set fonts
local function _font(fontSize)
	return Font:load(fontpath .. FONT_NAME .. ".ttf", fontSize)
end

-- define a local function that makes it easier to set bold fonts
local function _boldfont(fontSize)
	return Font:load(fontpath .. FONT_NAME .. BOLD_PREFIX .. ".ttf", fontSize)
end

-- defines a new style that inherrits from an existing style
local function _uses(parent, value)
	if parent == nil then
		log:warn("nil parent in _uses at:\n", debug.traceback())
	end
	local style = {}
	setmetatable(style, { __index = parent })
	for k,v in pairs(value or {}) do
		if type(v) == "table" and type(parent[k]) == "table" then
			-- recursively inherrit from parent style
			style[k] = _uses(parent[k], v)
		else
			style[k] = v
		end
	end

	return style
end

function displayName(self)
	return "Clock (NEW)"
end


Clock  = oo.class()

function Clock:__init(skin, windowStyle)
	log:debug("Init Clock")

	local obj = oo.rawnew(self)

	obj.screen_width, obj.screen_height = Framework:getScreenSize()

	-- create window and icon
	if not windowStyle then
		windowStyle = 'Clock'
	end
	obj.window = Window(windowStyle)
	obj.window:setSkin(skin)
	obj.window:reSkin()
	obj.window:setShowFrameworkWidgets(false)

	obj.window:addListener(EVENT_MOTION,
		function()
			obj.window:hide(Window.transitionNone)
			return EVENT_CONSUME
		end)

	-- register window as a screensaver
	local manager = appletManager:getAppletInstance("ScreenSavers")
	manager:screensaverWindow(obj.window)

	return obj
end

DotMatrix = oo.class({}, Clock)

function DotMatrix:__init(ampm, shortDateFormat)
	log:debug("Init Dot Matrix Clock")

	local skinName   = jiveMain:getSelectedSkin()
	local skin       = DotMatrix:getDotMatrixClockSkin(skinName)

	obj = oo.rawnew(self, Clock(skin))

	obj.ampm = ampm

	obj.h1   = Group('h1', {
		digit = Icon('icon_dotMatrixDigit0'),
	})
	obj.h2   = Group('h2', {
		digit = Icon('icon_dotMatrixDigit0'),
	})
	local clockDots = Group('dots', { 
		dots = Icon('icon_dotMatrixDots'),
	})
	obj.m1   = Group('m1', {
		digit = Icon('icon_dotMatrixDigit0'),
	})
	obj.m2   = Group('m2', {
		digit = Icon('icon_dotMatrixDigit0')
	})
	obj.alarm = Group('alarm', {
		alarm = Icon('icon_dotMatrixAlarmOff'),
	})
	obj.M1    = Group('M1', {
		digit    = Icon('icon_dotMatrixDate0'),
	})
	obj.M2    = Group('M2', {
		digit    = Icon('icon_dotMatrixDate0'),
	})
	local dot1  = Group('dot1', {
		dot  = Icon('icon_dotMatrixDateDot'),
	})
	obj.D1    = Group('D1', {
		digit    = Icon('icon_dotMatrixDate0'),
	})
	obj.D2    = Group('D2', {
		digit    = Icon('icon_dotMatrixDate0'),
	})
	local dot2  = Group('dot2', {
		dot  = Icon('icon_dotMatrixDateDot'),
	})
	obj.Y1    = Group('Y1', {
		digit    = Icon('icon_dotMatrixDate0'),
	})
	obj.Y2    = Group('Y2', {
		digit    = Icon('icon_dotMatrixDate0'),
	})
	obj.Y3    = Group('Y3', {
		digit    = Icon('icon_dotMatrixDate0'),
	})
	obj.Y4    = Group('Y4', {
		digit    = Icon('icon_dotMatrixDate0'),
	})

	obj.window:addWidget(obj.h1)
	obj.window:addWidget(obj.h2)
	obj.window:addWidget(clockDots)
	obj.window:addWidget(obj.m1)
	obj.window:addWidget(obj.m2)

	obj.window:addWidget(obj.alarm)
	obj.window:addWidget(obj.M1)
	obj.window:addWidget(obj.M2)
	obj.window:addWidget(dot1)
	obj.window:addWidget(obj.D1)
	obj.window:addWidget(obj.D2)
	obj.window:addWidget(dot2)
	obj.window:addWidget(obj.Y1)
	obj.window:addWidget(obj.Y2)
	obj.window:addWidget(obj.Y3)
	obj.window:addWidget(obj.Y4)

	obj.show_ampm = ampm

	if ampm then
		obj.clock_format_hour = "%I"
	else
		obj.clock_format_hour = "%H"
	end

	obj.clock_format_minute = "%M"
	obj.clock_format_month  = "%m"
	obj.clock_format_day    = "%d"
	obj.clock_format_year   = "%Y"
	
	-- do not allow any format for date here, but instead decide 
	-- based on the position of %m and %d in shortDateFormat 
	-- if the format should end up on this clock as MM.DD.YYYY or DD.MM.YYYY
	local monthSpot = string.find(shortDateFormat, "m")
	local daySpot   = string.find(shortDateFormat, "d")
	if daySpot < monthSpot then
		obj.clock_format_date   = "%d%m%Y"
	else
		obj.clock_format_date   = "%m%d%Y"
	end
	
	obj.clock_format = obj.clock_format_hour .. ":" .. obj.clock_format_minute

	return obj
end


function DotMatrix:Draw()


	local theHour   = os.date(self.clock_format_hour)
	local theMinute = os.date(self.clock_format_minute)
	local theDate   = os.date(self.clock_format_date)

--[[
	FOR TESTING PURPOSES 

	-- MIN test
	local theHour   = '01'
	local theMinute = '01'
	local theDate   = '01012009'

	-- MAX test
	local theHour   = '12'
	local theMinute = '59'
	local theDate   = '12312009'
--]]

	-- draw hour digits
	self:DrawClock(string.sub(theHour, 1, 1), 'h1')
	self:DrawClock(string.sub(theHour, 2, 2), 'h2')

	-- draw minute digits
	theTime = os.date(self.clock_format_minute)
	self:DrawClock(string.sub(theMinute, 1, 1), 'm1')
	self:DrawClock(string.sub(theMinute, 2, 2), 'm2')

	-- draw month digits
	theTime = os.date(self.clock_format_date)
	self:DrawDate(string.sub(theDate, 1, 1), 'M1')
	self:DrawDate(string.sub(theDate, 2, 2), 'M2')

	-- draw day digits
	self:DrawDate(string.sub(theDate, 3, 3), 'D1')
	self:DrawDate(string.sub(theDate, 4, 4), 'D2')

	-- draw year digits
	self:DrawDate(string.sub(theDate, 5, 5), 'Y1')
	self:DrawDate(string.sub(theDate, 6, 6), 'Y2')
	self:DrawDate(string.sub(theDate, 7, 7), 'Y3')
	self:DrawDate(string.sub(theDate, 8, 8), 'Y4')
	--self:DrawMinTest()
end


function DotMatrix:DrawClock(digit, groupKey)
	local style = 'icon_dotMatrixDigit' .. digit
	if digit == '0' and groupKey == 'h1' and self.ampm then
		style = 'icon_dotMatrixDigitNone'
	end
	local widget = self[groupKey]:getWidget('digit')
	widget:setStyle(style)
end


function DotMatrix:DrawDate(digit, groupKey)
	local style = 'icon_dotMatrixDate' .. digit
	local widget = self[groupKey]:getWidget('digit')
	widget:setStyle(style)
end

Digital = oo.class({}, Clock)

function Digital:__init(applet, ampm)
	log:debug("Init Digital Clock")
	
	local windowStyle = applet.windowStyle or 'Clock'

	local skinName   = jiveMain:getSelectedSkin()
	local skin       = Digital:getDigitalClockSkin(skinName)

	obj = oo.rawnew(self, Clock(skin, windowStyle))

	-- store the applet's self so we can call self.applet:string() for localizations
	obj.applet = applet

	obj.h1   = Label('h1', '1')
	obj.h2   = Label('h2', '2')
	local dots = Group('dots', { 
		dots = Icon("icon_digitalDots") 
		}
	)
	obj.m1   = Label('m1', '0')
	obj.m2   = Label('m2', '0')
	obj.ampm = Label('ampm', '')


	obj.alarm = Group('alarm', {
		Icon('icon_digitalAlarmOn')
	})

	obj.today = Label('today', '')
	obj.dateGroup = Group('date', {
		dayofweek  = Label('dayofweek', ''),
		vdivider1  = Icon('icon_digitalClockVDivider'),
		dayofmonth = Label('dayofmonth'),
		vdivider2  = Icon('icon_digitalClockVDivider'),
		month      = Label('month'),
	})

	obj.ampm = Label('ampm')

	local hdivider = Group('horizDivider', {
		horizDivider = Icon('icon_digitalClockHDivider'),
	})
	local hdivider2 = Group('horizDivider2', {
		horizDivider = Icon('icon_digitalClockHDivider'),
	})

	obj.h1Shadow   = Group('h1Shadow', { 
		h1Shadow = Icon('icon_digitalClockDropShadow'), 
	})
	obj.h2Shadow   = Group('h2Shadow', {
		h2Shadow = Icon('icon_digitalClockDropShadow'),
	})
	obj.m1Shadow   = Group('m1Shadow', {
		m1Shadow = Icon('icon_digitalClockDropShadow'),
	})
	obj.m2Shadow   = Group('m2Shadow', {
		m2Shadow = Icon('icon_digitalClockDropShadow'),
	})

	obj.window:addWidget(obj.today)
	--obj.window:addWidget(obj.alarm)
	-- clock widgets
	obj.window:addWidget(obj.h1)
	obj.window:addWidget(obj.h1Shadow)
	obj.window:addWidget(obj.h2)
	obj.window:addWidget(obj.h2Shadow)
	obj.window:addWidget(dots)
	obj.window:addWidget(obj.m1)
	obj.window:addWidget(obj.m1Shadow)
	obj.window:addWidget(obj.m2)
	obj.window:addWidget(obj.m2Shadow)
	obj.window:addWidget(obj.ampm)

	obj.window:addWidget(hdivider)
	obj.window:addWidget(hdivider2)

	-- date widgets
	obj.window:addWidget(obj.dateGroup)

	obj.show_ampm = ampm

	if ampm then
		obj.clock_format_hour = "%I"
		obj.useAmPm = true
	else
		obj.clock_format_hour = "%H"
		obj.useAmPm = false
	end
	obj.clock_format_minute = "%M"

	obj.clock_format = obj.clock_format_hour .. ":" .. obj.clock_format_minute

	return obj
end

	
function Digital:Draw()

	-- string day of week
	local dayOfWeek   = os.date("%w")
	local token = "SCREENSAVER_CLOCK_DAY_" .. tostring(dayOfWeek)
	local dayOfWeekString = self.applet:string(token)
	self.today:setValue(dayOfWeekString)
	local widget = self.dateGroup:getWidget('dayofweek')
	widget:setValue(dayOfWeekString)

	-- numerical day of month
	local dayOfMonth = os.date("%d")
	widget = self.dateGroup:getWidget('dayofmonth')
	widget:setValue(dayOfMonth)

	-- string month of year
	local monthOfYear = os.date("%m")
	token = "SCREENSAVER_CLOCK_MONTH_" .. tostring(monthOfYear)
	local monthString = self.applet:string(token)
	widget = self.dateGroup:getWidget('month')
	widget:setValue(monthString)

	-- what time is it? it's time to get ill!
	self:DrawTime()
	
	--FOR DEBUG
	--[[
	self:DrawMinTest()
	self:DrawMaxTest()
	--]]
end
	
-- this method is around for testing the rendering of different elements
-- it is not called in practice
function Digital:DrawMinTest()

	self.h1:setValue('')
	local widget = self.h1Shadow:getWidget('h1Shadow')
	widget:setStyle('icon_digitalClockNoShadow')
	self.h2:setValue('1')
	self.m1:setValue('0')
	self.m2:setValue('1')
	
	self.ampm:setValue('AM')

	widget = self.dateGroup:getWidget('dayofweek')
	widget:setValue('Monday')
	widget = self.dateGroup:getWidget('dayofmonth')
	widget:setValue('01')
	widget = self.dateGroup:getWidget('month')
	widget:setValue('July')

end

-- this method is around for testing the rendering of different elements
-- it is not called in practice
function Digital:DrawMaxTest()

	self.h1:setValue('1')
	self.h2:setValue('2')
	self.m1:setValue('5')
	self.m2:setValue('9')
	
	self.ampm:setValue('PM')

	widget = self.dateGroup:getWidget('dayofweek')
	widget:setValue('Wednesday')
	widget = self.dateGroup:getWidget('dayofmonth')
	widget:setValue('31')
	widget = self.dateGroup:getWidget('month')
	widget:setValue('September')
end


function Digital:DrawTime()
	local theHour   = os.date(self.clock_format_hour)
	local theMinute = os.date(self.clock_format_minute)

	if string.sub(theHour, 1, 1) == '0' then
		self.h1:setValue('')
		widget = self.h1Shadow:getWidget('h1Shadow')
		widget:setStyle('icon_digitalClockNoShadow')
	else
		self.h1:setValue(string.sub(theHour, 1, 1))
		widget = self.h1Shadow:getWidget('h1Shadow')
		widget:setStyle('icon_digitalClockDropShadow')
	end
	self.h2:setValue(string.sub(theHour, 2, 2))

	self.m1:setValue(string.sub(theMinute, 1, 1))
	self.m2:setValue(string.sub(theMinute, 2, 2))
	
	-- Draw AM PM
	if self.useAmPm then
		-- localized ampm rendering
		local ampm = os.date("%p")
		self.ampm:setValue(ampm)
	end

end

-- TODO: Radial Clock
Radial = oo.class({}, Clock)

function Radial:__init(applet, weekstart)
	log:info("Init Radial Clock")

	local skinName   = jiveMain:getSelectedSkin()
	local skin       = Radial:getRadialClockSkin(skinName)

	obj = oo.rawnew(self, Clock(skin))

	obj.skinParams = Radial:getSkinParams(skinName)

	obj.hourTick   = Surface:loadImage(obj.skinParams.hourTickPath)
	obj.minuteTick = Surface:loadImage(obj.skinParams.minuteTickPath)

	-- bring in applet's self so strings are available
	obj.applet    = applet
	-- weekstart is "Sunday" or "Monday"
	obj.weekstart = weekstart

	obj.canvas   = Canvas('debug_canvas', function(screen)
		obj:_reDraw(screen)
	end)
	obj.window:addWidget(obj.canvas)

	obj.ticksOff = Icon('icon_radialClockTicksOff')
	obj.tickGroup = Group('ticks', {
		ticksOff = obj.ticksOff
	})

	local _dayGroup = function() 
		return {
			dot = Icon('icon_radialClockBlankDot'),
			day  = Label('day', '')
		} 
	end

	-- days of week
	obj.day1 = Group('day1', _dayGroup())
	obj.day2 = Group('day2', _dayGroup())
	obj.day3 = Group('day3', _dayGroup())
	obj.day4 = Group('day4', _dayGroup())
	obj.day5 = Group('day5', _dayGroup())
	obj.day6 = Group('day6', _dayGroup())
	obj.day7 = Group('day7', _dayGroup())

	obj.dayOfMonth = Group('dayOfMonth', {
		DoM = Label('DoM', ''),
	})

	obj.window:addWidget(obj.tickGroup)
	obj.window:addWidget(obj.day1)
	obj.window:addWidget(obj.day2)
	obj.window:addWidget(obj.day3)
	obj.window:addWidget(obj.day4)
	obj.window:addWidget(obj.day5)
	obj.window:addWidget(obj.day6)
	obj.window:addWidget(obj.day7)
	obj.window:addWidget(obj.dayOfMonth)

	obj.clock_format = "%H:%M"
	return obj
end


function Radial:Draw()
	self:drawDay()
	self.canvas:reDraw()
end


function Radial:drawDay()

	local dayOfMonth = os.date("%d")
	if self.today == dayOfMonth then
		return
	end

	local dayOfMonthWidget = self.dayOfMonth:getWidget('DoM')
	dayOfMonthWidget:setValue(dayOfMonth)
	self.today = today

	local DAYS_SUN = { "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY" }
	local DAYS_MON = { "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY" }
	local days

	-- if week starts with monday, monday = 1 and days start from monday
        if self.weekstart == "Monday" then
                dayOfWeek = tonumber(os.date("%u"))
                days = DAYS_MON
	-- if week starts with sunday, sunday = 1 and days start from sunday
	else
                dayOfWeek = tonumber(os.date("%w"))+1
                days = DAYS_SUN
        end
	local tokenStub = "SCREENSAVER_CLOCK_DAYSHORT_" 

	local monthString = self.applet:string(token)
	for i = 1, 7 do
		local token = tokenStub .. tostring(days[i])
		local key = "day" .. tostring(i)
		local textWidget = self[key]:getWidget('day')
		textWidget:setValue(self.applet:string(token))

		-- when i is today, style accordingly
		local iconWidget = self[key]:getWidget('dot')
		if i == dayOfWeek then
			-- style icon to be glowing dot
			iconWidget:setStyle('icon_radialClockDot')
			-- style text to be correct color
			textWidget:setStyle('radialClockToday')
			
		else
			-- not today, so style accordingly
			textWidget:setStyle('radialClockNotToday')
			iconWidget:setStyle('icon_radialClockBlankDot')
		end
	end

end


function Radial:_reDraw(screen)

	-- Draw Background
	local x, y, facew, faceh
	
	-- Setup Time Objects
	local m = os.date("%M")
	local h = os.date("%I")

	-- Hour Pointer
	for i = 0, tonumber(h) do
		local angle = (360 / 12) * i
		local tmp = self.hourTick:rotozoom(-angle, 1, 5)
		facew, faceh = tmp:getSize()
		x = math.floor((self.screen_width/2) - (facew/2))
		y = math.floor((self.screen_height/2) - (faceh/2))
		tmp:blit(screen, x, y)
	end

	-- Minute Pointer
	for i = 0, tonumber(m) do
		local angle = (360 / 60) * i
		local tmp = self.minuteTick:rotozoom(-angle, 1, 5)
		facew, faceh = tmp:getSize()
		x = math.floor((self.screen_width/2) - (facew/2))
		y = math.floor((self.screen_height/2) - (faceh/2))
		tmp:blit(screen, x, y)
	end

end


-- keep these methods with their legacy names
-- to ensure backwards compatibility with old settings.lua files
function openDetailedClock(self, force)
	return self:_openScreensaver("Digital", 'Clock', force)
end

function openDetailedClockBlack(self, force)
	return self:_openScreensaver("Digital", 'ClockBlack', force)
end

function openDetailedClockTransparent(self, force)
	return self:_openScreensaver("Digital", 'ClockTransparent', force)
end

function openAnalogClock(self, force)
	return self:_openScreensaver("Radial", _, force)
end

function openStyledClock(self, force)
	return self:_openScreensaver("DotMatrix", _, force)
end


function _tick(self)
	local theTime = os.date(self.clock[1].clock_format)
	if theTime == self.oldTime then
		-- nothing to do yet
		return
	end

	self.oldTime = theTime

	self.clock[self.buffer]:Draw()
	self.clock[self.buffer].window:showInstead(Window.transitionFadeIn)

	self.buffer = (self.buffer == 1) and 2 or 1
end


function _openScreensaver(self, type, windowStyle, force)
	log:debug("Type: " .. type)

	local year = os.date("%Y")
	if tonumber(year) < 2009 and not force then
		local time = os.date()
		log:warn('This device does not seem to have the right time: ', time)
		return
	end
	-- Global Date/Time Settings
	local weekstart       = datetime:getWeekstart() 
	local hours           = datetime:getHours() 
	local shortDateFormat = datetime:getShortDateFormat() 

	hours = (hours == "12")

	-- Create two clock instances, so that we can do use a fade in transition
	self.clock = {}
	self.buffer = 2 -- buffer to display

	if type == "DotMatrix" then
		self.clock[1] = DotMatrix(hours, shortDateFormat)
		self.clock[2] = DotMatrix(hours, shortDateFormat)
	elseif type == "Digital" then
		self.windowStyle = windowStyle
		self.clock[1] = Digital(self, hours)
		self.clock[2] = Digital(self, hours)
	elseif type == "Radial" then
		self.clock[1] = Radial(self, weekstart)
		self.clock[2] = Radial(self, weekstart)
	else
		log:error("Unknown clock type")
		return
	end

	self.clock[1].window:addTimer(1000, function() self:_tick() end)
	self.clock[2].window:addTimer(1000, function() self:_tick() end)

	self.clock[1]:Draw()
	self.clock[1].window:show(Window.transitionFadeIn)
end


-- DOT MATRIX CLOCK SKIN
function DotMatrix:getDotMatrixClockSkin(skinName)

	if skinName == 'WQVGAlargeSkin' then
		skinName = 'WQVGAsmallSkin'
	end

	self.skinName = skinName
	self.imgpath = _imgpath(self)

	local s = {}

	if skinName == 'WQVGAsmallSkin' then

		local dotMatrixBackground = Tile:loadImage(self.imgpath .. "Clocks/Dot_Matrix/wallpaper_clock_dotmatrix.png")

		local _dotMatrixDigit = function(self, digit)
			local fileName = "Clocks/Dot_Matrix/dotmatrix_clock_" .. tostring(digit) .. ".png"
			return {
				w = 61,
				h = 134,
				img = _loadImage(self, fileName),
				border = { 6, 0, 6, 0 },
				align = 'bottom',
			}
		end
	
		local _dotMatrixDate = function(self, digit)
			local fileName = "Clocks/Dot_Matrix/dotmatrix_date_" .. tostring(digit) .. ".png"
			return {
				w = 27,
				h = 43,
				img = _loadImage(self, fileName),
				align = 'bottom',
				border = { 1, 0, 1, 0 },
			}
		end
	
		s.icon_dotMatrixDigit0 = _dotMatrixDigit(self, 0)
		s.icon_dotMatrixDigit1 = _dotMatrixDigit(self, 1)
		s.icon_dotMatrixDigit2 = _dotMatrixDigit(self, 2)
		s.icon_dotMatrixDigit3 = _dotMatrixDigit(self, 3)
		s.icon_dotMatrixDigit4 = _dotMatrixDigit(self, 4)
		s.icon_dotMatrixDigit5 = _dotMatrixDigit(self, 5)
		s.icon_dotMatrixDigit6 = _dotMatrixDigit(self, 6)
		s.icon_dotMatrixDigit7 = _dotMatrixDigit(self, 7)
		s.icon_dotMatrixDigit8 = _dotMatrixDigit(self, 8)
		s.icon_dotMatrixDigit9 = _dotMatrixDigit(self, 9)
		s.icon_dotMatrixDigitNone = _uses(s.icon_dotMatrixDigit9, {
			img = false,
		})
	
		s.icon_dotMatrixDate0 = _dotMatrixDate(self, 0)
		s.icon_dotMatrixDate1 = _dotMatrixDate(self, 1)
		s.icon_dotMatrixDate2 = _dotMatrixDate(self, 2)
		s.icon_dotMatrixDate3 = _dotMatrixDate(self, 3)
		s.icon_dotMatrixDate4 = _dotMatrixDate(self, 4)
		s.icon_dotMatrixDate5 = _dotMatrixDate(self, 5)
		s.icon_dotMatrixDate6 = _dotMatrixDate(self, 6)
		s.icon_dotMatrixDate7 = _dotMatrixDate(self, 7)
		s.icon_dotMatrixDate8 = _dotMatrixDate(self, 8)
		s.icon_dotMatrixDate9 = _dotMatrixDate(self, 9)
	
		s.icon_dotMatrixDateDot = {
			align = 'bottom',
			img = _loadImage(self, "Clocks/Dot_Matrix/dotmatrix_dot_sm.png")
		}
	
		s.icon_dotMatrixDots = {
			align = 'center',
			border = { 4, 0, 3, 0 },
			img = _loadImage(self, "Clocks/Dot_Matrix/dotmatrix_clock_dots.png"),
		}
	
		s.icon_dotMatrixAlarmOn = {
			align = 'bottom',
			img = _loadImage(self, "Clocks/Dot_Matrix/dotmatrix_alarm_on.png"),
			w   = 36,
			border = { 0, 0, 13, 0 },
		}
	
		s.icon_dotMatrixAlarmOff = _uses(s.icon_dotMatrixAlarmOn, {
			img = false,
		})
	
		local _clockDigit = {
			position = LAYOUT_NONE,
			w = 61,
			y = 35,
		}
		local _dateDigit = {
			position = LAYOUT_NONE,
			w = 27,
			y = 191,
		}

		local x = {}
		x.h1 = 72
		x.h2 = x.h1 + 73
		x.dots = x.h2 + 71
		x.m1 = x.dots + 28
		x.m2 = x.m1 + 73
		x.alarm = 72
		x.M1 = 72 + 36 + 14
		x.M2 = x.M1 + 28
		x.dot1 = x.M2 + 27 + 6
		x.D1 = x.dot1 + 13
		x.D2 = x.D1 + 28
		x.dot2 = x.D2 + 27 + 6
		x.Y1 = x.dot2 + 13
		x.Y2 = x.Y1 + 28
		x.Y3 = x.Y2 + 28
		x.Y4 = x.Y3 + 28

		s.Clock = {
			w = 480,
			h = 272,
			bgImg = dotMatrixBackground,
			h1 = _uses(_clockDigit, {
				x = x.h1,
			}),
			h2 = _uses(_clockDigit, {
				x = x.h2,
			}),
			dots = {
				position = LAYOUT_NONE,
				x = x.dots,
				w = 38,
				y = 70,
			},
			m1 = _uses(_clockDigit, {
				x = x.m1,
			}),
			m2 = _uses(_clockDigit, {
				x = x.m2,
			}),

			alarm = _uses(_dateDigit, {
				w = 36,
				x = x.alarm,
			}),
			M1 = _uses(_dateDigit, {
				x = x.M1,
			}),
			M2 = _uses(_dateDigit, {
				x = x.M2,
			}),
			dot1 = _uses(_dateDigit, {
				x = x.dot1,
				w = 13,
				y = 221,
			}),
			D1 = _uses(_dateDigit, {
				x = x.D1,
			}),
			D2 = _uses(_dateDigit, {
				x = x.D2,
			}),
			dot2 = _uses(_dateDigit, {
				x = x.dot2,
				w = 13,
				y = 221,
			}),
			Y1 = _uses(_dateDigit, {
				x = x.Y1,
			}),
			Y2 = _uses(_dateDigit, {
				x = x.Y2,
			}),
			Y3 = _uses(_dateDigit, {
				x = x.Y3,
			}),
			Y4 = _uses(_dateDigit, {
				x = x.Y4,
			}),

		}

	-- dot matrix for landscape QVGA
	elseif skinName == 'QVGAlandscapeSkin' then

		local dotMatrixBackground = Tile:loadImage(self.imgpath .. "Clocks/Dot_Matrix/wallpaper_clock_dotmatrix.png")

		local _dotMatrixDigit = function(self, digit)
			local fileName = "Clocks/Dot_Matrix/dotmatrix_clock_" .. tostring(digit) .. ".png"
			return {
				w = 61,
				h = 134,
				img = _loadImage(self, fileName),
				border = { 6, 0, 6, 0 },
				align = 'bottom',
			}
		end
	
		local _dotMatrixDate = function(self, digit)
			local fileName = "Clocks/Dot_Matrix/dotmatrix_date_" .. tostring(digit) .. ".png"
			return {
				w = 27,
				h = 43,
				img = _loadImage(self, fileName),
				align = 'bottom',
				border = { 1, 0, 1, 0 },
			}
		end
	
		s.icon_dotMatrixDigit0 = _dotMatrixDigit(self, 0)
		s.icon_dotMatrixDigit1 = _dotMatrixDigit(self, 1)
		s.icon_dotMatrixDigit2 = _dotMatrixDigit(self, 2)
		s.icon_dotMatrixDigit3 = _dotMatrixDigit(self, 3)
		s.icon_dotMatrixDigit4 = _dotMatrixDigit(self, 4)
		s.icon_dotMatrixDigit5 = _dotMatrixDigit(self, 5)
		s.icon_dotMatrixDigit6 = _dotMatrixDigit(self, 6)
		s.icon_dotMatrixDigit7 = _dotMatrixDigit(self, 7)
		s.icon_dotMatrixDigit8 = _dotMatrixDigit(self, 8)
		s.icon_dotMatrixDigit9 = _dotMatrixDigit(self, 9)
		s.icon_dotMatrixDigitNone = _uses(s.icon_dotMatrixDigit9, {
			img = false,
		})
	
		s.icon_dotMatrixDate0 = _dotMatrixDate(self, 0)
		s.icon_dotMatrixDate1 = _dotMatrixDate(self, 1)
		s.icon_dotMatrixDate2 = _dotMatrixDate(self, 2)
		s.icon_dotMatrixDate3 = _dotMatrixDate(self, 3)
		s.icon_dotMatrixDate4 = _dotMatrixDate(self, 4)
		s.icon_dotMatrixDate5 = _dotMatrixDate(self, 5)
		s.icon_dotMatrixDate6 = _dotMatrixDate(self, 6)
		s.icon_dotMatrixDate7 = _dotMatrixDate(self, 7)
		s.icon_dotMatrixDate8 = _dotMatrixDate(self, 8)
		s.icon_dotMatrixDate9 = _dotMatrixDate(self, 9)
	
		s.icon_dotMatrixDateDot = {
			align = 'bottom',
			img = _loadImage(self, "Clocks/Dot_Matrix/dotmatrix_dot_sm.png")
		}
	
		s.icon_dotMatrixDots = {
			align = 'center',
			border = { 4, 0, 3, 0 },
			img = _loadImage(self, "Clocks/Dot_Matrix/dotmatrix_clock_dots.png"),
		}
	
		s.icon_dotMatrixAlarmOn = {
			align = 'bottom',
			img = _loadImage(self, "Clocks/Dot_Matrix/dotmatrix_alarm_on.png"),
			w   = 36,
			border = { 0, 0, 13, 0 },
		}
	
		s.icon_dotMatrixAlarmOff = _uses(s.icon_dotMatrixAlarmOn, {
			img = false,
		})
	
		local _clockDigit = {
			position = LAYOUT_NONE,
			w = 61,
			y = 20,
		}
		local _dateDigit = {
			position = LAYOUT_NONE,
			w = 27,
			y = 183,
		}

		local x = {}
		x.h1 = -7
		x.h2 = x.h1 + 72
		x.dots = x.h2 + 74
		x.m1 = x.dots + 28
		x.m2 = x.m1 + 72
		x.alarm = 10 
		x.M1 = x.alarm + 35
		x.M2 = x.M1 + 30
		x.dot1 = x.M2 + 27 + 5
		x.D1 = x.dot1 + 10
		x.D2 = x.D1 + 30
		x.dot2 = x.D2 + 27 + 5
		x.Y1 = x.dot2 + 10
		x.Y2 = x.Y1 + 30
		x.Y3 = x.Y2 + 30
		x.Y4 = x.Y3 + 30

		s.Clock = {
			w = 320,
			h = 240,
			bgImg = dotMatrixBackground,
			h1 = _uses(_clockDigit, {
				x = x.h1,
			}),
			h2 = _uses(_clockDigit, {
				x = x.h2,
			}),
			dots = {
				position = LAYOUT_NONE,
				x = x.dots,
				w = 38,
				y = 57,
			},
			m1 = _uses(_clockDigit, {
				x = x.m1,
			}),
			m2 = _uses(_clockDigit, {
				x = x.m2,
			}),

			alarm = _uses(_dateDigit, {
				w = 36,
				x = x.alarm,
				y = 182,
			}),
			M1 = _uses(_dateDigit, {
				x = x.M1,
			}),
			M2 = _uses(_dateDigit, {
				x = x.M2,
			}),
			dot1 = _uses(_dateDigit, {
				x = x.dot1,
				w = 13,
				y = 213,
			}),
			D1 = _uses(_dateDigit, {
				x = x.D1,
			}),
			D2 = _uses(_dateDigit, {
				x = x.D2,
			}),
			dot2 = _uses(_dateDigit, {
				x = x.dot2,
				w = 13,
				y = 213,
			}),
			Y1 = _uses(_dateDigit, {
				x = x.Y1,
			}),
			Y2 = _uses(_dateDigit, {
				x = x.Y2,
			}),
			Y3 = _uses(_dateDigit, {
				x = x.Y3,
			}),
			Y4 = _uses(_dateDigit, {
				x = x.Y4,
			}),

		}


	-- dot matrix for Controller
	elseif skinName == 'QVGAportraitSkin' then
		local dotMatrixBackground = Tile:loadImage(self.imgpath .. "Clocks/Dot_Matrix/jive_wallpaper_clock_dotmatrix.png")

		local _dotMatrixDigit = function(self, digit)
			local fileName = "Clocks/Dot_Matrix/dotmatrix_clock_" .. tostring(digit) .. ".png"
			return {
				w = 61,
				h = 134,
				img = _loadImage(self, fileName),
				border = { 6, 0, 6, 0 },
				align = 'bottom',
			}
		end
	
		local _dotMatrixDate = function(self, digit)
			local fileName = "Clocks/Dot_Matrix/dotmatrix_date_" .. tostring(digit) .. ".png"
			return {
				w = 27,
				h = 43,
				img = _loadImage(self, fileName),
				align = 'bottom',
				border = { 1, 0, 1, 0 },
			}
		end
	
		s.icon_dotMatrixDigit0 = _dotMatrixDigit(self, 0)
		s.icon_dotMatrixDigit1 = _dotMatrixDigit(self, 1)
		s.icon_dotMatrixDigit2 = _dotMatrixDigit(self, 2)
		s.icon_dotMatrixDigit3 = _dotMatrixDigit(self, 3)
		s.icon_dotMatrixDigit4 = _dotMatrixDigit(self, 4)
		s.icon_dotMatrixDigit5 = _dotMatrixDigit(self, 5)
		s.icon_dotMatrixDigit6 = _dotMatrixDigit(self, 6)
		s.icon_dotMatrixDigit7 = _dotMatrixDigit(self, 7)
		s.icon_dotMatrixDigit8 = _dotMatrixDigit(self, 8)
		s.icon_dotMatrixDigit9 = _dotMatrixDigit(self, 9)
		s.icon_dotMatrixDigitNone = _uses(s.icon_dotMatrixDigit9, {
			img = false,
		})
	
		s.icon_dotMatrixDate0 = { img = false }
		s.icon_dotMatrixDate1 = { img = false }
		s.icon_dotMatrixDate2 = { img = false }
		s.icon_dotMatrixDate3 = { img = false }
		s.icon_dotMatrixDate4 = { img = false }
		s.icon_dotMatrixDate5 = { img = false }
		s.icon_dotMatrixDate6 = { img = false }
		s.icon_dotMatrixDate7 = { img = false }
		s.icon_dotMatrixDate8 = { img = false }
		s.icon_dotMatrixDate9 = { img = false }
	
		s.icon_dotMatrixDateDot = {
			img = false,
		}
	
		s.icon_dotMatrixDots = {
			img = false,
		}
	
		s.icon_dotMatrixAlarmOn = {
			img = false,
		}
		s.icon_dotMatrixAlarmOff = _uses(s.icon_dotMatrixAlarmOn)
	
		s.icon_dotMatrixPowerOn = {
			img = false,
		}
		s.icon_dotMatrixPowerButtonOff = _uses(s.icon_dotMatrixPowerOn, {
			img = false,
		})
	
		local _clockDigit = {
			position = LAYOUT_NONE,
			w = 61,
		}

		local leftDigit = 53
		local rightDigit = 126
		local topDigit = 22
		local bottomDigit = 160

		s.Clock = {
			w = 240,
			h = 320,
			bgImg = dotMatrixBackground,
			h1 = _uses(_clockDigit, {
				x = leftDigit,
				y = topDigit,
			}),
			h2 = _uses(_clockDigit, {
				x = rightDigit,
				y = topDigit,
			}),
			m1 = _uses(_clockDigit, {
				x = leftDigit,
				y = bottomDigit,
			}),
			m2 = _uses(_clockDigit, {
				x = rightDigit,
				y = bottomDigit,
			}),

			dots = { hidden = 1 },
			alarm = { hidden = 1 },
			M1 = { hidden = 1 },
			M2 = { hidden = 1 },
			dot1 = { hidden = 1 },
			D1 = { hidden = 1 },
			D2 = { hidden = 1 },
			dot2 = { hidden = 1 },
			Y1 = { hidden = 1 },
			Y2 = { hidden = 1 },
			Y3 = { hidden = 1 },
			Y4 = { hidden = 1 },
		}


	end

	return s
end

-- DIGITAL CLOCK SKIN
function Digital:getDigitalClockSkin(skinName)
	if skinName == 'WQVGAlargeSkin' then
		skinName = 'WQVGAsmallSkin'
	end
	self.skinName = skinName
	self.imgpath = _imgpath(self)

	local s = {}

	if skinName == 'WQVGAsmallSkin' then

		local digitalClockBackground = Tile:loadImage(self.imgpath .. "Clocks/Digital/wallpaper_clock_digital.png")
		local digitalClockDigit = {
			font = _font(143),
			align = 'center',
			fg = { 0xcc, 0xcc, 0xcc },
			w = 76,
		}
		local shadow = {
			w = 76,
		}

		local x = {}
                x.h1 = 48
                x.h2 = x.h1 + 75
                x.dots = x.h2 + 75
                x.m1 = x.dots + 39
                x.m2 = x.m1 + 86 
                x.alarm = x.m2 + 63
		x.ampm = x.alarm

		local _clockDigit = {
			position = LAYOUT_NONE,
			font = _font(143),
			align = 'center',
			fg = { 0xcc, 0xcc, 0xcc },
			y = 54,
			zOrder = 10,
		}
		local _digitShadow = _uses(_clockDigit, {
			y = 54 + 100,
			zOrder = 1,
		})
	
		s.icon_digitalClockDropShadow = {
			img = _loadImage(self, "Clocks/Digital/drop_shadow_digital.png"),
			align = 'center',
			padding = { 4, 0, 0, 0 },
			w = 76,
		}

		s.icon_digitalClockNoShadow = _uses(s.icon_digitalClockDropShadow, {
			img = false
		})

		s.icon_digitalClockHDivider = {
			w = WH_FILL,
			img = _loadImage(self, "Clocks/Digital/divider_hort_digital.png"),
		}

		s.icon_digitalClockVDivider = {
			w = 3,
			img = _loadImage(self, "Clocks/Digital/divider_vert_digital.png"),
			align = 'center',
		}

		s.icon_digitalDots = {
			img = _loadImage(self, "Clocks/Digital/clock_dots_digital.png"),
			align = 'center',
			w = 40,
			border = { 14, 0, 12, 0 },
		}

		s.icon_digitalClockBlank = {
			img = false,
			w = 40,
		}

		s.Clock = {
			bgImg = digitalClockBackground,
			h1 = _uses(_clockDigit, {
				x = x.h1,
			}),
			h1Shadow = _uses(_digitShadow, {
				x = x.h1,
			}),
			h2 = _uses(_clockDigit, {
				x = x.h2,
			}),
			h2Shadow = _uses(_digitShadow, {
				x = x.h2,
			}),
			dots = _uses(_clockDigit, {
				x = x.dots,
				y = 93,
				w = 40,
			}),
			m1 = _uses(_clockDigit, {
				x = x.m1,
			}),
			m1Shadow = _uses(_digitShadow, {
				x = x.m1,
			}),
			m2 = _uses(_clockDigit, {
				x = x.m2,
			}),
			m2Shadow = _uses(_digitShadow, {
				x = x.m2,
			}),

			ampm = {
				position = LAYOUT_NONE,
				x = x.ampm,
				y = 112,
				font = _font(11),
				align = 'bottom',
				fg = { 0xcc, 0xcc, 0xcc },
			},
			alarm = {
				position = LAYOUT_NONE,
				x = x.alarm,
				y = 65,
			},
			ampm = {
				position = LAYOUT_NONE,
				x = 403,
				y = 144,
				font = _font(20),
				align = 'bottom',
				fg = { 0xcc, 0xcc, 0xcc },
			},
			horizDivider2 = { hidden = 1 },
			today = { hidden = 1 },
			horizDivider = {
				position = LAYOUT_NONE,
				x = 0,
				y = 194,
			},
			date = {
				position = LAYOUT_SOUTH,
				order = { 'dayofweek', 'vdivider1', 'dayofmonth', 'vdivider2', 'month' },
				w = WH_FILL,
				h = 70,
				padding = { 0, 0, 0, 6 },
				dayofweek = {
					align = 'center',
					w = 190,
					h = WH_FILL,
					font = _font(20),
					fg = { 0xcc, 0xcc, 0xcc },
					padding  = { 1, 0, 0, 6 },
				},
				vdivider1 = {
					align = 'center',
					w = 3,
				},
				dayofmonth = {
					font = _font(56),
					w = 95,
					h = WH_FILL,
					align = 'center',
					fg = { 0xcc, 0xcc, 0xcc },
					padding = { 0, 0, 0, 4 },
				},
				vdivider2 = {
					align = 'center',
					w = 3,
				},
				month = {
					font = _font(20),
					w = WH_FILL,
					h = WH_FILL,
					align = 'center',
					fg = { 0xcc, 0xcc, 0xcc },
					padding = { 0, 0, 0, 5 },
				},
				year = {
					font = _boldfont(20),
					w = 50,
					h = WH_FILL,
					align = 'left',
					fg = { 0xcc, 0xcc, 0xcc },
					padding = { 3, 0, 0, 5 },
				},
			},
		}
	
		local blackMask = Tile:fillColor(0x000000ff)
		s.ClockBlack = _uses(s.Clock, {
			bgImg = blackMask,
			horizDivider = { hidden = 1 },
			horizDivider2 = { hidden = 1 },
			today = { hidden = 1 },
			date = {
				order = { 'dayofweek', 'dayofmonth', 'month', 'year' },
			},
			h1Shadow = { hidden = 1 },
			h2Shadow = { hidden = 1 },
			m1Shadow = { hidden = 1 },
			m2Shadow = { hidden = 1 },
		})
		s.ClockTransparent = _uses(s.Clock, {
			bgImg = false,
			horizDivider = { hidden = 1 },
			horizDivider2 = { hidden = 1 },
			today = { hidden = 1 },
			date = {
				order = { 'dayofweek', 'dayofmonth', 'month', 'year' },
			},
			h1Shadow = { hidden = 1 },
			h2Shadow = { hidden = 1 },
			m1Shadow = { hidden = 1 },
			m2Shadow = { hidden = 1 },
		})
	elseif skinName == 'QVGAlandscapeSkin'  then

		local digitalClockBackground = Tile:loadImage(self.imgpath .. "Clocks/Digital/bb_clock_digital.png")
		local shadow = {
			w = 62,
		}
		local _clockDigit = {
			position = LAYOUT_NONE,
			font = _font(100),
			align = 'right',
			fg = { 0xcc, 0xcc, 0xcc },
			w = 62,
			y = 48,
			zOrder = 10,
		}
		local _digitShadow = _uses(_clockDigit, {
			y = 116,
			zOrder = 1,
		})
	
		local x = {}
                x.h1 = 19
                x.h2 = x.h1 + 50 
                x.dots = x.h2 + 65
                x.m1 = x.dots + 15
                x.m2 = x.m1 + 64
                x.alarm = x.m2 + 63
		x.ampm = x.alarm

		s.icon_digitalClockDropShadow = {
			img = _loadImage(self, "Clocks/Digital/drop_shadow_digital.png"),
			align = 'center',
			padding = { 4, 0, 0, 0 },
			w = 62,
		}

		s.icon_digitalClockNoShadow = _uses(s.icon_digitalClockDropShadow, {
				img = false
		})

		s.icon_digitalClockHDivider = {
			w = WH_FILL,
			img = _loadImage(self, "Clocks/Digital/divider_hort_digital.png"),
		}

		s.icon_digitalClockVDivider = {
			w = 3,
			img = _loadImage(self, "Clocks/Digital/divider_vert_digital.png"),
			padding = { 0, 0, 0, 8 },
			align = 'center',
		}

		s.icon_digitalDots = {
			img = _loadImage(self, 'Clocks/Digital/clock_dots_digital.png'),
			align = 'center',
			w = 16,
			padding = { 0, 26, 0, 0 },
		}

		s.icon_digitalClockBlank = {
			img = false,
		}


		s.Clock = {
			bgImg = digitalClockBackground,
			h1 = _uses(_clockDigit, {
				x = x.h1,
			}),
			h1Shadow = _uses(_digitShadow, {
				x = x.h1,
			}),
			h2 = _uses(_clockDigit, {
				x = x.h2,
			}),
			h2Shadow = _uses(_digitShadow, {
				x = x.h2,
			}),
			dots = _uses(_clockDigit, {
				x = x.dots,
				w = 16,
			}),
			m1 = _uses(_clockDigit, {
				x = x.m1,
			}),
			m1Shadow = _uses(_digitShadow, {
				x = x.m1,
			}),
			m2 = _uses(_clockDigit, {
				x = x.m2,
			}),
			m2Shadow = _uses(_digitShadow, {
				x = x.m2,
			}),

			ampm = {
				position = LAYOUT_NONE,
				x = x.ampm,
				y = 112,
				font = _font(11),
				align = 'bottom',
				fg = { 0xcc, 0xcc, 0xcc },
			},
			alarm = {
				position = LAYOUT_NONE,
				x = x.alarm,
				y = 65,
			},
			horizDivider2 = { hidden = 1 },
			horizDivider = {
				position = LAYOUT_NONE,
				x = 0,
				y = 173,
			},
			today = { hidden = '1' },
			date = {
				position = LAYOUT_SOUTH,
				order = { 'dayofweek', 'vdivider1', 'dayofmonth', 'vdivider2', 'month' },
				w = WH_FILL,
				h = 65,
				padding = { 0, 10, 0, 0 },
				dayofweek = {
					align = 'center',
					w = 115,
					h = WH_FILL,
					font = _font(18),
					fg = { 0xcc, 0xcc, 0xcc },
					padding = { 0, 0, 0, 14 },
				},
				vdivider1 = {
					align = 'center',
					w = 2,
				},
				dayofmonth = {
					font = _font(48),
					w = 86,
					h = WH_FILL,
					align = 'center',
					fg = { 0xcc, 0xcc, 0xcc },
					padding = { 0, 0, 0, 12 },
				},
				vdivider2 = {
					align = 'center',
					w = 2,
				},
				month = {
					font = _font(18),
					w = WH_FILL,
					h = WH_FILL,
					align = 'center',
					fg = { 0xcc, 0xcc, 0xcc },
					padding = { 0, 0, 0, 14 },
				},
			},
		}
	
		local blackMask = Tile:fillColor(0x000000ff)
		s.ClockBlack = _uses(s.Clock, {
			bgImg = blackMask,
			horizDivider = { hidden = 1 },
			horizDivider2 = { hidden = 1 },
			today = { hidden = 1 },
			date = {
				order = { 'dayofweek', 'dayofmonth', 'month', 'year' },
			},
			h1Shadow = { hidden = 1 },
			h2Shadow = { hidden = 1 },
			m1Shadow = { hidden = 1 },
			m2Shadow = { hidden = 1 },
		})
		s.ClockTransparent = _uses(s.Clock, {
			bgImg = false,
			horizDivider = { hidden = 1 },
			horizDivider2 = { hidden = 1 },
			today = { hidden = 1 },
			date = {
				order = { 'dayofweek', 'dayofmonth', 'month', 'year' },
			},
			h1Shadow = { hidden = 1 },
			h2Shadow = { hidden = 1 },
			m1Shadow = { hidden = 1 },
			m2Shadow = { hidden = 1 },
		})

	elseif skinName == 'QVGAportraitSkin'  then
		local digitalClockBackground = Tile:loadImage(self.imgpath .. "Clocks/Digital/jive_clock_digital.png")
		local digitalClockDigit = {
			font = _font(100),
			fg = { 0xcc, 0xcc, 0xcc },
			w = WH_FILL,
		}
		local shadow = {
			w = 62,
		}
		local _clockDigit = {
			position = LAYOUT_NONE,
			font = _font(100),
			align = 'right',
			fg = { 0xcc, 0xcc, 0xcc },
			w = 62,
			y = 121,
			zOrder = 10,
		}
		local _digitShadow = _uses(_clockDigit, {
			y = 188,
			zOrder = 1,
		})
	
		local x = {}
                x.h1 = -7
                x.h2 = x.h1 + 45
                x.dots = x.h2 + 65
                x.m1 = x.dots + 7
                x.m2 = x.m1 + 62
                x.alarm = x.m2 + 62
		x.ampm = x.alarm

		s.icon_digitalClockDropShadow = {
			img = _loadImage(self, "Clocks/Digital/drop_shadow_digital.png"),
			align = 'center',
			padding = { 4, 0, 0, 0 },
		}

		s.icon_digitalClockNoShadow = _uses(s.icon_digitalClockDropShadow, {
			img = false
		})

		s.icon_digitalClockHDivider = {
			w = WH_FILL,
			img = _loadImage(self, "Clocks/Digital/divider_hort_digital.png"),
		}

		s.icon_digitalClockVDivider = {
			w = 3,
			img = _loadImage(self, "Clocks/Digital/divider_vert_digital.png"),
			align = 'center',
		}

		s.icon_digitalDots = {
			img = _loadImage(self, 'Clocks/Digital/clock_dots_digital.png'),
			align = 'center',
			w = 16,
			padding = { 0, 0, 0, 0 },
		}

		s.icon_digitalClockBlank = {
			img = false,
		}

		s.Clock = {
			bgImg = digitalClockBackground,
			h1 = _uses(_clockDigit, {
				x = x.h1,
			}),
			h1Shadow = _uses(_digitShadow, {
				x = x.h1,
			}),
			h2 = _uses(_clockDigit, {
				x = x.h2,
			}),
			h2Shadow = _uses(_digitShadow, {
				x = x.h2,
			}),
			dots = _uses(_clockDigit, {
				x = x.dots,
				w = 7,
				y = 148,
			}),
			m1 = _uses(_clockDigit, {
				x = x.m1,
			}),
			m1Shadow = _uses(_digitShadow, {
				x = x.m1,
			}),
			m2 = _uses(_clockDigit, {
				x = x.m2,
			}),
			m2Shadow = _uses(_digitShadow, {
				x = x.m2,
			}),

			today = {
				position = LAYOUT_NORTH,
				h = 83,
				zOrder = 2,
				w = WH_FILL,
				align = 'center',
				fg = { 0xcc, 0xcc, 0xcc },
				font = _font(20),
			},

			ampm = {
				position = LAYOUT_NONE,
				x = 207,
				y = 214,
				font = _font(14),
				align = 'bottom',
				fg = { 0xcc, 0xcc, 0xcc },
			},
			alarm = {
				position = LAYOUT_NONE,
				x = 12,
				y = 148,
			},
			horizDivider = {
				position = LAYOUT_NONE,
				x = 0,
				y = 320 - 84,
			},
			horizDivider2 = {
				position = LAYOUT_NONE,
				x = 0,
				y = 84,
			},
			date = {
				position = LAYOUT_SOUTH,
				order = { 'month', 'vdivider1', 'dayofmonth' },
				w = WH_FILL,
				h = 83,
				padding = { 0, 10, 0, 0 },
				dayofweek = { hidden = 1 },
				vdivider1 = {
					align = 'center',
					w = 2,
					h = WH_FILL,
				},
				month = {
					font = _font(20),
					w = WH_FILL,
					h = WH_FILL,
					align = 'center',
					fg = { 0xcc, 0xcc, 0xcc },
					padding = { 2, 0, 0, 15 },
				},
				dayofmonth = {
					font = _font(48),
					w = 86,
					h = WH_FILL,
					align = 'center',
					fg = { 0xcc, 0xcc, 0xcc },
					padding = { 0, 0, 0, 15 },
				},
			},
		}
	
		local blackMask = Tile:fillColor(0x000000ff)
		s.ClockBlack = _uses(s.Clock, {
			bgImg = blackMask,
			horizDivider = { hidden = 1 },
			horizDivider2 = { hidden = 1 },
			date = {
				order = { 'month', 'dayofmonth' },
			},
			h1Shadow = { hidden = 1 },
			h2Shadow = { hidden = 1 },
			m1Shadow = { hidden = 1 },
			m2Shadow = { hidden = 1 },
		})
		s.ClockTransparent = _uses(s.Clock, {
			bgImg = false,
			horizDivider = { hidden = 1 },
			horizDivider2 = { hidden = 1 },
			date = {
				order = { 'month', 'dayofmonth' },
			},
			h1Shadow = { hidden = 1 },
			h2Shadow = { hidden = 1 },
			m1Shadow = { hidden = 1 },
			m2Shadow = { hidden = 1 },
		})
	
	end

	return s
end

-- RADIAL CLOCK
function Radial:getRadialClockSkin(skinName)
	if skinName == 'WQVGAlargeSkin' then
		skinName = 'WQVGAsmallSkin'
	end
	self.skinName = skinName
	self.imgpath = _imgpath(self)

	local s = {}

	if skinName == 'WQVGAsmallSkin' then

		local radialClockBackground = Tile:loadImage(self.imgpath .. "Clocks/Radial/wallpaper_clock_radial.png")
		s.icon_radialClockTicksOff = {
			img = _loadImage(self, "Clocks/Radial/radial_ticks_off.png"),
			align = 'center',
		}
		s.icon_radialClockMinuteTick = {
			img = _loadImage(self, "Clocks/Radial/radial_ticks_min_on.png"),
		}
		s.icon_radialClockHourTick = {
			img = _loadImage(self, "Clocks/Radial/radial_ticks_hr_on.png"),
		}
	
		s.radialClockToday = {
			w = 14,
			align = 'center',
			font = _font(14),
			fg = { 0xe6, 0xe6, 0xe6 },
		}
		s.radialClockNotToday = {
			w = 14,
			align = 'center',
			font = _font(14),
			fg = { 0x66, 0x66, 0x66 },
		}
		s.icon_radialClockDot = {
			w   = 26,
			h   = 18,
			img = _loadImage(self, "Clocks/Radial/dot_weekday_indicator.png"),
			padding = { 4, 0, 4, 0 },
		}
		s.icon_radialClockBlankDot = {
			w   = 26,
			h   = 18,
			img = false,
			padding = { 4, 0, 4, 0 },
		}
	
		local _dayPosition = function(day)
			local y = 33*day - 3 
			return {
				position = LAYOUT_NONE,
				x = 6,
				y = y,
				w = 42,
				h = 18,
				order = { 'dot', 'day' },
			}
		end
	
		s.Clock = {
			bgImg = radialClockBackground,
			ticks = {
				position = LAYOUT_CENTER,
				order = { 'ticksOff' },
				padding = { 122, 36, 0, 0 },
			},
			day1 = _dayPosition(1),
			day2 = _dayPosition(2),
			day3 = _dayPosition(3),
			day4 = _dayPosition(4),
			day5 = _dayPosition(5),
			day6 = _dayPosition(6),
			day7 = _dayPosition(7),
			dayOfMonth = {
				position = LAYOUT_EAST,
				w = 80,
				h = WH_FILL,
				align = 'center',
				padding = { 0, 120, 0, 0 },
				order = { 'DoM' },
				DoM = {
					align = 'center',
					font = _font(32),
					fg   = { 0xb3, 0xb3, 0xb3 },
				},
			},
		}

	elseif skinName == 'QVGAportraitSkin' then

	elseif skinName == 'SomeOtherSkin' then

	end
	
	return s

end

function Radial:getSkinParams(skin)
        return {
		hourTickPath     = 'applets/' .. skin .. '/images/Clocks/Radial/radial_ticks_hr_on.png',
		minuteTickPath   = 'applets/' .. skin .. '/images/Clocks/Radial/radial_ticks_min_on.png',
	}
end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]

