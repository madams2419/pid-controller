`timescale 1ns / 1ps
`include "parameters.vh"

// ====================================================================
// PID Controller
// ====================================================================
// Dope pid controller module.
// ====================================================================

// TODO
// * figure out channel activation shit
// * add overflow checking to osf


// TODO
// 2. figure out OSF init set
// 2. compartmentalize PID pipeline
// 3  change naming (name all internal data differently, dout and din for outputs only)
// 3. check all params (change modules to include ep_map instead of params header)
// 3. check addresses
// 4. check overflow in all modules
// 4. Implement PID clear and OSF clear
// 5. decide what to do with PID lock en 
// 5. Implement OSF write constant or constant mode
// 6. add adc state write handling to adc controller
// 7. channel deactive to act as reset
// 8. opp write init function
// 9. convert all operators to logical ( double symbol )

module pid_controller (
    // Inputs <- Opal Kelly PLL
    input wire                  sys_clk_in,
    input wire                  adc_clk_in,

    // Inputs <- ADC (AD7608)
    input wire                  adc_busy_in,
    input wire                  adc_data_a_in,
    input wire                  adc_data_b_in,

    // Outputs -> ADC (AD7608)
    output wire [W_ADC_OS-1:0]  adc_os_out,
    output wire                 adc_convst_out,
    output wire                 adc_reset_out,
    output wire                 adc_sclk_out,
    output wire                 adc_n_cs_out,

    // Outputs -> DAC (DAC8568)
    output wire                 dac_nldac_out,
    output wire                 dac_nsync_out,
    output wire                 dac_sclk_out,
    output wire                 dac_din_out,
    output wire                 dac_nclr_out,

    // Outputs -> DDS (AD9912)
    output wire [N_DDS-1:0]     dds_sclk_out,
    output wire [N_DDS-1:0]     dds_reset_out,
    output wire [N_DDS-1:0]     dds_csb_out,
    output wire [N_DDS-1:0]     dds_sdio_out,
    output wire [N_DDS-1:0]     dds_io_update_out,

    // Outputs -> Breakout Board
    output wire                 obuf_en_out = 1'b0, // active low

    // Inouts <-> Frontpanel Host Interface
    input wire  [7:0]           hi_in,
    output wire [1:0]           hi_out,
    inout wire  [15:0]          hi_inout,
    inout wire                  hi_aa,

    output wire                 i2c_sda,
    output wire                 i2c_scl,
    output wire                 hi_muxsel
    );

//--------------------------------------------------------------------
// Frontpanel Interface
//--------------------------------------------------------------------
wire sys_rst;
wire adc_cstart;
wire wr_en;
wire dac_ref_set;
wire [N_CHAN-1:0] opf_inject;
wire [W_EP-1:0] wr_addr;
wire [W_EP-1:0] wr_chan;
wire [W_EP*3-1:0] wr_data;

frontpanel_interface #(
    .N_LOG          (N_ADC),
    .W_LCHAN        (W_SRC_SEL),
    .W_LDATA        (W_ADC_DATA),
    .W_EP           (W_EP))
fp_intf (
    .adc_clk        (adc_clk),
    .sys_clk        (sys_clk_in),
    .log_dv         (pid_pipe.osf_dv),
    .log_chan       (pid_pipe.osf_chan),
    .log_data       (pid_pipe.osf_data),
    .sys_rst        (sys_rst),
    .adc_cstart     (adc_cstart),
    .wr_en          (wr_en),
    .dac_ref_set    (dac_ref_set),
    .opf_inject     (opf_inject),
    .wr_addr        (wr_addr),
    .wr_chan        (wr_chan),
    .wr_data        (wr_data),
    .hi_in          (hi_in),
    .hi_out         (hi_out),
    .hi_inout       (hi_inout),
    .hi_aa          (hi_aa),
    .i2c_sda        (i2c_sda),
    .i2c_scl        (i2c_sel),
    .hi_muxsel      (hi_muxsel)
);

//--------------------------------------------------------------------
// ADC Input
//--------------------------------------------------------------------
wire adc_dv;
wire [W_ADC_OS-1:0] adc_os;
wire [W_SRC_SEL-1:0] adc_src_a;
wire [W_SRC_SEL-1:0] adc_src_b;
wire [W_ADC_DATA-1:0] adc_data_a;
wire [W_ADC_DATA-1:0] adc_data_b;

wire adc_sync_dv;
wire [W_SRC_SEL-1:0] adc_sync_src;
wire [W_ADC_DATA-1:0] adc_sync_data;

// ADC controller
adc_controller #(
    .W_OUT          (W_ADC_DATA),
    .N_CHAN         (N_ADC),
    .W_CHS          (W_ADC_CHS),
    .W_OS           (W_ADC_OS))
adc_cntrl (
    .clk_in         (adc_clk_in),
    .reset_in       (sys_rst),
    .busy_in        (adc_busy_in),
    .data_a_in      (adc_data_a_in),
    .data_b_in      (adc_data_b_in),
    .os_in          (adc_os),
    .cstart_in      (adc_cstart),
    .os_out         (adc_os_out),
    .convst_out     (adc_convst_out),
    .reset_out      (adc_reset_out),
    .sclk_out       (adc_sclk_out),
    .n_cs_out       (adc_n_cs_out),
    .dv_out         (adc_dv),
    .chan_a_out     (adc_src_a),
    .chan_b_out     (adc_src_b),
    .data_a_out     (adc_data_a),
    .data_b_out     (adc_data_b)
    );

