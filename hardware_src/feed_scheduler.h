#ifndef __FEED_SCHEDULER_H__
#define __FEED_SCHEDULER_H__

#include <stdbool.h>
#include <stdint.h>

#define MAX_SCHEDULE_ENTRIES 8

typedef struct {
    uint8_t  hour;
    uint8_t  minute;
    uint16_t grams;         // 投喂克数 (g)，默认50g/餐
    bool     enabled;
} feed_schedule_entry_t;

void feed_scheduler_init(void);

// Called each main loop iteration (~3s). Checks if any schedule entry
// matches current time and hasn't been fired yet this minute.
// Returns grams if a feed was triggered, 0 otherwise.
unsigned int feed_scheduler_check(void);

// Sync time from App: sets base for deriving current wall-clock time.
void feed_scheduler_sync_time(uint32_t unix_ts);

// Parse {"cmd":"scheduleSync","plans":[{"time":"08:00","amount":50,"enabled":true},...]}
// amount 字段语义为克数(g)
// Returns number of entries parsed, or -1 on error.
int feed_scheduler_parse_json(const char *json_str);

// Read-only access for MQTT response / debug
uint8_t feed_scheduler_get_count(void);
const feed_schedule_entry_t *feed_scheduler_get_entries(void);

// For main loop time derivation
void feed_scheduler_tick(uint32_t loop_ticks);

/* Flash persistence — 4K sector, same pattern as geofence */
int feed_scheduler_save_to_flash(void);
int feed_scheduler_load_from_flash(void);

#endif
