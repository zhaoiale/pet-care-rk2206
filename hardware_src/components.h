#ifndef __COMPONENTS_H__
#define __COMPONENTS_H__

#include "stdio.h"
#include "stdint.h"
#include "stdbool.h"
#include "stdlib.h"

typedef struct text{
    char name[32];
    int font_size;
    int fc;
    int bc;
}text_t;

typedef struct image{
    uint8_t *img;
    int width;
    int height;
}image_t;

typedef struct lcd_menu{
    image_t img;
    text_t text;
    int base_x;
    int base_y;
    bool is_selected;
    void (*enterFunc)(struct lcd_menu *menu);
    void (*exitFunc)(struct lcd_menu *menu);

}lcd_menu_t;

typedef struct lcd_display_board{
    image_t img;
    text_t text;
    int base_x;
    int base_y;
}lcd_display_board_t;

int lcd_menu_init(void);
int  lcd_menu_show(lcd_menu_t *menus[] , int menu_num);

int lcd_menu_entry(lcd_menu_t *menu);

#endif