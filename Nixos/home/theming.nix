{ config, pkgs, ... }:

{
  xdg.configFile = {
    "Kvantum".source = ../../Themes/Kvantum;
    "qt5ct".source = ../../Themes/QT/qt5ct;
    "qt6ct/style-colors.conf".source = ../../Themes/QT/qt6ct/style-colors.conf;
    "nostripes.qss".source = ../../Themes/Dolphin/nostripes.qss;

    "qt6ct/qt6ct.conf".text = ''
      [Appearance]
      color_scheme_path=${config.home.homeDirectory}/.config/qt6ct/style-colors.conf
      custom_palette=true
      icon_theme=breeze
      standard_dialogs=kde
      style=kvantum-dark

      [Fonts]
      fixed="Sans Serif,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
      general="Sans Serif,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"

      [Interface]
      activate_item_on_single_click=1
      buttonbox_layout=0
      cursor_flash_time=1000
      dialog_buttons_have_icons=1
      double_click_interval=400
      gui_effects=General
      keyboard_scheme=2
      menus_have_icons=true
      show_shortcuts_in_context_menus=true
      stylesheets=${pkgs.qt6Packages.qt6ct}/share/qt6ct/qss/fusion-fixes.qss, ${pkgs.qt6Packages.qt6ct}/share/qt6ct/qss/scrollbar-simple.qss, ${pkgs.qt6Packages.qt6ct}/share/qt6ct/qss/sliders-simple.qss, ${pkgs.qt6Packages.qt6ct}/share/qt6ct/qss/tooltip-simple.qss, ${pkgs.qt6Packages.qt6ct}/share/qt6ct/qss/traynotification-simple.qss, ${config.home.homeDirectory}/.config/nostripes.qss
      toolbutton_style=4
      underline_shortcut=1
      wheel_scroll_lines=3

      [Troubleshooting]
      force_raster_widgets=1
      ignored_applications=@Invalid()
    '';
  };
}