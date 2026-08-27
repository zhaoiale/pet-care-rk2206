#include "voice_adc.h"
#include "iot_adc.h"
#include "iot_errno.h"
#include "los_task.h"
#include <stdio.h>

#define BUSY_CYCLES_PER_SAMPLE 18000  /* ~125us of nops at 160MHz (tune with scope) */

static uint16_t g_adc_buf[VOICE_ADC_RB_SIZE];
static volatile int g_wr = 0;
static volatile int g_rd = 0;
static volatile bool g_running = false;

static void voice_adc_task(uint32_t arg)
{
    (void)arg;
    unsigned int data = 0;

    while (g_running) {
        if (IoTAdcGetVal(VOICE_ADC_CHANNEL, &data) == IOT_SUCCESS) {
            g_adc_buf[g_wr] = (uint16_t)data;
            int next = g_wr + 1;
            if (next >= VOICE_ADC_RB_SIZE) next = 0;
            if (next == g_rd) {
                /* ring full: drop oldest */
                int rnext = g_rd + 1;
                if (rnext >= VOICE_ADC_RB_SIZE) rnext = 0;
                g_rd = rnext;
            }
            g_wr = next;
        }
        /* busy-wait ~125us for ~8kHz sampling (calibrate with hardware) */
        for (volatile int i = 0; i < BUSY_CYCLES_PER_SAMPLE; i++) {
            __asm volatile("nop");
        }
    }
}

int voice_adc_init(void)
{
    unsigned int ret = IoTAdcInit(VOICE_ADC_CHANNEL);
    if (ret != IOT_SUCCESS) {
        printf("[VOICE_ADC] init failed: %u\n", ret);
        return -1;
    }
    g_wr = 0;
    g_rd = 0;
    g_running = false;
    printf("[VOICE_ADC] init ok, channel=%d\n", VOICE_ADC_CHANNEL);
    return 0;
}

int voice_adc_start(void)
{
    if (g_running) return 0;
    g_running = true;

    unsigned int task_id;
    TSK_INIT_PARAM_S task = {0};
    task.pfnTaskEntry = (TSK_ENTRY_FUNC)voice_adc_task;
    task.uwStackSize = 4096;
    task.pcName = "voice_adc";
    task.usTaskPrio = 25;  /* below main loop (24) to avoid starving command processing */
    unsigned int ret = LOS_TaskCreate(&task_id, &task);
    if (ret != LOS_OK) {
        printf("[VOICE_ADC] task create failed: %u\n", ret);
        g_running = false;
        return -1;
    }
    printf("[VOICE_ADC] task started, id=%u\n", task_id);
    return 0;
}

void voice_adc_stop(void) { g_running = false; }
bool voice_adc_is_running(void) { return g_running; }

int voice_adc_available(void)
{
    if (g_wr >= g_rd) return g_wr - g_rd;
    return VOICE_ADC_RB_SIZE - g_rd + g_wr;
}

int voice_adc_read(uint16_t *buf, int max_samples)
{
    int avail = voice_adc_available();
    int count = (avail < max_samples) ? avail : max_samples;
    for (int i = 0; i < count; i++) {
        buf[i] = g_adc_buf[g_rd];
        int rnext = g_rd + 1;
        if (rnext >= VOICE_ADC_RB_SIZE) rnext = 0;
        g_rd = rnext;
    }
    return count;
}

void voice_adc_flush(void) { g_rd = g_wr; }
