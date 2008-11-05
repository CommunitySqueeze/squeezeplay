/*
** Copyright 2007-2008 Logitech. All Rights Reserved.
**
** This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.
*/

#define RUNTIME_DEBUG 1

#include "common.h"

#include "audio/streambuf.h"
#include "audio/decode/decode.h"
#include "audio/decode/decode_priv.h"


#define BLOCKSIZE 4096

struct decode_pcm {
	sample_t *write_buffer;
	u8_t *read_buffer;
	size_t leftover;

	bool_t big_endian;
	u32_t sample_rate;
	u32_t sample_size;
	bool_t stereo;
};


/* Indexed by pcm_sample_rate. Sample rate in Hz. */
static u32_t pcm_sample_rates[] = {
	11025, 22050, 32000, 44100, 48000, 8000, 12000, 16000, 24000, 96000, 88200
};


/* Indexed by pcm_sample_size. Width in bytes. */
static u32_t pcm_sample_widths[] = {
	1, 2, 3, 4
};


static sample_t pcm_read8bitBE(u8_t *pos) { 
	sample_t sample;
	struct { s32_t sign_extend:8; } s;

	/* XXXX: REVIEW */

	sample = *pos;

	sample = s.sign_extend = sample;
	return sample << 24;
}


static sample_t pcm_read8bitLE(u8_t *pos) { 
	sample_t sample;
	struct { s32_t sign_extend:8; } s;

	/* XXXX: REVIEW */

	sample = *pos;

	sample = s.sign_extend = sample;
	return sample << 24;
}


static sample_t pcm_read16bitBE(u8_t *pos) { 
	sample_t sample;
	struct { s32_t sign_extend:16; } s;

	/* XXXX: REVIEW */

	sample = *pos++ << 8;
	sample = *pos;

	sample = s.sign_extend = sample;
	return sample << 16;
}


static sample_t pcm_read16bitLE(u8_t *pos) {
	sample_t sample;
	struct { s32_t sign_extend:16; } s;

	sample = *pos++;
	sample = *pos << 8;

	sample = s.sign_extend = sample;
	return sample << 16;
}


static sample_t pcm_read24bitBE(u8_t *pos) { 
	sample_t sample;
	struct { s32_t sign_extend:24; } s;

	/* XXXX: REVIEW */

	sample = *pos++ << 16;
	sample |= *pos++ << 8;
	sample |= *pos;

	sample = s.sign_extend = sample;
	return sample << 8;
}


static sample_t pcm_read24bitLE(u8_t *pos) { 
	sample_t sample;
	struct { s32_t sign_extend:24; } s;

	sample = *pos++;
	sample |= *pos++ << 8;
	sample |= *pos << 16;

	sample = s.sign_extend = sample;
	return sample << 8;
}


static sample_t pcm_read32bitBE(u8_t *pos) { 
	sample_t sample;
	struct { s32_t sign_extend:32; } s;

	/* XXXX: REVIEW */

	sample = *pos++ << 24;
	sample |= *pos++ << 16;
	sample |= *pos++ << 8;
	sample |= *pos;

	sample = s.sign_extend = sample;
	return sample;
}


static sample_t pcm_read32bitLE(u8_t *pos) { 
	sample_t sample;

	sample = *((s32_t *)(void *)pos);
	return sample;
}


typedef sample_t (*pcm_read_func_t)(u8_t *pos);
static pcm_read_func_t pcm_read_funcs[] = {
	pcm_read8bitLE,
	pcm_read8bitBE,
	pcm_read16bitLE,
	pcm_read16bitBE,
	pcm_read24bitLE,
	pcm_read24bitBE,
	pcm_read32bitLE,
	pcm_read32bitBE
};


static bool_t decode_pcm_callback(void *data) {
	struct decode_pcm *self = (struct decode_pcm *) data;
	pcm_read_func_t read_func;
	sample_t *write_pos;
	u8_t *read_pos;
	u32_t s, num_samples;
	sample_t sample;
	size_t sz;


	if (!decode_output_can_write(sizeof(sample_t) * BLOCKSIZE, self->sample_rate)) {
		return FALSE;
	}

	sz = streambuf_read(self->read_buffer + self->leftover, 0, BLOCKSIZE - self->leftover, NULL);
	if (!sz) {
		current_decoder_state |= DECODE_STATE_UNDERRUN;
		return FALSE;
	}

	current_decoder_state &= ~DECODE_STATE_UNDERRUN;

	sz += self->leftover;

	read_func = pcm_read_funcs[(2 * self->sample_size) + self->big_endian];
	read_pos = self->read_buffer;
	write_pos = self->write_buffer;

	num_samples = sz / pcm_sample_widths[self->sample_size];
	if (self->stereo) {
		/* we need the same number of sample for both channels */
		num_samples &= ~0x01;
	}

	for (s = 0; s < num_samples; s++) {
		sample = read_func(read_pos);
		*write_pos++ = sample;
		if (!self->stereo) {
			*write_pos++ = sample;
		}
		read_pos += pcm_sample_widths[self->sample_size];
	}

	if (num_samples) {
		decode_output_samples(self->write_buffer, self->stereo ? num_samples / 2 : num_samples, self->sample_rate, FALSE);
	}

	self->leftover = sz - (read_pos - self->read_buffer);

	if (self->leftover) {
		memcpy(self->read_buffer, read_pos, self->leftover);
	}
					      
	return TRUE;
}		


static u32_t decode_pcm_period(void *data) {
	struct decode_pcm *self = (struct decode_pcm *) data;

	if (self->sample_rate <= 48000) {
		return 8;
	}
	else {
		return 1;
	}
}


static void *decode_pcm_start(u8_t *params, u32_t num_params) {
	struct decode_pcm *self;

	DEBUG_TRACE("decode_pcm_start()");

	self = malloc(sizeof(struct decode_pcm));
	memset(self, 0, sizeof(struct decode_pcm));

	self->sample_size = (params[0] - '0');
	self->sample_rate = pcm_sample_rates[(params[1] - '0')];
	self->stereo = (params[2] == '2');
	self->big_endian = (params[3] == '0');

	DEBUG_TRACE("sample_size=%d sample_rate=%d stereo=%d big_endian=%d",
		    self->sample_size, self->sample_rate, self->stereo, self->big_endian);

	self->read_buffer = malloc(sizeof(u8_t) * BLOCKSIZE);
	self->write_buffer = malloc(sizeof(sample_t) * 2 * BLOCKSIZE);
	
	return self;
}


static void decode_pcm_stop(void *data) {
	struct decode_pcm *self = (struct decode_pcm *) data;

	DEBUG_TRACE("decode_pcm_stop()");
	
	free(self->read_buffer);
	free(self->write_buffer);
	free(self);
}


struct decode_module decode_pcm = {
	'p',
	decode_pcm_start,
	decode_pcm_stop,
	decode_pcm_period,
	decode_pcm_callback,
};
