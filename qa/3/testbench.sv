//
// cache
//
`timescale 100ps / 100ps
//
`default_nettype none

module testbench;

  localparam int unsigned RAM_ADDRESS_BIT_WIDTH = 4;

  logic rst;
  logic clk = 1;
  localparam int unsigned clk_tk = 36;
  always #(clk_tk / 2) clk = ~clk;

  // ----------------------------------------------------------
  // -- Gowin_rPLL
  // ----------------------------------------------------------
  wire rpll_lock;
  wire rpll_clkout;

  Gowin_rPLL rpll (
      .clkin(clk),  // 27 MHz
      .lock(rpll_lock),
      .clkout(rpll_clkout)  // 66 MHz
  );

  // SDRAM wires
  wire O_sdram_clk;
  wire O_sdram_cke;
  wire O_sdram_cs_n;  // chip select
  wire O_sdram_cas_n;  // columns address select
  wire O_sdram_ras_n;  // row address select
  wire O_sdram_wen_n;  // write enable
  wire [31:0] IO_sdram_dq;  // 32 bit bidirectional data bus
  wire [10:0] O_sdram_addr;  // 11 bit multiplexed address bus
  wire [1:0] O_sdram_ba;  // two banks
  wire [3:0] O_sdram_dqm;  // 32/4

  // wires between 'sdram_controller' interface and 'cache'
  wire I_sdrc_rst_n = !rst;
  wire I_sdrc_clk = clk;  // 27 MHz
  wire I_sdram_clk = rpll_clkout;  // 66 MHz
  logic I_sdrc_cmd_en;
  logic [2:0] I_sdrc_cmd;
  logic I_sdrc_precharge_ctrl;
  logic I_sdram_power_down;
  logic I_sdram_selfrefresh;
  logic [20:0] I_sdrc_addr;
  logic [3:0] I_sdrc_dqm;
  logic [31:0] I_sdrc_data;
  logic [7:0] I_sdrc_data_len;
  wire [31:0] O_sdrc_data;
  wire O_sdrc_init_done;
  wire O_sdrc_cmd_ack;

  SDRAM_Controller_HS_Top sdram_controller (
      // inferred ports connecting to SDRAM
      .O_sdram_clk,
      .O_sdram_cke,
      .O_sdram_cs_n,
      .O_sdram_cas_n,
      .O_sdram_ras_n,
      .O_sdram_wen_n,
      .O_sdram_dqm,
      .O_sdram_addr,
      .O_sdram_ba,
      .IO_sdram_dq,

      // interface
      .I_sdrc_rst_n,
      .I_sdrc_clk,
      .I_sdram_clk,
      .I_sdrc_cmd_en,
      .I_sdrc_cmd,
      .I_sdrc_precharge_ctrl,
      .I_sdram_power_down,
      .I_sdram_selfrefresh,
      .I_sdrc_addr,
      .I_sdrc_dqm,
      .I_sdrc_data,
      .I_sdrc_data_len,
      .O_sdrc_data,
      .O_sdrc_init_done,
      .O_sdrc_cmd_ack
  );


  mt48lc2m32b2 sdram (
      .Clk(O_sdram_clk),
      .Cke(O_sdram_cke),
      .Cs_n(O_sdram_cs_n),
      .Cas_n(O_sdram_cas_n),
      .Ras_n(O_sdram_ras_n),
      .We_n(O_sdram_wen_n),
      .Dq(IO_sdram_dq),
      .Addr(O_sdram_addr),
      .Ba(O_sdram_ba),
      .Dqm(O_sdram_dqm)
  );

  initial begin
    $dumpfile("log.vcd");
    $dumpvars(0, testbench);

    rst <= 1;
    #clk_tk;
    rst <= 0;

    // wait for burst RAM to initiate
    while (!O_sdrc_init_done || !rpll_lock) #clk_tk;

    I_sdrc_precharge_ctrl <= 0;
    I_sdram_power_down <= 0;
    I_sdram_selfrefresh <= 0;

    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b011;  // active
    I_sdrc_addr <= 0;
    #clk_tk;
    I_sdrc_cmd_en <= 0;
    I_sdrc_cmd <= 3'b111;  // nop
    #clk_tk;
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b100;  // write
    I_sdrc_addr <= 0;
    I_sdrc_data_len <= 7;
    I_sdrc_data <= 32'h1234_5678;
    I_sdrc_dqm <= 4'b0000;
    #clk_tk;
    I_sdrc_cmd_en <= 0;
    I_sdrc_data   <= 32'habcd_ef01;
    #clk_tk;
    I_sdrc_data <= 32'hbaba_fefe;
    #clk_tk;
    I_sdrc_data <= 32'habba_5a5a;
    #clk_tk;
    I_sdrc_data <= 32'h0234_5670;
    #clk_tk;
    I_sdrc_data <= 32'h0bcd_ef00;
    #clk_tk;
    I_sdrc_data <= 32'h0aba_fef0;
    #clk_tk;
    I_sdrc_data <= 32'h0bba_5a50;
    #clk_tk;

    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    // I_sdrc_cmd_en <= 1;
    // I_sdrc_cmd <= 3'b011;  // active
    // I_sdrc_addr <= 0;
    #clk_tk;
    I_sdrc_cmd_en <= 0;
    I_sdrc_cmd <= 3'b111;  // nop
    #clk_tk;
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b101;  // read
    I_sdrc_addr <= 0;
    I_sdrc_data_len <= 3;
    #clk_tk;
    I_sdrc_cmd_en <= 0;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;

    $finish;
  end

endmodule

`default_nettype wire
