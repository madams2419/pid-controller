`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:   14:32:40 12/15/2014
// Design Name:   pid_controller
// Module Name:   Y:/Documents/MIST/pid_controller/pid_controller_tf.v
// Project Name:  pid_controller
// Target Device:
// Tool versions:
// Description:
//
// Verilog Test Fixture created by ISE for module: pid_controller
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
////////////////////////////////////////////////////////////////////////////////

module pid_controller_tf;
	// Parameters
	localparam	W_DATA	= 18;
	localparam 	N_CHAN	= 8;
	localparam	T_CYCLE 	= 85;
	localparam	TX_LEN	= W_DATA*N_CHAN/2;

	// Simulation structures
	reg signed [W_DATA-1:0]	chan[0:N_CHAN-1];
	reg [TX_LEN-1:0] 	data_a_tx;
	reg [TX_LEN-1:0] 	data_b_tx;
	reg [15:0] wire_out;

	// Inputs
	reg clk50_in;
	reg clk17_in;
	reg adc_busy_in;
	wire adc_data_a_in;
	wire adc_data_b_in;

	// Outputs
	wire [2:0] adc_os_out;
	wire adc_convst_out;
	wire adc_reset_out;
	wire adc_sclk_out;
	wire adc_n_cs_out;
	wire dac_nldac_out;
	wire dac_nsync_out;
	wire dac_sclk_out;
	wire dac_din_out;
	wire dac_nclr_out;
	wire [1:0] dds_sclk_out;
	wire [1:0] dds_reset_out;
	wire [1:0] dds_csb_out;
	wire [1:0] dds_sdio_out;
	wire [1:0] dds_io_update_out;
	wire out_buf_en;

	// Frontpanel
	reg [7:0] hi_in;
	wire [1:0] hi_out;
	wire [15:0] hi_inout;
	wire hi_aa;

	//DEBUG
	wire signed [17:0] pid_data;
	reg signed [17:0] pid_data_reg;
	wire pid_dv;
	wire [15:0] opp_data;
	wire opp_dv;

	// Instantiate the Unit Under Test (UUT)
	pid_controller uut (
		.clk50_in(clk50_in),
		.clk17_in(clk17_in),
		.adc_busy_in(adc_busy_in),
		.adc_data_a_in(adc_data_a_in),
		.adc_data_b_in(adc_data_b_in),
		.adc_os_out(adc_os_out),
		.adc_convst_out(adc_convst_out),
		.adc_reset_out(adc_reset_out),
		.adc_sclk_out(adc_sclk_out),
		.adc_n_cs_out(adc_n_cs_out),
		.dac_nldac_out(dac_nldac_out),
		.dac_nsync_out(dac_nsync_out),
		.dac_sclk_out(dac_sclk_out),
		.dac_din_out(dac_din_out),
		.dac_nclr_out(dac_nclr_out),
		.dds_sclk_out(dds_sclk_out),
		.dds_reset_out(dds_reset_out),
		.dds_csb_out(dds_csb_out),
		.dds_sdio_out(dds_sdio_out),
		.dds_io_update_out(dds_io_update_out),
		.n_out_buf_en(out_buf_en),
		.hi_in(hi_in),
		.hi_out(hi_out),
		.hi_inout(hi_inout),
		.hi_aa(hi_aa),
		//DEBUG
		.pid_data_out(pid_data),
		.pid_dv_out(pid_dv),
		.opp_data_out(opp_data),
		.opp_dv_out(opp_dv)
	);

	//------------------------------------------------------------------------
	// Begin okHostInterface simulation user configurable  global data
	//------------------------------------------------------------------------
	parameter BlockDelayStates = 5;   // REQUIRED: # of clocks between blocks of pipe data
	parameter ReadyCheckDelay = 5;    // REQUIRED: # of clocks before block transfer before
												 //           host interface checks for ready (0-255)
	parameter PostReadyDelay = 5;     // REQUIRED: # of clocks after ready is asserted and
												 //           check that the block transfer begins (0-255)
	parameter pipeInSize = 1024;      // REQUIRED: byte (must be even) length of default
												 //           PipeIn; Integer 0-2^32
	parameter pipeOutSize = 1024;     // REQUIRED: byte (must be even) length of default
												 //           PipeOut; Integer 0-2^32

	integer k;
	reg  [7:0]  pipeIn [0:(pipeInSize-1)];
	initial for (k=0; k<pipeInSize; k=k+1) pipeIn[k] = 8'h00;

	reg  [7:0]  pipeOut [0:(pipeOutSize-1)];
	initial for (k=0; k<pipeOutSize; k=k+1) pipeOut[k] = 8'h00;

	//------------------------------------------------------------------------
	//  Available User Task and Function Calls:
	//    FrontPanelReset;                  // Always start routine with FrontPanelReset;
	//    SetWireInValue(ep, val, mask);
	//    UpdateWireIns;
	//    UpdateWireOuts;
	//    GetWireOutValue(ep);
	//    ActivateTriggerIn(ep, bit);       // bit is an integer 0-15
	//    UpdateTriggerOuts;
	//    IsTriggered(ep, mask);            // Returns a 1 or 0
	//    WriteToPipeIn(ep, length);        // passes pipeIn array data
	//    ReadFromPipeOut(ep, length);      // passes data to pipeOut array
	//    WriteToBlockPipeIn(ep, blockSize, length);    // pass pipeIn array data; blockSize and length are integers
	//    ReadFromBlockPipeOut(ep, blockSize, length);  // pass data to pipeOut array; blockSize and length are integers
	//
	//    *Pipes operate by passing arrays of data back and forth to the user's
	//    design.  If you need multiple arrays, you can create a new procedure
	//    above and connect it to a differnet array.  More information is
	//    available in Opal Kelly documentation and online support tutorial.
	//------------------------------------------------------------------------

	// generate ~17MHz clock
	always #30 clk17_in = ~clk17_in;

	// generate 50MHz clock
	always #10 clk50_in = ~clk50_in;

	// serial data channels
	assign adc_data_a_in = data_a_tx[TX_LEN-1];
	assign adc_data_b_in = data_b_tx[TX_LEN-1];

	// endpoint params
	parameter adc_os_owi					= 8'h01;
	parameter adc_cstart_ti				= 8'h53;

	parameter osf_activate_owi			= 8'h15;
	parameter osf_cycle_delay_owi		= 8'h02;
	parameter osf_log_ovr_owi			= 8'h03;
	parameter osf_update_en_owi		= 8'h04;

	parameter pid_clear_ti				= 8'h55;
	parameter pid_lock_en_owi			= 8'h17;
	parameter pid_setpoint_owi			= 8'h04;
	parameter pid_p_coef_owi			= 8'h05;
	parameter pid_i_coef_owi			= 8'h06;
	parameter pid_d_coef_owi			= 8'h07;
	parameter pid_update_en_owi		= 8'h08;

	parameter rtr_src_sel_owi			= 8'h09;
	parameter rtr_dest_sel_owi			= 8'h0a;
	parameter rtr_output_active_owi	= 8'h16;

	parameter opp_init_owi0				= 8'h0b;
	parameter opp_init_owi1				= 8'h0c;
	parameter opp_init_owi2				= 8'h0d;
	parameter opp_min_owi0				= 8'h0e;
	parameter opp_min_owi1				= 8'h0f;
	parameter opp_min_owi2				= 8'h10;
	parameter opp_max_owi0				= 8'h11;
	parameter opp_max_owi1				= 8'h12;
	parameter opp_max_owi2				= 8'h13;
	parameter opp_update_en_owi		= 8'h14;

	parameter dac_ref_set_ti			= 8'h56;

	parameter module_update_ti			= 8'h57;

	parameter sys_reset_ti				= 8'h58;

	parameter osf_bulk_data_opo		= 8'ha3;

	parameter mask							= 32'hffffffff;

	// set channel values
	initial begin
		chan[0] = 10;
		chan[1] = 2222;
		chan[2] = 3333;
		chan[3] = 4444;
		chan[4] = 5555;
		chan[5] = 6666;
		chan[6] = 7777;
		chan[7] = 8888;
	end

	// misc structures
	reg [15:0] output_init = 0;
	reg [15:0] output_min = 0;
	reg [15:0] output_max = 0;

	reg signed [15:0] setpoint = 0, p_coef = 0, i_coef = 0, d_coef = 0;
	integer error = 0, error_prev = 0, integral = 0, derivative = 0, u_expected = 0, e_count = 0;

	// dac received data
	reg [31:0] r_instr;
	wire [15:0] r_data;
	wire [3:0] r_prefix, r_control, r_address, r_feature;
	assign {r_prefix, r_control, r_address, r_data, r_feature} = r_instr;

	initial begin
		// Initialize Inputs
		clk50_in = 0;
		clk17_in = 0;
		adc_busy_in = 0;
		data_a_tx = 0;
		data_b_tx = 0;
		wire_out = 0;

		// Frontpanel reset
		FrontPanelReset;

		// System reset
		ActivateTriggerIn(sys_reset_ti, 0);

		// Set ADC oversampling mode
		SetWireInValue(adc_os_owi, 0, mask);	// os = 0

		UpdateWireIns;
		ActivateTriggerIn(module_update_ti, 0);

		// Set OSF ratio and activate channel 0
		SetWireInValue(osf_activate_owi, 16'd1, mask); // set OSF[0] activation
		SetWireInValue(osf_cycle_delay_owi, 16'd0, mask); // cycle delay = 0
		SetWireInValue(osf_log_ovr_owi, 16'd0, mask); // log ovr = 0
		SetWireInValue(osf_update_en_owi, 16'd1, mask); // sensitize OSF channel 0

		UpdateWireIns;
		ActivateTriggerIn(module_update_ti, 0);


		// Set channel 0 PID params
		setpoint = 0;
		p_coef = 10;
		i_coef = 3;
		d_coef = 2;
		SetWireInValue(pid_setpoint_owi, setpoint, mask);	// setpoint = 3
		SetWireInValue(pid_p_coef_owi, p_coef, mask);	// p = 10
		SetWireInValue(pid_i_coef_owi, i_coef, mask);	// i = 3
		SetWireInValue(pid_d_coef_owi, d_coef, mask);	// d = 0
		SetWireInValue(pid_update_en_owi, 16'd1, mask);	// sensitize PID channel 0

		UpdateWireIns;
		ActivateTriggerIn(module_update_ti, 0);

		// Route input channel 0 to output channel 0 and activate output 0
		SetWireInValue(rtr_src_sel_owi, 16'd0, mask);	// router source
		SetWireInValue(rtr_dest_sel_owi, 16'd0, mask);	// router destination
		SetWireInValue(rtr_output_active_owi, 16'd1, mask);	// activate channel 0

		UpdateWireIns;
		ActivateTriggerIn(module_update_ti, 0);

		// Set channel 0 OPP params
		output_init = 500;
		output_min = 99;
		output_max = 1111;
		SetWireInValue(opp_init_owi0, output_init, mask); // set output init
		SetWireInValue(opp_min_owi0, output_min, mask); // set output min
		SetWireInValue(opp_max_owi0, output_max, mask); // set output max
		SetWireInValue(opp_update_en_owi, 16'd1, mask);	// sensitize OPP channel 0

		UpdateWireIns;
		ActivateTriggerIn(module_update_ti, 0);

		// activate pid lock 0
		SetWireInValue(pid_lock_en_owi, 16'd1, mask);
		UpdateWireIns;

		// activate adc channel 0
		SetWireInValue(osf_activate_owi, 16'd1, mask);
		UpdateWireIns;

		// trigger adc cstart
		ActivateTriggerIn(adc_cstart_ti, 0);

		fork

			// transmission simulation
			forever begin
				// wait for convst_out to pulse and then assert busy
				@(posedge adc_convst_out) begin
					@(posedge clk17_in) adc_busy_in = 1;
				end

				// set random chan[0] value
				chan[0] = $random % 1000;

				// simulate serial transmission from adc to fpga
				@(negedge adc_n_cs_out) begin
					data_a_tx = {chan[0], chan[1], chan[2], chan[3]};
					data_b_tx = {chan[4], chan[5], chan[6], chan[7]};
				end

				// wait one cycle before transmitting
				@(posedge clk17_in);

				// simulate serial data transmission
				repeat (71) begin
					@(negedge clk17_in)
					data_a_tx = data_a_tx << 1;
					data_b_tx = data_b_tx << 1;
				end

				// simulate conversion end
				#200;
				@(posedge clk17_in) adc_busy_in = 0;

			end

			// check pid value
			forever begin
				@(posedge pid_dv) begin
					pid_data_reg = pid_data;
					e_count = e_count + 1;
					error = setpoint - chan[0];
					#1;
					integral = integral + error;
					derivative = error - error_prev;
					#1;
					u_expected = (p_coef * error) + (i_coef * integral) + (d_coef * derivative);
					error_prev = error;
					#1;
					if(u_expected == pid_data_reg) begin
						$display("PID Success\t(%d, %d)\t--\tExpected: %d\tReceived: %d", error, integral, u_expected, pid_data_reg);
					end else begin
						$display("PID Failure\t(%d, %d)\t--\tExpected: %d\tReceived: %d", error, integral, u_expected, pid_data_reg);
					end
				end
			end

			// adc data receive
			forever begin
				@(negedge dac_nsync_out) begin
					repeat(32) begin
						@(negedge dac_sclk_out) begin
							r_instr = {r_instr[30:0], dac_din_out}; // shift data in
						end
					end

				end
			end

		join

		$stop;

	end

	`include "Z:/Users/mba13/pidc/ok_sim/okHostCalls.v"

	endmodule
