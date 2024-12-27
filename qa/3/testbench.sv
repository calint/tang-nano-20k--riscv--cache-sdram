//
// cache
//
`timescale 1ns / 1ps
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
  wire rpll_clkoutp;

  Gowin_rPLL rpll (
      .clkin(clk),  // 27 MHz
      .lock(rpll_lock),
      .clkoutp(rpll_clkoutp)  // 66 MHz phased 180 deg
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
  wire I_sdram_clk = clk;  // 66 MHz
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

  // sdram sdram (
  //     .SDRAM_DQ(IO_sdram_dq),    // Bidirectional data bus
  //     .SDRAM_A(O_sdram_addr),     // Address bus
  //     .SDRAM_DQM(O_sdram_dqm),   // High/low byte mask
  //     .SDRAM_BA(O_sdram_ba),    // Bank select (single bits)
  //     .SDRAM_nCS(O_sdram_cs_n),   // Chip select, neg triggered
  //     //output wire                  SDRAM_nWE,   // Write enable, neg triggered
  //     .SDRAM_nRAS(O_sdram_ras_n),  // Select row address, neg triggered
  //     .SDRAM_nCAS(O_sdram_cas_n),  // Select column address, neg triggered
  //     .SDRAM_CKE(O_sdram_cke),   // Clock enable
  //     .SDRAM_CLK(O_sdram_clk)    // Chip clock
  // );


  localparam SDRAM_BANKS = 2;
  localparam SDRAM_ROWS_WIDTH = 12;
  localparam SDRAM_COLS_WIDTH = 8;

  reg [32-1:0] address = -1;
  reg [32-8-1:0] previous_active_bank_row = -1;
  reg [7:0] data;
  initial begin
    $dumpfile("log.vcd");
    $dumpvars(0, testbench);

    rst <= 1;
    #clk_tk;
    rst <= 0;

    // wait for burst RAM to initiate
    while (!O_sdrc_init_done || !rpll_lock) #clk_tk;

    I_sdrc_precharge_ctrl = 0;
    I_sdram_power_down = 0;
    I_sdram_selfrefresh = 0;

    for (int i = 0; i < 1024; i += 4 * 8) begin
      address = i;
      $display(" *** write address: %h", address);
      if (address[32-1-:24-SDRAM_ROWS_WIDTH] == previous_active_bank_row) begin
      end else begin
        $display(" *** activate: %h", address[32-1-:24-SDRAM_ROWS_WIDTH]);
        I_sdrc_cmd_en <= 1;
        I_sdrc_cmd <= 3'b011;  // active
        I_sdrc_addr <= address[32-1-:24];
        previous_active_bank_row <= address[32-1-:24];
        #clk_tk;
      end
      I_sdrc_cmd_en <= 1;
      I_sdrc_cmd <= 3'b100;  // write
      I_sdrc_addr <= address;
      I_sdrc_data_len <= 7;
      data = i & 8'hff;
      I_sdrc_data <= {4{data}};
      I_sdrc_dqm  <= 4'b0000;
      #clk_tk;
      I_sdrc_cmd_en <= 0;
      for (int j = 1; j < 8; j++) begin
        data = (i + j) & 8'hff;
        I_sdrc_data <= {4{data}};
        #clk_tk;
      end
    end

    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    // I_sdrc_cmd_en <= 1;
    // I_sdrc_cmd <= 3'b011;  // active
    // I_sdrc_addr <= 0;
    // #clk_tk;
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
