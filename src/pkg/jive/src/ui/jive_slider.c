/*
** Copyright 2007 Logitech. All Rights Reserved.
**
** This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.
*/

#include "common.h"
#include "jive.h"


typedef struct slider_widget {
	JiveWidget w;

	JiveTile *bg;
	JiveTile *tile;
	bool horizontal;
} SliderWidget;


static JivePeerMeta sliderPeerMeta = {
	sizeof(SliderWidget),
	"JiveSlider",
	jiveL_slider_gc,
};


int jiveL_slider_skin(lua_State *L) {
	SliderWidget *peer;
	JiveTile *bg, *tile;

	/* stack is:
	 * 1: widget
	 */

	lua_pushcfunction(L, jiveL_style_path);
	lua_pushvalue(L, -2);
	lua_call(L, 1, 0);

	peer = jive_getpeer(L, 1, &sliderPeerMeta);

	jive_widget_pack(L, 1, (JiveWidget *)peer);

	/* slider background */
	bg = jive_style_tile(L, 1, "bgImg", NULL);
	if (peer->bg != bg) {
		if (peer->bg) {
			jive_tile_free(peer->bg);
		}

		peer->bg = jive_tile_ref(bg);
	}

	/* vertial or horizontal */
	peer->horizontal = jive_style_int(L, 1, "horizontal", 1);

	/* slider bubble */
	tile = jive_style_tile(L, 1, "img", NULL);
	if (peer->tile != tile) {
		if (peer->tile) {
			jive_tile_free(peer->tile);
		}

		peer->tile = jive_tile_ref(tile);
	}

	return 0;
}


int jiveL_slider_layout(lua_State *L) {

	/* stack is:
	 * 1: widget
	 */

	return 0;
}

int jiveL_slider_draw(lua_State *L) {

	/* stack is:
	 * 1: widget
	 * 2: surface
	 * 3: layer
	 */

	SliderWidget *peer = jive_getpeer(L, 1, &sliderPeerMeta);
	JiveSurface *srf = tolua_tousertype(L, 2, 0);
	bool drawLayer = luaL_optinteger(L, 3, JIVE_LAYER_ALL) & peer->w.layer;

	if (!drawLayer) {
		return 0;
	}

	if (peer->bg) {
		jive_tile_blit(peer->bg, srf, peer->w.bounds.x, peer->w.bounds.y, peer->w.bounds.w, peer->w.bounds.h);
	}

	if (peer->tile) {
		int height, width;
		int range, value, size;
		int x, y, w, h;
		Uint16 tw, th;

		height = peer->w.bounds.h - peer->w.padding.top - peer->w.padding.bottom;
		width = peer->w.bounds.w - peer->w.padding.left - peer->w.padding.right;
	
		lua_getfield(L, 1, "range");
		range = lua_tointeger(L, -1);

		lua_getfield(L, 1, "value");
		value = lua_tointeger(L, -1);
		lua_pop(L, 2);

		lua_getfield(L, 1, "size");
		size = lua_tointeger(L, -1);
		lua_pop(L, 2);

		jive_tile_get_min_size(peer->tile, &tw, &th);

		if (peer->horizontal) {
			width -= tw;
			x = (width / (float)(range - 1)) * (value - 1);
			w = (width / (float)(range - 1)) * (size - 1) + tw;
			y = 0;
			h = height;
		}
		else {
			height -= th;
			x = 0;
			w = width;
			y = (height / (float)(range - 1)) * (value - 1);
			h = (height / (float)(range - 1)) * (size - 1) + th;
		}

		jive_tile_blit(peer->tile, srf, peer->w.bounds.x + peer->w.padding.left + x, peer->w.bounds.y + peer->w.padding.right + y, w, h);
	}

	return 0;
}

int jiveL_slider_get_preferred_bounds(lua_State *L) {
	SliderWidget *peer;
	Uint16 w = 0;
	Uint16 h = 0;

	/* stack is:
	 * 1: widget
	 */

	if (jive_getmethod(L, 1, "checkSkin")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);
	}

	peer = jive_getpeer(L, 1, &sliderPeerMeta);

	if (peer->bg) {
		jive_tile_get_min_size(peer->bg, &w, &h);
	}

	if (peer->w.preferred_bounds.x == JIVE_XY_NIL) {
		lua_pushnil(L);
	}
	else {
		lua_pushinteger(L, peer->w.preferred_bounds.x);
	}
	if (peer->w.preferred_bounds.y == JIVE_XY_NIL) {
		lua_pushnil(L);
	}
	else {
		lua_pushinteger(L, peer->w.preferred_bounds.y);
	}

	if (peer->horizontal) {
		lua_pushinteger(L, JIVE_WH_FILL);
		lua_pushinteger(L, (peer->w.preferred_bounds.h == JIVE_WH_NIL) ? h : peer->w.preferred_bounds.h);
	}
	else {
		lua_pushinteger(L, (peer->w.preferred_bounds.w == JIVE_WH_NIL) ? w : peer->w.preferred_bounds.w);
		lua_pushinteger(L, JIVE_WH_FILL);
	}
	return 4;
}

int jiveL_slider_gc(lua_State *L) {
	SliderWidget *peer;

	luaL_checkudata(L, 1, sliderPeerMeta.magic);

	peer = lua_touserdata(L, 1);

	if (peer->bg) {
		jive_tile_free(peer->bg);
		peer->bg = NULL;
	}
	if (peer->tile) {
		jive_tile_free(peer->tile);
		peer->tile = NULL;
	}

	return 0;
}
