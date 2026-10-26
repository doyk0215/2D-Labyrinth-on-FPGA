`timescale 1ns / 1ps

// Integration top: mouse/board buttons turn the generated maze on VGA.
//   sw[0]   = debug seed (fixed seed, same maze every time)
//   sw[4:1] = maze size in cells (2..10); 0 selects 10
//   sw[5]   = 90-degree snap fallback (off = smooth rotation)
//   btnD    = regenerate; a maze is also generated when btnC is released
//   Any of btnU/L/R/D latches the random seed (first press only).
module top #(
    parameter integer SNAP_DEBOUNCE_CYCLES = 1_000_000  // 10 ms at 100 MHz
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

    wire rst = btnC;
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

    // Synchronise the buttons, then turn them into one-cycle pulses.
    reg [2:0] btnD_s = 3'b000;
    reg [2:0] btnAny_s = 3'b000;
    reg       rst_d = 1'b1;
    wire any_btn = btnU | btnL | btnR | btnD;
    always @(posedge clk) begin
        btnD_s   <= {btnD_s[1:0], btnD};
        btnAny_s <= {btnAny_s[1:0], any_btn};
        rst_d    <= rst;
    end
    wire regen     = btnD_s[1] & ~btnD_s[2];
    wire latch_en  = btnAny_s[1] & ~btnAny_s[2];
    wire gen_start = (rst_d & ~rst) | regen;
    wire [3:0] n_cells = (sw[4:1] == 4'd0) ? 4'd10 : sw[4:1];

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
        .latch_en    (latch_en),
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

    // maze_gen is the sole writer; the physics port is idle in this story.
    assign maze_raddr_p = 9'd0;

    maze_ram maze_ram_i (
        .clk     (clk),
        .we      (maze_we),
        .waddr   (maze_waddr),
        .wdata   (maze_wdata),
        .raddr_p (maze_raddr_p),
        .rdata_p (maze_rdata_p),
        .raddr_r (maze_raddr_r),
        .rdata_r (maze_rdata_r)
    );

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
        .vga_r        (vga_r),
        .vga_g        (vga_g),
        .vga_b        (vga_b),
        .vga_hs       (vga_hs),
        .vga_vs       (vga_vs)
    );

    // LED[1:0] show the signed rotation command; LED[2] = generating and
    // LED[3] = a maze has been generated. Mouse debug: LED[4] = a packet in the
    // last 500 ms, LED[5] = mouse left, LED[6] = mouse right. Keep the OLED idle. The
    // Pmod OLED VDDC/VBATC power controls are ACTIVE LOW (low = supply on),
    // so drive them high (off) until the OLED driver (Story 4.1) applies
    // the manual's power-up sequence.
    assign led = {9'b0, mouse_right, mouse_left, mouse_connected, gen_done_seen, gen_busy, rot_cmd};
    assign oled_cs = 1'b1;
    assign oled_mosi = 1'b0;
    assign oled_sclk = 1'b0;
    assign oled_dc = 1'b0;
    assign oled_res = 1'b0;
    assign oled_vbatc = 1'b1;
    assign oled_vddc = 1'b1;

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
