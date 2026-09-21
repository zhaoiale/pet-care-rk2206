#include "cli.h"
#include "geofence.h"
#include "drv_feeder.h"
#include "iot_gpio.h"
#include "shell.h"
#include "los_tick.h"
#include <stdio.h>
#include <stdlib.h>

/* ---- feed: test feeder relay ---- */

static UINT32 cmd_feed(UINT32 argc, const CHAR **argv)
{
    unsigned int grams = 50;
    if (argc >= 2) {
        grams = (unsigned int)atoi(argv[1]);
    }
    printf("[CLI] feeder on, %ug\n", grams);
    feeder_feed_grams(grams);
    printf("[CLI] feeder off\n");
    return 0;
}

/* ---- gpio: read/write any GPIO ---- */

static UINT32 cmd_gpio(UINT32 argc, const CHAR **argv)
{
    if (argc < 3) {
        printf("usage: gpio <pin> <0|1>   e.g. gpio PB1 0\n");
        return 1;
    }
    const char *pin_str = argv[1];
    unsigned int pin;
    char port = pin_str[0];
    char bank = pin_str[1];
    int num = atoi(pin_str + 2);
    if (port == 'P') {
        if (bank == 'B') pin = GPIO0_PB0 + num;
        else if (bank == 'C') pin = GPIO0_PC0 + num;
        else { printf("unknown bank %c\n", bank); return 1; }
    } else {
        pin = (unsigned int)atoi(pin_str);
    }
    int val = atoi(argv[2]);
    IoTGpioInit(pin);
    IoTGpioSetDir(pin, IOT_GPIO_DIR_OUT);
    IoTGpioSetOutputVal(pin, val ? IOT_GPIO_VALUE1 : IOT_GPIO_VALUE0);
    printf("[CLI] gpio %s(%u) -> %d\n", pin_str, pin, val);
    return 0;
}

/* ---- path ---- */

static UINT32 cmd_path(UINT32 argc, const CHAR **argv)
{
    (void)argc;
    (void)argv;
    geofence_dump_path();
    return 0;
}

static UINT32 cmd_pathsave(UINT32 argc, const CHAR **argv)
{
    (void)argc;
    (void)argv;
    int ret = geofence_save_to_flash();
    if (ret == 0) {
        printf("[CLI] path saved to flash OK\n");
    } else {
        printf("[CLI] path save failed: %d\n", ret);
    }
    return (UINT32)ret;
}

static UINT32 cmd_geohome(UINT32 argc, const CHAR **argv)
{
    (void)argc;
    (void)argv;
    float lat, lon;
    if (geofence_get_home(&lat, &lon)) {
        printf("[CLI] home: lat=%.6f lon=%.6f\n", lat, lon);
    } else {
        printf("[CLI] home not set\n");
    }
    return 0;
}

static UINT32 cmd_sethome(UINT32 argc, const CHAR **argv)
{
    (void)argc;
    (void)argv;
    extern bool g_pending_set_home;
    g_pending_set_home = true;
    printf("[CLI] set-home flag raised, will use next GPS fix\n");
    return 0;
}

static UINT32 cmd_status(UINT32 argc, const CHAR **argv)
{
    (void)argc;
    (void)argv;
    int count = geofence_get_path_count();
    float lat, lon;
    bool home = geofence_get_home(&lat, &lon);

    printf("[CLI] ---- status ----\n");
    printf("  path points: %d (max 256)\n", count);
    printf("  home: %s", home ? "SET" : "NOT SET");
    if (home) printf(" (%.6f, %.6f)", lat, lon);
    printf("\n");
    printf("  uptime ticks: %llu\n", LOS_TickCountGet());
    printf("  feeder pin: PA5\n");
    return 0;
}

/* ---- simpath: inject simulated GPS walking route ---- */

