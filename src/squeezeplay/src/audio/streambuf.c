/*
** Copyright 2007-2008 Logitech. All Rights Reserved.
**
** This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.
*/

#define RUNTIME_DEBUG 1

#include "common.h"

#include "audio/fifo.h"
#include "audio/streambuf.h"
#include "audio/decode/decode.h"
#include "audio/decode/decode_priv.h"


#if defined(WIN32)

#include <winsock2.h>

typedef SOCKET socket_t;
#define CLOSESOCKET(s) closesocket(s)
#define SHUT_WR SD_SEND
#define SOCKETERROR WSAGetLastError()

#else

typedef int socket_t;
#define CLOSESOCKET(s) close(s)
#define INVALID_SOCKET (-1)
#define SOCKETERROR errno

#endif


#define STREAMBUF_SIZE (3 * 1024 * 1024)

static u8_t streambuf_buf[STREAMBUF_SIZE];
static struct fifo streambuf_fifo;
static size_t streambuf_lptr = 0;
static bool_t streambuf_loop = FALSE;
static bool_t streambuf_streaming = FALSE;
static u64_t streambuf_bytes_received = 0;

/* streambuf filter, used to parse metadata */
static streambuf_filter_t streambuf_filter;
static streambuf_filter_t streambuf_next_filter;

/* shoutcast metadata state */
static u32_t icy_meta_interval;
static s32_t icy_meta_remaining;


size_t streambuf_get_size(void) {
	return STREAMBUF_SIZE;
}


size_t streambuf_get_freebytes(void) {
	size_t n;

	fifo_lock(&streambuf_fifo);

	n = fifo_bytes_free(&streambuf_fifo);

	fifo_unlock(&streambuf_fifo);

	return n;
}


size_t streambuf_get_usedbytes(void) {
	size_t n;

	fifo_lock(&streambuf_fifo);

	n = fifo_bytes_used(&streambuf_fifo);

	fifo_unlock(&streambuf_fifo);

	return n;
}
/* returns true if the stream is still open but cannot yet supply the requested bytes */
bool_t streambuf_would_wait_for(size_t bytes) {
	size_t n;
	
	if (!streambuf_streaming) {
		return FALSE;
	}

	fifo_lock(&streambuf_fifo);

	n = fifo_bytes_used(&streambuf_fifo);

	fifo_unlock(&streambuf_fifo);

	return n < bytes;
}

void streambuf_get_status(size_t *size, size_t *usedbytes, u32_t *bytesL, u32_t *bytesH) {

	fifo_lock(&streambuf_fifo);

	*size = STREAMBUF_SIZE;
	*usedbytes = fifo_bytes_used(&streambuf_fifo);
	*bytesL = streambuf_bytes_received & 0xFFFFFFFF;
	*bytesH = streambuf_bytes_received >> 32;

	fifo_unlock(&streambuf_fifo);
}


void streambuf_mark_loop(void) {
	fifo_lock(&streambuf_fifo);

	streambuf_lptr = streambuf_fifo.wptr;
	streambuf_loop = TRUE;

	fifo_unlock(&streambuf_fifo);
}


void streambuf_clear_loop(void) {
	fifo_lock(&streambuf_fifo);

	streambuf_loop = FALSE;

	fifo_unlock(&streambuf_fifo);
}


bool_t streambuf_is_looping(void) {
	bool_t n;

	fifo_lock(&streambuf_fifo);

	n = streambuf_loop;

	fifo_unlock(&streambuf_fifo);

	return n;
}


void streambuf_flush(void) {
	fifo_lock(&streambuf_fifo);

	streambuf_fifo.rptr = 0;
	streambuf_fifo.wptr = 0;

	fifo_unlock(&streambuf_fifo);
}


void streambuf_feed(u8_t *buf, size_t size) {
	size_t n;

	fifo_lock(&streambuf_fifo);

	streambuf_streaming = TRUE;

	streambuf_bytes_received += size;

	while (size) {
		n = fifo_bytes_until_wptr_wrap(&streambuf_fifo);

		if (n > size) {
			n = size;
		}

		memcpy(streambuf_buf + streambuf_fifo.wptr, buf, n);
		fifo_wptr_incby(&streambuf_fifo, n);
		size -= n;
	}

	fifo_unlock(&streambuf_fifo);
}


