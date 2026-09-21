#include "drv_hx711.h"
#include "iot_gpio.h"
#include "iot_errno.h"
#include "los_task.h"
#include <stdio.h>

static int g_zero_offset = 0;       // 去皮偏移量
static float g_cal_factor = 216.3f; // 校准系数 (raw/g), 220g→net=47576, cal=47576/220≈216.3
static bool g_tared = false;       // 是否已执行过去皮

// ~1μs busy-wait at 200MHz
static void hx711_udelay(int us)
{
    for (volatile int i = 0; i < us * 50; i++) { }
}

void hx711_init(void)
{
    IoTGpioInit(HX711_DOUT_PIN);
    IoTGpioInit(HX711_SCK_PIN);
    IoTGpioSetDir(HX711_DOUT_PIN, IOT_GPIO_DIR_IN);   // input
    IoTGpioSetDir(HX711_SCK_PIN, IOT_GPIO_DIR_OUT);   // output
    IoTGpioSetOutputVal(HX711_SCK_PIN, 0);
    // read back DOUT level — should be HIGH (1) when HX711 is converting
    unsigned short dout_level = 0;
    IoTGpioGetInputVal(HX711_DOUT_PIN, &dout_level);
    printf("HX711: init OK, DOUT=PB0 (level=%d) SCK=PB1\n", dout_level);
}

bool hx711_is_ready(void)
{
    unsigned short val = 1;
    IoTGpioGetInputVal(HX711_DOUT_PIN, &val);
    return (val == 0);
}

// send N SCK pulses without reading data
static void hx711_sck_pulse(int n)
{
    for (int i = 0; i < n; i++) {
        IoTGpioSetOutputVal(HX711_SCK_PIN, 1);
        hx711_udelay(1);
        IoTGpioSetOutputVal(HX711_SCK_PIN, 0);
        hx711_udelay(1);
    }
}

// read 24-bit value after DOUT goes LOW (caller must check ready)
// 参考 Arduino/STM32/STC 三方例程：SCK上升→下降→延时→读DOUT
static int hx711_read_bits(void)
{
    int value = 0;
    for (int i = 0; i < 24; i++) {
        IoTGpioSetOutputVal(HX711_SCK_PIN, 1);
        hx711_udelay(1);
        IoTGpioSetOutputVal(HX711_SCK_PIN, 0);
        hx711_udelay(1);
        unsigned short bit = 0;
        IoTGpioGetInputVal(HX711_DOUT_PIN, &bit);
        if (bit) {
            value = (value << 1) | 1;
        } else {
            value = value << 1;
        }
    }
    // 25th pulse: set channel A gain 128, start next conversion
    hx711_sck_pulse(1);
    // 24-bit two's complement → sign-extend to 32-bit
    if (value & 0x800000) {
        value = value - 0x1000000;
    }
    // Reject near-saturation readings (DOUT floating/disconnected → all 1s)
    if (value > 0x700000 || value < -0x700000) {
        return (int)0x80000000;
    }
    return value;
}

static int g_hx711_muted = 0;  // suppress log spam when sensor absent

int hx711_read(void)
{
    int retry;
    for (retry = 0; retry < 3; retry++) {
        int timeout = 20;  // ~20ms per try
        while (!hx711_is_ready()) {
            if (--timeout <= 0) break;
            LOS_Msleep(1);
        }
        if (timeout > 0) {
            g_hx711_muted = 0;  // successful read, unmute
            return hx711_read_bits();
        }
        hx711_sck_pulse(30);
        LOS_Msleep(50);
    }
    static int timeout_count = 0;
    if (!g_hx711_muted) {
        timeout_count++;
        if (timeout_count <= 3) {
            printf("HX711: not connected, skipping\n");
        } else if (timeout_count == 4) {
            printf("HX711: muted (sensor absent), will retry on next read\n");
            g_hx711_muted = 1;
        }
    }
    return (int)0x80000000;
}

void hx711_tare(int samples)
{
    if (samples <= 0) samples = 10;
    long long sum = 0;
    int count = 0;
    for (int i = 0; i < samples; i++) {
        int val = hx711_read();
        if (val != (int)0x80000000) {
            sum += val;
            count++;
        }
        LOS_Msleep(100);  // 100ms between samples (10Hz data rate)
    }
    if (count > 0) {
        g_zero_offset = (int)(sum / count);
        g_tared = true;
        printf("HX711: tare done, offset=%d (from %d samples)\n", g_zero_offset, count);
    }
}

#define HX711_MEDIAN_LEN  5     // 中值滤波窗口（参考Arduino例程）
#define HX711_MEDIAN_IDX  2     // 中值在排序数组中的位置 (0-indexed)

float hx711_get_grams(void)
{
    // auto-tare on first call (assumes empty bowl at boot)
    if (!g_tared) {
        int first = hx711_read();
        if (first == (int)0x80000000) {
            g_tared = true;
            g_zero_offset = 0;  // sentinel: tare deferred until sensor ready
            printf("HX711: absent, tare deferred\n");
        } else {
            hx711_tare(10);
        }
    }

    if (g_hx711_muted) return 0.0f;

    int raw = hx711_read();
    if (raw == (int)0x80000000) return -1.0f;

    // Re-tare on first successful read after deferred tare
    if (g_zero_offset == 0) {
        hx711_tare(10);
        raw = hx711_read();
        if (raw == (int)0x80000000) return -1.0f;
    }

    int net = raw - g_zero_offset;
    if (net < 0) net = -net;  // abs: works regardless of sensor direction
    float grams = (float)net / g_cal_factor;

    // 5-sample median filter (参照Arduino例程的插入排序中值滤波)
    static float buf[HX711_MEDIAN_LEN] = {0};
    static int fill = 0;
    float tmp;

    // 插入排序：从小到大排列
    if (fill == 0) {
        buf[0] = grams;
        fill = 1;
    } else {
        int i;
        for (i = 0; i < fill; i++) {
            if (buf[i] > grams) {
                tmp = grams;
                grams = buf[i];
                buf[i] = tmp;
            }
        }
        if (fill < HX711_MEDIAN_LEN) {
            buf[fill] = grams;
            fill++;
        }
    }

    float result;
    if (fill >= HX711_MEDIAN_LEN) {
        result = buf[HX711_MEDIAN_IDX];  // 取中值
        fill = 0;  // 重置，开始下一组
    } else {
        result = grams;  // buffer未满时用原始值
    }

    // debug every 5th full median result
    static int dbg_cnt = 0;
    if (fill == 0 && ++dbg_cnt >= 3) {
        dbg_cnt = 0;
        printf("HX711 dbg: raw=%d net=%d cal=%.1f grams=%.1f\n",
               raw, net, g_cal_factor, result);
    }
    return result;
}

void hx711_set_calibration(float cal_factor)
{
    g_cal_factor = cal_factor;
    printf("HX711: calibration factor set to %.2f\n", cal_factor);
}
