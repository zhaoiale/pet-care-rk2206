/*
 * ATGM336H GPS/BDS dual-mode positioning module driver
 * UART NMEA-0183 parser for RK2206 OpenHarmony LiteOS
 *
 * Default: 9600 baud, 8N1, 1Hz update
 * Connect: VCC→3.3V, GND→GND, TX→UART0_RX (GPIO0_PB6), RX→UART0_TX (GPIO0_PB7)
 * NOTE: If using different pins, change GPS_UART_ID below.
 */

#include "atgm336h.h"
#include "iot_uart.h"
#include "iot_errno.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

/* UART config — EUART0_M0 (RX=PB6 TX=PB7), not conflicting with debug UART */
#define GPS_UART_ID       EUART0_M0
#define GPS_BAUD_RATE     9600
#define GPS_RX_BUF_SIZE   512

static gps_data_t g_latest_gps = {0};
static char g_rx_buf[GPS_RX_BUF_SIZE];

/* ---- NMEA helpers ---- */

static float nmea_to_deg(float raw, char dir)
{
    int   deg = (int)(raw / 100.0f);
    float min = raw - deg * 100.0f;
    float val = deg + min / 60.0f;
    if (dir == 'S' || dir == 'W') val = -val;
    return val;
}

/* Extract the N-th comma-separated field from a sentence.
   Returns pointer into the sentence buffer (not null-terminated);
   sets *len to field length. Returns NULL if field doesn't exist. */
static const char *get_field(const char *s, int n, int *len)
{
    for (int i = 0; i < n; i++) {
        const char *p = strchr(s, ',');
        if (!p) { *len = 0; return NULL; }
        s = p + 1;
    }
    const char *end = strchr(s, ',');
    if (!end) end = strchr(s, '*');  /* checksum delimiter */
    if (!end) end = s + strlen(s);
    *len = (int)(end - s);
    return (*len > 0) ? s : NULL;
}

static int field_to_int(const char *s, int len)
{
    if (!s || len <= 0) return 0;
    char tmp[16];
    int n = (len < (int)sizeof(tmp) - 1) ? len : (int)sizeof(tmp) - 1;
    memcpy(tmp, s, n);
    tmp[n] = '\0';
    return atoi(tmp);
}

static float field_to_float(const char *s, int len)
{
    if (!s || len <= 0) return 0.0f;
    char tmp[32];
    int n = (len < (int)sizeof(tmp) - 1) ? len : (int)sizeof(tmp) - 1;
    memcpy(tmp, s, n);
    tmp[n] = '\0';
    return atof(tmp);
}

static char field_to_char(const char *s, int len)
{
    return (s && len > 0) ? s[0] : '\0';
}

/* Parse $GNRMC — Recommended Minimum Specific GNSS Data
   $GNRMC,HHMMSS.ss,A,ddmm.mmmm,N,dddmm.mmmm,E,spd,ang,date,,,mode*CS */
static void parse_rmc(const char *sentence)
{
    int len;
    const char *f;

    /* Field 2: validity A=valid, skip if not */
    f = get_field(sentence, 2, &len);
    if (!f || field_to_char(f, len) != 'A') return;

    /* Field 4: N/S — must exist, otherwise sentence is truncated */
    f = get_field(sentence, 4, &len);
    char ns = field_to_char(f, len);
    if (ns != 'N' && ns != 'S') return;

    /* Field 6: E/W */
    f = get_field(sentence, 6, &len);
    char ew = field_to_char(f, len);
    if (ew != 'E' && ew != 'W') return;

    /* Field 1: UTC time */
    f = get_field(sentence, 1, &len);
    if (f) {
        int n = (len < 11) ? len : 11;
        memcpy(g_latest_gps.utc_time, f, n);
        g_latest_gps.utc_time[n] = '\0';
    }

    /* Field 3: latitude raw */
    f = get_field(sentence, 3, &len);
    float lat_raw = field_to_float(f, len);

    /* Field 5: longitude raw */
    f = get_field(sentence, 5, &len);
    float lon_raw = field_to_float(f, len);

    g_latest_gps.latitude  = nmea_to_deg(lat_raw, ns);
    g_latest_gps.longitude = nmea_to_deg(lon_raw, ew);

    /* Field 7: speed in knots → convert to km/h */
    f = get_field(sentence, 7, &len);
    g_latest_gps.speed_kmh = field_to_float(f, len) * 1.852f;

    g_latest_gps.is_valid = 1;
}

/* Parse $GNGGA — Global Positioning System Fix Data
   $GNGGA,HHMMSS.ss,ddmm.mmmm,N,dddmm.mmmm,E,qual,num,hdop,alt,M,...*CS */
