#include "components.h"
#include "lcd.h"


int lcd_menu_init(void)
{
    return 0;
}


int lcd_menu_draw(lcd_menu_t *menu)
{
    // printf(">>__%s\n",__func__);
    if(menu == NULL) {
        return -1;
    }

    /*先显示图片*/
    lcd_show_picture(menu->base_x, menu->base_y, menu->img.width, menu->img.height, menu->img.img);
    
    /* LCD中英文混合显示*/
    lcd_show_text(menu->base_x,menu->base_y+menu->img.height+3  , menu->text.name, menu->text.fc,
        menu->is_selected?LCD_BROWN: menu->text.bc, menu->text.font_size, 0);
    return 0;
}

int lcd_menu_show(lcd_menu_t *menus[] , int menu_num){

      for(int i = 0;i<menu_num;i++){
        lcd_menu_draw(menus[i]);

    }
}
void lcd_menu_update(lcd_menu_t *menus[] , int menu_num,int  lcd_menu_selected_index){

      for (int i=0;i<menu_num;i++){
        if(i == lcd_menu_selected_index){

            lcd_menu_select(menus[i]);
        }else{
            lcd_menu_unselect(menus[i]);
        
        }
    }
}


int lcd_menu_select(lcd_menu_t *menu){
    menu->is_selected = true;
    return 0;
}
int lcd_menu_unselect(lcd_menu_t *menu){
    menu->is_selected = false;
    return 0;
}

int lcd_menu_entry(lcd_menu_t *menu){
    if(menu == NULL) {
        return -1;
    }
    if(menu->enterFunc != NULL) {
        menu->enterFunc(menu);
    }
    
}

int lcd_db_draw(lcd_display_board_t *db){

    //  printf(">>__%s\n",__func__);
    if(db == NULL) {
        return -1;
    }

    /*先显示图片*/
    lcd_show_picture(db->base_x, db->base_y, db->img.width, db->img.height, db->img.img);

    /* LCD中英文混合显示*/
    lcd_show_text(db->base_x+db->img.width+3,db->base_y+8  , db->text.name, db->text.fc,
        db->text.bc, db->text.font_size, 0);

    return 0;
}

int lcd_db_show(lcd_display_board_t *lcd_dbs[] , int db_num){
    
      for(int i = 0;i<db_num;i++){
        lcd_display_board_t *db = lcd_dbs[i];
        lcd_db_draw(db);

    }
}



