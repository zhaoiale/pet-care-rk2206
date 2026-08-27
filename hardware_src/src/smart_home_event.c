#include "smart_home_event.h"
#include "ohos_init.h"
#include "los_task.h"

static unsigned int event_queue_id;

#define EVENT_QUEUE_LENGTH 10 //number of events
#define BUFFER_LEN         20 //bytes of event
 
void smart_home_event_init(){
    unsigned int ret = LOS_OK;

    ret = LOS_QueueCreate("eventQ", EVENT_QUEUE_LENGTH, &event_queue_id, 0, BUFFER_LEN);
    if (ret != LOS_OK)
    {
        printf("Falied to create Message Queue ret:0x%x\n", ret);
        return;
    }
}
void smart_home_event_send(event_info_t *event)
{
     LOS_QueueWriteCopy(event_queue_id, event, sizeof(event_info_t),LOS_WAIT_FOREVER);
}
int smart_home_event_wait(event_info_t *event,int timeoutMs){

    return LOS_QueueReadCopy(event_queue_id, event, sizeof(event_info_t), 
        LOS_MS2Tick(timeoutMs));

}