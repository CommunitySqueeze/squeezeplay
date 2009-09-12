
--[[
=head1 NAME

applets.ImageViewer.ImageSourceServer - Image source for Image Viewer

=head1 DESCRIPTION

Reads image list from SC or SN, currently just continuous photo streams, not fixed list based

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local setmetatable, tonumber, tostring, ipairs, locale, type, pairs = setmetatable, tonumber, tostring, ipairs, locale, type, pairs

local Applet		= require("jive.Applet")
local appletManager	= require("jive.AppletManager")
local Event			= require("jive.ui.Event")
local io			= require("io")
local oo			= require("loop.simple")
local math			= require("math")
local table			= require("jive.utils.table")
local string		= require("jive.utils.string")
local debug                  = require("jive.utils.debug")
local lfs			= require('lfs')
local Group			= require("jive.ui.Group")
local Keyboard		= require("jive.ui.Keyboard")
local Textarea		= require("jive.ui.Textarea")
local Textinput     = require("jive.ui.Textinput")
local Window        = require("jive.ui.Window")
local SocketHttp	= require("jive.net.SocketHttp")
local RequestHttp	= require("jive.net.RequestHttp")
local URL       	= require("socket.url")
local Surface		= require("jive.ui.Surface")
local Process		= require("jive.net.Process")
local Player             = require("jive.slim.Player")
local Framework		= require("jive.ui.Framework")

local jnt = jnt
local jiveMain = jiveMain
local json                   = json

local log 		= require("jive.utils.log").logger("applet.ImageViewer")
local require = require
local ImageSource	= require("applets.ImageViewer.ImageSource")

module(...)
oo.class(_M, ImageSource)

function __init(self, applet, serverData)
	log:info("initialize ImageSourceServer")
	obj = oo.rawnew(self, ImageSource(applet))

	obj.imgFiles = {}

	obj.serverData = serverData


	obj.imageDataHistory = {}
	obj.imageDataHistoryMax = 30
	
	obj:readImageList()

	return obj
end


function readImageList(self)
	local cmd = self.serverData.cmd
	local playerId = self.serverData.playerId
	local server = self.serverData.server
	log:debug("readImageList: server:", server, " id: ", self.serverData.id, " playerId: ", playerId)

	server:request(
		imgFilesSink(self),
		playerId,
		cmd
	)
end

function getImage(self)
	return self.image
end

function imgFilesSink(self)
	return function(chunk, err)
	       	if err then
			log:warn("err in sink ", err)

		elseif chunk then
			if log:isDebug() then
				log:debug("imgFilesSink:")
				debug.dump(chunk, 5)
			end
			if chunk and chunk.data and chunk.data.data then
				self.imgFiles = _cleanseNilListData(chunk.data.data)
				self.currentImageIndex = 0
				self.lstReady = true

				log:debug("Image list response count: ", #self.imgFiles)
			end
		end
	end

end

function _cleanseNilListData(inputList)
	local outputList = {}

	for _,data in ipairs(inputList) do
		if data.image ~= json.null then
			table.insert(outputList, data)
		end
	end

	return outputList
end

function nextImage(self)
	if #self.imgFiles == 0 then
		self:emptyListError()
		return
	end

	self.currentImageIndex = self.currentImageIndex + 1
	if self.currentImageIndex <= #self.imgFiles then
		local imageData = self.imgFiles[self.currentImageIndex]
		self:requestImage(imageData, true)
	end
	--else might exceed if connection is down, if so don't try to reload another pic, just keep retrying until success

	if self.currentImageIndex == #self.imgFiles then
		--queue up next list
		self:readImageList()
	end
end

function previousImage(self, ordering)
	if #self.imageDataHistory == 1 then
		return
	end

	--remove from history, similar to brwoser back history, except forward always move to next fetched image.
	table.remove(self.imageDataHistory, #self.imageDataHistory) -- remove current
	local imageData = table.remove(self.imageDataHistory, #self.imageDataHistory) -- get previous

	self:requestImage(imageData)
end

function _updateImageDataHistory(self, imageData)
	table.insert(self.imageDataHistory, imageData)

	if #self.imageDataHistory > self.imageDataHistoryMax then
		table.remove(self.imageDataHistory, 1)
	end

end


function requestImage(self, imageData)
	log:debug("request new image")
	-- request current image
	self.imgReady = false

	local screenWidth, screenHeight = Framework:getScreenSize()

	local urlString = imageData.image
	--use SN image proxy for resizing
	urlString = 'http://' .. jnt:getSNHostname() .. '/public/imageproxy?w=' .. screenWidth .. '&h=' .. screenHeight .. '&f=' .. ''  .. '&u=' .. string.urlEncode(urlString)

	self.currentImageFile = urlString

	local textLines = {}
	if imageData.caption and imageData.caption ~= "" then
		table.insert(textLines, imageData.caption)
	end
	if imageData.date and imageData.date ~= "" then
		table.insert(textLines, imageData.date)
	end
	if imageData.owner and imageData.owner ~= "" then
		table.insert(textLines, imageData.owner)
	end

	self.currentCaption = ""
	self.currentCaptionMultiline = ""
	for i,line in ipairs(textLines) do
		self.currentCaption = self.currentCaption .. line
		self.currentCaptionMultiline = self.currentCaptionMultiline .. line
		if i < #textLines then
			self.currentCaption = self.currentCaption .. " - "
			self.currentCaptionMultiline = self.currentCaptionMultiline .. "\n\n"
		end
	end

	-- Default URI settings
	local defaults = {
	    host   = "",
	    port   = 80,
	    path   = "/",
	    scheme = "http"
	}
	local parsed = URL.parse(urlString, defaults)

	log:debug("url: " .. urlString)

	-- create a HTTP socket (see L<jive.net.SocketHttp>)
	local http = SocketHttp(jnt, parsed.host, parsed.port, "ImageSourceServer")
	local req = RequestHttp(function(chunk, err)
			if chunk then
				local image = Surface:loadImageData(chunk, #chunk)
				self.image = image
				self.imgReady = true
				log:debug("image ready")
				self:_updateImageDataHistory(imageData)
			elseif err then
				log:debug("error loading picture")
			end
		end,
		'GET', urlString)
	http:fetch(req)
end

function getText(self)
	return self.currentCaption
end


function getMultilineText(self)
	return self.currentCaptionMultiline
end


function settings(self, window)
    return window
end

function updateLoadingIcon(self, icon)
	if self.serverData.appParameters and self.serverData.appParameters.iconId then
		self.serverData.server:fetchArtwork(self.serverData.appParameters.iconId, icon, jiveMain:getSkinParam('THUMB_SIZE'), 'png')
	end
end

function useAutoZoom(self)
	return false
end


--[[

=head1 LICENSE

Copyright 2008 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]

