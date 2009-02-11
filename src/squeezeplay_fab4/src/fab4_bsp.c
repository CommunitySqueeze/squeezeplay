/*
** Copyright 2007 Logitech. All Rights Reserved.
**
** This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.
*/
#define RUNTIME_DEBUG 1

#include "common.h"
#include "ui/jive.h"

#include <linux/input.h>
#include <sys/time.h>
#include <time.h>


static int clearpad_event_fd = -1;
static int ir_event_fd = -1;

/* touchpad state */
static JiveEvent clearpad_event;
static int clearpad_state = 0;
static int clearpad_max_x, clearpad_max_y;

/* button hold threshold .9 seconds - HOLD event is sent when a new ir code is received after IR_HOLD_TIMEOUT ms*/
#define IR_HOLD_TIMEOUT 900


/* time after which, if no additional ir code is received, a button input is considered complete */
#define IR_KEYUP_TIME 128

/* This ir code used by some remotes, such as the boom remote, to indicate that a code is repeating */
#define IR_REPEAT_CODE 0

/* time that new ir input has occurred (using the input_event time as the time source) */
Uint32 ir_down_millis = 0;

/* time that the last ir input was received (using the input_event time as the time source)*/
Uint32 ir_last_input_millis = 0;

/* last ir code received */
Uint32 ir_last_code = 0;

Uint32 last_change_clearpad_x = 0;
Uint32 last_change_clearpad_y = 0;

bool ir_received_this_loop = false;
 
static enum jive_ir_state {
	IR_STATE_NONE,
	IR_STATE_DOWN,
	IR_STATE_HOLD_SENT,
} ir_state = IR_STATE_NONE;


#define TIMEVAL_TO_TICKS(tv) ((tv.tv_sec * 1000) + (tv.tv_usec / 1000))