static UINT32 cmd_simpath(UINT32 argc, const CHAR **argv)
{
    (void)argc;
    (void)argv;

    float hlat, hlon;
    if (!geofence_get_home(&hlat, &hlon)) {
        printf("[SIM] No home set. Use 'sethome' first or set from App.\n");
        printf("[SIM] Using default: 34.1084, 109.0030\n");
        hlat = 34.1084f;
        hlon = 109.0030f;
        geofence_set_home(hlat, hlon);
    }

    int count = geofence_get_path_count();
    if (count > 200) {
        printf("[SIM] Path already full (%d pts), clear first with 'path' then 'pathsave' to reset\n", count);
        return 1;
    }

    printf("[SIM] Injecting walking route around (%.6f, %.6f)...\n", hlat, hlon);

    // Simulated route: 3 min walk, ~60 track points (every 3s)
    // Phase 1: stay at home (0-30s, 10 pts)
    // Phase 2: walk north out of fence (30-90s, 20 pts, ~150m)
    // Phase 3: wander outside (90-120s, 10 pts)
    // Phase 4: walk back south (120-180s, 20 pts)

    struct { float dlat; float dlon; } const route[] = {
        // Phase 1: home area (10 pts, 0-30s)
        {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0},
        {0.00002, 0.00001}, {0.00004, 0}, {0.00006, -0.00001}, {0.00004, 0.00002}, {0.00002, 0},
        // Phase 2: walking north out (20 pts, 30-90s)
        {0.00010, 0.00002}, {0.00018, 0.00001}, {0.00026, -0.00003}, {0.00034, 0.00002},
        {0.00042, 0}, {0.00050, -0.00001}, {0.00058, 0.00003}, {0.00066, 0.00002},
        {0.00074, 0.00001}, {0.00082, -0.00002}, {0.00090, 0}, {0.00098, 0.00001},
        {0.00106, -0.00001}, {0.00114, 0.00002}, {0.00122, -0.00002}, {0.00130, 0},
        {0.00135, 0.00003}, {0.00138, 0.00001}, {0.00141, -0.00002}, {0.00144, 0},
        // Phase 3: outside wandering (10 pts, 90-120s) — still beyond fence
        {0.00142, 0.00005}, {0.00140, 0.00010}, {0.00143, 0.00015},
        {0.00145, 0.00010}, {0.00148, 0.00005}, {0.00144, -0.00005},
        {0.00140, -0.00010}, {0.00137, -0.00005}, {0.00140, 0}, {0.00142, 0.00005},
        // Phase 4: walking back south (20 pts, 120-180s)
        {0.00135, 0}, {0.00126, -0.00001}, {0.00118, 0.00002}, {0.00110, 0},
        {0.00102, -0.00002}, {0.00094, 0.00001}, {0.00086, 0}, {0.00078, -0.00001},
        {0.00070, 0.00002}, {0.00062, 0}, {0.00054, -0.00002}, {0.00046, 0.00001},
        {0.00038, 0}, {0.00030, -0.00001}, {0.00022, 0.00002}, {0.00014, 0},
        {0.00008, 0}, {0.00004, 0.00001}, {0.00002, 0}, {0, 0},
    };

    int n = sizeof(route) / sizeof(route[0]);

    for (int i = 0; i < n; i++) {
        float lat = hlat + route[i].dlat;
        float lon = hlon + route[i].dlon;
        float dist;
        geofence_check(lat, lon, &dist);
    }

    printf("[SIM] Injected %d path points (total: %d)\n", n, geofence_get_path_count());
    printf("[SIM] Route: home -> ~160m north (out of fence) -> back home\n");

    int ret = geofence_save_to_flash();
    printf("[SIM] Flash save: %s\n", ret == 0 ? "OK" : "FAILED");

    // Force publish the path to MQTT so App can display it
    extern bool g_pending_path_upload;
    g_pending_path_upload = true;

    return 0;
}

/* ---- anxiety: simulate emotion/anxiety level for demo ---- */

static UINT32 cmd_anxiety(UINT32 argc, const CHAR **argv)
{
    extern int g_anxiety_sim;
    extern int g_anxiety_sim_level;
    extern int g_anxiety_level;
    extern bool g_force_publish;

    if (argc < 2) {
        printf("usage: anxiety <0..100>   simulate anxiety level\n");
        printf("       anxiety off         disable simulation\n");
        printf("  current: sim=%d level=%d\n", g_anxiety_sim, g_anxiety_sim_level);
        return 1;
    }

    if (argv[1][0] == 'o' || argv[1][0] == 'O') {
        g_anxiety_sim = 0;
        printf("[ANXIETY SIM] disabled, returning to real sensor data\n");
        return 0;
    }

    int level = atoi(argv[1]);
    if (level < 0) level = 0;
    if (level > 100) level = 100;

    g_anxiety_sim = 1;
    g_anxiety_sim_level = level;
    g_anxiety_level = level;
    g_force_publish = true;

    const char *emo;
    if (level >= 61)      emo = "ANXIOUS";
    else if (level >= 36) emo = "ALERT";
    else if (level >= 16) emo = "CALM";
    else                  emo = "HAPPY";

    printf("[ANXIETY SIM] level=%d (%s), force publish\n", level, emo);
    return 0;
}

/* ---- hrsim: toggle MAX30102 simulation mode ---- */

static UINT32 cmd_hrsim(UINT32 argc, const CHAR **argv)
{
    extern int g_hr_sim_enabled;

    if (argc < 2) {
        printf("usage: hrsim on|off\n");
        printf("  current: %s\n", g_hr_sim_enabled ? "ON (simulated)" : "OFF (real sensor)");
        return 1;
    }

    if (argv[1][0] == 'o' || argv[1][0] == 'O') {
        g_hr_sim_enabled = 1;
        printf("[HRSIM] ON — using simulated HR/SpO2\n");
    } else if (argv[1][0] == 'f' || argv[1][0] == 'F') {
        g_hr_sim_enabled = 0;
        printf("[HRSIM] OFF — using real MAX30102 sensor\n");
    } else {
        printf("[HRSIM] unknown: %s (use 'on' or 'off')\n", argv[1]);
        return 1;
    }
    return 0;
}

/* ---- registration ---- */

void cli_register_commands(void)
{
    osCmdReg(CMD_TYPE_STD, "feed",      0, cmd_feed);
    osCmdReg(CMD_TYPE_STD, "gpio",      0, cmd_gpio);
    osCmdReg(CMD_TYPE_STD, "path",      0, cmd_path);
    osCmdReg(CMD_TYPE_STD, "pathsave",  0, cmd_pathsave);
    osCmdReg(CMD_TYPE_STD, "geohome",   0, cmd_geohome);
    osCmdReg(CMD_TYPE_STD, "sethome",   0, cmd_sethome);
    osCmdReg(CMD_TYPE_STD, "status",    0, cmd_status);
    osCmdReg(CMD_TYPE_STD, "simpath",   0, cmd_simpath);
    osCmdReg(CMD_TYPE_STD, "anxiety",  0, cmd_anxiety);
    osCmdReg(CMD_TYPE_STD, "hrsim",    0, cmd_hrsim);
    printf("[CLI] commands registered: feed, gpio, path, pathsave, geohome, sethome, status, simpath, anxiety, hrsim\n");
}
