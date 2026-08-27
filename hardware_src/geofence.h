#ifndef _GEOFENCE_H_
#define _GEOFENCE_H_
#include <stdbool.h>
#include <stdint.h>

/* Geofence status */
#define GEOFENCE_INSIDE   0
#define GEOFENCE_OUTSIDE  1

/* One GPS path point */
typedef struct {
    float    lat;
    float    lon;
    uint32_t timestamp;   /* LOS_TickCountGet() when recorded */
} gps_point_t;

/* Default geofence radius in meters */
#define GEOFENCE_DEFAULT_RADIUS  100.0f

void geofence_init(void);

/* Set home position (usually current GPS when user presses "set home") */
void geofence_set_home(float lat, float lon);

/* Get home position (returns false if not set) */
bool geofence_get_home(float *lat, float *lon);

/* Set geofence radius in meters */
void geofence_set_radius(float radius_m);

/* Check if position is inside fence.
 * Returns GEOFENCE_INSIDE or GEOFENCE_OUTSIDE.
 * distance_m is set to distance from home in meters.
 * Every call also records the point to the path ring buffer. */
int geofence_check(float lat, float lon, float *distance_m);

/* Offline path recording */
int  geofence_get_path_count(void);
void geofence_get_path(gps_point_t *buf, int max_count);
void geofence_get_path_range(gps_point_t *buf, int offset, int count);
void geofence_clear_path(void);

/* Serial dump */
void geofence_dump_path(void);

/* Flash persistence */
int  geofence_save_to_flash(void);
int  geofence_load_from_flash(void);

#endif
