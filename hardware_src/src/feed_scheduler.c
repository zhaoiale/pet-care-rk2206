#include "feed_scheduler.h"
#include "drv_feeder.h"
#include <stdio.h>
#include <string.h>
#include "cJSON.h"
#include "lz_hardware/flash.h"

static feed_schedule_entry_t g_schedule[MAX_SCHEDULE_ENTRIES];
static uint8_t  g_schedule_count = 0;
static uint32_t g_base_timestamp = 0;
static uint32_t g_base_ticks = 0;
static uint32_t g_current_ticks = 0;
static uint16_t g_last_fired_minute = 0xFFFF;

/* --- Flash layout --- */
#define FLASH_SCHED_OFFSET  0x7F1000
#define FLASH_SCHED_MAGIC   0x53434844  /* "SCHD" */

typedef struct {
    uint32_t magic;
    uint32_t count;
    uint32_t checksum;
    uint32_t enabled_mask;
} sched_flash_header_t;

static uint32_t sched_checksum(const feed_schedule_entry_t *entries, int count)
{
    uint32_t sum = 0;
    const uint8_t *p = (const uint8_t *)entries;
    for (unsigned i = 0; i < (unsigned)count * sizeof(feed_schedule_entry_t); i++) {
        sum = sum * 31 + p[i];
    }
    return sum;
}

void feed_scheduler_init(void)
{
    g_schedule_count = 0;
    g_base_timestamp = 0;
    g_base_ticks = 0;
    g_current_ticks = 0;
    g_last_fired_minute = 0xFFFF;
    memset(g_schedule, 0, sizeof(g_schedule));
    printf("[SCHED] init done\n");
}

void feed_scheduler_tick(uint32_t loop_ticks)
{
    g_current_ticks = loop_ticks;
}

static uint32_t scheduler_get_timestamp(void)
{
    if (g_base_timestamp == 0) return 0;
    uint32_t elapsed = (g_current_ticks - g_base_ticks) * 3;
    return g_base_timestamp + elapsed;
}

static uint16_t timestamp_to_minute(uint32_t ts)
{
    uint32_t local = ts + 8 * 3600;
    uint32_t day_seconds = local % 86400;
    return (uint16_t)(day_seconds / 60);
}

void feed_scheduler_sync_time(uint32_t unix_ts)
{
    g_base_timestamp = unix_ts;
    g_base_ticks = g_current_ticks;
    g_last_fired_minute = timestamp_to_minute(unix_ts);
    printf("[SCHED] time synced: ts=%u ticks=%u minute=%u\n",
           unix_ts, g_current_ticks, g_last_fired_minute);
}

unsigned int feed_scheduler_check(void)
{
    if (g_schedule_count == 0 || g_base_timestamp == 0) return 0;

    uint32_t now_ts = scheduler_get_timestamp();
    if (now_ts == 0) return 0;

    uint16_t now_minute = timestamp_to_minute(now_ts);
    if (now_minute == g_last_fired_minute) return 0;

    uint8_t now_hour = (uint8_t)(now_minute / 60);
    uint8_t now_min  = (uint8_t)(now_minute % 60);

    for (uint8_t i = 0; i < g_schedule_count; i++) {
        if (!g_schedule[i].enabled) continue;
        if (g_schedule[i].hour != now_hour) continue;
        if (g_schedule[i].minute != now_min) continue;

        unsigned int grams = g_schedule[i].grams;
        if (grams == 0) grams = 50;
        if (grams > 2000) grams = 2000;

        feeder_feed_grams(grams);

        printf("[SCHED] auto-feed fired: %02u:%02u %ug\n",
               now_hour, now_min, grams);

        g_last_fired_minute = now_minute;
        return grams;
    }

    g_last_fired_minute = now_minute;
    return 0;
}

int feed_scheduler_parse_json(const char *json_str)
{
    cJSON *root = cJSON_Parse(json_str);
    if (!root) return -1;

    cJSON *plans = cJSON_GetObjectItem(root, "plans");
    if (!plans || !cJSON_IsArray(plans)) {
        cJSON_Delete(root);
        return -1;
    }

    int count = cJSON_GetArraySize(plans);
    if (count > MAX_SCHEDULE_ENTRIES) count = MAX_SCHEDULE_ENTRIES;

    g_schedule_count = (uint8_t)count;

    for (int i = 0; i < count; i++) {
        cJSON *item = cJSON_GetArrayItem(plans, i);
        if (!item) continue;

        cJSON *time_obj = cJSON_GetObjectItem(item, "time");
        cJSON *amount_obj = cJSON_GetObjectItem(item, "amount");
        cJSON *enabled_obj = cJSON_GetObjectItem(item, "enabled");

        if (time_obj && time_obj->type == cJSON_String) {
            const char *time_str = time_obj->valuestring;
            int h = 0, m = 0;
            if (sscanf(time_str, "%d:%d", &h, &m) == 2) {
                g_schedule[i].hour = (uint8_t)h;
                g_schedule[i].minute = (uint8_t)m;
            }
        }

        g_schedule[i].grams = (amount_obj && amount_obj->type == cJSON_Number)
                               ? (uint16_t)amount_obj->valueint : 50;

        g_schedule[i].enabled = (enabled_obj && enabled_obj->type == cJSON_False)
                                ? false : true;
    }

    printf("[SCHED] parsed %d entries:\n", count);
    for (int i = 0; i < count; i++) {
        printf("  [%d] %02u:%02u %ug %s\n", i,
               g_schedule[i].hour, g_schedule[i].minute,
               g_schedule[i].grams,
               g_schedule[i].enabled ? "ON" : "OFF");
    }

    cJSON_Delete(root);

    // Auto-save to flash after parsing (App-synced schedule)
    feed_scheduler_save_to_flash();

    return count;
}

