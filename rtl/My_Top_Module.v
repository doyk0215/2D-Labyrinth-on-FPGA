`timescale 1ns / 1ps

// Integration top: game_ctrl sequences generation/play, and the renderer is
// held off while maze_gen writes the single map; rotation supports the SW5
// snap fallback as well as the smooth mouse/button path.
//   sw[0]   = debug seed (fixed seed, same maze every time)
//   sw[4:1] = retained debug value; Story 4.2 stage configuration selects N
//   sw[5]   = 90-degree snap fallback (off = smooth rotation)
//   btnU/D  = stage navigation in MENU
//   btnC    = confirm in MENU; return to MENU from other states
//   btnD    = regenerate while playing
//   Any of btnU/L/R/D latches the random seed (first press only).
module My_Top_Module #(
    parameter integer SNAP_DEBOUNCE_CYCLES = 1_000_000, // 10 ms at 100 MHz
    parameter integer MENU_DEBOUNCE_CYCLES = 1_000_000, // 10 ms at 100 MHz
    parameter integer POR_CYCLES = 100_000,             // 1 ms at 100 MHz
    parameter START_IN_MENU = 1'b1
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
    wire game_reset_request;
    wire [1:0] game_state;
    assign rst = por_reset | game_reset_request;

    wire btnU_press, btnD_menu_press, btnC_press;
    button_press_debounce #(.STABLE_CYCLES(MENU_DEBOUNCE_CYCLES)) btnU_menu_i (
        .clk(clk), .rst(por_reset), .level_in(btnU), .press(btnU_press)
    );
    button_press_debounce #(.STABLE_CYCLES(MENU_DEBOUNCE_CYCLES)) btnD_menu_i (
        .clk(clk), .rst(por_reset), .level_in(btnD), .press(btnD_menu_press)
    );
    button_press_debounce #(.STABLE_CYCLES(MENU_DEBOUNCE_CYCLES)) btnC_menu_i (
        .clk(clk), .rst(por_reset), .level_in(btnC), .press(btnC_press)
    );

    wire start_game;
    wire [7:0] game_cfg;
    wire [7:0] active_game_cfg;
    wire [511:0] status_text;
    wire menu_active = (game_state == 2'b00);
    assign game_reset_request = btnC_press && !menu_active;

    menu_ctrl menu_ctrl_i (
        .clk           (clk),
        .rst           (rst),
        .menu_active   (menu_active),
        .btn_up        (btnU_press),
        .btn_down      (btnD_menu_press),
        .btn_confirm   (btnC_press),
        .start_game    (start_game),
        .game_cfg      (game_cfg),
        .status_text   (status_text),
        .selected_stage()
    );
    wire ce_pix;
    wire frame_tick;
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    wire active_video;
    wire timing_hsync;
    wire timing_vsync;

    wire [8:0] maze_raddr_p;
    wire maze_rdata_p;
    wire [8:0] maze_raddr_r;
    wire maze_rdata_r;

    wire        maze_we;
    wire [8:0]  maze_waddr;
    wire        maze_wdata;
    wire [4:0]  start_col;
    wire [4:0]  start_row;
    wire [4:0]  goal_col;
    wire [4:0]  goal_row;
    wire        gen_busy;
    wire        gen_done;
    wire [31:0] seed;
    wire        gen_start;
    wire        seed_capture;
    wire        phys_init;
    wire        phys_en;
    wire        render_enable;
    reg         render_enable_d = 1'b0;
    reg         active_video_d = 1'b0;

    wire mouse_left;
    wire mouse_right;
    wire mouse_middle;
    wire mouse_event;
    wire [11:0] mouse_x;
    wire [11:0] mouse_y;
    wire [3:0] mouse_z;
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
        btnL_sync <= {btnL_sync[0], btnL};
        btnR_sync <= {btnR_sync[0], btnR};
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
    assign angle_rot_cmd = !snap_mode ? rot_cmd :
                           (snap_left && !snap_right) ? -2'sd1 :
                           (snap_right && !snap_left) ? 2'sd1 : 2'sd0;
    always @(posedge clk)
        snap_sw_sync <= {snap_sw_sync[0], sw[5]};

    // Synchronize BTND and convert its rising edge into a one-cycle request.
    (* ASYNC_REG = "TRUE" *)
    reg [2:0] btnD_s = 3'b000;
    always @(posedge clk) begin
        btnD_s <= {btnD_s[1:0], btnD};
    end
    wire regen_request = btnD_s[1] & ~btnD_s[2];
    wire [3:0] legacy_n_cells = (sw[4:1] == 4'd0) ? 4'd10 : sw[4:1];
    wire [3:0] n_cells = START_IN_MENU ? active_game_cfg[3:0] : legacy_n_cells;

    assign render_enable = (game_state == 2'b10); // PLAY

    game_ctrl #(.START_IN_MENU(START_IN_MENU)) game_ctrl_i (
        .clk          (clk),
        .rst          (rst),
        .frame_tick   (frame_tick),
        .start_game   (start_game),
        .game_cfg     (game_cfg),
        .regen_button (regen_request),
        .gen_busy     (gen_busy),
        .gen_done     (gen_done),
        .in_goal      (1'b0),
        .game_state   (game_state),
        .gen_start    (gen_start),
        .seed_capture (seed_capture),
        .phys_init    (phys_init),
        .active_game_cfg(active_game_cfg),
        .phys_en      (phys_en)
    );

    // Align the display mask with render's one-cycle pixel pipeline.
    always @(posedge clk) begin
        if (rst) begin
            render_enable_d <= 1'b0;
            active_video_d  <= 1'b0;
        end else begin
            render_enable_d <= render_enable;
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
        .rst        (rst),
        .frame_tick (frame_tick),
        .rot_cmd    (angle_rot_cmd),
        .snap_mode  (snap_mode),
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
        .debug_fixed (sw[0]),
        .latch_en    (seed_capture),
        .seed        (seed)
    );

    maze_gen gen_i (
        .clk       (clk),
        .rst       (rst),
        .gen_start (gen_start),
        .n_cells   (n_cells),
        .seed      (seed),
        .gen_busy  (gen_busy),
        .gen_done  (gen_done),
        .we        (maze_we),
        .waddr     (maze_waddr),
        .wdata     (maze_wdata),
        .start_col (start_col),
        .start_row (start_row),
        .goal_col  (goal_col),
        .goal_row  (goal_row)
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

    ball_physics ball_i (
        .clk        (clk),
        .rst        (rst),
        .frame_tick (frame_tick),
        .phys_init  (phys_init),
        .phys_en    (phys_en),
        .spawn_col  (start_col),
        .spawn_row  (start_row),
        .sin_q      (sin_q),
        .cos_q      (cos_q),
        .restitution_sel (active_game_cfg[5:4]),
        .maze_raddr (maze_raddr_p),
        .maze_rdata (maze_rdata_p),
        .ball_x     (ball_x),
        .ball_y     (ball_y),
        .vel_x      (ball_vx),
        .vel_y      (ball_vy),
        .phys_done  (phys_done)
    );

    ball_overlay ball_ov_i (
        .clk          (clk),
        .rst          (rst),
        .start        (phys_done),
        .ball_x       (ball_x),
        .ball_y       (ball_y),
        .sin_q        (sin_frame),  // registered snapshot keeps the trig ROM off the DSP input path
        .cos_q        (cos_frame),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .active_video (active_video),
        .ball_sx      (ball_sx),
        .ball_sy      (ball_sy),
        .ball_on      (ball_on)
    );

    wire [3:0] render_r;
    wire [3:0] render_g;
    wire [3:0] render_b;

    render render_i (
        .clk          (clk),
        .rst          (rst),
        .ce_pix       (ce_pix),
        .frame_tick   (frame_tick),
        .angle        (angle),
        .sin_q        (sin_q),
        .cos_q        (cos_q),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .active_video (active_video),
        .hsync_in     (timing_hsync),
        .vsync_in     (timing_vsync),
        .maze_raddr   (maze_raddr_r),
        .maze_rdata   (maze_rdata_r),
        .start_col    (start_col),
        .start_row    (start_row),
        .goal_col     (goal_col),
        .goal_row     (goal_row),
        .ball_on      (ball_on),
        .vga_r        (render_r),
        .vga_g        (render_g),
        .vga_b        (render_b),
        .vga_hs       (vga_hs),
        .vga_vs       (vga_vs),
        .sin_snap     (sin_frame),
        .cos_snap     (cos_frame)
    );

    // Do not present stale or partially written map pixels during GENERATE.
    assign vga_r = render_enable_d ? render_r : (active_video_d ? 4'h0 : 4'h0);
    assign vga_g = render_enable_d ? render_g : (active_video_d ? 4'h0 : 4'h0);
    assign vga_b = render_enable_d ? render_b : (active_video_d ? 4'h2 : 4'h0);

    // Transfer the menu's 512-bit text buffer through a held-data toggle
    // mailbox. The OLED domain acknowledges a complete snapshot, then applies
    // it only at frame_begin so a changed selection cannot tear a display frame.
    wire clk_6m25;
    oled_clk_div oled_div_i (.clk(clk), .clk_6m25(clk_6m25));

    (* ASYNC_REG = "TRUE" *) reg [1:0] oled_reset_sync = 2'b11;
    wire [12:0] oled_pixel_index;
    wire [15:0] oled_pixel_data;
    wire oled_frame_begin, oled_sending_pixels, oled_sample_pixel;
    always @(posedge clk_6m25) begin
        if (por_reset)
            oled_reset_sync <= 2'b11;
        else
            oled_reset_sync <= {oled_reset_sync[0], 1'b0};
    end
    wire oled_reset = oled_reset_sync[1];

    (* ASYNC_REG = "TRUE" *) reg [1:0] text_ack_sync = 2'b00;
    reg text_ack_toggle = 1'b0;
    reg text_req_toggle = 1'b0;
    reg [511:0] text_mailbox = 512'd0;
    always @(posedge clk) begin
        if (por_reset) begin
            text_ack_sync <= 2'b00;
            text_mailbox <= status_text;
            text_req_toggle <= 1'b1;
        end else begin
            text_ack_sync <= {text_ack_sync[0], text_ack_toggle};
            if ((text_req_toggle == text_ack_sync[1]) &&
                (status_text != text_mailbox)) begin
                text_mailbox <= status_text;
                text_req_toggle <= ~text_req_toggle;
            end
        end
    end

    (* ASYNC_REG = "TRUE" *) reg [1:0] text_req_sync = 2'b00;
    reg [511:0] text_pending = 512'd0;
    reg [511:0] text_active = 512'd0;
    reg text_pending_valid = 1'b0;
    always @(posedge clk_6m25) begin
        if (oled_reset) begin
            text_req_sync <= 2'b00;
            text_ack_toggle <= 1'b0;
            text_pending <= 512'd0;
            text_active <= 512'd0;
            text_pending_valid <= 1'b0;
        end else begin
            text_req_sync <= {text_req_sync[0], text_req_toggle};
            if (text_req_sync[1] != text_ack_toggle) begin
                text_pending <= text_mailbox;
                text_ack_toggle <= text_req_sync[1];
                text_pending_valid <= 1'b1;
            end
            if (oled_frame_begin && text_pending_valid &&
                (text_req_sync[1] == text_ack_toggle)) begin
                text_active <= text_pending;
                text_pending_valid <= 1'b0;
            end
        end
    end

    oled_text_pixel oled_text_i (
        .clk(clk_6m25), .pixel_index(oled_pixel_index),
        .status_text(text_active), .pixel_data(oled_pixel_data)
    );

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