ssize_t streambuf_feed_fd(int fd) {
	ssize_t n, size;

	fifo_lock(&streambuf_fifo);

	streambuf_streaming = TRUE;

	size = fifo_bytes_free(&streambuf_fifo);
	if (size < 4096) {
		fifo_unlock(&streambuf_fifo);
		return -ENOSPC; /* no space */
	}

	n = fifo_bytes_until_wptr_wrap(&streambuf_fifo);
	if (n > size) {
		n = size;
	}

	n = recv(fd, streambuf_buf + streambuf_fifo.wptr, n, 0);
	if (n < 0) {
		streambuf_streaming = FALSE;

		fifo_unlock(&streambuf_fifo);
		return -SOCKETERROR;
	}
	else if (n == 0) {
		streambuf_streaming = FALSE;
	}
	else {
		fifo_wptr_incby(&streambuf_fifo, n);

		streambuf_bytes_received += n;
	}

	fifo_unlock(&streambuf_fifo);
	return n;
}


size_t streambuf_fast_read(u8_t *buf, size_t min, size_t max, bool_t *streaming) {
	size_t sz, w;

	if (streaming) {
		*streaming = streambuf_streaming;
	}

	sz = fifo_bytes_used(&streambuf_fifo);
	if (sz < min) {
		return 0; /* underrun */
	}

	if (sz > max) {
		sz = max;
	}

	w = fifo_bytes_until_rptr_wrap(&streambuf_fifo);
	if (w < sz) {
		sz = w;
	}

	memcpy(buf, streambuf_buf + streambuf_fifo.rptr, sz);
	fifo_rptr_incby(&streambuf_fifo, sz);

	fifo_signal(&streambuf_fifo);

	if ((streambuf_fifo.rptr == streambuf_fifo.wptr) && streambuf_loop) {
		streambuf_fifo.rptr = streambuf_lptr;
	}

	return sz;
}


size_t streambuf_read(u8_t *buf, size_t min, size_t max, bool_t *streaming) {
	ssize_t n;

	fifo_lock(&streambuf_fifo);

	if (streambuf_filter) {
		/* filters are called with the streambuf locked */
		n = streambuf_filter(buf, min, max, streaming);

		if (n < 0) {
			/* filter returned an error */
			current_decoder_state |= DECODE_STATE_ERROR;
			n = 0;
		}
	}
	else {
		n = streambuf_fast_read(buf, min, max, streaming);
	}

	fifo_unlock(&streambuf_fifo);

	return n;
}


void streambuf_set_filter(streambuf_filter_t filter) {
	fifo_lock(&streambuf_fifo);

	streambuf_next_filter = filter;

	fifo_unlock(&streambuf_fifo);
}


ssize_t streambuf_icy_filter(u8_t *buf, size_t min, size_t max, bool_t *streaming) {
	size_t avail, r, n = 0;
	
	/* streambuf is locked */

	/* icy is only used with the mp3 decoder, it always uses min=0.
	 * let's use this to make this code simpler.
	 */
	assert(min == 0);

	avail = fifo_bytes_used(&streambuf_fifo);
	while (avail && n < max) {
		if (icy_meta_remaining > 0) {
			/* we're waiting for the metadata */
			r = icy_meta_remaining;
			if (r > max - n) {
				r = max - n;
			}

			r = streambuf_fast_read(buf, 0, r, streaming);

			buf += r;
			n += r;
			icy_meta_remaining -= r;

		}
		else if (icy_meta_remaining == 0) {
			/* we're reading the metadata length byte */
			u8_t len;

			r = streambuf_fast_read(&len, 1, 1, NULL);
			assert(r == 1);

			icy_meta_remaining = -16 * len;
			if (!icy_meta_remaining) {
				/* it's a zero length metadata, reset to the next interval */
				icy_meta_remaining = icy_meta_interval;
			}
		}
		else {
			/* we're reading the metadata */
			struct decode_metadata *icy_buf;
			size_t icy_len = -icy_meta_remaining;

			if (avail < icy_len) {
				/* wait for more data */
				break;
			}

			icy_buf = malloc(sizeof(struct decode_metadata) + icy_len - 1);

			icy_buf->type = SHOUTCAST;
			icy_buf->len = icy_len;

			r = streambuf_fast_read(&icy_buf->data, icy_len, icy_len, NULL);
			assert(r == icy_len);

			// XXXX queue metadata
			assert( strstr( (char *)&icy_buf->data, "StreamTitle" ) != NULL );
			DEBUG_TRACE("got icy metadata: %s", (char *) &icy_buf->data);

			decode_queue_metadata(icy_buf);
			/* decode will free icy_buf */

			icy_meta_remaining = icy_meta_interval;
		}

		avail = fifo_bytes_used(&streambuf_fifo);
	}

	return n;
}


