`timescale 1ns / 1ps
`include "ep_map.vh"

//--------------------------------------------------------------------
// Output Filter
//--------------------------------------------------------------------
// Take delta value as an input. Optionally multiplies and right
// shifts the delta before adding it to the previously outputted
// value. Enforces max and min bounds on the resulting value.
//--------------------------------------------------------------------

module output_filter #(
    parameter W_CHAN = 5,
    parameter W_DELTA = 18,
    parameter W_DOUT = 64,
    parameter W_MTRS = 8,
    parameter W_RS = 8,
    parameter W_WR_ADDR = 16,
    parameter W_WR_CHAN = 16,
    parameter W_WR_DATA = 48
    )(
    // Inputs
    input wire clk_in,
    input wire rst_in,

    input wire dv_in,
    input wire [W_CHAN-1:0] chan_in,
    input wire signed [W_DELTA-1:0] delta_in,

    input wire wr_en,
    input wire [W_WR_ADDR-1:0] wr_addr,
    input wire [W_WR_CHAN-1:0] wr_chan,
    input wire [W_WR_DATA-1:0] wr_data,

    // Outputs
    output wire dv_out,
    output wire [W_CHAN-1:0] chan_out,
    output wire signed [W_OUT-1:0] data_out
    );

//--------------------------------------------------------------------
// Constants
//--------------------------------------------------------------------
localparam W_DMULT = W_DELTA + W_MTRS;
localparam W_DSUM = W_DMULT + 1;
localparam W_DOUT_UC = ((W_DSUM > W_DOUT) ? W_DSUM : W_DOUT) + 1;

reg [W_CHAN:0] null_chan = 1 << W_CHAN;

//--------------------------------------------------------------------
// Request Registers
//--------------------------------------------------------------------
reg [N_CHAN-1:0] clr_req = 0;
reg [N_CHAN-1:0] inj_req = 0;

// Manage clear register
integer i;
always @( posedge clk_in ) begin
    // Handle writes
    if ( wr_en && ( wr_addr == opt_clr_reg_addr )) begin
        opt_clr_req_addr : clr_req[wr_chan] <= wr_data[0];
    end

    // Zero on reset or clear
    for ( i = 0; i < N_CHAN; i = i + 1 ) begin
        if ( rst_in || clr_req[i] ) begin
            clr_req[i] = 0;
        end
    end
end

//--------------------------------------------------------------------
// Configuration Memory
//--------------------------------------------------------------------
reg [W_RS-1:0] rs_mem[0:N_CHAN-1];
reg [W_CHAN:0] add_chan_mem[0:N_CHAN-1];
reg signed [W_MTRS-1:0] mult_mem[0:N_CHAN-1];
reg signed [W_DOUT-1:0] max_mem[0:N_CHAN-1];
reg signed [W_DOUT-1:0] min_mem[0:N_CHAN-1];
reg signed [W_DOUT-1:0] init_mem[0:N_CHAN-1];

// Initialize memory
initial begin
    for ( i = 0; i < N_CHAN; i = i+1 ) begin
        add_chan_mem[i] = null_chan;
    end
end

// Handle writes
always @( posedge clk_in ) begin
    if ( wr_en ) begin
        case ( wr_addr ) begin
            opt_min_addr : min_mem[wr_chan] <= wr_data[W_DOUT-1:0];
            opt_max_addr : max_mem[wr_chan] <= wr_data[W_DOUT-1:0];
            opt_init_addr : init_mem[wr_chan] <= wr_data[W_DOUT-1:0];
            opt_mult_addr : mult_mem[wr_chan] <= wr_data[W_MTRS-1:0];
            opt_rs_addr : rs_mem[wr_chan] <= wr_data[W_RS-1:0];
            opt_add_chan : add_chan_mem[wr_chan] <= wr_data[W_CHAN:0];
        end
    end
end

