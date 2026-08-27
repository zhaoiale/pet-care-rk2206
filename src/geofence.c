#include "geofence.h"
#include <math.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include "los_tick.h"
#include "lz_hardware/flash.h"

/* --- Geofence state --- */
static float g_home_lat = 0.0f;
static float g_home_lon = 0.0f;
static bool  g_home_set = false;
static float g_radius_m = GEOFENCE_DEFAULT_RADIUS;
static int   g_prev_status = GEOFENCE_INSIDE;

/* --- Path ring buffer --- */
#define PATH_MAX  256
static gps_point_t g_path[PATH_MAX];
static int g_path_head = 0;
static int g_path_count = 0;

/* --- Flash layout --- */
#define FLASH_PATH_OFFSET   0x7F0000
#define FLASH_PATH_MAGIC    0x50415448  /* "PATH" */
#define FLASH_PATH_MAX      ((4096 - 16) / sizeof(gps_point_t))  /* ~340 points per 4K block */

typedef struct {
    uint32_t magic;
    uint32_t count;
    uint32_t checksum;
    uint32_t reserved;
} path_flash_header_t;

/* --- Helpers --- */
static float deg2rad(float deg) { return deg * 3.14159265358979323846f / 180.0f; }

/* Haversine distance in meters between two lat/lon points */
static float haversine(float lat1, float lon1, float lat2, float lon2)
{
    float dlat = deg2rad(lat2 - lat1);
    float dlon = deg2rad(lon2 - lon1);
    float a = sinf(dlat / 2.0f) * sinf(dlat / 2.0f) +
              cosf(deg2rad(lat1)) * cosf(deg2rad(lat2)) *
              sinf(dlon / 2.0f) * sinf(dlon / 2.0f);
    float c = 2.0f * atan2f(sqrtf(a), sqrtf(1.0f - a));
    return 6371000.0f * c;
}

static uint32_t path_checksum(const gps_point_t *pts, int count)
{
    uint32_t sum = 0;
    const uint8_t *p = (const uint8_t *)pts;
    for (unsigned i = 0; i < count * sizeof(gps_point_t); i++) {
        sum = sum * 31 + p[i];
    }
    return sum;
}

static void path_push(float lat, float lon)
{
    g_path[g_path_head].lat = lat;
    g_path[g_path_head].lon = lon;
    g_path[g_path_head].timestamp = (uint32_t)(LOS_TickCountGet() & 0xFFFFFFFFULL);
    g_path_head = (g_path_head + 1) % PATH_MAX;
    if (g_path_count < PATH_MAX) g_path_count++;
}

/* --- Public API --- */

void geofence_init(void)
{
    g_home_set = false;
    g_prev_status = GEOFENCE_INSIDE;
    g_path_head = 0;
    g_path_count = 0;
    printf("GEOFENCE: init (ring=%d pts, flash offset=0x%X)\n", PATH_MAX, FLASH_PATH_OFFSET);
}

void geofence_set_home(float lat, float lon)
{
    g_home_lat = lat;
    g_home_lon = lon;
    g_home_set = true;
    g_prev_status = GEOFENCE_INSIDE;
    printf("GEOFENCE: home set to (%.6f, %.6f)\n", lat, lon);
}

bool geofence_get_home(float *lat, float *lon)
{
    if (!g_home_set) return false;
    *lat = g_home_lat;
    *lon = g_home_lon;
    return true;
}

void geofence_set_radius(float radius_m)
{
    g_radius_m = radius_m;
    printf("GEOFENCE: radius set to %.0fm\n", radius_m);
}

int geofence_check(float lat, float lon, float *distance_m)
{
    /* Always record the path point */
    if (lat != 0.0f || lon != 0.0f) {
        path_push(lat, lon);
    }

    if (!g_home_set) {
        if (distance_m) *distance_m = 0.0f;
        return GEOFENCE_INSIDE;
    }

    float dist = haversine(g_home_lat, g_home_lon, lat, lon);
    if (distance_m) *distance_m = dist;

    int status = (dist > g_radius_m) ? GEOFENCE_OUTSIDE : GEOFENCE_INSIDE;

    /* Log transitions */
    if (status != g_prev_status) {
        if (status == GEOFENCE_OUTSIDE) {
            printf("GEOFENCE: PET LEFT fence! distance=%.0fm (limit=%.0fm)\n",
                   dist, g_radius_m);
        } else {
            printf("GEOFENCE: pet returned inside fence, distance=%.0fm\n", dist);
        }
        g_prev_status = status;
    }

    return status;
}

int geofence_get_path_count(void)
{
    return g_path_count;
}

void geofence_get_path(gps_point_t *buf, int max_count)
{
    int n = (g_path_count < max_count) ? g_path_count : max_count;
    int start = (g_path_count < PATH_MAX) ? 0 : g_path_head;
    for (int i = 0; i < n; i++) {
        int idx = (start + i) % PATH_MAX;
        buf[i] = g_path[idx];
    }
}

void geofence_get_path_range(gps_point_t *buf, int offset, int count)
{
    int total = (g_path_count < PATH_MAX) ? g_path_count : PATH_MAX;
    if (offset >= total) return;
    int n = (offset + count <= total) ? count : (total - offset);
    int start = (g_path_count < PATH_MAX) ? 0 : g_path_head;
    for (int i = 0; i < n; i++) {
        int idx = (start + offset + i) % PATH_MAX;
        buf[i] = g_path[idx];
    }
}

