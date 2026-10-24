`timescale 1ns/1ps

// PS/2 mouse stream receiver and host enable-command sender.
// The top level must implement the open-drain pins by pulling a line low
// when the corresponding *_drive_low output is asserted, and otherwise
// releasing it (normally with a pull-up).
module ps2_mouse #(
    parameter integer CLK_HZ = 100000000,
    parameter integer PS2_TIMEOUT_CYCLES = CLK_HZ / 2
) (
    input  wire clk,
    input  wire rst,
    input  wire ps2_clk_i,
    input  wire ps2_data_i,
    output reg  ps2_clk_drive_low,
    output reg  ps2_data_drive_low,
    output reg  left_button,
    output reg  right_button,
    output reg  connected
);

    localparam [2:0] ST_WAIT_IDLE = 3'd0;
    localparam [2:0] ST_INHIBIT   = 3'd1;
    localparam [2:0] ST_TX        = 3'd2;
    localparam [2:0] ST_ACK       = 3'd3;
    localparam [2:0] ST_RX        = 3'd4;

    localparam integer INHIBIT_CYCLES = CLK_HZ / 10000; // 100 us
    localparam integer TIMER_WIDTH = 32;

    reg [2:0] state;
    reg [31:0] timer;
    reg [1:0] clk_sync;
    reg [1:0] data_sync;
    reg clk_sync_d;
    wire ps2_clk_fall = clk_sync_d && !clk_sync[1];
    wire ps2_clk_rise = !clk_sync_d && clk_sync[1];

    reg [3:0] tx_edge_count;
    reg [3:0] rx_bit_count;
    reg [7:0] rx_shift;
    reg rx_parity;
    reg [7:0] packet_byte0;
    reg [7:0] packet_byte1;
    reg [1:0] packet_index;
    reg [31:0] activity_timer;

    wire [7:0] tx_byte = 8'hF4;
    wire tx_odd_parity = ~(^tx_byte);

    always @(posedge clk) begin
        if (rst) begin
            clk_sync       <= 2'b11;
            data_sync      <= 2'b11;
            clk_sync_d     <= 1'b1;
            state          <= ST_WAIT_IDLE;
            timer          <= 32'd0;
            activity_timer <= 32'd0;
            ps2_clk_drive_low  <= 1'b0;
            ps2_data_drive_low <= 1'b0;
            tx_edge_count  <= 4'd0;
            rx_bit_count   <= 4'd0;
            rx_shift       <= 8'd0;
            rx_parity      <= 1'b0;
            packet_byte0   <= 8'd0;
            packet_byte1   <= 8'd0;
            packet_index   <= 2'd0;
            left_button    <= 1'b0;
            right_button   <= 1'b0;
            connected      <= 1'b0;
        end else begin
            // Two-flop synchronizers for both asynchronous PS/2 wires.
            clk_sync   <= {clk_sync[0], ps2_clk_i};
            data_sync  <= {data_sync[0], ps2_data_i};
            clk_sync_d <= clk_sync[1];

            if (connected) begin
                if (activity_timer < PS2_TIMEOUT_CYCLES)
                    activity_timer <= activity_timer + 1'b1;
                else begin
                    connected    <= 1'b0;
                    left_button  <= 1'b0;
                    right_button <= 1'b0;
                    packet_index <= 2'd0;
                    state        <= ST_WAIT_IDLE;
                    timer        <= 32'd0;
                    ps2_clk_drive_low  <= 1'b0;
                    ps2_data_drive_low <= 1'b0;
                end
            end

            case (state)
                ST_WAIT_IDLE: begin
                    ps2_clk_drive_low  <= 1'b0;
                    ps2_data_drive_low <= 1'b0;
                    timer <= 32'd0;
                    if (!connected && clk_sync[1] && data_sync[1]) begin
                        if (INHIBIT_CYCLES <= 1) begin
                            ps2_clk_drive_low  <= 1'b1;
                            ps2_data_drive_low <= 1'b1;
                            timer <= 32'd0;
                            state <= ST_INHIBIT;
                        end else begin
                            timer <= timer + 1'b1;
                            if (timer >= (INHIBIT_CYCLES - 1)) begin
                                ps2_clk_drive_low  <= 1'b1;
                                ps2_data_drive_low <= 1'b1;
                                timer <= 32'd0;
                                state <= ST_INHIBIT;
                            end
                        end
                    end
                end

                ST_INHIBIT: begin
                    // Keep clock inhibited, assert request-to-send, then
                    // release clock so the mouse supplies the transfer clock.
                    if (timer < INHIBIT_CYCLES) begin
                        timer <= timer + 1'b1;
                        ps2_clk_drive_low  <= 1'b1;
                        ps2_data_drive_low <= 1'b1;
                    end else begin
                        ps2_clk_drive_low  <= 1'b0;
                        ps2_data_drive_low <= 1'b1; // start bit
                        tx_edge_count <= 4'd0;
                        timer <= 32'd0;
                        state <= ST_TX;
                    end
                end

                ST_TX: begin
                    if (timer < PS2_TIMEOUT_CYCLES)
                        timer <= timer + 1'b1;
                    else begin
                        // No device clock: release the bus and retry startup.
                        state <= ST_WAIT_IDLE;
                        timer <= 32'd0;
                        ps2_clk_drive_low  <= 1'b0;
                        ps2_data_drive_low <= 1'b0;
                    end

                    if (ps2_clk_fall) begin
                        timer <= 32'd0;
                        if (tx_edge_count == 4'd0) begin
                            // The request-to-send level is the start bit;
                            // hold it through the first device sampling edge.
                            ps2_data_drive_low <= 1'b1;
                        end else if (tx_edge_count <= 4'd8)
                            ps2_data_drive_low <= ~tx_byte[tx_edge_count - 1'b1];
                        else if (tx_edge_count == 4'd9)
                            ps2_data_drive_low <= ~tx_odd_parity;
                        else if (tx_edge_count == 4'd10)
                            ps2_data_drive_low <= 1'b0; // stop bit high
                        else begin
                            ps2_data_drive_low <= 1'b0; // release for device ACK
                            state <= ST_ACK;
                        end
                        tx_edge_count <= tx_edge_count + 1'b1;
                    end
                end

                ST_ACK: begin
                    if (timer < PS2_TIMEOUT_CYCLES)
                        timer <= timer + 1'b1;
                    else begin
                        state <= ST_WAIT_IDLE;
                        timer <= 32'd0;
                    end

                    if (ps2_clk_rise) begin
                        timer <= 32'd0;
                        if (!data_sync[1]) begin
                            state <= ST_RX;
                            rx_bit_count <= 4'd0;
                            rx_shift <= 8'd0;
                            packet_index <= 2'd0;
                            activity_timer <= 32'd0;
                        end else begin
                            state <= ST_WAIT_IDLE;
                        end
                    end
                end

                ST_RX: begin
                    if (ps2_clk_rise) begin
                        case (rx_bit_count)
                            4'd0: begin
                                if (!data_sync[1]) begin
                                    rx_shift <= 8'd0;
                                    rx_bit_count <= 4'd1;
                                end else begin
                                    // Ignore an out-of-frame high bit.
                                    rx_bit_count <= 4'd0;
                                end
                            end
                            4'd1, 4'd2, 4'd3, 4'd4,
                            4'd5, 4'd6, 4'd7, 4'd8: begin
                                rx_shift[rx_bit_count - 1'b1] <= data_sync[1];
                                rx_bit_count <= rx_bit_count + 1'b1;
                            end
                            4'd9: begin
                                rx_parity <= data_sync[1];
                                rx_bit_count <= 4'd10;
                            end
                            default: begin
                                rx_bit_count <= 4'd0;
                                if (data_sync[1] && ((^rx_shift) ^ rx_parity)) begin
                                    activity_timer <= 32'd0;
                                    if (packet_index == 2'd0) begin
                                        if (rx_shift[3]) begin
                                            packet_byte0 <= rx_shift;
                                            packet_index <= 2'd1;
                                        end
                                    end else if (packet_index == 2'd1) begin
                                        packet_byte1 <= rx_shift;
                                        packet_index <= 2'd2;
                                    end else begin
                                        left_button  <= packet_byte0[0];
                                        right_button <= packet_byte0[1];
                                        connected    <= 1'b1;
                                        packet_index <= 2'd0;
                                    end
                                end else begin
                                    packet_index <= 2'd0;
                                end
                            end
                        endcase
                    end

                    if (connected && activity_timer >= PS2_TIMEOUT_CYCLES) begin
                        connected    <= 1'b0;
                        left_button  <= 1'b0;
                        right_button <= 1'b0;
                        packet_index <= 2'd0;
                        state        <= ST_WAIT_IDLE;
                        ps2_clk_drive_low  <= 1'b0;
                        ps2_data_drive_low <= 1'b0;
                    end
                end

                default: begin
                    state <= ST_WAIT_IDLE;
                    timer <= 32'd0;
                end
            endcase
        end
    end

endmodule