static int handle_clearpad_events(int fd) {
	JiveEvent event;
	struct input_event ev[64];
	size_t rd;
	int i;

	int flick_y = 0;
	int flick_x = 0;

	rd = read(fd, ev, sizeof(struct input_event) * 64);

	if (rd < (int) sizeof(struct input_event)) {
		perror("read error");
		return -1;
	}

	memcpy(&event, &clearpad_event, sizeof(JiveEvent));

	for (i = 0; i <= rd / sizeof(struct input_event); i++) {    
		if (ev[i].type == EV_ABS) {
			Uint16 new_mouse_x;
			Uint16 new_mouse_y;
			switch (ev[i].code) {
			case ABS_X:
				new_mouse_x = (Uint16) 480 - ((ev[i].value / (double)clearpad_max_x) * 480);

				//jitter correction - for stablizing drag when finger is stopped
				if (abs(new_mouse_x - clearpad_event.u.mouse.x) == 1) {
					//movement by only one pixel, confirm finger has deviated far enough to trigger a switch
					//"far enough" is a fraction of the clearpad "distance" between mouse points
					if ( abs(ev[i].value - last_change_clearpad_x) > (.7 * clearpad_max_x/(double)480)) {
						event.u.mouse.x = new_mouse_x;
						last_change_clearpad_x = ev[i].value;
					} //else don't change x, since finger haven't deviated enough
				}
				else if (abs(new_mouse_x - clearpad_event.u.mouse.x) > 1) {
					event.u.mouse.x = new_mouse_x;
					last_change_clearpad_x = ev[i].value;
				}
				else {
					//no change
					event.u.mouse.x = new_mouse_x;
				}
				break;
			case ABS_Y:
				new_mouse_y = (Uint16) 272 - ((ev[i].value / (double)clearpad_max_y) * 272);
//				fprintf(stderr, "clearpad_event.u.mouse.y %d maxY %d  ev[i].value:%d y: %d fractional y: %f clearpad dev: %d required: %f \n",
//					clearpad_event.u.mouse.y, clearpad_max_y, ev[i].value, new_mouse_y, 272.0 - ((ev[i].value / (double)clearpad_max_y) * 272),
//					abs(ev[i].value - last_change_clearpad_y) , (.7 * clearpad_max_y/(double)272));

				//jitter correction - for stablizing drag when finger is stopped
				if (abs(new_mouse_y - clearpad_event.u.mouse.y) == 1) {
					//movement by only one pixel, confirm finger has traveled far enough to trigger a switch
					//"far enough" is a fraction of the clearpad "distance" between mouse points
					if ( abs(ev[i].value - last_change_clearpad_y) > (.75 * clearpad_max_y/(double)272)) {
						event.u.mouse.y = new_mouse_y;
						last_change_clearpad_y = ev[i].value;
					} //else don't change y, since finger haven't deviated enough
				}
				else if (abs(new_mouse_y - clearpad_event.u.mouse.y) > 1) {
					event.u.mouse.y = new_mouse_y;
					last_change_clearpad_y = ev[i].value;
				}
				else {
					//no change
					event.u.mouse.y = new_mouse_y;
				}

				break;
			case ABS_MISC: /* finger_count */
				event.u.mouse.finger_count = ev[i].value;
				break;
			case ABS_PRESSURE:
				event.u.mouse.finger_pressure = ev[i].value;
				break;
			case ABS_TOOL_WIDTH:
				event.u.mouse.finger_width = ev[i].value;
				break;
			}


		}
		else if (ev[i].type == EV_REL) {
			// FIXME just temporary until we've worked out
			// how to handle gestures correctly
			switch (ev[i].code) {
			case REL_RX:
				flick_x = ev[i].value;
				break;
			case REL_RY:
				flick_y = ev[i].value;
				break;
			}
		}
		else if (ev[i].type == EV_SYN) {
			if (flick_x != 0) {
				if (abs(flick_x) > abs(flick_y)) { //must have more x than y component to be considered a vertical gesture
					if (flick_x > 0) {
						JiveEvent event;

						event.type = (JiveEventType) JIVE_EVENT_KEY_PRESS;
						event.u.key.code = JIVE_KEY_HOME;
						event.ticks = TIMEVAL_TO_TICKS(ev[i].time);
						jive_queue_event(&event);
					}
					if (flick_x < 0) {
						JiveEvent event;

						event.type = (JiveEventType) JIVE_EVENT_CHAR_PRESS;
						event.u.text.unicode = '['; // '[' the temporary go_now_playing shortcut
						event.ticks = TIMEVAL_TO_TICKS(ev[i].time);
						jive_queue_event(&event);
					}
				}

				//reset flick data
				flick_x = 0;
				flick_y = 0;

			}
			else if (flick_y != 0) {

				//no y_click handling yet, so just ignore y flick data, still need to reset
				//reset flick data
				flick_x = 0;
				flick_y = 0;

			}


			/* We must move more than 10 pixels to enter a 
			 * finger drag.
			 */
			if (clearpad_state == 1 &&
			    abs(event.u.mouse.x - clearpad_event.u.mouse.x) < 10
			    && abs(event.u.mouse.y - clearpad_event.u.mouse.y) < 10
			    && event.u.mouse.finger_count == clearpad_event.u.mouse.finger_count
			    ) {
				continue;
			}

			/* Don't send repeated drag values when no movement or finger change occurred
			 */
			if (clearpad_state == 3 &&
			    event.u.mouse.x == clearpad_event.u.mouse.x
			    && event.u.mouse.y == clearpad_event.u.mouse.y
			    && event.u.mouse.finger_count == clearpad_event.u.mouse.finger_count
			    ) {
				continue;
			}

			event.ticks = TIMEVAL_TO_TICKS(ev[i].time);

			if (event.u.mouse.finger_count == 0) {
				if (clearpad_state == 1) {
					event.type = (JiveEventType) JIVE_EVENT_MOUSE_PRESS;
					jive_queue_event(&event);
				}

				event.type = (JiveEventType) JIVE_EVENT_MOUSE_UP;
				clearpad_state = 0;
			}
			else if (clearpad_state == 0) {
				event.type = (JiveEventType) JIVE_EVENT_MOUSE_DOWN;
				clearpad_state = 1;
			}
			else if (clearpad_state == 1) {
				event.type = (JiveEventType) JIVE_EVENT_MOUSE_DRAG;
				clearpad_state = 3;
			}

			memcpy(&clearpad_event, &event, sizeof(JiveEvent));
			jive_queue_event(&event);
		}
	}

	return 0;
}

