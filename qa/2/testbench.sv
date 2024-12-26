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

  wire clkin = clk;
  wire clkout = clk;
  wire lock = 1;

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
  wire I_sdram_clk = clkout;  // 143 MHz
  wire I_sdrc_cmd_en;
  wire [2:0] I_sdrc_cmd;
  wire I_sdrc_precharge_ctrl;
  wire I_sdram_power_down;
  wire I_sdram_selfrefresh;
  wire [20:0] I_sdrc_addr;
  wire [3:0] I_sdrc_dqm;
  wire [31:0] I_sdrc_data;
  wire [7:0] I_sdrc_data_len;
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

  logic enable;
  logic [31:0] address;
  logic [31:0] data_out;
  logic data_out_ready;
  logic [31:0] data_in;
  logic [3:0] write_enable;
  logic busy;

  cache #(
      .LineIndexBitWidth (1),
      .RamAddressBitWidth(8)
  ) cache (
      .rst_n(!rst),
      .clk,

      .enable(enable),
      .address(address),
      .data_out(data_out),
      .data_out_ready(data_out_ready),
      .data_in(data_in),
      .write_enable(write_enable),
      .busy(busy),

      // sdram controller wires
      // to preserve names for consistency, invert I_ and O_ to output and input
      //   .I_sdrc_rst_n,
      //   .I_sdrc_clk,
      //   .I_sdram_clk,
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

  initial begin
    $dumpfile("log.vcd");
    $dumpvars(0, testbench);

    rst <= 1;
    #clk_tk;
    rst <= 0;

    // wait for burst RAM to initiate
    while (!O_sdrc_init_done || !lock) #clk_tk;

    // keep enabled
    enable <= 1;

    // read; cache miss
    while (busy) #clk_tk;
    address <= 4;
    write_enable <= 4'b1111;
    data_in <= 32'h1234_5678;
    #clk_tk;

    while (busy) #clk_tk;
    write_enable <= 0;
    address <= 4;
    #clk_tk;

    assert (data_out == 32'h1234_5678 && data_out_ready)
    else $error();

    while (busy) #clk_tk;
    address <= 70;
    write_enable <= 4'b1111;
    data_in <= 32'habcd_ef01;
    #clk_tk;

    while (busy) #clk_tk;
    address <= 4;
    write_enable <= '0;
    while (!data_out_ready) #clk_tk;

    assert (data_out == 32'h1234_5678)
    else $error();

    $finish;
  end

endmodule

`default_nettype wire