uint8_t feed_scheduler_get_count(void)
{
    return g_schedule_count;
}

const feed_schedule_entry_t *feed_scheduler_get_entries(void)
{
    return g_schedule;
}

/* ================================================================
 * Flash persistence — 4K sector at FLASH_SCHED_OFFSET
 * Format: magic(4B) + count(4B) + checksum(4B) + enabled_mask(4B)
 *         + entries[count] * sizeof(feed_schedule_entry_t)
 * ================================================================ */

int feed_scheduler_save_to_flash(void)
{
    if (g_schedule_count == 0) return 0;

    static uint8_t block[4096];
    memset(block, 0xFF, sizeof(block));

    sched_flash_header_t *hdr = (sched_flash_header_t *)block;
    hdr->magic = FLASH_SCHED_MAGIC;
    hdr->count = g_schedule_count;

    uint32_t mask = 0;
    for (int i = 0; i < g_schedule_count; i++) {
        if (g_schedule[i].enabled) mask |= (1u << i);
    }
    hdr->enabled_mask = mask;

    memcpy(block + sizeof(sched_flash_header_t), g_schedule,
           g_schedule_count * sizeof(feed_schedule_entry_t));
    hdr->checksum = sched_checksum(g_schedule, (int)g_schedule_count);

    unsigned int ret = FlashErase(FLASH_SCHED_OFFSET, 4096);
    if (ret != 0) {
        printf("[SCHED-FLASH] erase failed: %u\n", ret);
        return -1;
    }

    ret = FlashWrite(FLASH_SCHED_OFFSET, 4096, block, 1);
    if (ret != 0) {
        printf("[SCHED-FLASH] write failed: %u\n", ret);
        return -1;
    }

    printf("[SCHED-FLASH] saved %d entries (offset=0x%X)\n", g_schedule_count, FLASH_SCHED_OFFSET);
    return 0;
}

int feed_scheduler_load_from_flash(void)
{
    static uint8_t block[4096];

    unsigned int ret = FlashRead(FLASH_SCHED_OFFSET, 4096, block);
    if (ret != 0) {
        printf("[SCHED-FLASH] read failed: %u\n", ret);
        goto use_defaults;
    }

    sched_flash_header_t *hdr = (sched_flash_header_t *)block;

    if (hdr->magic != FLASH_SCHED_MAGIC) {
        printf("[SCHED-FLASH] no valid data (magic=0x%X), using defaults\n", hdr->magic);
        goto use_defaults;
    }

    if (hdr->count == 0 || hdr->count > MAX_SCHEDULE_ENTRIES) {
        printf("[SCHED-FLASH] invalid count: %u, using defaults\n", hdr->count);
        goto use_defaults;
    }

    feed_schedule_entry_t *entries =
        (feed_schedule_entry_t *)(block + sizeof(sched_flash_header_t));

    uint32_t calc_sum = sched_checksum(entries, (int)hdr->count);
    if (calc_sum != hdr->checksum) {
        printf("[SCHED-FLASH] checksum mismatch (calc=0x%X stored=0x%X), using defaults\n",
               calc_sum, hdr->checksum);
        goto use_defaults;
    }

    // Load into RAM
    g_schedule_count = (uint8_t)hdr->count;
    memcpy(g_schedule, entries, hdr->count * sizeof(feed_schedule_entry_t));

    printf("[SCHED-FLASH] loaded %u entries from flash:\n", hdr->count);
    for (uint32_t i = 0; i < hdr->count; i++) {
        printf("  [%u] %02u:%02u %ug %s\n", i,
               g_schedule[i].hour, g_schedule[i].minute,
               g_schedule[i].grams,
               g_schedule[i].enabled ? "ON" : "OFF");
    }
    return (int)hdr->count;

use_defaults:
    // Populate factory defaults: 8:00 / 14:00 / 20:00, 50g each
    printf("[SCHED-FLASH] loading factory defaults\n");
    g_schedule_count = 3;

    g_schedule[0].hour = 8;   g_schedule[0].minute = 0;
    g_schedule[0].grams = 50;
    g_schedule[0].enabled = true;

    g_schedule[1].hour = 14;  g_schedule[1].minute = 0;
    g_schedule[1].grams = 50;
    g_schedule[1].enabled = true;

    g_schedule[2].hour = 20;  g_schedule[2].minute = 0;
    g_schedule[2].grams = 50;
    g_schedule[2].enabled = true;

    for (int i = 3; i < MAX_SCHEDULE_ENTRIES; i++) {
        g_schedule[i].hour = 0;
        g_schedule[i].minute = 0;
        g_schedule[i].grams = 50;
        g_schedule[i].enabled = false;
    }

    for (int i = 0; i < g_schedule_count; i++) {
        printf("  [%d] %02u:%02u %ug %s\n", i,
               g_schedule[i].hour, g_schedule[i].minute,
               g_schedule[i].grams,
               g_schedule[i].enabled ? "ON" : "OFF");
    }

    // Save defaults to flash so they survive next reboot
    feed_scheduler_save_to_flash();
    return (int)g_schedule_count;
}
