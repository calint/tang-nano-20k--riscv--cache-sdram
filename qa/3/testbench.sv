//
// SDRAM
//   data width=32  bank width=2  row width=11  column width=8
//   tRP=3  tRFC=9  tMRD=3  tRCD=2  LWR=2  CL=2
//
`timescale 1ns / 1ps
//
`default_nettype none

module testbench;

  logic rst;
  logic clk = 1;
  localparam int unsigned clk_tk = 10;
  always #(clk_tk / 2) clk = ~clk;

  //------------------------------------------------------------------------
  // sdram
  //------------------------------------------------------------------------

  // 'sdram' wires between 'sdram' and 'sdram_controller'
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
  // sdram_controller
  //------------------------------------------------------------------------

  // register and wires to 'sdram_controller'
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

  //------------------------------------------------------------------------

  localparam SDRAM_BANKS_WIDTH = 2;
  localparam SDRAM_ROWS_WIDTH = 11;
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

    I_sdrc_precharge_ctrl = 1;
    I_sdram_power_down = 0;
    I_sdram_selfrefresh <= 0;

    // wait for SDRAM to initiate
    while (!O_sdrc_init_done) #clk_tk;

    // I_sdram_selfrefresh <= 1;
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b001;  // auto-refresh
    #clk_tk;
    I_sdrc_cmd_en <= 0;
    while (!O_sdrc_cmd_ack) #clk_tk;
    // I_sdram_selfrefresh <= 0;
    // #1000;

    // -----------------------------------------------------------------------
    // activate and write 8 data to bank 0 row 0
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b011;  // active
    I_sdrc_addr <= 0;  // activate bank 0 row 0
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;
    assert (O_sdrc_cmd_ack)
    else $fatal;

    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b100;  // write
    I_sdrc_addr <= 0;  // bank 0, row 0
    I_sdrc_data_len <= 7;
    I_sdrc_dqm <= 4'b0000;
    I_sdrc_data <= 32'h1234_5678;
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    I_sdrc_data   <= 32'habcd_ef01;
    #clk_tk;

    I_sdrc_data <= 32'h5678_1010;
    #clk_tk;

    I_sdrc_data <= 32'habcd_fefe;
    #clk_tk;

    I_sdrc_data <= 32'habce_ef01;
    #clk_tk;

    I_sdrc_data <= 32'habcd_ef02;
    #clk_tk;

    I_sdrc_data <= 32'habcd_ef03;
    #clk_tk;

    I_sdrc_data <= 32'habcd_ef04;
    #clk_tk;

    // wait for ack
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    assert (O_sdrc_cmd_ack)
    else $fatal;

    // -----------------------------------------------------------------------
    // activate and write 8 data to bank 0 row 1
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b011;  // active
    I_sdrc_addr <= 'h1_00;  // bank 0, row 1
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;
    assert (O_sdrc_cmd_ack)
    else $fatal;

    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b100;  // write
    I_sdrc_addr <= 32'h100;
    I_sdrc_data_len <= 7;
    I_sdrc_dqm <= 4'b0000;
    I_sdrc_data <= 32'h1010_2020;
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    I_sdrc_data   <= 32'habcd_ef01;
    #clk_tk;

    I_sdrc_data <= 32'h5678_1010;
    #clk_tk;

    I_sdrc_data <= 32'habcd_fefe;
    #clk_tk;

    I_sdrc_data <= 32'habce_ef01;
    #clk_tk;

    I_sdrc_data <= 32'habcd_ef02;
    #clk_tk;

    I_sdrc_data <= 32'habcd_ef03;
    #clk_tk;

    I_sdrc_data <= 32'habcd_ef04;
    #clk_tk;

    // wait for ack
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    assert (O_sdrc_cmd_ack)
    else $fatal;

    // -----------------------------------------------------------------------
    // activate and write 1 data to bank 0 row 2 
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b011;  // active
    I_sdrc_addr <= 'h2_00;  // bank 0, row 2
    #clk_tk;
    I_sdrc_cmd_en <= 0;
    #clk_tk;
    assert (O_sdrc_cmd_ack)
    else $fatal;

    // avoid tRAS violation ??
    #clk_tk;

    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b100;  // write
    I_sdrc_addr <= 32'h204;
    I_sdrc_data_len <= 0;
    I_sdrc_dqm <= 4'b0000;
    I_sdrc_data <= 32'h1e1f_2a2b;
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;

    // wait for ack
    #clk_tk;
    #clk_tk;
    #clk_tk;
    assert (O_sdrc_cmd_ack)
    else $fatal;

    // -----------------------------------------------------------------------
    // activate and read 8 data from bank 0 row 0
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b011;  // active
    I_sdrc_addr <= 0;  // bank 0, row 0
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;
    assert (O_sdrc_cmd_ack)
    else $fatal;

    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b101;  // read
    I_sdrc_addr <= 0;  // bank 0 row 0 col 0
    I_sdrc_data_len <= 7;
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;

    #clk_tk;

    #clk_tk;

    // data arrives
    #clk_tk;  // 1st
    assert (O_sdrc_data == 'h1234_5678)
    else $fatal;

    #clk_tk;  // 2nd

    #clk_tk;  // 3rd

    #clk_tk;  // 4th

    #clk_tk;  // 5th

    #clk_tk;  // 6th

    #clk_tk;  // 7th

    #clk_tk;  // 8th


    // -----------------------------------------------------------------------
    // activate and read 4 data from bank 0 row 1
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b011;  // active
    I_sdrc_addr <= 32'h100;
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;

    // read 4 data starting from column 0
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b101;  // read
    I_sdrc_addr <= 'h1_00;  // bank 0, row 1, column 0
    I_sdrc_data_len <= 3;
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;

    #clk_tk;
    #clk_tk;

    // data arrives
    #clk_tk;
    assert (O_sdrc_data == 'h10102020)
    else $fatal;

    #clk_tk;

    #clk_tk;

    #clk_tk;
    assert (O_sdrc_data == 'habcd_fefe)
    else $fatal;


    // -----------------------------------------------------------------------
    // activate and read 1 data from bank 0 row 0
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b011;  // active
    I_sdrc_addr <= 32'h000;
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;

    // tRCD (Row to Column Delay): The minimum time between an ACTIVE command and a READ or WRITE command.
    // CAS Latency (CL)
    // note: tRAS violation without the delay
    #clk_tk;
    #clk_tk;

    // read 1 data starting from column 1
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b101;  // read
    I_sdrc_addr <= 'h1_01;  // bank 0, row 1, column 0
    I_sdrc_data_len <= 0;
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;

    #clk_tk;
    #clk_tk;

    // data arrives
    #clk_tk;
    assert (O_sdrc_data == 'habcd_ef01)
    else $fatal;

    // -----------------------------------------------------------------------
    // activate and read 1 data from bank 0 row 1
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b011;  // active
    I_sdrc_addr <= 32'h100;
    #clk_tk;
    I_sdrc_cmd_en <= 0;
    #clk_tk;

    // tRCD (Row to Column Delay): The minimum time between an ACTIVE command and a READ or WRITE command.
    // note: tRAS violation without the delay
    #clk_tk;
    #clk_tk;

    // read 1 data starting from column 2
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b101;  // read
    I_sdrc_addr <= 'h1_02;  // bank 0, row 1, column 0
    I_sdrc_data_len <= 0;
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;

    #clk_tk;
    #clk_tk;

    // data arrives
    #clk_tk;
    assert (O_sdrc_data == 'h5678_1010)
    else $fatal;

    // -----------------------------------------------------------------------
    // activate and write 1 data to bank 0 row 1
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b011;  // active
    I_sdrc_addr <= 32'h1fc;
    #clk_tk;
    I_sdrc_cmd_en <= 0;
    #clk_tk;

    // tRCD (Row to Column Delay): The minimum time between an ACTIVE command and a READ or WRITE command.
    // note: tRAS violation without the delay
    #clk_tk;
    #clk_tk;

    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b100;  // write
    I_sdrc_addr <= 32'h1fc;
    I_sdrc_data_len <= 0;
    I_sdrc_dqm <= 4'b0000;
    I_sdrc_data <= 32'h1a1e_2121;
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;

    #clk_tk;
    #clk_tk;
    #clk_tk;

    // -----------------------------------------------------------------------
    // test cache like operation
    // write dirty line and read new data from new row
    //

    // evict
    // -----------------------------------------------------------------------
    // activate and write 8 data to bank 0 row 0
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b011;  // active
    I_sdrc_addr <= 0;  // activate bank 0 row 0
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;
    assert (O_sdrc_cmd_ack)
    else $fatal;

    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b100;  // write
    I_sdrc_addr <= 0;  // bank 0, row 0
    I_sdrc_data_len <= 7;
    I_sdrc_dqm <= 4'b0000;
    I_sdrc_data <= 32'h1234_5678;
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    I_sdrc_data   <= 32'habcd_ef01;
    #clk_tk;

    I_sdrc_data <= 32'h5678_1010;
    #clk_tk;

    I_sdrc_data <= 32'habcd_fefe;
    #clk_tk;

    I_sdrc_data <= 32'habce_ef01;
    #clk_tk;

    I_sdrc_data <= 32'habcd_ef02;
    #clk_tk;

    I_sdrc_data <= 32'habcd_ef03;
    #clk_tk;

    I_sdrc_data <= 32'habcd_ef04;
    #clk_tk;

    // wait for ack
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    assert (O_sdrc_cmd_ack)
    else $fatal;

    // fetch
    // -----------------------------------------------------------------------
    // activate and read 8 data from bank 0 row 1
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b011;  // active
    I_sdrc_addr <= 32'h100;
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;

    // read 4 data starting from column 0
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b101;  // read
    I_sdrc_addr <= 'h1_00;  // bank 0, row 1, column 0
    I_sdrc_data_len <= 7;
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;

    #clk_tk;
    #clk_tk;

    // data arrives
    #clk_tk;
    assert (O_sdrc_data == 'h10102020)
    else $fatal;

    #clk_tk;

    #clk_tk;

    #clk_tk;
    assert (O_sdrc_data == 'habcd_fefe)
    else $fatal;

    #clk_tk;

    #clk_tk;

    #clk_tk;

    #clk_tk;
    assert (O_sdrc_data == 'habcd_ef04)
    else $fatal;

    // fetch from same row (note: result expected to be xxxxxxxx. testing for timing violations)
    // -----------------------------------------------------------------------
    // activate and read 8 data from bank 0 row 1
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b011;  // active
    I_sdrc_addr <= 32'h100;
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;

    // read 4 data starting from column 0
    I_sdrc_cmd_en <= 1;
    I_sdrc_cmd <= 3'b101;  // read
    I_sdrc_addr <= 'h1_08;  // bank 0, row 1, column 0
    I_sdrc_data_len <= 7;
    #clk_tk;

    I_sdrc_cmd_en <= 0;
    #clk_tk;

    #clk_tk;
    #clk_tk;

    // data arrives
    #clk_tk;

    #clk_tk;

    #clk_tk;

    #clk_tk;

    #clk_tk;

    #clk_tk;

    #clk_tk;

    #clk_tk;
    // -----------------------------------------------------------------------

    $display("");
    $display("PASSED");
    $display("");
    $finish;

  end

endmodule

`default_nettype wire