struct stream {
	socket_t fd;
	int num_crlf;

	/* save http headers or body */
	u8_t *body;
	int body_len;
};


static int stream_connectL(lua_State *L) {

	/*
	 * 1: self
	 * 2: server_ip
	 * 3: server_port
	 */

	struct sockaddr_in serv_addr;
	struct stream *stream;
	int flags;
	int err;
	socket_t fd;

	/* Server address and port */
	memset(&serv_addr, 0, sizeof(serv_addr));
	if (lua_type(L, 2) == LUA_TSTRING) {
		serv_addr.sin_addr.s_addr = inet_addr(luaL_checkstring(L, 2));
	}
	else {
		serv_addr.sin_addr.s_addr = htonl(luaL_checkinteger(L, 2));
	}
	serv_addr.sin_port = htons(luaL_checkinteger(L, 3));
	serv_addr.sin_family = AF_INET;


	DEBUG_TRACE("streambuf connect %s:%d", inet_ntoa(serv_addr.sin_addr), serv_addr.sin_port);

	/* Create socket */
	fd = socket(AF_INET, SOCK_STREAM, 0);
	if (fd == INVALID_SOCKET) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(SOCKETERROR));
		return 2;
	}

	/* Make socket non-blocking */
#if defined(WIN32)
	{
		u_long iMode = 0;
		flags = ioctlsocket(fd, FIONBIO, &iMode);
	}
#else
	flags = fcntl(fd, F_GETFL, 0);
	flags |= O_NONBLOCK;
	fcntl(fd, F_SETFL, flags);
#endif

	/* Connect socket */
	err = connect(fd, (struct sockaddr *)&serv_addr, sizeof(serv_addr));
	if (err != 0
#if !defined(WIN32)
		&&  SOCKETERROR != EINPROGRESS
#endif
		) {
		CLOSESOCKET(fd);

		lua_pushnil(L);
		lua_pushstring(L, strerror(SOCKETERROR));
		return 2;
	}

	/* Stream object */
	stream = lua_newuserdata(L, sizeof(struct stream));

	memset(stream, 0, sizeof(*stream));
	stream->fd = fd;

	luaL_getmetatable(L, "squeezeplay.stream");
	lua_setmetatable(L, -2);

	streambuf_clear_loop();
	streambuf_bytes_received = 0;
	streambuf_filter = streambuf_next_filter;
	streambuf_next_filter = NULL;

	return 1;
}


static int stream_disconnectL(lua_State *L) {
	struct stream *stream;

	/*
	 * 1: self
	 */

	stream = lua_touserdata(L, 1);

	if (stream->body) {
		free(stream->body);
		stream->body = NULL;
		stream->body_len = 0;
	}

	if (stream->fd) {
		CLOSESOCKET(stream->fd);
		stream->fd = 0;
	}

	streambuf_bytes_received = 0;

	return 0;
}


static int stream_flushL(lua_State *L) {
	streambuf_flush();
	return 0;
}


static int stream_getfdL(lua_State *L) {
	struct stream *stream;

	/*
	 * 1: self
	 */

	stream = lua_touserdata(L, 1);

	if (stream->fd > 0) {
		lua_pushinteger(L, stream->fd);
	}
	else {
		lua_pushnil(L);
	}
	return 1;
}