static void parse_gga(const char *sentence)
{
    int len;
    const char *f;

    /* Field 6: fix quality (0=invalid, 1=GPS, 2=DGPS, 4=RTK) */
    f = get_field(sentence, 6, &len);
    int quality = field_to_int(f, len);
    g_latest_gps.fix_quality = quality;

    /* Field 7: satellites used */
    f = get_field(sentence, 7, &len);
    g_latest_gps.satellites = field_to_int(f, len);

    /* Field 9: altitude in meters */
    f = get_field(sentence, 9, &len);
    g_latest_gps.altitude = field_to_float(f, len);

    /* No position if fix is invalid */
    if (quality == 0) return;

    /* Field 3: N/S — must exist */
    f = get_field(sentence, 3, &len);
    char ns = field_to_char(f, len);
    if (ns != 'N' && ns != 'S') return;

    /* Field 5: E/W */
    f = get_field(sentence, 5, &len);
    char ew = field_to_char(f, len);
    if (ew != 'E' && ew != 'W') return;

    /* Field 1: UTC time */
    f = get_field(sentence, 1, &len);
    if (f) {
        int n = (len < 11) ? len : 11;
        memcpy(g_latest_gps.utc_time, f, n);
        g_latest_gps.utc_time[n] = '\0';
    }

    /* Field 2: latitude raw */
    f = get_field(sentence, 2, &len);
    float lat_raw = field_to_float(f, len);

    /* Field 4: longitude raw */
    f = get_field(sentence, 4, &len);
    float lon_raw = field_to_float(f, len);

    g_latest_gps.latitude  = nmea_to_deg(lat_raw, ns);
    g_latest_gps.longitude = nmea_to_deg(lon_raw, ew);
    g_latest_gps.is_valid = 1;
}

/* Parse $GNGLL — Geographic Position, Latitude/Longitude
   $GNGLL,ddmm.mmmm,N,dddmm.mmmm,E,HHMMSS.ss,A,M*CS */
static void parse_gll(const char *sentence)
{
    int len;
    const char *f;

    /* Field 6: validity A=valid */
    f = get_field(sentence, 6, &len);
    if (!f || field_to_char(f, len) != 'A') return;

    /* Field 2: N/S — must exist */
    f = get_field(sentence, 2, &len);
    char ns = field_to_char(f, len);
    if (ns != 'N' && ns != 'S') return;

    /* Field 4: E/W */
    f = get_field(sentence, 4, &len);
    char ew = field_to_char(f, len);
    if (ew != 'E' && ew != 'W') return;

    /* Field 1: latitude raw */
    f = get_field(sentence, 1, &len);
    float lat_raw = field_to_float(f, len);

    /* Field 3: longitude raw */
    f = get_field(sentence, 3, &len);
    float lon_raw = field_to_float(f, len);

    g_latest_gps.latitude  = nmea_to_deg(lat_raw, ns);
    g_latest_gps.longitude = nmea_to_deg(lon_raw, ew);
    g_latest_gps.is_valid = 1;

    /* Field 5: UTC time */
    f = get_field(sentence, 5, &len);
    if (f) {
        int n = (len < 11) ? len : 11;
        memcpy(g_latest_gps.utc_time, f, n);
        g_latest_gps.utc_time[n] = '\0';
    }
}

/* Process one complete NMEA sentence */
static void process_sentence(char *s)
{
    /* Strip trailing \r\n */
    int sl = (int)strlen(s);
    while (sl > 0 && (s[sl-1] == '\r' || s[sl-1] == '\n')) {
        s[--sl] = '\0';
    }

    /* Validate checksum (simple XOR, skip if absent) */
    char *star = strchr(s, '*');
    if (star) *star = '\0';  /* terminate before checksum for parsing */

    /* Debug: print first 25 raw sentences to verify NMEA format */
    static int raw_dbg = 0;
    if (raw_dbg < 25) {
        printf("GPS RAW[%d]: %s\n", raw_dbg, s);
        raw_dbg++;
    }

    if (strncmp(s, "$GNRMC", 6) == 0 || strncmp(s, "$GPRMC", 6) == 0) {
        parse_rmc(s);
    } else if (strncmp(s, "$GNGGA", 6) == 0 || strncmp(s, "$GPGGA", 6) == 0 ||
               strncmp(s, "$BDGGA", 6) == 0 || strncmp(s, "$GLGGA", 6) == 0) {
        parse_gga(s);
    } else if (strncmp(s, "$GNGLL", 6) == 0 || strncmp(s, "$GPGLL", 6) == 0 ||
               strncmp(s, "$BDGLL", 6) == 0 || strncmp(s, "$GLGLL", 6) == 0) {
        parse_gll(s);
    } else if (s[0] >= '0' && s[0] <= '9') {
        /* AT6558F sometimes drops the $ header entirely.
           If the line starts with a time field (HHMMSS.ss),
           try prepending $GPRMC, and re-parsing. */
        int commas = 0;
        for (int i = 0; s[i]; i++) if (s[i] == ',') commas++;
        if (commas >= 8) {
            char fixed[160];
            int n = snprintf(fixed, sizeof(fixed), "$GPRMC,%s", s);
            if (n > 0 && n < (int)sizeof(fixed)) {
                parse_rmc(fixed);
            }
        }
    }
    /* Other sentences ($GNVTG, $GNGSA, $GPGSV, etc.) ignored */
}

