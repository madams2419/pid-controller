`timescale 1ns / 1ps

// dds_controller -- mba 2014
// -----------------------------------------------------------
// Sends update instructions to AD9912 DDS chip.
// -----------------------------------------------------------

/*
TODO
- add phase and amplitude update functionality
*/

module dds_controller(
	// inputs <- top level entity
	input wire				clk_in,				// system clock
	input wire				reset_in, 			// system reset

	// inputs <- output preprocessor
	input wire	[47:0]	freq_in,				// frequency data
	input wire	[13:0]	phase_in,			// phase data
	input wire	[9:0]		amp_in,				// amplitude data
	input wire				freq_dv_in,			// frequency data valid signal
	input wire				phase_dv_in,		// phase data valid signal
	input wire				amp_dv_in, 			// amplitude data valid signal

	// outputs -> dds hardware
	output wire				sclk_out,			// serial clock signal to dds
	output wire				reset_out,			// reset signal to dds
	output reg				csb_out,				// chip select signal to dds
	output wire				sdio_out,			// serial data line to dds
	output wire				io_update_out,		// io update signal to dds

	// outputs -> top level entity
	output wire				dds_done_out 		// pulsed to indicate dds has finished updating
   );

//////////////////////////////////////////
// local parameters
//////////////////////////////////////////

/* state parameters */
localparam 	ST_IDLE			= 3'd0,			// wait for new data
				ST_TX 			= 3'd1,			// transmit update instruction
				ST_IO_UPDATE	= 3'd2,			// pulse io_update signal to initiate dds update
				ST_DDS_DONE		= 3'd3;			// pulse dds_done signal to indicate operation completion

//////////////////////////////////////////
// internal structures
//////////////////////////////////////////

/* input data registers */
reg	[47:0]	freq = 0;						// active frequency value
reg	[13:0]	phase = 0;						// active phase value
reg	[9:0]		amp = 0;							// active amplitude value

reg				freq_dv;							// frequency data valid
reg				phase_dv;						// phase data valid
reg				amp_dv;							// amplitude data valid

/* write instructions */
wire	[63:0]	freq_wr_instr;					// frequency write instruction
wire	[31:0] 	phase_wr_instr;				// phase write instruction
wire	[31:0] 	amp_wr_instr;					// amplitude write instruction

/* transmission registers */
reg	[63:0] 	tx_data = 0;					// active data to be sent to dds
reg	[5:0]		tx_len = 0;						// length of current write instruction

/* state registers */
reg	[31:0] 	counter = 0; 					// intrastate counter
reg	[2:0] 	cur_state = ST_IDLE;			// current state
reg	[2:0] 	next_state = ST_IDLE; 		// next state

//////////////////////////////////////////
// combinational logic
//////////////////////////////////////////

/* dds control signals */
assign reset_out			= reset_in;
assign sdio_out			= tx_data[63];
assign io_update_out		= ( cur_state == ST_IO_UPDATE );

/* loop flow control */
assign dds_done_out		= ( cur_state == ST_DDS_DONE );

/* frequency, phase, and amplitude instruction words */
assign freq_wr_instr 	= {1'b0, 2'b11, 13'h01AB, freq};
assign phase_wr_instr	= {1'b0, 2'b01, 13'h01AD, {2'd0, phase}};
assign amp_wr_instr		= {1'b0, 2'b01, 13'h040C, {6'd0, amp}};

//////////////////////////////////////////
// sequential logic
//////////////////////////////////////////

/* freq data registers */
always @( posedge clk_in ) begin
	if ( freq_dv_in == 1 ) begin
		freq		<= freq_in;
		freq_dv	<= freq_dv_in;
	end
end

/* phase data registers */
always @( posedge clk_in ) begin
	if ( phase_dv_in == 1 ) begin
		phase		<= phase_in;
		phase_dv	<= phase_dv;
	end
end

/* amplitude data registers */
always @( posedge clk_in ) begin
	if ( amp_dv_in == 1 ) begin
		amp		<= amp_in;
		amp_dv	<= amp_dv_in;
	end
end

/* serial data transmission */
always @( negedge clk_in ) begin
	case ( cur_state )
		ST_IDLE: begin
			tx_data	<= 0;
			tx_len	<= 0;
		end
		ST_TX: begin
			if ( counter == 0 ) begin
				if ( freq_dv == 1 ) begin
					tx_data	<= freq_wr_instr;
					tx_len	<= 64;
				end else if ( phase_dv == 1 ) begin
					tx_data	<= phase_wr_instr;
					tx_len	<= 32;
				end else if ( amp_dv == 1 ) begin
					tx_data	<= amp_wr_instr;
					tx_len	<= 32;
				end
			end else begin
				tx_data	<= tx_data << 1;
			end
		end
	endcase
end

/* dds chip select */
always @( negedge clk_in ) begin
	case ( cur_state )
		ST_TX: begin
			if ( counter == 0 ) begin
				csb_out <= 0;
			end else if ( counter == tx_len ) begin
				csb_out <= 1;
			end
		end
		default: begin
			csb_out <= 1;
		end
	endcase
end

//////////////////////////////////////////
// modules
//////////////////////////////////////////

/* dds sclk forwarding buffer
   helps prevent clock skew issues */
ODDR2 #(
	.DDR_ALIGNMENT	("NONE"),
	.INIT				(1'b1),
	.SRTYPE			("SYNC")
) dac_clk_fwd (
	.Q					(sclk_out),
	.C0				(clk_in),
	.C1				(~clk_in),
	.CE				(1'b1),
	.D0				(1'b1), // VCC
	.D1				(1'b0), // GND
	.R					(reset_in),
	.S					( ~(cur_state == ST_TX ) )
);

//////////////////////////////////////////
// state machine
//////////////////////////////////////////

/* state sequential logic */
always @( posedge clk_in ) begin
	if ( reset_in == 1 ) begin
		cur_state <= ST_IDLE;
	end else begin
		cur_state <= next_state;
	end
end

/* state counter sequential logic */
always @( posedge clk_in ) begin
	if ( reset_in == 1 ) begin
		counter <= 0;
	end else if ( cur_state != next_state ) begin
		counter <= 0;
	end else begin
		counter <= counter + 1'b1;
	end
end

/* next state combinational logic */
always @( * ) begin
	next_state <= cur_state; // default assignment if no case and condition is satisfied
	case (cur_state)
		ST_IDLE: begin
			if ( freq_dv | phase_dv | amp_dv ) begin
				next_state <= ST_TX;
			end
		end
		ST_TX: begin
			if ( counter == tx_len ) begin
				next_state <= ST_IO_UPDATE;
			end
		end
		ST_IO_UPDATE: begin
			next_state <= ST_IDLE;
		end
		ST_DDS_DONE: begin
			next_state <= ST_IDLE;
		end
	endcase
end

endmodule
