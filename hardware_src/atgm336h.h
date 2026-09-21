#ifndef _ATGM336H_H_
#define _ATGM336H_H_

/* ATGM336H GPS/BDS 双模定位模块 — UART NMEA 解析 */

typedef struct {
    float  latitude;       /* 纬度 (decimal degrees), 未定位时为 0 */
    float  longitude;      /* 经度 (decimal degrees), 未定位时为 0 */
    float  altitude;       /* 海拔 (m) */
    float  speed_kmh;      /* 地面速率 (km/h) */
    int    satellites;     /* 有效卫星数 */
    int    fix_quality;    /* 0=未定位, 1=GPS, 2=DGPS, 4=RTK */
    char   utc_time[12];   /* HHMMSS.sss */
    int    is_valid;        /* 定位有效标志 */
} gps_data_t;

void atgm336h_init(void);
int  atgm336h_get_data(gps_data_t *gps);

#endif /* _ATGM336H_H_ */
