#ifndef __SMART_HOME_EVENT_H__
#define __SMART_HOME_EVENT_H__

#include "stdint.h"
#include "stdbool.h"



typedef enum event_type{

    event_key_press = 1,
    event_iot_cmd,
    event_su03t,

}event_type_t;


typedef struct event_info
{
    event_type_t event;

    union {
        uint8_t key_no;
        int iot_data;
        int su03t_data;

    } data;
} event_info_t;

void smart_home_event_init();
void smart_home_event_send(event_info_t *event);
int smart_home_event_wait(event_info_t *event,int timeoutMs);

#endif