//--------------------------------------------------------------------
// Internal Memory
//--------------------------------------------------------------------
reg signed [W_DOUT-1:0] dout_prev_mem[0:N_CHAN-1];
reg signed [W_DMULT-1:0] dmtrs_prev_mem[0:N_CHAN-1];

//--------------------------------------------------------------------
// Pipe Stage 1: Fetch
//--------------------------------------------------------------------
reg inj_p1 = 0;
reg dv_p1 = 0;
reg [W_CHAN-1:0] chan_p1 = 0;
reg signed [W_DELTA-1:0] delta_p1 = 0;
reg signed [W_MTRS-1:0] mult_p1 = 0;
reg [W_RS-1:0] rs_p1 = 0;
reg [W_CHAN:0] add_chan_p1 = 0;

always @( posedge clk_in ) begin
    // Register input instruction if input data is valid. Otherwise, if
    // there are pending inject requests, inject write instruction.
    // Injection channel preference is low to high.
    if ( dv_in ) begin
        inj_p1 = 0;
        dv_p1 = dv_in;
        chan_p1 = chan_in;
        delta_p1 = delta_in;
    end else begin
        // Don't inject by default
        inj_p1 = 0;
        dv_p1 = 0;

        // Inject instruction if request is pending
        for ( i = N_CHAN; i >= 0; i = i - 1 ) begin
            if ( inj_req[i] ) begin
                inj_p1 = 1;
                dv_p1 = 1;
                chan_p1 = i;
                delta_p1 = 0;
            end
        end
    end

    // Manage injection register
    begin
        // Handle writes
        if ( wr_en && ( wr_addr == opt_clr_reg_addr )) begin
            opt_inj_req_addr : inj_req[wr_chan] = wr_data[0];
        end

        // Zero after successful injection
        if ( inj_p1 ) begin
            inj_req[chan_p1] = 0;
        end

        // Zero on reset or clear
        for ( i = 0; i < N_CHAN; i = i + 1 ) begin
            if ( rst_in || clr_req[i] ) begin
                inj_reg[i] = 0;
            end
        end
    end

    // Fetch multiplier, right shift, and add channel
	mult_p1 = mult_mem[chan_in];
	rs_p1 = rs_mem[chan_in];
    add_chan_p1 = add_chan_mem[chan_in];

    // Flush stage on reset or clear
    if ( rst_in || clr_req[chan_in] ) begin
        inj_p1 = 0;
        dv_p1 = 0;
    end
end

//--------------------------------------------------------------------
// Pipe Stage 2: Multiply and right shift
//--------------------------------------------------------------------
reg inj_p2 = 0;
reg dv_p2 = 0;
reg [W_CHAN-1:0] chan_p2 = 0;
reg signed [W_DMULT-1:0] dmtrs_p2 = 0;
reg signed [W_DMULT-1:0] add_dmtrs_p2 = 0;

always @( posedge clk_in ) begin
    // Pass instruction
    inj_p2 = inj_p1;
	dv_p2 = dv_p1;
	chan_p2 = chan_p1;

	// Multiply and right shift delta
	dmtrs_p2 = (delta_p1 * mult_p1) >>> rs_p1;

    // Fetch add data if channel is valid. Otherwise set add data
    // value to zero.
    if ( add_chan_p1 < N_CHAN ) begin
        add_dmtrs_p2 = dmtrs_prev_mem[add_chan_p1];
    end else begin
        add_dmtrs_p2 = 0;
    end

    // Flush stage on reset or clear
    if ( rst_in || clr_req[chan_p1] ) begin
        inj_p2 = 0;
        dv_p2 = 0;
    end
end

