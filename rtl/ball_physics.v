`timescale 1ns / 1ps
`include "labyrinth_pkg.vh"

// ball_physics: ball state, gravity and wall collisions (Stories 3.1 and 3.2,
// AD-3 / AD-4 / AD-6 / AD-11).
//
// Position and velocity live in MAZE coordinates (x right, y down as the maze
// is drawn at angle 0). Position is signed Q9.8 maze pixels measured from the
// centre of the 21x21 map; velocity is signed Q4.8 pixels per frame.
//
// Screen-down seen from the maze frame. render.v maps a screen offset
// (dx, dy) from the screen centre to maze pixels as
//     maze_x = 168 + dx*cos + dy*sin,   maze_y = 168 - dx*sin + dy*cos,
// so the screen-down direction (0, +1) is (sin, cos) in the maze frame:
//     gravity = g * (sin(theta), cos(theta)),   g = 0.15 px/frame^2.
// (The earlier AD-3 text said (-sin, cos); that does not match render.v.)
//
// One update per frame, in vertical blanking, after the angle accumulator and
// the registered sincos_rom have settled (the same moment render snapshots):
//     velocity += gravity, clamped to +/-VEL_CAP per axis
//     then per axis, x first and then y with the new x (AD-11):
//       move by the velocity; if the ball's box would enter a wall tile, clamp
//       the box to that tile's edge and bounce: v = -restitution(|v|) * sign(v)
// The other axis's velocity is never touched (no friction, no drag).
//
// Collision geometry. The ball's box is centre +/- R (R = BALL_RADIUS) per
// axis, right/bottom edge exclusive, so it covers at most two tiles across
// (10 px < 16 px). At the start of a frame the box never overlaps a wall, and
// a step is at most 5 px, so only the leading column (or row) can be newly
// entered: two reads of maze_ram per axis decide it. Tiles outside the 21x21
// map count as wall. maze_ram's physics port has one clock of read latency.
module ball_physics (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         frame_tick,
    input  wire                         phys_init,    // pulse: place the ball at spawn tile, velocity 0
    input  wire                         phys_en,      // 1 = PLAY: apply gravity
    input  wire [`COORD_W-1:0]          spawn_col,
    input  wire [`COORD_W-1:0]          spawn_row,
    input  wire [`COORD_W-1:0]          goal_col,
    input  wire [`COORD_W-1:0]          goal_row,
    input  wire signed [`TRIG_W-1:0]    sin_q,
    input  wire signed [`TRIG_W-1:0]    cos_q,
    input  wire [`RESTIT_SEL_W-1:0]     restitution_sel, // 0 = 0.5, 1 = 0.75, 2 = 0.625, 3 = 0.375
    output reg  [`MAP_ADDR_W-1:0]       maze_raddr,   // maze_ram physics read port
    input  wire                         maze_rdata,   // 1 = wall, one clock after maze_raddr
    output reg  signed [`POS_W-1:0]     ball_x,
    output reg  signed [`POS_W-1:0]     ball_y,
    output reg  signed [`VEL_W-1:0]     vel_x,
    output reg  signed [`VEL_W-1:0]     vel_y,
    output reg                          phys_done,    // pulse once the new position is valid
    output wire                         in_goal       // ball centre inside the goal tile
);

    localparam signed [`VEL_W-1:0] CAP   = `VEL_CAP;
    localparam signed [12:0] GRAVITY_COEFF = `GRAVITY_Q14;
    localparam integer GRAVITY_FRAC_BITS = `GRAVITY_FRAC;

    // Absolute maze pixel = position + half the map (168 px); widths leave room
    // for a box edge just outside the map.
    localparam integer AW = `POS_W + 1;
    localparam signed [AW-1:0] OFF = `MAP_DIM * `TILE_PX * (1 << (`POS_FRAC - 1));
    localparam signed [AW-1:0] R   = `BALL_RADIUS << `POS_FRAC;

    // Convert an absolute map tile's left/top edge to maze-centred Q9.8.
    // OFF is the 168 px map-centre offset; each tile is 1 << TILE_SHIFT units.
    function signed [`POS_W-1:0] tile_min_q;
        input [`COORD_W-1:0] tile;
        reg signed [AW-1:0] tile_index;
        reg signed [AW-1:0] edge_q;
        begin
            tile_index = $signed({1'b0, tile});
            edge_q = (tile_index <<< `TILE_SHIFT) - OFF;
            tile_min_q = edge_q[`POS_W-1:0];
        end
    endfunction

    wire signed [`POS_W-1:0] goal_x_min = tile_min_q(goal_col);
    wire signed [`POS_W-1:0] goal_y_min = tile_min_q(goal_row);
    wire signed [`POS_W-1:0] goal_x_max = goal_x_min + (1 <<< `TILE_SHIFT);
    wire signed [`POS_W-1:0] goal_y_max = goal_y_min + (1 <<< `TILE_SHIFT);
    assign in_goal = (ball_x >= goal_x_min) && (ball_x < goal_x_max) &&
                     (ball_y >= goal_y_min) && (ball_y < goal_y_max);

    // frame_tick -> angle updates -> registered ROM: sin/cos are valid when ft_d[1] is high
    reg [4:0] ft_d;
    reg       go2, go3;

    // Gravity step in Q4.8 velocity units, with a carried 20-bit fraction so
    // the 0.15 px/frame^2 acceleration is not rounded to 38/256 each frame.
    reg signed [`VEL_W-1:0] gx, gy;
    reg [GRAVITY_FRAC_BITS-1:0] gx_frac, gy_frac;
    reg signed [`TRIG_W-1:0] sin_g_r, cos_g_r;
    // The coefficient is a constant, so the product is a few shifted adds in
    // LUTs; keeping it out of DSP48s leaves the AD-8 budget (<= 8) its spares.
    (* use_dsp = "no" *) reg signed [28:0] gx_prod_r, gy_prod_r;
    wire signed [29:0] gx_accum = {gx_prod_r[28], gx_prod_r} + $signed({10'b0, gx_frac});
    wire signed [29:0] gy_accum = {gy_prod_r[28], gy_prod_r} + $signed({10'b0, gy_frac});

    // tile (col,row) has its centre at 16*(col-10) px from the map centre -> (col-10) << 12 in Q9.8
    wire signed [`POS_W-1:0] spawn_x = ($signed({1'b0, spawn_col}) - 6'sd10) <<< 12;
    wire signed [`POS_W-1:0] spawn_y = ($signed({1'b0, spawn_row}) - 6'sd10) <<< 12;

    wire signed [`VEL_W:0]   vx_sum = vel_x + gx;
    wire signed [`VEL_W:0]   vy_sum = vel_y + gy;

    // ---- collision step for the axis being moved (axis 0 = x, 1 = y) ----
    localparam [2:0] S_IDLE = 3'd0, S_ADDR0 = 3'd1, S_ADDR1 = 3'd2, S_READ0 = 3'd3, S_RESOLVE = 3'd4;
    reg [2:0] state;
    reg       axis;
    reg       wall0;                                   // first tile of the leading edge

    wire signed [`POS_W-1:0] pos_m = axis ? ball_y : ball_x;   // moving axis
    wire signed [`VEL_W-1:0] vel_m = axis ? vel_y  : vel_x;
    wire signed [`POS_W-1:0] pos_o = axis ? ball_x : ball_y;   // other axis

    wire signed [AW-1:0] a_new = pos_m + vel_m + OFF;          // moved centre, absolute
    wire signed [AW-1:0] a_o   = pos_o + OFF;
    wire signed [AW-1:0] lead_edge = (vel_m > 0) ? (a_new + R - 1) : (a_new - R);
    wire signed [AW-`TILE_SHIFT-1:0] lead = lead_edge >>> `TILE_SHIFT;   // newly entered column/row
    wire signed [AW-`TILE_SHIFT-1:0] o0   = (a_o - R) >>> `TILE_SHIFT;   // tiles the box spans across
    wire signed [AW-`TILE_SHIFT-1:0] o1   = (a_o + R - 1) >>> `TILE_SHIFT;

    function in_map;
        input signed [AW-`TILE_SHIFT-1:0] t;
        begin
            in_map = (t >= 0) && (t < `MAP_DIM);
        end
    endfunction

    // addr = row*21 + col with shifts and adds (row*16 + row*4 + row)
    function [`MAP_ADDR_W-1:0] tile_addr;
        input [`COORD_W-1:0] col;
        input [`COORD_W-1:0] row;
        begin
            tile_addr = {row, 4'b0000} + {2'b00, row, 2'b00} + {4'b0000, row} + {4'b0000, col};
        end
    endfunction

    wire [`COORD_W-1:0] lead_t = lead[`COORD_W-1:0];
    wire [`COORD_W-1:0] o0_t   = o0[`COORD_W-1:0];
    wire [`COORD_W-1:0] o1_t   = o1[`COORD_W-1:0];
    wire [`MAP_ADDR_W-1:0] addr0 = axis ? tile_addr(o0_t, lead_t) : tile_addr(lead_t, o0_t);
    wire [`MAP_ADDR_W-1:0] addr1 = axis ? tile_addr(o1_t, lead_t) : tile_addr(lead_t, o1_t);
    wire oob0 = !(in_map(lead) && in_map(o0));
    wire oob1 = !(in_map(lead) && in_map(o1));

    // Clamp: moving +: box right edge (exclusive) on the wall's near edge;
    // moving -: box left edge on the wall's far edge.
    wire signed [AW-1:0] lead_px = $signed({lead, {`TILE_SHIFT{1'b0}}});
    wire signed [AW-1:0] a_clamp = (vel_m > 0) ? (lead_px - R) : (lead_px + (1 <<< `TILE_SHIFT) + R);
    wire signed [AW-1:0] p_clamp = a_clamp - OFF;
    wire signed [AW-1:0] p_free  = pos_m + vel_m;

    // Restitution by shifts and adds on the magnitude, then the sign reversed.
    wire [`VEL_W-1:0] mag = vel_m[`VEL_W-1] ? -vel_m : vel_m;
    reg  [`VEL_W-1:0] mag_b;
    always @* begin
        case (restitution_sel)
            2'd0:    mag_b = mag >> 1;                    // 0.5
            2'd1:    mag_b = (mag >> 1) + (mag >> 2);     // 0.75, rounded down so tiny bounces die out
            2'd2:    mag_b = (mag >> 1) + (mag >> 3);     // 0.625
            default: mag_b = (mag >> 2) + (mag >> 3);     // 0.375
        endcase
    end
    wire signed [`VEL_W-1:0] v_bounce = vel_m[`VEL_W-1] ? $signed(mag_b) : -$signed(mag_b);

    wire blocked = wall0 | oob0 | maze_rdata | oob1;

    // The moving axis, positions and velocities hold from S_ADDR0 to S_RESOLVE,
    // so both outcomes are registered in S_READ0; S_RESOLVE only chooses one.
    reg signed [`POS_W-1:0] p_clamp_r, p_free_r;
    reg signed [`VEL_W-1:0] v_bounce_r;

    always @(posedge clk) begin
        phys_done <= 1'b0;
        if (rst) begin
            ft_d <= 5'b0; go2 <= 1'b0; go3 <= 1'b0;
            gx <= 0; gy <= 0; gx_frac <= 0; gy_frac <= 0;
            sin_g_r <= 0; cos_g_r <= 0; gx_prod_r <= 0; gy_prod_r <= 0;
            ball_x <= 0; ball_y <= 0; vel_x <= 0; vel_y <= 0;
            state <= S_IDLE; axis <= 1'b0; wall0 <= 1'b0;
            maze_raddr <= 0;
        end else begin
            ft_d <= {ft_d[3:0], frame_tick};
            go2  <= ft_d[4] & phys_en;
            go3  <= go2;

            // Pipeline gravity across three clocks: first capture settled
            // trig, then multiply, then add the carried fraction. This keeps
            // the ROM/sign, constant-multiply adder and wide carry paths out of
            // one 100 MHz path.
            if (ft_d[1]) begin
                sin_g_r <= sin_q;
                cos_g_r <= cos_q;
            end
            if (ft_d[2]) begin
                gx_prod_r <= sin_g_r * GRAVITY_COEFF;
                gy_prod_r <= cos_g_r * GRAVITY_COEFF;
            end
            if (ft_d[3]) begin
                gx <= gx_accum >>> GRAVITY_FRAC_BITS;
                gy <= gy_accum >>> GRAVITY_FRAC_BITS;
                gx_frac <= gx_accum[GRAVITY_FRAC_BITS-1:0];
                gy_frac <= gy_accum[GRAVITY_FRAC_BITS-1:0];
            end

            // stage 2: velocity, capped per axis
            if (go2) begin
                vel_x <= (vx_sum >  CAP) ?  CAP : (vx_sum < -CAP) ? -CAP : vx_sum[`VEL_W-1:0];
                vel_y <= (vy_sum >  CAP) ?  CAP : (vy_sum < -CAP) ? -CAP : vy_sum[`VEL_W-1:0];
            end

            // stage 3: per-axis move and tile test, x then y
            case (state)
                S_IDLE: begin
                    if (go3) begin
                        axis  <= 1'b0;
                        state <= S_ADDR0;
                    end
                end

                S_ADDR0: begin
                    if (vel_m == 0) begin                    // no motion on this axis
                        if (axis) begin
                            state <= S_IDLE;
                            phys_done <= 1'b1;
                        end else
                            axis <= 1'b1;
                    end else begin
                        maze_raddr <= addr0;
                        state <= S_ADDR1;
                    end
                end

                S_ADDR1: begin                               // maze_ram samples addr0 now
                    maze_raddr <= addr1;
                    state <= S_READ0;
                end

                S_READ0: begin                               // addr0's tile is on maze_rdata
                    wall0 <= maze_rdata;
                    p_clamp_r  <= p_clamp[`POS_W-1:0];
                    p_free_r   <= p_free[`POS_W-1:0];
                    v_bounce_r <= v_bounce;
                    state <= S_RESOLVE;
                end

                S_RESOLVE: begin                             // addr1's tile is on maze_rdata
                    if (blocked) begin
                        if (axis) begin ball_y <= p_clamp_r; vel_y <= v_bounce_r; end
                        else      begin ball_x <= p_clamp_r; vel_x <= v_bounce_r; end
                    end else begin
                        if (axis) ball_y <= p_free_r;
                        else      ball_x <= p_free_r;
                    end
                    if (axis) begin
                        state <= S_IDLE;
                        phys_done <= 1'b1;
                    end else begin
                        axis  <= 1'b1;
                        state <= S_ADDR0;
                    end
                end

                default: state <= S_IDLE;
            endcase

            // a new maze puts the ball at the selected spawn tile, at rest
            if (phys_init) begin
                ball_x <= spawn_x; ball_y <= spawn_y;
                vel_x  <= 0;       vel_y  <= 0;
                gx_frac <= 0;      gy_frac <= 0;
                ft_d <= 5'b0;
                go2 <= 1'b0; go3 <= 1'b0;
                state <= S_IDLE;
            end
        end
    end

endmodule