static Uint32 bsp_get_realtime_millis() {
	Uint32 millis;
	struct timespec now;
	clock_gettime(CLOCK_REALTIME,&now);
	millis=now.tv_sec*1000+now.tv_nsec/1000000;
	return(millis);
}
		
static Uint32 queue_ir_event(Uint32 ticks, Uint32 code, JiveEventType type) {
	JiveEvent event;
	
/*	
	switch(type) {
		case JIVE_EVENT_IR_UP: fprintf(stderr,"Queuing JIVE_EVENT_IR_UP event\n"); break;
		case JIVE_EVENT_IR_DOWN: fprintf(stderr,"Queuing JIVE_EVENT_IR_DOWN event\n"); break;
		case JIVE_EVENT_IR_PRESS: fprintf(stderr,"Queuing JIVE_EVENT_IR_PRESS event\n"); break;
		case JIVE_EVENT_IR_HOLD: fprintf(stderr,"Queuing JIVE_EVENT_IR_HOLD event\n"); break;
		case JIVE_EVENT_IR_REPEAT: fprintf(stderr,"Queuing JIVE_EVENT_IR_REPEAT event\n"); break;
		default: fprintf(stderr,"Invalid IR JiveEventType Value");
	}
*/

	memset(&event, 0, sizeof(JiveEvent));

	event.type = type;
	event.u.ir.code = code;
	event.ticks = ticks;
	jive_queue_event(&event);

	return 0;
}

static int ir_handle_up() {
	if (ir_state != IR_STATE_HOLD_SENT) {
		//odd to use sdl_getTicks here, since other ir events sent input_event time - code using PRESS and UP shouldn't care yet about the time....
		queue_ir_event(SDL_GetTicks(), ir_last_code, (JiveEventType) JIVE_EVENT_IR_PRESS);
	}

	ir_state = IR_STATE_NONE;
	queue_ir_event(SDL_GetTicks(), ir_last_code, (JiveEventType) JIVE_EVENT_IR_UP);
	
	ir_down_millis = 0;
	ir_last_input_millis = 0;
	ir_last_code = 0;
	
	return 0;
}

static int ir_handle_down(Uint32 code, Uint32 time) {
	ir_state = IR_STATE_DOWN;
	ir_down_millis = time;

	queue_ir_event(time, code, (JiveEventType) JIVE_EVENT_IR_DOWN);
					
	return 0;
}


/**

IR input will cause the following events to be sent:
EVENT_IR_DOWN - sent as soon as a new code has been sent
EVENT_IR_REPEAT - sent out as fast as ir codes are received after IR_DOWN occurs
EVENT_IR_PRESS - sent when no new codes are received (or a new key is pressed) prior to the IR_HOLD_TIMEOUT time
EVENT_IR_HOLD - sent once when ir input occurs and the IR_HOLD_TIMEOUT time has been exceeded
EVENT_IR_UP - sent when input stops (IR_KEYUP_TIME exceeded) or the ir code changes

*/
static int handle_ir_events(int fd) {
	struct input_event ev[64];
	size_t rd;
	int i;

	rd = read(fd, ev, sizeof(struct input_event) * 64);

	if (rd < (int) sizeof(struct input_event)) {
		perror("read error");
		return -1;
	}

	for (i = 0; i <= rd / sizeof(struct input_event); i++) {	
		if (ev[i].type == EV_MSC) {
			bool repeatCodeSent = false;
						
			ir_received_this_loop = true;
			//TIMEVAL_TO_TICKS doesn't not really return ticks since these ev times are jiffies, but we won't be comparing against real ticks.
			Uint32 input_time = TIMEVAL_TO_TICKS(ev[i].time);
			Uint32 ir_code = ev[i].value;
			
			if (ir_code == IR_REPEAT_CODE) {
				if (ir_state == IR_STATE_NONE) {
					//ignore, since we have no way to know what key was sent
					continue;
				} else {
					ir_code = ir_last_code;   
					repeatCodeSent = true;
				}
			}

			//fprintf(stderr,"ir code: %x %d %d\n", ir_code, input_time, SDL_GetTicks());
			
			//did ir code change, if so complete the old code
			if (ir_state != IR_STATE_NONE && ir_code != ir_last_code) {
				//fprintf(stderr,"******************************UP triggered by code switch\n");
				ir_handle_up();
			}

			switch (ir_state) {
			case IR_STATE_NONE:
				ir_handle_down(ir_code, input_time);
				break;

			case IR_STATE_DOWN:
			case IR_STATE_HOLD_SENT: 
				//pump's up check might not have kicked in yet, so we need the check for a quick second press
				if (!repeatCodeSent && input_time >= ir_last_input_millis + IR_KEYUP_TIME) {
					//quick second press of same key occurred: complete the first, start the second.
					// though if repeat code is sent, we always know that it is not a quick 
					
					//fprintf(stderr,"******************************UP triggered by quick second press\n");
					ir_handle_up();
					ir_handle_down(ir_code, input_time);
					break;
				}
				
				queue_ir_event(input_time, ir_code, (JiveEventType) JIVE_EVENT_IR_REPEAT);

				if (ir_state == IR_STATE_DOWN && input_time >= ir_down_millis + IR_HOLD_TIMEOUT) {
					ir_state = IR_STATE_HOLD_SENT;
					queue_ir_event(input_time, ir_code, (JiveEventType) JIVE_EVENT_IR_HOLD);
				}
				break;

			}

			ir_last_input_millis = input_time;
			ir_last_code = ir_code;
		}
		// ignore EV_SYN
	}

	return 0;
}

