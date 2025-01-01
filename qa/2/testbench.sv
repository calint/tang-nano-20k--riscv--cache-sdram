//
// sdram + cache
//
`timescale 1ns / 1ps
//
`default_nettype none

module testbench;

  localparam int unsigned RAM_ADDRESS_BIT_WIDTH = 7;

  logic rst_n;
  logic clk = 1;
  localparam int unsigned clk_tk = 36;
  always #(clk_tk / 2) clk = ~clk;

  //------------------------------------------------------------------------
  // sdram_controller
  //------------------------------------------------------------------------

  // wires between SDRAM and 'sdram_controller'
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
  wire I_sdrc_rst_n = rst_n;
  wire I_sdrc_clk = clk;
  wire I_sdram_clk = clk;
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
      // connected to SDRAM
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

  //------------------------------------------------------------------------
  // cache
  //------------------------------------------------------------------------

  // wires and logics to cache
  logic enable;
  logic [31:0] address;
  wire [31:0] data_out;
  wire data_out_ready;
  logic [31:0] data_in;
  logic [3:0] write_enable;
  wire busy;

  cache #(
      .LineIndexBitWidth (1),
      .RamAddressBitWidth(RAM_ADDRESS_BIT_WIDTH),
      .RamAddressingMode (2)
  ) cache (
      .rst_n(rst_n && O_sdrc_init_done),
      .clk,

      .enable,
      .address,
      .data_out,
      .data_out_ready,
      .data_in,
      .write_enable,
      .busy,

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

  //------------------------------------------------------------------------

  logic [31:0] address_next;

  initial begin
    $dumpfile("log.vcd");
    $dumpvars(0, testbench);

    rst_n <= 0;
    #clk_tk;
    #clk_tk;
    rst_n <= 1;
    #clk_tk;

    // wait for burst RAM to initiate
    while (!O_sdrc_init_done) #clk_tk;

    // I_sdrc_cmd_en <= 1;
    // I_sdrc_cmd <= 3'b001;  // auto-refresh
    // #clk_tk;
    // I_sdrc_cmd_en <= 0;
    // while (!O_sdrc_cmd_ack) #clk_tk;

    // $finish;

    address <= 0;
    address_next <= 0;
    #clk_tk;

    // write some data
    for (int i = 0; i < 2 ** RAM_ADDRESS_BIT_WIDTH; i = i + 1) begin
      enable <= 1;
      address <= address_next;
      address_next <= address_next + 4;
      write_enable <= 4'b1111;
      data_in <= i;
      #clk_tk;
      while (busy) #clk_tk;
    end

    // read cache miss
    address <= 4;
    write_enable <= 0;
    #clk_tk;
    assert (!data_out_ready && busy)
    else $fatal;
    while (!data_out_ready) #clk_tk;
    assert (data_out == 1)
    else $fatal;

    // read cache hit
    address <= 8;
    write_enable <= 0;
    #clk_tk;
    assert (data_out_ready && !busy)
    else $fatal;
    assert (data_out == 2)
    else $fatal;

    // write cache hit
    address <= 4;
    data_in <= 32'habcd_1234;
    write_enable <= 4'b1111;
    #clk_tk;
    assert (!busy)
    else $fatal;

    // read cache hit
    address <= 4;
    write_enable <= 0;
    #clk_tk;
    assert (data_out_ready && !busy)
    else $fatal;
    assert (data_out == 32'habcd_1234)
    else $fatal;

    // read cache miss
    address <= 64;
    write_enable <= 0;
    #clk_tk;
    assert (!data_out_ready && busy)
    else $fatal;
    while (!data_out_ready) #clk_tk;
    assert (data_out == 16)
    else $fatal;

    // read cache miss
    address <= 12;
    write_enable <= 0;
    #clk_tk;
    while (!data_out_ready) #clk_tk;
    assert (data_out == 3)
    else $fatal;

    // write cache miss -> evict dirty
    address <= 64;
    data_in <= 32'hf55e_1234;
    write_enable <= 4'b1111;
    #clk_tk;
    assert (!data_out_ready && busy)
    else $fatal;
    while (busy) #clk_tk;

    // read cache hit
    address <= 64;
    write_enable <= 0;
    #clk_tk;
    assert (data_out_ready && !busy)
    else $fatal;
    assert (data_out == 32'hf55e_1234)
    else $fatal;

    // read cache miss -> evict dirty
    address <= 4;
    write_enable <= 0;
    #clk_tk;
    assert (!data_out_ready && busy)
    else $fatal;
    while (!data_out_ready) #clk_tk;
    assert (data_out == 32'habcd_1234)
    else $fatal;

    // read cache miss -> evict not dirty
    address <= 64;
    write_enable <= 0;
    #clk_tk;
    assert (!data_out_ready && busy)
    else $fatal;
    while (!data_out_ready) #clk_tk;
    assert (data_out == 32'hf55e_1234)
    else $fatal;


    $display("");
    $display("PASSED");
    $display("");
    $finish;

  end

endmodule

`default_nettype wire