void geofence_clear_path(void)
{
    g_path_head = 0;
    g_path_count = 0;
    printf("GEOFENCE: path cleared\n");
}

/* --- Serial dump --- */

void geofence_dump_path(void)
{
    int count = g_path_count;
    if (count == 0) {
        printf("[PATH] no trajectory data (0 points)\n");
        return;
    }

    /* Linearize ring buffer */
    int start = (g_path_count < PATH_MAX) ? 0 : g_path_head;
    float home_lat, home_lon;
    bool has_home = geofence_get_home(&home_lat, &home_lon);

    printf("[PATH] %d points", count);
    if (has_home) {
        printf("  home=(%.6f,%.6f) radius=%.0fm", home_lat, home_lon, g_radius_m);
    }
    printf("\n");
    printf("[PATH] ---- trajectory dump start ----\n");

    uint32_t base_tick = 0;
    for (int i = 0; i < count; i++) {
        int idx = (start + i) % PATH_MAX;
        gps_point_t *p = &g_path[idx];

        if (i == 0) base_tick = p->timestamp;

        uint32_t rel_ms = LOS_Tick2MS(p->timestamp - base_tick);
        uint32_t sec = rel_ms / 1000;
        uint32_t min = sec / 60;
        uint32_t ms  = rel_ms % 1000;

        float dist = 0.0f;
        if (has_home) {
            dist = haversine(home_lat, home_lon, p->lat, p->lon);
        }

        printf("[%3d] %3u:%02u.%03u  lat=%.6f lon=%.6f",
               i, min, sec % 60, ms, p->lat, p->lon);
        if (has_home) {
            printf("  dist=%.0fm", dist);
        }
        printf("\n");
    }

    printf("[PATH] ---- trajectory dump end ----\n");
}

/* --- Flash persistence --- */

int geofence_save_to_flash(void)
{
    int count = g_path_count;
    if (count == 0) return 0;

    /* Linearize ring buffer into contiguous array */
    int start = (g_path_count < PATH_MAX) ? 0 : g_path_head;
    int save_count = (count > (int)FLASH_PATH_MAX) ? (int)FLASH_PATH_MAX : count;

    static gps_point_t save_buf[FLASH_PATH_MAX];
    for (int i = 0; i < save_count; i++) {
        int idx = (start + i) % PATH_MAX;
        save_buf[i] = g_path[idx];
    }

    /* Build header + data in a 4K-aligned buffer */
    static uint8_t block[4096];
    memset(block, 0xFF, sizeof(block));

    path_flash_header_t *hdr = (path_flash_header_t *)block;
    hdr->magic    = FLASH_PATH_MAGIC;
    hdr->count    = (uint32_t)save_count;
    hdr->reserved = 0;

    memcpy(block + sizeof(path_flash_header_t), save_buf,
           save_count * sizeof(gps_point_t));

    hdr->checksum = path_checksum(save_buf, save_count);

    /* Erase and write */
    unsigned int ret = FlashErase(FLASH_PATH_OFFSET, 4096);
    if (ret != 0) {
        printf("[PATH-FLASH] erase failed: %u\n", ret);
        return -1;
    }

    ret = FlashWrite(FLASH_PATH_OFFSET, 4096, block, 1);
    if (ret != 0) {
        printf("[PATH-FLASH] write failed: %u\n", ret);
        return -1;
    }

    printf("[PATH-FLASH] saved %d points (offset=0x%X)\n", save_count, FLASH_PATH_OFFSET);
    return 0;
}

int geofence_load_from_flash(void)
{
    static uint8_t block[4096];

    unsigned int ret = FlashRead(FLASH_PATH_OFFSET, 4096, block);
    if (ret != 0) {
        printf("[PATH-FLASH] read failed: %u\n", ret);
        return -1;
    }

    path_flash_header_t *hdr = (path_flash_header_t *)block;

    /* Validate header */
    if (hdr->magic != FLASH_PATH_MAGIC) {
        printf("[PATH-FLASH] no valid data (magic=0x%X)\n", hdr->magic);
        return -1;
    }

    if (hdr->count == 0 || hdr->count > FLASH_PATH_MAX) {
        printf("[PATH-FLASH] invalid count: %u\n", hdr->count);
        return -1;
    }

    gps_point_t *pts = (gps_point_t *)(block + sizeof(path_flash_header_t));

    /* Verify checksum */
    uint32_t calc_sum = path_checksum(pts, (int)hdr->count);
    if (calc_sum != hdr->checksum) {
        printf("[PATH-FLASH] checksum mismatch (calc=0x%X stored=0x%X)\n",
               calc_sum, hdr->checksum);
        return -1;
    }

    /* Load into ring buffer */
    g_path_head = 0;
    g_path_count = 0;
    for (uint32_t i = 0; i < hdr->count; i++) {
        g_path[g_path_head].lat       = pts[i].lat;
        g_path[g_path_head].lon       = pts[i].lon;
        g_path[g_path_head].timestamp = pts[i].timestamp;
        g_path_head = (g_path_head + 1) % PATH_MAX;
        if (g_path_count < PATH_MAX) g_path_count++;
    }

    printf("[PATH-FLASH] loaded %u points from flash\n", hdr->count);
    geofence_dump_path();
    return 0;
}
