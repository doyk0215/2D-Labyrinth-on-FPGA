`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"
//////////////////////////////////////////////////////////////////////////////////
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME: Han Qi-Ze
//  STUDENT B NAME: Kim Doyeon
//  STUDENT C NAME: Chua Choon Hsiang
//////////////////////////////////////////////////////////////////////////////////

// Integration top: game_ctrl sequences generation/play, and the renderer is
// held off while maze_gen writes the single map; rotation supports the SW0
// snap fallback as well as the smooth mouse/button path.
//   sw[15]  = 90-degree snap fallback (off = smooth rotation)
//   sw[14]  = debug seed (fixed seed, same maze every time)
//   sw[3:0] = CUSTOM size offset X; CUSTOM N is 5 + unsigned X (5..20)
//   sw[4]   = unused
//   btnU/D  = stage navigation in MENU, rotation-rate selection in settings,
//             and pause-menu navigation while paused; btnU pauses during PLAY
//   btnL    = open the settings page from the stage menu
//   btnR    = open the scrollable instruction page from the stage menu
//   btnC    = short release: confirm in MENU / return to MENU elsewhere;
//             hold about 2 seconds: full reset, including menu/mouse/OLED
//   btnD    = regenerate while playing
//   Any of btnU/L/R/D latches the random seed (first press only).
module My_Top_Module #(
    parameter integer SNAP_DEBOUNCE_CYCLES = 1_000_000, // 10 ms at 100 MHz
    parameter integer MENU_DEBOUNCE_CYCLES = 1_000_000, // 10 ms at 100 MHz
    parameter integer POR_CYCLES = 100_000,             // 1 ms at 100 MHz
    parameter integer WIN_HOLD_FRAMES = 180,            // about 3 s at 60 Hz
    parameter integer TIMER_CLK_HZ = 100_000_000,
    parameter START_IN_MENU = 1'b1,
    parameter integer LONG_PRESS_CYCLES = 200_000_000,
    parameter integer LOSE_HOLD_FRAMES = 120,
    parameter integer EASY_TIME_SECONDS = 60,
    parameter integer HARD_TIME_SECONDS = 120,
    parameter integer HUGE_TIME_SECONDS = 180,
    // Item effect durations, per effect (the time bonus is instant).
    parameter integer ITEM_LOW_GRAV_SECONDS = 12,
    parameter integer ITEM_HIGH_GRAV_SECONDS = 12,
    parameter integer ITEM_INVINCIBLE_SECONDS = 12,
    parameter integer ITEM_REVERSE_GRAV_SECONDS = 10,
    parameter integer ITEM_ZERO_GRAV_SECONDS = 10,
    parameter integer ITEM_INVERT_SECONDS = 10,
    parameter integer ITEM_FOG_SECONDS = 10,
    parameter integer ITEM_RESPAWN_SECONDS = 15,
    parameter integer ITEM_TIME_BONUS_SECONDS = 10,
    parameter ITEM_STUB_LOW_ONLY = 1'b0,
    parameter ITEM_ROULETTE_ENABLE = 1'b1,
    parameter integer ITEM_ROULETTE_SPIN_MS = 1500,
    parameter integer ITEM_ROULETTE_HOLD_MS = 1000,
    parameter integer ITEM_BLOCK_ICON_MS = 1000,
    parameter integer FOG_RADIUS_PX = 48,    // fog of war clear radius (Story 9.4)
    // Time limits by N: EASY = N 5, HARD = N 10 (the MEDIUM stage), HUGE = N 15
    // (the HARD stage), XL = N 20; any other custom N gets SECONDS_PER_CELL * N.
    parameter integer XL_TIME_SECONDS = 240,
    parameter integer SECONDS_PER_CELL = 12,
    parameter integer MENU_ERROR_CYCLES = 200_000_000   // invalid CUSTOM size, 2 s
) (
    input  wire       clk,
    input  wire       btnC,
    input  wire       btnU,
    input  wire       btnL,
    input  wire       btnR,
    input  wire       btnD,
    input  wire [15:0] sw,
    output wire [15:0] led,
    output wire [3:0] vga_r,
    output wire [3:0] vga_g,
    output wire [3:0] vga_b,
    output wire       vga_hs,
    output wire       vga_vs,
    output wire [6:0] seg,
    output wire       dp,
    output wire [3:0] an,
    inout  wire       ps2_clk,
    inout  wire       ps2_data,
    output wire       oled_cs,
    output wire       oled_mosi,
    output wire       oled_sclk,
    output wire       oled_dc,
    output wire       oled_res,
    output wire       oled_vbatc,
    output wire       oled_vddc
);

    reg [31:0] por_count = 32'd0;
    reg por_done = 1'b0;
    wire por_reset = !por_done;
    always @(posedge clk) begin
        if (!por_done) begin
            if (por_count >= POR_CYCLES - 1)
                por_done <= 1'b1;
            else
                por_count <= por_count + 1'b1;
        end
    end

    wire rst;
    wire full_reset;
    wire system_reset = por_reset | full_reset;
    wire game_reset_request;
    wire game_ctrl_rst = por_reset | game_reset_request;
    wire [`GAME_STATE_W-1:0] game_state;
    assign rst = system_reset | game_reset_request;

    wire btnU_press, btnD_menu_press, btnC_press, btnL_menu_press, btnR_menu_press;
    button_press_debounce #(.STABLE_CYCLES(MENU_DEBOUNCE_CYCLES)) btnU_menu_i (
        .clk(clk), .rst(system_reset), .level_in(btnU), .press(btnU_press)
    );
    button_press_debounce #(.STABLE_CYCLES(MENU_DEBOUNCE_CYCLES)) btnD_menu_i (
        .clk(clk), .rst(system_reset), .level_in(btnD), .press(btnD_menu_press)
    );
    centre_button #(
        .DEBOUNCE_CYCLES(MENU_DEBOUNCE_CYCLES),
        .LONG_PRESS_CYCLES(LONG_PRESS_CYCLES)
    ) btnC_menu_i (
        .clk(clk), .por_reset(por_reset), .level_in(btnC),
        .short_press(btnC_press), .full_reset(full_reset)
    );
    button_press_debounce #(.STABLE_CYCLES(MENU_DEBOUNCE_CYCLES)) btnL_menu_i (
        .clk(clk), .rst(system_reset), .level_in(btnL), .press(btnL_menu_press)
    );
    button_press_debounce #(.STABLE_CYCLES(MENU_DEBOUNCE_CYCLES)) btnR_menu_i (
        .clk(clk), .rst(system_reset), .level_in(btnR), .press(btnR_menu_press)
    );

    wire start_game;
    wire [9:0] game_cfg;
    wire [9:0] active_game_cfg;
    wire menu_error;
    // CUSTOM size offset X from SW3..SW0, synchronised like the snap switch.
    (* ASYNC_REG = "TRUE" *) reg [3:0] size_sw_meta = 4'd0;
    (* ASYNC_REG = "TRUE" *) reg [3:0] size_sw_sync = 4'd0;
    always @(posedge clk) begin
        size_sw_meta <= sw[3:0];
        size_sw_sync <= size_sw_meta;
    end
    wire [4:0] custom_n = 5'd5 + {1'b0, size_sw_sync};
    wire [511:0] status_text;
    wire [511:0] menu_page_text;
    wire settings_page;
    reg instructions_active = 1'b0;
    reg [2:0] instructions_scroll = 3'd0;
    wire menu_controls_active;
    wire menu_bg_visible;
    wire menu_bg_seed_capture;
    wire menu_bg_gen_start;
    wire gen_busy;
    wire gen_done;
    reg menu_bg_ready = 1'b0;
    reg [1:0] menu_bg_gen_state = 2'd0;
    reg menu_settings_page_d = 1'b0;
    reg menu_instructions_active_d = 1'b0;
    wire [7:0] elapsed_minutes_bcd;
    wire [7:0] elapsed_seconds_bcd;
    reg [11:0] levels_completed_bcd = 12'h000;
    reg [47:0] stage_high_scores_bcd = 48'h000000000000;
    wire time_up;
    wire time_up_game_ctrl;
    wire menu_active = (game_state == `ST_MENU);
    reg [1:0] pause_selection = 2'd0;
    wire pause_active = (game_state == `ST_PAUSED);
    wire pause_resume_request = btnC_press && pause_active &&
                                (pause_selection == 2'd0);
    wire pause_restart_request = btnC_press && pause_active &&
                                 (pause_selection == 2'd1);
    wire pause_menu_request = btnC_press && pause_active &&
                              (pause_selection == 2'd2);
    assign game_reset_request = (btnC_press && !menu_active && !pause_active) ||
                                pause_menu_request;

    // Resume is selected whenever the pause screen opens. Up/down wrap through
    // RESUME, RESTART, and MENU.
    always @(posedge clk) begin
        if (system_reset || game_reset_request) begin
            pause_selection <= 2'd0;
        end else if ((game_state == `ST_PLAY) && btnU_press) begin
            pause_selection <= 2'd0;
        end else if (pause_active) begin
            if (btnU_press && !btnD_menu_press)
                pause_selection <= (pause_selection == 2'd0) ? 2'd2 :
                                   pause_selection - 2'd1;
            else if (btnD_menu_press && !btnU_press)
                pause_selection <= (pause_selection == 2'd2) ? 2'd0 :
                                   pause_selection + 2'd1;
        end
    end

    assign menu_controls_active = menu_active && menu_bg_ready && !instructions_active;

    // Generate a random N=20 backdrop on menu entry and when returning from a
    // submenu. The maze remains centered and fixed while each page is shown.
    localparam [1:0] MENU_BG_IDLE = 2'd0, MENU_BG_CAPTURE = 2'd1,
                     MENU_BG_START = 2'd2, MENU_BG_WAIT = 2'd3;
    assign menu_bg_seed_capture = menu_active && (menu_bg_gen_state == MENU_BG_CAPTURE);
    assign menu_bg_gen_start = menu_active && (menu_bg_gen_state == MENU_BG_START);
    always @(posedge clk) begin
        if (system_reset) begin
            menu_bg_gen_state <= MENU_BG_IDLE;
            menu_bg_ready <= 1'b0;
            menu_settings_page_d <= 1'b0;
            menu_instructions_active_d <= 1'b0;
        end else if (!menu_active) begin
            menu_bg_gen_state <= MENU_BG_IDLE;
            menu_bg_ready <= 1'b0;
            menu_settings_page_d <= 1'b0;
            menu_instructions_active_d <= 1'b0;
        end else if (menu_bg_ready &&
                     ((menu_settings_page_d && !settings_page) ||
                      (menu_instructions_active_d && !instructions_active))) begin
            // Back from Settings/Instructions: capture a fresh seed and
            // replace the backdrop before enabling menu controls again.
            menu_bg_ready <= 1'b0;
            menu_bg_gen_state <= MENU_BG_IDLE;
            menu_settings_page_d <= settings_page;
            menu_instructions_active_d <= instructions_active;
        end else begin
            menu_settings_page_d <= settings_page;
            menu_instructions_active_d <= instructions_active;
            case (menu_bg_gen_state)
                MENU_BG_IDLE: if (!menu_bg_ready && !gen_busy)
                    menu_bg_gen_state <= MENU_BG_CAPTURE;
                MENU_BG_CAPTURE: menu_bg_gen_state <= MENU_BG_START;
                MENU_BG_START: menu_bg_gen_state <= MENU_BG_WAIT;
                MENU_BG_WAIT: if (gen_done) begin
                    menu_bg_ready <= 1'b1;
                    menu_bg_gen_state <= MENU_BG_IDLE;
                end
                default: menu_bg_gen_state <= MENU_BG_IDLE;
            endcase
        end
    end

    always @(posedge clk) begin
        if (system_reset || game_reset_request || !menu_active) begin
            instructions_active <= 1'b0;
            instructions_scroll <= 3'd0;
        end else if (menu_bg_ready && !settings_page) begin
            if (instructions_active) begin
                if (btnC_press)
                    instructions_active <= 1'b0;
                else if (btnU_press && !btnD_menu_press && instructions_scroll != 0)
                    instructions_scroll <= instructions_scroll - 1'b1;
                else if (btnD_menu_press && !btnU_press && instructions_scroll < 3)
                    instructions_scroll <= instructions_scroll + 1'b1;
            end else if (btnR_menu_press && !menu_error) begin
                instructions_active <= 1'b1;
                instructions_scroll <= 3'd0;
            end
        end
    end

    menu_ctrl #(.ERROR_HOLD_CYCLES(MENU_ERROR_CYCLES)) menu_ctrl_i (
        .clk           (clk),
        .rst           (system_reset),
        .return_to_menu(game_reset_request),
        .menu_active   (menu_controls_active),
        .btn_up        (btnU_press && !instructions_active),
        .btn_down      (btnD_menu_press && !instructions_active),
        .btn_confirm   (btnC_press && !instructions_active),
        .btn_settings  (btnL_menu_press && !instructions_active),
        .custom_n      (custom_n),
        .stage_high_scores_bcd(stage_high_scores_bcd),
        .start_game    (start_game),
        .game_cfg      (game_cfg),
        .status_text   (menu_page_text),
        .selected_stage(),
        .settings_page(settings_page),
        .error_active  (menu_error)
    );
    wire ce_pix;
    wire frame_tick;
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    wire active_video;
    wire timing_hsync;
    wire timing_vsync;

    wire [`MAP_ADDR_W-1:0] maze_raddr_p;
    wire maze_rdata_p;
    wire [`MAP_ADDR_W-1:0] maze_raddr_r;
    wire maze_rdata_r;

    wire        maze_we;
    wire [`MAP_ADDR_W-1:0] maze_waddr;
    wire        maze_wdata;
    wire [`COORD_W-1:0] start_col;
    wire [`COORD_W-1:0] start_row;
    wire [`COORD_W-1:0] goal_col;
    wire [`COORD_W-1:0] goal_row;
    wire [8*`COORD_W-1:0] box_cols;    // up to eight item boxes (N=20)
    wire [8*`COORD_W-1:0] box_rows;
    wire [7:0]  box_valid;
    wire [7:0] box_visible;
    wire [`ITEM_EFFECT_W-1:0] item_effect;
    wire [6:0] item_seconds;
    wire item_pickup;
    wire [2:0] item_pickup_index;
    wire [`ITEM_EFFECT_W-1:0] item_pickup_effect;
    wire item_debuff_blocked;
    wire item_time_bonus;
    wire item_pending_valid;
    wire [`ITEM_EFFECT_W-1:0] item_pending_effect;
    wire roulette_busy,roulette_commit,roulette_returning;
    wire [3:0] roulette_visual;
    reg oled_display_frame=0;
    reg [3:0] oled_display_visual=0;
    wire [31:0] seed;
    wire        gen_start;
    wire        seed_capture;
    wire        game_gen_start;
    wire        game_seed_capture;
    wire [`N_CELLS_W-1:0] gen_n_cells;
    wire        phys_init;
    wire        phys_en;
    wire        in_goal;
    wire        render_enable;
    reg         render_enable_d = 1'b0;
    reg         menu_bg_visible_d = 1'b0;
    wire        maze_pixel_visible;
    reg         active_video_d = 1'b0;

    wire mouse_left;
    wire mouse_right;
    wire mouse_middle;
    wire mouse_event;
    wire [11:0] mouse_x;
    wire [11:0] mouse_y;
    wire [3:0] mouse_z;
    wire timer_player_action;
    reg mouse_connected = 1'b0;
    reg [25:0] mouse_event_timer = 26'd0;
    wire signed [1:0] rot_cmd;
    wire signed [1:0] angle_rot_cmd;
    wire rot_held;
    wire snap_left, snap_right;
    wire btnL_snap, btnR_snap;
    (* ASYNC_REG = "TRUE" *) reg [1:0] snap_sw_sync = 2'b00;
    wire snap_mode = snap_sw_sync[1];
    wire [11:0] angle;
    wire signed [15:0] sin_q;
    wire signed [15:0] cos_q;
    wire signed [15:0] sin_frame;   // render's per-frame snapshot of sin_q/cos_q
    wire signed [15:0] cos_frame;

    // MouseCtl wraps Ps2Interface, which drives the PS/2 lines open-drain
    // (low or high impedance). mouse_connected only means "a packet arrived
    // in the last 500 ms" and drives a debug LED; it does not gate rotation,
    // because a button held still sends no packets (see input_mux).
    MouseCtl mouse_controller (
        .clk       (clk),
        .rst       (rst),
        .xpos      (mouse_x),
        .ypos      (mouse_y),
        .zpos      (mouse_z),
        .left      (mouse_left),
        .middle    (mouse_middle),
        .right     (mouse_right),
        .new_event (mouse_event),
        .value     (12'd0),
        .setx      (1'b0),
        .sety      (1'b0),
        .setmax_x  (1'b0),
        .setmax_y  (1'b0),
        .ps2_clk   (ps2_clk),
        .ps2_data  (ps2_data)
    );

    always @(posedge clk) begin
        if (rst) begin
            mouse_connected  <= 1'b0;
            mouse_event_timer <= 26'd0;
        end else if (mouse_event) begin
            mouse_connected  <= 1'b1;
            mouse_event_timer <= 26'd0;
        end else if (mouse_connected) begin
            if (mouse_event_timer >= 26'd49_999_999) begin
                mouse_connected  <= 1'b0;
                mouse_event_timer <= 26'd0;
            end else begin
                mouse_event_timer <= mouse_event_timer + 1'b1;
            end
        end
    end

    // Synchronize board-button fallback controls into the 100 MHz domain.
    (* ASYNC_REG = "TRUE" *) reg [1:0] btnL_sync = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [1:0] btnR_sync = 2'b00;
    always @(posedge clk) begin
        if (system_reset) begin
            btnL_sync <= 2'b00;
            btnR_sync <= 2'b00;
        end else begin
            btnL_sync <= {btnL_sync[0], btnL};
            btnR_sync <= {btnR_sync[0], btnR};
        end
    end

    input_mux input_mux_i (
        .mouse_left      (mouse_left),
        .mouse_right     (mouse_right),
        .btn_left        (btnL_sync[1]),
        .btn_right       (btnR_sync[1]),
        .rot_cmd         (rot_cmd)
    );
    // Debounce board buttons only for the one-shot fallback. The original
    // synchronized button levels still drive the unchanged smooth path.
    snap_button_debounce #(.STABLE_CYCLES(SNAP_DEBOUNCE_CYCLES)) snap_l_i (
        .clk(clk), .rst(rst), .level_in(btnL_sync[1]), .level_out(btnL_snap)
    );
    snap_button_debounce #(.STABLE_CYCLES(SNAP_DEBOUNCE_CYCLES)) snap_r_i (
        .clk(clk), .rst(rst), .level_in(btnR_sync[1]), .level_out(btnR_snap)
    );
    // A held PS/2 button remains asserted even when packet activity times out.
    // Match input_mux: mouse and board buttons may both drive snap mode.
    assign snap_left = mouse_left | btnL_snap;
    assign snap_right = mouse_right | btnR_snap;
    assign rot_held = snap_left | snap_right;
    // Start the countdown only after a rotation input (mouse left/right click
    // or board BTNL/BTNR) and a visible maze pixel. Mouse motion does not count.
    assign timer_player_action = rot_held;
    wire signed [1:0] rot_cmd_normal = (menu_active || (game_state == `ST_WIN) ||
                           (game_state == `ST_LOSE) || pause_active) ? 2'sd0 :
                           !snap_mode ? rot_cmd :
                           (snap_left && !snap_right) ? -2'sd1 :
                           (snap_right && !snap_left) ? 2'sd1 : 2'sd0;
    // Invert controls (Story 9.4): swap left and right for the mouse and the
    // buttons, smooth and snap alike. A snap press held while the effect
    // starts or ends changes direction, so angle_accumulator cancels it.
    assign angle_rot_cmd = (item_effect == `ITEM_INVERT) ? -rot_cmd_normal : rot_cmd_normal;
    always @(posedge clk) begin
        if (system_reset) snap_sw_sync <= 2'b00;
        else snap_sw_sync <= {snap_sw_sync[0], sw[15]};
    end

    // Synchronize BTND and convert its rising edge into a one-cycle request.
    (* ASYNC_REG = "TRUE" *)
    reg [2:0] btnD_s = 3'b000;
    always @(posedge clk) begin
        if (system_reset) btnD_s <= 3'b000;
        else btnD_s <= {btnD_s[1:0], btnD};
    end
    wire regen_request = btnD_s[1] & ~btnD_s[2];
    // Legacy auto-start builds use the same CUSTOM mapping: N = 5 + SW3..SW0.
    wire [`N_CELLS_W-1:0] legacy_n_cells = custom_n;
    wire [`N_CELLS_W-1:0] n_cells = START_IN_MENU ? active_game_cfg[4:0] : legacy_n_cells;

    // A normal in-game BTND regeneration reuses the latched seed and keeps
    // the current timer running through maze generation. Pause-menu Restart
    // deliberately leaves this clear, preserving its original fresh-run reset.
    reg preserve_timer = 1'b0;
    always @(posedge clk) begin
        if (system_reset || game_reset_request || pause_restart_request ||
            game_state == `ST_MENU || game_state == `ST_PAUSED ||
            game_state == `ST_WIN || game_state == `ST_LOSE) begin
            preserve_timer <= 1'b0;
        end else if ((game_state == `ST_PLAY) && regen_request) begin
            preserve_timer <= 1'b1;
        end else if ((game_state == `ST_PLAY) && preserve_timer && phys_init) begin
            preserve_timer <= 1'b0;
        end
    end

    // Keep maps visible behind game-state panels, and enable maze reads for
    // the generated menu backdrop once it is ready.
    assign menu_bg_visible = menu_active && menu_bg_ready;
    assign gen_start = game_gen_start | menu_bg_gen_start;
    assign seed_capture = game_seed_capture | menu_bg_seed_capture;
    assign gen_n_cells = menu_bg_gen_start || (menu_bg_gen_state != MENU_BG_IDLE && menu_active)
                       ? 5'd20 : n_cells;
    assign render_enable = (game_state == `ST_PLAY) || (game_state == `ST_WIN) ||
                           (game_state == `ST_LOSE) || pause_active || menu_bg_visible;
    wire timer_display_active = render_enable_d && maze_pixel_visible;

    game_ctrl #(
        .START_IN_MENU(START_IN_MENU),
        .WIN_HOLD_FRAMES(WIN_HOLD_FRAMES),
        .LOSE_HOLD_FRAMES(LOSE_HOLD_FRAMES)
    ) game_ctrl_i (
        .clk          (clk),
        .rst          (game_ctrl_rst),
        .full_reset   (full_reset),
        .frame_tick   (frame_tick),
        .start_game   (start_game),
        .game_cfg     (game_cfg),
        .regen_button (regen_request),
        .pause_button (btnU_press),
        .pause_resume (pause_resume_request),
        .pause_restart(pause_restart_request),
        .gen_busy     (gen_busy),
        .gen_done     (gen_done),
        .in_goal      (in_goal),
        .time_up      (time_up_game_ctrl),
        .game_state   (game_state),
        .gen_start    (game_gen_start),
        .seed_capture (game_seed_capture),
        .phys_init    (phys_init),
        .active_game_cfg(active_game_cfg),
        .phys_en      (phys_en)
    );

    // Count each completed maze once on the PLAY-to-WIN frame transition.
    // Timeout, BTNC-to-menu, and pause-menu Restart clear the run count;
    // ordinary BTND regeneration preserves it. Saturate at 999.
    function [11:0] increment_levels_bcd;
        input [11:0] value;
        begin
            if (value >= 12'h999)
                increment_levels_bcd = 12'h999;
            else if (value[3:0] != 4'd9)
                increment_levels_bcd = {value[11:4], value[3:0] + 4'd1};
            else if (value[7:4] != 4'd9)
                increment_levels_bcd = {value[11:8], value[7:4] + 4'd1, 4'd0};
            else
                increment_levels_bcd = {value[11:8] + 4'd1, 8'h00};
        end
    endfunction
    wire [11:0] next_levels_completed_bcd = increment_levels_bcd(levels_completed_bcd);

    always @(posedge clk) begin
        if (system_reset || game_reset_request || pause_restart_request ||
            ((game_state == `ST_PLAY) && time_up)) begin
            levels_completed_bcd <= 12'h000;
        end else if ((game_state == `ST_PLAY) && frame_tick && in_goal) begin
            levels_completed_bcd <= next_levels_completed_bcd;
        end
    end

    // Keep independent best completed-level counts for Easy, Medium, Hard,
    // and EPIC; CUSTOM games (cfg bit 9) never update them.
    // Ordinary gameplay resets preserve these records.
    always @(posedge clk) begin
        if (por_reset) begin
            stage_high_scores_bcd <= 48'h000000000000;
        end else if (!active_game_cfg[9] && !btnC_press && !btnD_menu_press &&
                     !((game_state == `ST_PLAY) && (regen_request || time_up)) &&
                     (game_state == `ST_PLAY) && frame_tick && in_goal) begin
            case (active_game_cfg[4:0])
                5'd5: if (next_levels_completed_bcd > stage_high_scores_bcd[11:0])
                    stage_high_scores_bcd[11:0] <= next_levels_completed_bcd;
                5'd10: if (next_levels_completed_bcd > stage_high_scores_bcd[23:12])
                    stage_high_scores_bcd[23:12] <= next_levels_completed_bcd;
                5'd15: if (next_levels_completed_bcd > stage_high_scores_bcd[35:24])
                    stage_high_scores_bcd[35:24] <= next_levels_completed_bcd;
                5'd20: if (next_levels_completed_bcd > stage_high_scores_bcd[47:36])
                    stage_high_scores_bcd[47:36] <= next_levels_completed_bcd;
                default: begin end
            endcase
        end
    end

    game_timer #(.CLK_HZ(TIMER_CLK_HZ),
        .EASY_SECONDS(EASY_TIME_SECONDS), .HARD_SECONDS(HARD_TIME_SECONDS),
        .HUGE_SECONDS(HUGE_TIME_SECONDS), .XL_SECONDS(XL_TIME_SECONDS),
        .SECONDS_PER_CELL(SECONDS_PER_CELL),
        .BONUS_SECONDS(ITEM_TIME_BONUS_SECONDS)) elapsed_timer_i (
        .clk(clk),
        .rst(rst),
        .preserve_time(preserve_timer),
        .maze_pixel_visible(timer_display_active),
        .player_action(timer_player_action),
        .time_bonus_pulse(item_time_bonus),
        .game_state(game_state),
        .phys_init(phys_init),
        .n_cells(n_cells),
        .time_up(time_up),
        .time_up_game_ctrl(time_up_game_ctrl),
        .elapsed_minutes_bcd(elapsed_minutes_bcd),
        .elapsed_seconds_bcd(elapsed_seconds_bcd)
    );

    seven_seg_timer #(.CLK_HZ(TIMER_CLK_HZ)) timer_7seg_i (
        .clk(clk), .rst(rst),
        .enable((game_state == `ST_PLAY) || (game_state == `ST_WIN) ||
                (game_state == `ST_LOSE) || pause_active),
        .minutes_bcd(elapsed_minutes_bcd), .seconds_bcd(elapsed_seconds_bcd),
        .seg(seg), .dp(dp), .an(an)
    );

    oled_status_text oled_status_i (
        .menu_text(menu_page_text),
        .instructions_active(instructions_active),
        .instructions_scroll(instructions_scroll),
        .game_state(game_state),
        .active_game_cfg(active_game_cfg),
        .elapsed_minutes_bcd(elapsed_minutes_bcd),
        .elapsed_seconds_bcd(elapsed_seconds_bcd),
        .levels_completed_bcd(levels_completed_bcd),
        .pause_selection(pause_selection),
        .active_effect(item_effect), .effect_seconds(item_seconds),
        .status_text(status_text)
    );

    // Align the display mask with render's one-cycle pixel pipeline.
    always @(posedge clk) begin
        if (rst) begin
            render_enable_d <= 1'b0;
            menu_bg_visible_d <= 1'b0;
            active_video_d  <= 1'b0;
        end else begin
            render_enable_d <= render_enable;
            menu_bg_visible_d <= menu_bg_visible;
            active_video_d  <= active_video;
        end
    end

    reg gen_done_seen = 1'b0;
    always @(posedge clk) begin
        if (rst)
            gen_done_seen <= 1'b0;
        else if (gen_done)
            gen_done_seen <= 1'b1;
    end

    vga_timing timing_i (
        .clk          (clk),
        .rst          (rst),
        .ce_pix       (ce_pix),
        .frame_tick   (frame_tick),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .active_video (active_video),
        .hsync        (timing_hsync),
        .vsync        (timing_vsync)
    );

    angle_accumulator angle_i (
        .clk        (clk),
        // Menu-driven games start each freshly generated maze at canonical
        // orientation, including automatic replay after WIN. Preserve the
        // legacy auto-start path, where rotation may be held during GENERATE.
        .rst        (rst | (START_IN_MENU && phys_init)),
        .frame_tick (frame_tick),
        .rot_cmd    (angle_rot_cmd),
        .rot_speed_sel (active_game_cfg[8:7]),
        // LOSE discards queued snap releases as well as smooth commands.
        .snap_mode  (snap_mode && (game_state != `ST_LOSE)),
        .rot_held   (rot_held),
        .angle      (angle)
    );

    sincos_rom trig_i (
        .clk   (clk),
        .angle (angle),
        .sin_q (sin_q),
        .cos_q (cos_q)
    );

    seed_source seed_i (
        .clk         (clk),
        .rst         (rst),
        .debug_fixed (menu_active ? 1'b0 : sw[14]),
        .latch_en    (seed_capture),
        .seed        (seed)
    );

    maze_gen gen_i (
        .clk       (clk),
        .rst       (rst),
        .gen_start (gen_start),
        .n_cells   (gen_n_cells),
        .seed      (seed),
        .gen_busy  (gen_busy),
        .gen_done  (gen_done),
        .we        (maze_we),
        .waddr     (maze_waddr),
        .wdata     (maze_wdata),
        .start_col (start_col),
        .start_row (start_row),
        .goal_col  (goal_col),
        .goal_row  (goal_row),
        .box_cols  (box_cols),
        .box_rows  (box_rows),
        .box_valid (box_valid)
    );

    // maze_gen is the sole writer; ball_physics reads walls through the
    // physics port (Story 3.2) and render through the render port.
    maze_ram maze_ram_i (
        .clk     (clk),
        .we      (maze_we),
        .waddr   (maze_waddr),
        .wdata   (maze_wdata),
        .ren_r   (render_enable),
        .raddr_p (maze_raddr_p),
        .rdata_p (maze_rdata_p),
        .raddr_r (maze_raddr_r),
        .rdata_r (maze_rdata_r)
    );

    // Ball (Stories 3.1, 3.2). ball_physics moves the ball once per frame and
    // bounces it off walls with the stage's restitution; ball_overlay turns its
    // maze position into a screen position and draws the disc.
    // game_ctrl (Story 1.4) places the ball on the red start tile (the
    // bottom-right cell) when PLAY begins (phys_init) and enables gravity
    // only in PLAY (phys_en).
    wire signed [17:0] ball_x, ball_y;
    wire signed [11:0] ball_vx, ball_vy;
    wire        phys_done;
    wire signed [10:0] ball_sx, ball_sy;
    wire        ball_on;
    wire        fog_clear;              // inside the fog circle (Story 9.4)

    ball_physics ball_i (
        .clk        (clk),
        .rst        (rst),
        .frame_tick (frame_tick),
        .phys_init  (phys_init),
        .phys_en    (phys_en),
        .spawn_col  (start_col),
        .spawn_row  (start_row),
        .goal_col   (goal_col),
        .goal_row   (goal_row),
        .n_cells    (n_cells),
        .sin_q      (sin_q),
        .cos_q      (cos_q),
        .effect_code (item_effect),
        .restitution_sel (active_game_cfg[6:5]),
        .maze_raddr (maze_raddr_p),
        .maze_rdata (maze_rdata_p),
        .ball_x     (ball_x),
        .ball_y     (ball_y),
        .vel_x      (ball_vx),
        .vel_y      (ball_vy),
        .phys_done  (phys_done),
        .in_goal    (in_goal)
    );

    // Item coordinates share physics' stage-centred Q9.8 frame. The pickup
    // commits after physics and is visible to gravity on the following frame.
    item_ctrl #(.CLK_HZ(TIMER_CLK_HZ),
        .LOW_GRAV_SECONDS(ITEM_LOW_GRAV_SECONDS), .HIGH_GRAV_SECONDS(ITEM_HIGH_GRAV_SECONDS),
        .INVINCIBLE_SECONDS(ITEM_INVINCIBLE_SECONDS),
        .REVERSE_GRAV_SECONDS(ITEM_REVERSE_GRAV_SECONDS),
        .ZERO_GRAV_SECONDS(ITEM_ZERO_GRAV_SECONDS), .INVERT_SECONDS(ITEM_INVERT_SECONDS),
        .FOG_SECONDS(ITEM_FOG_SECONDS),
        .RESPAWN_SECONDS(ITEM_RESPAWN_SECONDS), .STUB_LOW_ONLY(ITEM_STUB_LOW_ONLY),
        .DEFER_EFFECT(ITEM_ROULETTE_ENABLE)) item_i (
        .clk(clk), .rst(rst), .game_state(game_state), .phys_init(phys_init),
        .phys_done(phys_done), .n_cells(n_cells), .ball_x(ball_x), .ball_y(ball_y),
        .box_cols(box_cols), .box_rows(box_rows), .box_valid(box_valid), .seed(seed),
        .roulette_busy(roulette_busy), .roulette_commit(roulette_commit),
        .box_visible(box_visible), .active_effect(item_effect), .effect_seconds(item_seconds),
        .pickup_pulse(item_pickup), .pickup_index(item_pickup_index),
        .pickup_effect(item_pickup_effect), .debuff_blocked(item_debuff_blocked),
        .time_bonus_pulse(item_time_bonus), .pending_valid(item_pending_valid),
        .pending_effect(item_pending_effect)
    );

    item_roulette #(.CLK_HZ(TIMER_CLK_HZ),.SPIN_MS(ITEM_ROULETTE_SPIN_MS),
        .HOLD_MS(ITEM_ROULETTE_HOLD_MS),.BLOCK_MS(ITEM_BLOCK_ICON_MS)) roulette_i (
        .clk(clk),.rst(rst || !ITEM_ROULETTE_ENABLE),.phys_init(phys_init),.game_state(game_state),
        .pickup_pulse(item_pickup),.pickup_index(item_pickup_index),.pickup_effect(item_pickup_effect),
        .debuff_blocked(item_debuff_blocked),.display_frame(oled_display_frame),
        .display_visual(oled_display_visual),.busy(roulette_busy),.visual(roulette_visual),
        .commit(roulette_commit),.returning(roulette_returning));

    // Camera (Story 7.2): follows the ball on stages too large for the
    // screen, the map centre otherwise. render centres the view on it and
    // ball_overlay draws the ball relative to it (Story 7.3); both see the
    // same value, which changes only in vertical blanking.
    wire signed [17:0] cam_x, cam_y;
    wire        cam_done;
    camera camera_i (
        .clk       (clk),
        .rst       (rst),
        .phys_init (phys_init),
        .phys_done (phys_done),
        .n_cells   (n_cells),
        .ball_x    (ball_x),
        .ball_y    (ball_y),
        .cam_x     (cam_x),
        .cam_y     (cam_y),
        .cam_done  (cam_done)
    );

    ball_overlay #(.FOG_RADIUS(FOG_RADIUS_PX)) ball_ov_i (
        .clk          (clk),
        .rst          (rst),
        .start        (cam_done),   // after the camera moves for this frame
        .ball_x       (ball_x),
        .ball_y       (ball_y),
        .cam_x        (cam_x),
        .cam_y        (cam_y),
        .sin_q        (sin_frame),  // registered snapshot keeps the trig ROM off the DSP input path
        .cos_q        (cos_frame),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .active_video (active_video),
        .ball_sx      (ball_sx),
        .ball_sy      (ball_sy),
        .ball_on      (ball_on),
        .fog_clear    (fog_clear)
    );

    wire [3:0] render_r;
    wire [3:0] render_g;
    wire [3:0] render_b;
    wire [`N_CELLS_W-1:0] render_n_cells = menu_bg_visible ? 5'd20 : n_cells;
    wire signed [17:0] render_cam_x = menu_bg_visible ? 18'sd0 : cam_x;
    wire signed [17:0] render_cam_y = menu_bg_visible ? 18'sd0 : cam_y;
    wire signed [15:0] render_sin_q = menu_bg_visible ? 16'sd0 : sin_q;
    wire signed [15:0] render_cos_q = menu_bg_visible ? 16'sd16923 : cos_q;
    // Tile 41 is just off the N = 20 backdrop, so it hides start and goal.
    wire [`COORD_W-1:0] render_start_col = menu_bg_visible ? 6'd41 : start_col;
    wire [`COORD_W-1:0] render_start_row = menu_bg_visible ? 6'd41 : start_row;
    wire [`COORD_W-1:0] render_goal_col = menu_bg_visible ? 6'd41 : goal_col;
    wire [`COORD_W-1:0] render_goal_row = menu_bg_visible ? 6'd41 : goal_row;

    render render_i (
        .clk          (clk),
        .rst          (rst),
        .ce_pix       (ce_pix),
        .frame_tick   (frame_tick),
        .game_state   (game_state),
        .n_cells      (render_n_cells),
        .cam_x        (render_cam_x),
        .cam_y        (render_cam_y),
        .time_min_bcd (elapsed_minutes_bcd),
        .time_sec_bcd (elapsed_seconds_bcd),
        .angle        (angle),
        .sin_q        (render_sin_q),
        .cos_q        (render_cos_q),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .active_video (active_video),
        .hsync_in     (timing_hsync),
        .vsync_in     (timing_vsync),
        .maze_raddr   (maze_raddr_r),
        .maze_rdata   (maze_rdata_r),
        .start_col    (render_start_col),
        .start_row    (render_start_row),
        .goal_col     (render_goal_col),
        .goal_row     (render_goal_row),
        .box_cols     (box_cols),
        .box_rows     (box_rows),
        .box_valid    (menu_bg_visible ? 8'd0 : box_valid),
        .box_visible  (menu_bg_visible ? 8'd0 : box_visible), // Story 9.2 pickup/respawn visibility
        .ball_on      (menu_bg_visible ? 1'b0 : ball_on),
        .fog_en       (menu_bg_visible ? 1'b0 : (item_effect == `ITEM_FOG)),
        .fog_clear    (fog_clear),
        .vga_r        (render_r),
        .vga_g        (render_g),
        .vga_b        (render_b),
        .vga_hs       (vga_hs),
        .vga_vs       (vga_vs),
        .maze_pixel_visible(maze_pixel_visible),
        .sin_snap     (sin_frame),
        .cos_snap     (cos_frame)
    );

    wire timer_warning_active, timer_flash_red;
    wire warning_edge_glow;
    wire [3:0] warning_edge_strength;
    timer_warning_overlay timer_warning_i (
        .clk(clk), .rst(rst), .frame_tick(frame_tick),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .active_video(active_video),
        .game_state(game_state), .minutes_bcd(elapsed_minutes_bcd),
        .seconds_bcd(elapsed_seconds_bcd), .warning_active(timer_warning_active),
        .timer_flash_red(timer_flash_red), .edge_glow(warning_edge_glow),
        .edge_strength(warning_edge_strength)
    );

    wire hud_panel, hud_accent, hud_text, hud_timer_line, hud_timer_red;
    wire hud_item_line, hud_debuff_line, hud_bonus_line;
    game_status_hud #(.CLK_HZ(TIMER_CLK_HZ),
        .BONUS_SECONDS(ITEM_TIME_BONUS_SECONDS)) hud_i (
        .clk(clk), .rst(rst), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .frame_tick(frame_tick), .phys_init(phys_init), .time_bonus_pulse(item_time_bonus),
        .active_video(active_video), .game_state(game_state),
        .n_cells(n_cells),
        .minutes_bcd(elapsed_minutes_bcd), .seconds_bcd(elapsed_seconds_bcd),
        .warning_active(timer_warning_active), .timer_flash_red(timer_flash_red),
        .active_effect(item_effect), .effect_seconds(item_seconds),
        .panel_on(hud_panel), .accent_on(hud_accent), .text_on(hud_text),
        .timer_line(hud_timer_line), .timer_red(hud_timer_red),
        .item_line(hud_item_line), .debuff_line(hud_debuff_line), .bonus_line(hud_bonus_line)
    );
    wire [11:0] hud_rgb = !hud_text ? (hud_accent ? 12'h0af : 12'h013) :
                          hud_timer_line ? (hud_timer_red ? 12'hf00 : 12'hfff) :
                          !hud_item_line ? 12'hfff :
                          hud_bonus_line ? 12'h4f4 :
                          hud_debuff_line ? 12'hf82 : 12'h4f4;

    // The huge background stays in RAM while only the menu overlay mode changes.
    wire [1:0] monitor_menu_mode = instructions_active ? 2'd2 :
                                   settings_page ? 2'd1 : 2'd0;
    wire menu_panel, menu_accent, menu_text;
    monitor_menu_overlay menu_overlay_i (
        .clk(clk), .rst(rst), .pixel_x(pixel_x), .pixel_y(pixel_y),
        .active_video(active_video), .mode(monitor_menu_mode),
        .panel_on(menu_panel), .accent_on(menu_accent), .text_on(menu_text)
    );
    wire [11:0] menu_rgb = menu_text ? 12'hfff : menu_accent ? 12'h0cf : 12'h012;
    wire [11:0] render_rgb = {render_r, render_g, render_b};
    wire [11:0] composed_rgb = menu_bg_visible_d ?
                                (menu_panel || menu_accent ? menu_rgb : render_rgb) :
                                (hud_panel ? hud_rgb : render_rgb);

    // Blend a narrow red vignette over the outer 16 pixels. Red is raised and
    // green/blue are only reduced slightly, preserving maze detail at maximum.
    wire [3:0] edge_red_add = {1'b0, warning_edge_strength[3:1]} +
                              warning_edge_strength[0];
    wire [4:0] edge_red_sum = {1'b0, composed_rgb[11:8]} + edge_red_add;
    wire [3:0] edge_dim = warning_edge_strength[3:2];
    wire [3:0] edge_green = (composed_rgb[7:4] > edge_dim) ?
                            (composed_rgb[7:4] - edge_dim) : 4'd0;
    wire [3:0] edge_blue = (composed_rgb[3:0] > edge_dim) ?
                           (composed_rgb[3:0] - edge_dim) : 4'd0;
    wire [11:0] warning_rgb = warning_edge_glow ?
        {(edge_red_sum[4] ? 4'hf : edge_red_sum[3:0]), edge_green, edge_blue} : composed_rgb;

    // Do not present stale or partially written map pixels during GENERATE.
    assign vga_r = render_enable_d ? warning_rgb[11:8] : 4'h0;
    assign vga_g = render_enable_d ? warning_rgb[7:4]  : 4'h0;
    assign vga_b = render_enable_d ? warning_rgb[3:0] :
                                      (active_video_d ? 4'h2 : 4'h0);

    // Transfer the composed 512-bit status_text buffer through a held-data
    // toggle mailbox. The OLED domain acknowledges a complete snapshot, then
    // applies it only at frame_begin so changing status cannot tear a frame.
    wire clk_6m25;
    oled_clk_div oled_div_i (.clk(clk), .clk_6m25(clk_6m25));

    (* ASYNC_REG = "TRUE" *) reg [1:0] oled_reset_sync = 2'b11;
    wire [12:0] oled_pixel_index;
    wire [15:0] oled_pixel_data;
    wire oled_frame_begin, oled_sending_pixels, oled_sample_pixel;
    // Asynchronous assertion catches even a short reset; release is
    // synchronized to the free-running OLED clock in two stages.
    always @(posedge clk_6m25 or posedge system_reset) begin
        if (system_reset)
            oled_reset_sync <= 2'b11;
        else
            oled_reset_sync <= {oled_reset_sync[0], 1'b0};
    end
    wire oled_reset = oled_reset_sync[1];

    (* ASYNC_REG = "TRUE" *) reg [1:0] text_ack_sync = 2'b00;
    reg text_ack_toggle = 1'b0;
    reg text_req_toggle = 1'b0;
    reg [511:0] text_mailbox = 512'd0;
    reg [3:0] visual_mailbox=0;
    always @(posedge clk) begin
        if (system_reset) begin
            text_ack_sync <= 2'b00;
            text_mailbox <= status_text;
            visual_mailbox <= 0;
            text_req_toggle <= 1'b1;
        end else begin
            text_ack_sync <= {text_ack_sync[0], text_ack_toggle};
            // Sample one complete OLED snapshot per VGA frame while the
            // mailbox is idle. Avoid a 512-bit change comparator on the
            // mailbox enable path; the OLED-side handshake still prevents
            // tearing and naturally skips a frame if the receiver is busy.
            if (frame_tick && (text_req_toggle == text_ack_sync[1])) begin
                text_mailbox <= status_text;
                visual_mailbox <= roulette_visual;
                text_req_toggle <= ~text_req_toggle;
            end
        end
    end

    (* ASYNC_REG = "TRUE" *) reg [1:0] text_req_sync = 2'b00;
    reg [511:0] text_pending = 512'd0;
    reg [511:0] text_active = 512'd0;
    reg text_pending_valid = 1'b0;
    reg [3:0] visual_pending=0,visual_active=0;
    reg oled_frame_toggle=0;
    always @(posedge clk_6m25) begin
        if (oled_reset) begin
            text_req_sync <= 2'b00;
            text_ack_toggle <= 1'b0;
            text_pending <= 512'd0;
            text_active <= 512'd0;
            text_pending_valid <= 1'b0;
            visual_pending<=0;visual_active<=0;oled_frame_toggle<=0;
        end else begin
            text_req_sync <= {text_req_sync[0], text_req_toggle};
            if (text_req_sync[1] != text_ack_toggle) begin
                text_pending <= text_mailbox;
                visual_pending <= visual_mailbox;
                text_ack_toggle <= text_req_sync[1];
                text_pending_valid <= 1'b1;
            end
            if (oled_frame_begin && text_pending_valid &&
                (text_req_sync[1] == text_ack_toggle)) begin
                text_active <= text_pending;
                visual_active <= visual_pending;
                text_pending_valid <= 1'b0;
            end
            // frame_begin also runs during OLED power-up. A display frame
            // counts only when the SPI driver actually requests its pixels.
            if(oled_frame_begin && oled_sample_pixel)oled_frame_toggle<=~oled_frame_toggle;
        end
    end

    // The applied visual is held for an entire OLED frame. Synchronising its
    // frame toggle gives the bundle time to settle before system-domain capture.
    (* ASYNC_REG="TRUE" *) reg [1:0] oled_frame_sync=0;
    reg oled_frame_seen=0;
    always @(posedge clk)begin
        if(system_reset)begin
            oled_frame_sync<=0;oled_frame_seen<=0;oled_display_frame<=0;oled_display_visual<=0;
        end else begin
            oled_frame_sync<={oled_frame_sync[0],oled_frame_toggle};
            oled_display_frame<=0;
            if(oled_frame_sync[1]!=oled_frame_seen)begin
                oled_frame_seen<=oled_frame_sync[1];oled_display_visual<=visual_active;oled_display_frame<=1;
            end
        end
    end

    wire [15:0] oled_text_data,oled_icon_data;

    oled_text_pixel oled_text_i (
        .clk(clk_6m25), .pixel_index(oled_pixel_index),
        .status_text(text_active), .pixel_data(oled_text_data)
    );
    oled_roulette_pixel roulette_pixel_i(.clk(clk_6m25),.pixel_index(oled_pixel_index),
        .icon(visual_active[2:0]),.pixel_data(oled_icon_data));
    assign oled_pixel_data=visual_active[3] ? oled_icon_data : oled_text_data;

    Oled_Display oled_i (
        .clk(clk_6m25), .reset(oled_reset),
        .frame_begin(oled_frame_begin), .sending_pixels(oled_sending_pixels),
        .sample_pixel(oled_sample_pixel), .pixel_index(oled_pixel_index),
        .pixel_data(oled_pixel_data), .cs(oled_cs), .sdin(oled_mosi),
        .sclk(oled_sclk), .d_cn(oled_dc), .resn(oled_res),
        .vccen(oled_vbatc), .pmoden(oled_vddc)
    );

    // LED[1:0] show the signed rotation command; LED[2] = generating and
    // LED[3] = a maze has been generated. Mouse debug: LED[4] = a packet in the
    // last 500 ms, LED[5] = mouse left, LED[6] = mouse right.
    assign led = {9'b0, mouse_right, mouse_left, mouse_connected, gen_done_seen, gen_busy, rot_cmd};

endmodule

// Requires a continuous level for STABLE_CYCLES before accepting either
// edge. This prevents mechanical contact bounce from producing extra snaps.
module snap_button_debounce #(
    parameter integer STABLE_CYCLES = 1_000_000
) (
    input  wire clk,
    input  wire rst,
    input  wire level_in,
    output reg  level_out = 1'b0
);
    reg [19:0] stable_count = 20'd0;
    always @(posedge clk) begin
        if (rst) begin
            level_out <= 1'b0;
            stable_count <= 20'd0;
        end else if (level_in == level_out) begin
            stable_count <= 20'd0;
        end else if (stable_count == STABLE_CYCLES - 1) begin
            level_out <= level_in;
            stable_count <= 20'd0;
        end else begin
            stable_count <= stable_count + 1'b1;
        end
    end
endmodule

// Two-flop synchronization, debounce, and one-cycle rising-edge event for
// the Story 4.2 menu buttons. Reset also re-arms the press detector.
module button_press_debounce #(
    parameter integer STABLE_CYCLES = 1_000_000
) (
    input  wire clk,
    input  wire rst,
    input  wire level_in,
    output reg  press = 1'b0
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] level_sync = 2'b00;
    reg debounced_level = 1'b0;
    reg [31:0] stable_count = 32'd0;

    always @(posedge clk) begin
        if (rst) begin
            level_sync <= 2'b00;
            debounced_level <= 1'b0;
            stable_count <= 32'd0;
            press <= 1'b0;
        end else begin
            level_sync <= {level_sync[0], level_in};
            press <= 1'b0;
            if (level_sync[1] == debounced_level) begin
                stable_count <= 32'd0;
            end else if (stable_count >= STABLE_CYCLES - 1) begin
                debounced_level <= level_sync[1];
                stable_count <= 32'd0;
                if (level_sync[1])
                    press <= 1'b1;
            end else begin
                stable_count <= stable_count + 1'b1;
            end
        end
    end
endmodule