//--------------------------------------------------------------------
// Pipe Stage 3: Sum with add channel data
//--------------------------------------------------------------------
reg inj_p3 = 0;
reg dv_p3 = 0;
reg [W_CHAN-1:0] chan_p3 = 0;
reg signed [W_DSUM-1:0] dsum_p3 = 0;
reg signed [W_DOUT-1:0] dout_prev_p3 = 0;
reg signed [W_DOUT-1:0] max_p3 = 0;
reg signed [W_DOUT-1:0] min_p3 = 0;
reg signed [W_DOUT-1:0] init_p3 = 0;

always @( posedge clk_in ) begin
    // Pass instruction
    inj_p3 = inj_p2;
	dv_p3 = dv_p2;
	chan_p3 = chan_p2;

	// Sum with add channel data
	dsum_p3 = dmtrs_p2 + add_dmtrs_p2;

    // Fetch previous output and output bounds
	dout_prev_p3 = dout_prev_mem[chan_p2];
	max_p3 = max_mem[chan_p2];
    min_p3 = min_mem[chan_p2];

    // Writeback multiplied and shifted data or zero on reset or clear
    begin
        if ( dv_p2 ) begin
            dmtrs_prev_mem[chan_p2] = dmtrs_p2;
        end

        for ( i = 0; i < N_CHAN; i = i + 1 ) begin
            if ( rst_in || clr_req[i] ) begin
                dmtrs_prev_mem[i] = 0;
            end
        end
    end

    // Flush stage on reset or clear
    if ( rst_in || clr_req[chan_p2] ) begin
        inj_p3 = 0;
        dv_p3 = 0;
    end

end

//--------------------------------------------------------------------
// Pipe Stage 4: Compute output
//--------------------------------------------------------------------
reg inj_p4 = 0;
reg dv_p4 = 0;
reg [W_CHAN-1:0] chan_p4 = 0;
reg signed [W_DOUT_UC-1:0] dout_uc_p4 = 0;
reg signed [W_DOUT-1:0] dout_p4 = 0;

always @( posedge clk_in ) begin
    // Pass instruction
    inj_p4 = inj_p3;
	dv_p4 = dv_p3;
	chan_p4 = chan_p3;

	// Sum data with previous output
	dout_uc_p4 = dsum_p3 + dout_prev_p3;

    // Handle output bounds violations
    if ( dout_uc_p4 > max_p3 ) begin
        dout_p4 = max_p3;
    end else if ( dout_uc_p4 < min_p3 ) begin
        dout_p4 = min_p3;
    end else begin
        dout_p4 = dout_uc_p4[W_DOUT-1:0];
    end

    // Fetch initial output value
    init_p4 = init_mem[chan_p3];

    // Flush stage on reset or clear
    if ( rst_in || clr_req[chan_p3] ) begin
        inj_p4 = 0;
        dv_p4 = 0;
    end
end

//--------------------------------------------------------------------
// Pipe Stage 5: Inject output and writeback
//--------------------------------------------------------------------
reg dv_p5 = 0;
reg [W_CHAN-1:0] chan_p5 = 0;
reg signed [W_DOUT-1:0] dout_p5 = 0;

always @( posedge clk_in ) begin
    // Pass instruction
	dv_p5 = dv_p4;
	chan_p5 = chan_p4;

    // Inject initial value if inject flag set
    dout_p5 = ( inj_p4 ) ? init_p4 : dout_p4;

    // Writeback output or set to initial output on reset or clear
    begin
        if ( dv_p4 ) begin
            dout_prev_mem[chan_p4] = dout_p5;
        end

        for ( i = 0; i < N_CHAN; i = i + 1 ) begin
            if ( rst_in || clr_req[i] ) begin
                dout_prev_mem[i] = init_mem[i];
            end
        end
    end

    // Flush stage on reset or clear
    if ( rst_in || clr_req[chan_p4] ) begin
        inj_p5 = 0;
        dv_p5 = 0;
    end

end

//--------------------------------------------------------------------
// Output Assigment
//--------------------------------------------------------------------
assign dv_out = dv_p5;
assign chan_out = chan_p4;
assign data_out = dout_p4;

endmodule
