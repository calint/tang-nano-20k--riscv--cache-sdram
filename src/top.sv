//
// RISC-V reduced rv32i for Tang Nano 9K
//
// reviewed 2024-06-25
//
`timescale 1ns / 1ps
//
`default_nettype none

module top (
    input wire rst,
    input wire clk,  // 27 MHz

    output logic [5:0] led,
    input wire uart_rx,
    output logic uart_tx,
    input wire btn1,

    output logic flash_clk,
    input  wire  flash_miso,
    output logic flash_mosi,
    output logic flash_cs_n,

    // "Magic" port names that the gowin compiler connects to the on-chip SDRAM
    output wire        O_sdram_clk,
    output wire        O_sdram_cke,
    output wire        O_sdram_cs_n,   // chip select
    output wire        O_sdram_cas_n,  // columns address select
    output wire        O_sdram_ras_n,  // row address select
    output wire        O_sdram_wen_n,  // write enable
    inout  wire [31:0] IO_sdram_dq,    // 32 bit bidirectional data bus
    output wire [10:0] O_sdram_addr,   // 11 bit multiplexed address bus
    output wire [ 1:0] O_sdram_ba,     // two banks
    output wire [ 3:0] O_sdram_dqm     // 32/4
);

  // ----------------------------------------------------------
  // -- Gowin_rPLL
  // ----------------------------------------------------------
  logic rpll_lock;
  logic rpll_clkout;

  Gowin_rPLL rpll (
      .clkin(clk),  // 27 MHz
      .clkout(rpll_clkout),  //  66 MHz
      .lock(rpll_lock)
  );

  localparam int unsigned CLOCK_FREQUENCY_HZ = 27_000_000;

  // ----------------------------------------------------------
  // -- SDRAM controller
  // ----------------------------------------------------------

  // wires between 'sdram_controller' interface and 'cache'
  wire I_sdrc_rst_n = !rst;
  wire I_sdrc_clk = clk;  // 27 MHz
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

  // ----------------------------------------------------------
  // -- ramio
  // ----------------------------------------------------------
  logic ramio_enable;
  logic [2:0] ramio_read_type;
  logic [1:0] ramio_write_type;
  logic [31:0] ramio_address;
  logic [31:0] ramio_data_in;
  logic [31:0] ramio_data_out;
  logic ramio_data_out_ready;
  logic ramio_busy;

  ramio #(
      .RamAddressBitWidth(configuration::RAM_ADDRESS_BITWIDTH),
      .RamAddressingMode(0),  // addressing 8 bit words
      .CacheLineIndexBitWidth(configuration::CACHE_LINE_INDEX_BITWIDTH),
      .CacheColumnIndexBitWidth(configuration::CACHE_COLUMN_INDEX_BITWIDTH),
      .ClockFrequencyHz(CLOCK_FREQUENCY_HZ),
      .BaudRate(configuration::UART_BAUD_RATE)
  ) ramio (
      .rst_n(!(rst || !rpll_lock || !O_sdrc_init_done)),
      .clk  (I_sdrc_clk),

      // interface
      .enable(ramio_enable),
      .read_type(ramio_read_type),
      .write_type(ramio_write_type),
      .address(ramio_address),
      .data_in(ramio_data_in),
      .data_out(ramio_data_out),
      .data_out_ready(ramio_data_out_ready),
      .busy(ramio_busy),

      .led(led[4:1]),

      .uart_tx,
      .uart_rx,

      // sdram controller wires
      // note: to preserve names for consistency, invert I_ and O_ to output and input
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

  // note: tang nano 20k has negative active chip select
  //       invert it to not modify the 'core'
  wire flash_cs;
  assign flash_cs_n = !flash_cs;

  // ----------------------------------------------------------
  // -- core
  // ----------------------------------------------------------

  core #(
      .StartupWaitCycles (configuration::STARTUP_WAIT_CYCLES),
      .FlashFromAddress  (configuration::FLASH_FROM_ADDRESS),
      .FlashTransferBytes(configuration::FLASH_TRANSFER_BYTES)
  ) core (
      .rst_n(!rst && rpll_lock && O_sdrc_init_done),
      .clk  (I_sdrc_clk),
      .led  (led[0]),

      .ramio_enable,
      .ramio_read_type,
      .ramio_write_type,
      .ramio_address,
      .ramio_data_in,
      .ramio_data_out,
      .ramio_data_out_ready,
      .ramio_busy,

      .flash_clk,
      .flash_miso,
      .flash_mosi,
      .flash_cs
  );

  assign led[5] = ~ramio_busy;

endmodule

`default_nettype wire
