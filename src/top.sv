//
// RISC-V reduced RV32I for Tang Nano 20K
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

    output logic sd_clk,
    inout wire sd_cmd,  // MOSI
    inout wire [3:0] sd_dat,  // 0: MISO, 3: CS_n

    // "magic" port names that the Gowin EDA connects to the on-chip SDRAM
    output wire        O_sdram_clk,    // clock
    output wire        O_sdram_cke,    // clock enable
    output wire        O_sdram_cs_n,   // chip select
    output wire        O_sdram_cas_n,  // columns address select
    output wire        O_sdram_ras_n,  // row address select
    output wire        O_sdram_wen_n,  // write enable
    inout  wire [31:0] IO_sdram_dq,    // 32 bit bidirectional data bus
    output wire [10:0] O_sdram_addr,   // 11 bit multiplexed address bus
    output wire [ 1:0] O_sdram_ba,     // bank address
    output wire [ 3:0] O_sdram_dqm     // data mask (byte enable)
);

  // ----------------------------------------------------------
  // -- rPLL
  // ----------------------------------------------------------

  // wires to 'sdram_controller'
  wire rpll_clk_out;
  wire rpll_lock;

  Gowin_rPLL rPLL (
      .clkin(clk),  // 27 MHz
      .clkout(rpll_clk_out),  // 60 MHz
      .lock(rpll_lock)
  );

  // ----------------------------------------------------------
  // -- sdram_controller
  // ----------------------------------------------------------

  // wires between 'sdram_controller' interface and 'ramio'
  wire I_sdrc_rst_n = !rst && rpll_lock;
  wire I_sdrc_clk = rpll_clk_out;
  wire I_sdram_clk = rpll_clk_out;
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
      // inferred ports connecting SDRAM
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

  // wires between 'ramio' and 'core'
  wire ramio_enable;
  wire [2:0] ramio_read_type;
  wire [1:0] ramio_write_type;
  wire [31:0] ramio_address;
  wire [31:0] ramio_data_in;
  wire [31:0] ramio_data_out;
  wire ramio_data_out_ready;
  wire ramio_busy;

  //  connect a led to 'busy' signal
  assign led[5] = ~ramio_busy;

  // wires related to SD card
  wire sd_cs_n;  // unused
  assign sd_dat[3:1] = 3'b011;
  // note: in SPI mode, the DAT3 pin is repurposed as the Chip Select (CS) pin.
  //       to enter SPI mode at power-up, the host must hold DAT3/CS low while
  //       sending at least 74 clock pulses

  ramio #(
      .RamAddressBitwidth(configuration::RAM_ADDRESS_BITWIDTH),
      .RamAddressingMode(configuration::RAM_ADDRESSING_MODE),
      .CacheLineIndexBitwidth(configuration::CACHE_LINE_INDEX_BITWIDTH),
      .CacheColumnIndexBitwidth(configuration::CACHE_COLUMN_INDEX_BITWIDTH),
      .ClockFrequencyHz(configuration::CPU_FREQUENCY_HZ),
      .BaudRate(configuration::UART_BAUD_RATE),
      .SDCardSimulate(0),
      .SDCardClockDivider(0),  // 0: works at 54 MHz and 60 MHz (1 does not)
      .SDRAMRefreshIntervalMs(64),  // 4096 refreshes during every 64 ms according to SDRAM spec
      .SDRAMRefreshCountDuringInterval(4096),
      .SDRAMClockFrequencyHz(configuration::CPU_FREQUENCY_HZ),
      .SDRAMRefreshRequirementsMarginPercent(10)  // note: 0 fails 'qa/end-to-end/test.sh' at 60 MHz
  ) ramio (
      .rst_n(!rst && O_sdrc_init_done),
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

      .sd_cs_n,
      .sd_clk,
      .sd_mosi(sd_cmd),
      .sd_miso(sd_dat[0]),

      // sdram controller wires
      // note: to preserve names for consistency, the I_* and O_* have inverted meaning
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

  // ----------------------------------------------------------
  // -- core
  // ----------------------------------------------------------

  core #(
      .StartupWaitCycles(configuration::STARTUP_WAIT_CYCLES),
      .FlashTransferFromAddress(configuration::FLASH_TRANSFER_FROM_ADDRESS),
      .FlashTransferByteCount(configuration::FLASH_TRANSFER_BYTE_COUNT)
  ) core (
      .rst_n(!rst && O_sdrc_init_done),
      .clk  (I_sdrc_clk),

      .led(led[0]),

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
      .flash_cs_n
  );

endmodule

`default_nettype wire
