# &desc: "MangoHud settings -- FPS/frametime graph, CPU/GPU/RAM stats, minimal top-left overlay, Shift_R+F12 toggle."

{ ... }:

{
  config.vars.packages.programs.mangohud.settings = {
    # ============================================================
    # Performance metrics
    # ============================================================
    fps = true;
    frame_timing = true;
    frametime = true;

    cpu_stats = true;
    cpu_temp = true;
    cpu_power = true;
    cpu_mhz = true;

    gpu_stats = true;
    gpu_temp = true;
    gpu_power = true;
    gpu_core_clock = true;
    gpu_mem_clock = true;

    ram = true;
    vram = true;
    swap = true;

    # ============================================================
    # Context
    # ============================================================
    gpu_name = true;
    engine_version = true;
    vulkan_driver = true;
    wine = true;
    resolution = true;

    # ============================================================
    # Layout / appearance
    # ============================================================
    position = "top-left";
    background_alpha = 0.4;
    round_corners = 6;
    font_size = 20;
    table_columns = 3;
    background_color = "1a1a1a";
    text_color = "ffffff";
    gpu_color = "2e97cb";
    cpu_color = "2e9762";
    vram_color = "ad64c1";
    ram_color = "c26693";
    frametime_color = "00ff00";

    # ============================================================
    # Behaviour
    # ============================================================
    toggle_hud = "Shift_R+F12";
    toggle_fps_limit = "Shift_R+F1";
    no_display = false;
    log_duration = 30;
  };
}