// Clock synchronizer
clk_sync #(
    .W_DATA         (W_ADC_DATA),
    .W_CHS          (W_ADC_CHS),
    .N_ADC          (N_ADC))
csync (
    .sys_clk_in     (sys_clk_in),
    .reset_in       (sys_rst),
    .dv_in          (adc_dv),
    .chan_a_in      (adc_src_a),
    .chan_b_in      (adc_src_b),
    .data_a_in      (adc_data_a),
    .data_b_in      (adc_data_b),
    .dv_out         (adc_sync_dv),
    .chan_out       (cs_src),
    .data_out       (cs_data)
    );

//--------------------------------------------------------------------
// PID Pipeline
//--------------------------------------------------------------------
wire pid_dv;
wire [W_EP-1:0] pid_chan;
wire [W_COMP-1:0] pid_data;

pid_pipeline #(
    .W_SRC          (W_ADC_CHS),
    .W_CHAN         (W_OUT_CHS),
    .N_CHAN         (N_OUT),
    .W_DATA_IN      (W_ADC_DATA),
    .W_DATA_OUT     (W_MAX_OUT),
    .W_WR_ADDR      (W_WR_ADDR),
    .W_WR_CHAN      (W_WR_CHAN),
    .W_WR_DATA      (W_WR_DATA),
    .W_COMP         (W_COMP),
    .W_OSF_OS       (W_OSF_OS),
    .W_OPP_MULT     (W_OPP_MULT),
    .W_OPP_RS       (W_OPP_RS))
pid_pipe (
    .clk_in         (sys_clk_in),
    .rst_in         (sys_rst),
    .dv_in          (adc_sync_dv),
    .src_in         (adc_sync_src),
    .data_in        (adc_sync_data),
    .wr_en          (wr_en),
    .wr_addr        (wr_addr),
    .wr_chan        (wr_chan),
    .wr_data        (wr_data),
    .dv_out         (pid_dv),
    .chan_out       (pid_chan),
    .data_out       (pid_data)
);

//--------------------------------------------------------------------
// DAC Output
//--------------------------------------------------------------------
wire pid_dac_dv = (pid_chan < N_DAC) ? pid_dv : 0;
wire pid_dac_chan = pid_chan[W_DAC_CHS-1:0];
wire pid_dac_data = pid_data[W_DAC_DATA-1:0];

wire diq_dv;
wire [W_DAC_CHS-1:0] diq_chan;
wire [W_DAC_DATA-1:0] diq_data;
wire dac_wr_done;

// DAC instruction queue
fifo_19 dac_instr_queue (
    .clk    (sys_clk_in),
    .rst    (sys_rst),
    .din    ({pid_dac_chan, pid_dac_data)),
    .wr_en  (pid_dac_dv),
    .rd_en  (dac_wr_done),
    .dout   ({diq_chan, diq_data}),
    .valid  (diq_dv)
    );

// DAC controller
dac_controller #(
    .W_DATA         (W_DAC_DATA),
    .W_CHS          (W_DAC_CHS),
    .N_CHAN         (N_DAC))
dac_cntrl (
    .clk_in         (sys_clk_in),
    .reset_in       (sys_rst),
    .ref_set_in     (dac_ref_set),
    .data_in        (diq_data),
    .channel_in     (diq_chan),
    .dv_in          (diq_dv),
    .nldac_out      (dac_nldac_out),
    .nsync_out      (dac_nsync_out),
    .sclk_out       (dac_sclk_out),
    .din_out        (dac_din_out),
    .nclr_out       (dac_nclr_out),
    .wr_done_out    (dac_wr_done)
    );

//--------------------------------------------------------------------
// DDS Output
//--------------------------------------------------------------------
generate
for ( i = 0; i < N_DDS; i = i + 1 ) begin : dds_array
    localparam F = FREQ0_ADDR + i;  // frequency absolute index
    localparam P = PHASE0_ADDR + i; // phase absolute index
    localparam A = AMP0_ADDR + i;       // amplitude absolute index

    pid_freq_dv[i] = (pid_chan == F) ? pid_dv : 0;
    pid_phase_dv[i] = (pid_chan == P) ? pid_dv : 0;
    pid_amp_dv[i] = (pid_chan == A) ? pid_dv : 0;

    dds_controller dds_cntrl (
        .clk_in         (sys_clk_in),
        .reset_in       (sys_rst),
        .freq_in        (pid_data[W_FREQ_DATA-1:0]),
        .phase_in       (pid_data[W_PHASE_DATA-1:0]),
        .amp_in         (pid_data[W_AMP_DATA-1:0]),
        .freq_dv_in     (pid_freq_dv),
        .phase_dv_in    (pid_phase_dv),
        .amp_dv_in      (pid_amp_dv),
        .sclk_out       (dds_sclk_out[i]),
        .reset_out      (dds_reset_out[i]),
        .csb_out        (dds_csb_out[i]),
        .sdio_out       (dds_sdio_out[i]),
        .io_update_out  (dds_io_update_out[i]),
    );
end
endgenerate

endmodule