/* ---- Public API ---- */

/* Reject physically impossible values from corrupted parses */
static int validate_gps(const gps_data_t *g)
{
    if (g->satellites < 0 || g->satellites > 32) return 0;
    if (g->fix_quality < 0 || g->fix_quality > 6) return 0;
    if (g->latitude < -90.0f || g->latitude > 90.0f) return 0;
    if (g->longitude < -180.0f || g->longitude > 180.0f) return 0;
    if (g->speed_kmh < 0.0f || g->speed_kmh > 500.0f) return 0;
    if (g->altitude < -500.0f || g->altitude > 10000.0f) return 0;
    return 1;
}

void atgm336h_init(void)
{
    printf("ATGM336H: init UART0 @ %d baud\n", GPS_BAUD_RATE);

    IotUartAttribute attr;
    attr.baudRate = GPS_BAUD_RATE;
    attr.dataBits = IOT_UART_DATA_BIT_8;
    attr.stopBits = IOT_UART_STOP_BIT_1;
    attr.parity   = IOT_UART_PARITY_NONE;
    attr.rxBlock  = IOT_UART_BLOCK_STATE_NONE_BLOCK;
    attr.txBlock  = IOT_UART_BLOCK_STATE_NONE_BLOCK;
    attr.pad      = 0;

    IoTUartDeinit(GPS_UART_ID);

    unsigned int ret = IoTUartInit(GPS_UART_ID, &attr);
    if (ret != IOT_SUCCESS) {
        printf("ATGM336H: UART init failed (ret=%u) — check wiring\n", ret);
    } else {
        printf("ATGM336H: UART init OK, waiting for fix...\n");
        (void)IoTUartSetFlowCtrl(GPS_UART_ID, IOT_FLOW_CTRL_NONE);
    }

    memset(&g_latest_gps, 0, sizeof(g_latest_gps));
}

int atgm336h_get_data(gps_data_t *gps)
{
    if (!gps) return -1;

    /* Drain UART RX buffer and parse any complete lines */
    int total = 0;
    static char line[128];
    static int  line_pos = 0;

    while (1) {
        int n = IoTUartRead(GPS_UART_ID,
                            (unsigned char *)g_rx_buf, GPS_RX_BUF_SIZE);
        if (n <= 0) break;
        total += n;

        for (int i = 0; i < n; i++) {
            char c = g_rx_buf[i];
            if (c == '\r' || c == '\n') {
                if (line_pos > 0) {
                    line[line_pos] = '\0';
                    process_sentence(line);
                }
                line_pos = 0;
            } else if (c == '$' && line_pos > 0) {
                /* AT6558F concatenates sentences without newline */
                line[line_pos] = '\0';
                process_sentence(line);
                line[line_pos++] = c;
            } else if (line_pos < (int)sizeof(line) - 1) {
                line[line_pos++] = c;
            } else {
                line_pos = 0;  /* overflow, discard */
            }
        }
    }

    /* Diagnostic: print status every call during bringup */
    {
        static int diag_cnt = 0;
        diag_cnt++;
        if (diag_cnt >= 2) {
            diag_cnt = 0;
            printf("GPS: rd=%d valid=%d lat=%.5f lon=%.5f sats=%d fix=%d\n",
                   total,
                   g_latest_gps.is_valid,
                   g_latest_gps.latitude, g_latest_gps.longitude,
                   g_latest_gps.satellites, g_latest_gps.fix_quality);
        }
    }

    *gps = g_latest_gps;
    if (g_latest_gps.is_valid && validate_gps(&g_latest_gps)) {
        return 0;
    }
    g_latest_gps.is_valid = 0;  /* clear flag so caller sees consistent state */
    return -1;
}