static int open_input_devices(void) {
	char path[PATH_MAX];
	struct stat sbuf;
	char name[254];
	int n, fd, abs[5];

	for (n=0; n<10; n++) {
		snprintf(path, sizeof(path), "/dev/input/event%d", n);

		if ((stat(path, &sbuf) != 0) | !S_ISCHR(sbuf.st_mode)) {
			continue;
		}

		if ((fd = open(path, O_RDONLY, 0)) < 0) {
			perror("open");
			continue;
		}

		if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) < 0) {
			perror("ioctrl");
			close(fd);
			continue;
		}

		if (strstr(name, "ClearPad")) {
			clearpad_event_fd = fd;

			ioctl(fd, EVIOCGABS(ABS_X), abs);
			clearpad_max_x = abs[2]; 

			ioctl(fd, EVIOCGABS(ABS_Y), abs);
			clearpad_max_y = abs[2];
		}
		else if (strstr(name, "FAB4 IR")) {
			ir_event_fd = fd;
		}
		else {
			close(fd);
		}
	}

	return (clearpad_event_fd != -1);
}


static int event_pump(lua_State *L) {
	fd_set fds;
	struct timeval timeout;

	Uint32 now;
	
	FD_ZERO(&fds);
	memset(&timeout, 0, sizeof(timeout));

	if (clearpad_event_fd != -1) {
		FD_SET(clearpad_event_fd, &fds);
	}
	if (ir_event_fd != -1) {
		FD_SET(ir_event_fd, &fds);
	}

	if (select(FD_SETSIZE, &fds, NULL, NULL, &timeout) < 0) {
		perror("jivebsp:");
		return -1;
	}

	if (clearpad_event_fd != -1 && FD_ISSET(clearpad_event_fd, &fds)) {
		handle_clearpad_events(clearpad_event_fd);
	}

	now = bsp_get_realtime_millis();

	ir_received_this_loop = false;
	if (ir_event_fd != -1 && FD_ISSET(ir_event_fd, &fds)) {
		handle_ir_events(ir_event_fd);
	}
	
	// Now that we've handled the ir input, determine if ir input has stopped
	if (!ir_received_this_loop && ir_last_input_millis && (now >= IR_KEYUP_TIME + ir_last_input_millis)) {
		//fprintf(stderr,"******************************UP triggered by pump check\n");
		ir_handle_up();
	}
	
	return 0;
}


int luaopen_fab4_bsp(lua_State *L) {
	if (open_input_devices()) {
		jive_sdlevent_pump = event_pump;
	}

	return 1;
}