static int stream_readL(lua_State *L) {
	struct stream *stream;
	u8_t buf[1024];
	u8_t *buf_ptr, *body_ptr;
	size_t header_len;
	ssize_t n;

	/*
	 * 1: Stream (self)
	 * 2: Playback (self)
	 */

	stream = lua_touserdata(L, 1);


	/* shortcut, just read to streambuf */
	if (stream->num_crlf == 4) {
		n = streambuf_feed_fd(stream->fd);		
		if (n == 0) {
			/* closed */
			lua_pushboolean(L, FALSE);
			return 1;
		}

		if (n == -ENOSPC) {
			lua_pushinteger(L, 0);
			return 1;
		}

		if (n < 0) {
			CLOSESOCKET(stream->fd);

			lua_pushnil(L);
			lua_pushstring(L, strerror(n));
			return 2;

		}

		lua_pushinteger(L, n);
		return 1;
	}

	/* read buffer, but we must not overflow the stream fifo */
	n = streambuf_get_freebytes();
	if (n > (ssize_t)sizeof(buf)) {
		n = sizeof(buf);
	}

	n = recv(stream->fd, buf, sizeof(buf), 0);

	/* socket closed */
	if (n == 0) {
		lua_pushboolean(L, FALSE);
		return 1;
	}

	/* socket error */
	if (n < 0) {
		// XXXX do we need to handle timeout here?
		CLOSESOCKET(stream->fd);

		lua_pushnil(L);
		lua_pushstring(L, strerror(SOCKETERROR));
		return 2;
	}

	buf_ptr = buf;


	/* read http header */
	if (stream->num_crlf < 4) {
		stream->body = realloc(stream->body, stream->body_len + n);
		body_ptr = stream->body + stream->body_len;
		stream->body_len += n;

		while (n) {
			*body_ptr++ = *buf_ptr;

			if (*buf_ptr == '\n' || *buf_ptr == '\r') {
				stream->num_crlf++;
			}
			else {
				stream->num_crlf = 0;
			}

			buf_ptr++;
			n--;

			if (stream->num_crlf == 4) {
				header_len = body_ptr - stream->body - 1;

				//DEBUG_TRACE("headers %d %*s\n", header_len, header_len, stream->body);

				/* Send headers to SqueezeCenter */
				lua_getfield(L, 2, "_streamHttpHeaders");
				lua_pushvalue(L, 2);
				lua_pushlstring(L, (char *)stream->body, header_len);
				lua_call(L, 2, 0);

				free(stream->body);
				stream->body = NULL;
				stream->body_len = 0;

				break;
			}
		}
	}


	// XXXX handle body and cont state


	/* feed remaining buffer */
	streambuf_feed(buf_ptr, n);

	lua_pushboolean(L, TRUE);
	return 1;
}


static int stream_writeL(lua_State *L) {
	struct stream *stream;
	const char *header;
	ssize_t n;
	size_t len;

	/*
	 * 1: Stream (self)
	 * 2: Playback (self)
	 * 3: header
	 */

	stream = lua_touserdata(L, 1);
	header = luaL_checkstring(L, 3);

	len = strlen(header);
	while (len > 0) {
		n = send(stream->fd, header, len, 0);

		if (n < 0) {
			CLOSESOCKET(stream->fd);

			lua_pushnil(L);
			lua_pushstring(L, strerror(SOCKETERROR));
			return 2;
		}

		len -= n;
	}

	/*
	if (shutdown(stream->fd, SHUT_WR) != 0) {
		CLOSESOCKET(stream->fd);

		lua_pushnil(L);
		lua_pushstring(L, strerror(SOCKETERROR));
		return 2;
	}
	*/

	lua_pushboolean(L, TRUE);
	return 1;
}


static int stream_mark_loopL(lua_State *L) {
	streambuf_mark_loop();

	return 0;
}


static int stream_icy_metaintervalL(lua_State *L) {
	/*
	 * 1: Stream (self)
	 * 2: meta interval
	 */

	fifo_lock(&streambuf_fifo);

	streambuf_filter = streambuf_icy_filter;

	icy_meta_interval = lua_tointeger(L, 2);
	icy_meta_remaining = icy_meta_interval;

	fifo_unlock(&streambuf_fifo);

	return 0;
}


static const struct luaL_Reg stream_f[] = {
	{ "connect", stream_connectL },
	{ NULL, NULL }
};

static const struct luaL_Reg stream_m[] = {
	{ "__gc", stream_disconnectL },
	{ "disconnect", stream_disconnectL },
	{ "flush", stream_flushL },
	{ "getfd", stream_getfdL },
	{ "read", stream_readL },
	{ "write", stream_writeL },
	{ "markLoop", stream_mark_loopL },
	{ "icyMetaInterval", stream_icy_metaintervalL },
	{ NULL, NULL }
};


int luaopen_streambuf(lua_State *L) {

	fifo_init(&streambuf_fifo, STREAMBUF_SIZE);

	/* stream methods */
	luaL_newmetatable(L, "squeezeplay.stream");

	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");

	luaL_register(L, NULL, stream_m);

	/* register lua functions */
	luaL_register(L, "squeezeplay.stream", stream_f);

	return 0;
}
