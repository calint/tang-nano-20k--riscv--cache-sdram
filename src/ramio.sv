//
// Interface to RAM, UART and LEDs
//
// reviewed 2024-06-25
//
`timescale 1ns / 1ps
//
`default_nettype none
//`define DBG
//`define INFO

module ramio #(
    parameter int unsigned RamAddressBitwidth = 10,
    // passed to 'cache': backing burst RAM depth

    parameter int unsigned RamAddressingMode = 3,
    // passed to 'cache': address refers to:
    //  0: byte, 1: half word, 2: word, 3: double word

    parameter int unsigned CacheColumnIndexBitwidth = 3,
    // 2 ^ 3 = 8 entries (32 B) per cache line

    parameter int unsigned CacheLineIndexBitwidth = 1,
    // passed to 'cache': 2 ^ value * 32 B cache size

    parameter int unsigned AddressBitwidth = 32,
    // client address bit width

    parameter int unsigned DataBitwidth = 32,
    // client data bit width

    parameter int unsigned ClockFrequencyHz = 30_000_000,
    // passed to 'uartrx' and 'uarttx'

    parameter int unsigned BaudRate = 115200,
    // passed to 'uartrx' and 'uarttx'

    parameter int unsigned AddressLed = 32'hffff_fffc,
    // 4 LEDs in the lower nibble of the int
    // note: 0 is led on, 1 is led off

    parameter int unsigned AddressUartOut = 32'hffff_fff8,
    // note: returns -1 if idle

    parameter int unsigned AddressUartIn = 32'hffff_fff4,
    // note: is set to -1 after read

    parameter int unsigned AddressSDCardBusy = 32'hffff_fff0,

    parameter int unsigned AddressSDCardReadSector = 32'hffff_ffec,

    parameter int unsigned AddressSDCardNextByte = 32'hffff_ffe8,

    parameter int unsigned AddressSDCardStatus = 32'hffff_ffe4,

    parameter int unsigned AddressSDCardWriteSector = 32'hffff_ffe0,

    parameter int unsigned AddressIOPortsStart = 32'hffff_ffe0,
    // where mapping of I/O ports start

    parameter bit SDCardSimulate = 0,
    // 1: if in simulation mode shortening delay cycles

    parameter int unsigned SDCardClockDivider = 0,
    // 0 when clk = 30 MHz, 54 MHz, 60 MHz

    // refresh SDRAM parameters
    parameter int unsigned SDRAMRefreshIntervalMs = 64,
    parameter int unsigned SDRAMRefreshCountDuringInterval = 4096,
    parameter int unsigned SDRAMClockFrequencyHz = 54_000_000,
    parameter int unsigned SDRAMRefreshRequirementsMarginPercent = 10
) (
    input wire rst_n,
    input wire clk,

    input wire enable,

    input wire [2:0] read_type,
    // b000 not a read; bit[2] flags sign extended or not, b01: byte, b10: half word, b11: word

    input wire [1:0] write_type,
    // b00 not a write; b01: byte, b10: half word, b11: word

    input wire [AddressBitwidth-1:0] address,
    // byte address (type aligned)

    input wire [DataBitwidth-1:0] data_in,
    // byte, half word, word

    output logic [DataBitwidth-1:0] data_out,
    // data at 'address' according to 'read_type'

    output logic data_out_ready,

    output logic busy,

    output logic [3:0] led,
    // I/O mapping of LEDs

    output logic uart_tx,
    input  wire  uart_rx,

    // SD card wiring: prefix 'sd_'
    output wire sd_cs_n,
    output wire sd_clk,
    output wire sd_mosi,
    input  wire sd_miso,

    // wires to sdram_controller
    // note: to preserve names for consistency, invert I_ and O_ to output and input
    // output wire I_sdrc_rst_n,
    // output wire I_sdrc_clk,
    // output wire I_sdram_clk,
    output logic I_sdrc_cmd_en,
    output logic [2:0] I_sdrc_cmd,
    output logic I_sdrc_precharge_ctrl,
    output logic I_sdram_power_down,
    output logic I_sdram_selfrefresh,
    output logic [20:0] I_sdrc_addr,
    output logic [3:0] I_sdrc_dqm,
    output logic [31:0] I_sdrc_data,
    output logic [7:0] I_sdrc_data_len,
    input wire [31:0] O_sdrc_data,
    input wire O_sdrc_init_done,
    input wire O_sdrc_cmd_ack
);

  logic cache_enable;
  // enables / disables 'cache' RAM operation

  wire [DataBitwidth-1:0] cache_data_out;
  wire cache_data_out_ready;
  wire cache_busy;

  logic [AddressBitwidth-1:0] cache_address;
  // 4-byte aligned address to RAM data

  logic [DataBitwidth-1:0] cache_data_in;
  // data for byte enabled write of 4-byte word

  logic [3:0] cache_write_enable;
  // bytes in the word enabled for writing; default 4-bytes in a word

  // forward 'busy' and 'data ready' signals from cache unless it is I/O
  assign busy = address == AddressUartOut || 
                address == AddressUartIn || 
                address == AddressLed ||
                address == AddressSDCardBusy ||
                address == AddressSDCardReadSector ||
                address == AddressSDCardWriteSector ||
                address == AddressSDCardNextByte ||
                address == AddressSDCardStatus
                ? 0 : cache_busy;

  assign data_out_ready = address == AddressUartOut || 
                          address == AddressUartIn ||
                          address == AddressLed ||
                          address == AddressSDCardBusy ||
                          address == AddressSDCardReadSector ||
                          address == AddressSDCardWriteSector ||
                          address == AddressSDCardNextByte ||
                          address == AddressSDCardStatus
                          ? 1 : cache_data_out_ready;

  // note: commented lines use 280 more LUT than the cumbersome code above

  // assign busy = address >= AddressIOPortsStart ? 0 : cache_busy;
  // assign data_out_ready = address >= AddressIOPortsStart ? 1 : cache_data_out_ready;

  // 'sdcard' related wirings and logic
  logic [2:0] sdcard_command;
  logic [31:0] sdcard_sector;
  wire [7:0] sdcard_data_out;
  logic [7:0] sdcard_data_in;
  wire sdcard_busy;
  wire [31:0] sdcard_status;

  logic [31:0] uarttx_data_sending;
  // data being sent by 'uarttx'
  //  -1 if idle

  logic [31:0] uartrx_data_received;
  // data copied from 'uartrx_data' when 'uartrx_data_ready' asserted
  //  -1 if none available


  always_comb begin
    // convert address to 4-byte word aligned addressing in RAM
    cache_address = {address[AddressBitwidth-1:2], 2'b00};

    data_out = 0;

    // initiate result
    cache_write_enable = 0;
    cache_data_in = 0;
    cache_enable = 0;
    sdcard_command = 0;
    sdcard_sector = 0;
    sdcard_data_in = 0;

    if (enable) begin

`ifdef DBG
      $display("%m: %0t: address: 0x%h  read_type: 0b%b  write_type: 0b%b  data_in: 0x%h", $time,
               address, read_type, write_type, data_in);
`endif

      if (write_type != 0) begin

        //------------------------------------------------------------------
        //
        // Write
        //  convert 'data_in' using 'write_type' to byte enabled 4-bytes word write to cache
        //   or do I/O
        //
        //------------------------------------------------------------------

        case (address)
          AddressUartOut: ;  // handled in always_ff
          AddressUartIn: ;  // ignore write
          AddressLed: ;  // handled in always_ff
          AddressSDCardBusy: ;  // ignore write
          AddressSDCardStatus: ;  // ignore write
          AddressSDCardNextByte: begin
            sdcard_command = 3;
            sdcard_data_in = data_in[7:0];
          end
          AddressSDCardReadSector: begin
            sdcard_command = 1;
            sdcard_sector  = data_in;
          end
          AddressSDCardWriteSector: begin
            sdcard_command = 4;
            sdcard_sector  = data_in;
          end
          default: begin
            cache_enable = 1;
            // convert input to cache interface expected byte enabled 4-bytes word
            unique case (write_type)
              2'b01: begin  // byte
                unique case (address[1:0])
                  2'b00: begin
                    cache_write_enable = 4'b0001;
                    cache_data_in[7:0] = data_in[7:0];
                  end
                  2'b01: begin
                    cache_write_enable  = 4'b0010;
                    cache_data_in[15:8] = data_in[7:0];
                  end
                  2'b10: begin
                    cache_write_enable   = 4'b0100;
                    cache_data_in[23:16] = data_in[7:0];
                  end
                  2'b11: begin
                    cache_write_enable   = 4'b1000;
                    cache_data_in[31:24] = data_in[7:0];
                  end
                endcase
              end
              2'b10: begin  // half word
                unique case (address[1:0])
                  2'b00: begin
                    cache_write_enable  = 4'b0011;
                    cache_data_in[15:0] = data_in[15:0];
                  end
                  2'b01: ;  // ? error
                  2'b10: begin
                    cache_write_enable   = 4'b1100;
                    cache_data_in[31:16] = data_in[15:0];
                  end
                  2'b11: ;  // ? error
                endcase
              end
              2'b11: begin  // word
                // ? assert(addr_lower_w==0)
                cache_write_enable = 4'b1111;
                cache_data_in = data_in;
              end
              default: ;  // ? error
            endcase
          end
        endcase
      end

      //------------------------------------------------------------------
      // 
      // Read
      //  convert 'cache_data_out' according to 'read_type'
      //   or handle I/O
      //
      //------------------------------------------------------------------

      if (read_type != 0) begin
        unique case (address)
          AddressLed: ;  // ignore read
          AddressSDCardReadSector: ;  // ignore read
          AddressSDCardWriteSector: ;  // ignore read
          AddressUartOut: begin
            // any read from 'uarttx' returns signed word
            data_out = uarttx_data_sending;
          end
          AddressUartIn: begin
            // any read from 'uartrx' returns signed word
            data_out = uartrx_data_received;
          end
          AddressSDCardBusy: begin
            data_out = sdcard_busy;
          end
          AddressSDCardStatus: begin
            data_out = sdcard_status;
          end
          AddressSDCardNextByte: begin
            sdcard_command = 2;
            data_out = sdcard_data_out;
          end
          default: begin
            cache_enable = 1;
            // read from ram
            unique casez (read_type)
              3'b?01: begin  // byte
                unique case (address[1:0])
                  2'b00: begin
                    data_out = read_type[2] ? 
                    {{24{cache_data_out[7]}}, cache_data_out[7:0]} :
                    {{24{1'b0}}, cache_data_out[7:0]};
                  end
                  2'b01: begin
                    data_out = read_type[2] ? 
                    {{24{cache_data_out[15]}}, cache_data_out[15:8]} :
                    {{24{1'b0}}, cache_data_out[15:8]};
                  end
                  2'b10: begin
                    data_out = read_type[2] ? 
                    {{24{cache_data_out[23]}}, cache_data_out[23:16]} :
                    {{24{1'b0}}, cache_data_out[23:16]};
                  end
                  2'b11: begin
                    data_out = read_type[2] ? 
                    {{24{cache_data_out[31]}}, cache_data_out[31:24]} :
                    {{24{1'b0}}, cache_data_out[31:24]};
                  end
                endcase
              end
              3'b?10: begin  // half word
                unique case (address[1:0])
                  2'b00: begin
                    data_out = read_type[2] ? 
                    {{16{cache_data_out[15]}}, cache_data_out[15:0]} :
                    {{16{1'b0}}, cache_data_out[15:0]};
                  end
                  2'b01: data_out = 0;  // ? error
                  2'b10: begin
                    data_out = read_type[2] ? 
                    {{16{cache_data_out[31]}}, cache_data_out[31:16]} :
                    {{16{1'b0}}, cache_data_out[31:16]};
                  end
                  2'b11: data_out = 0;  // ? error
                endcase
              end
              3'b111: begin  // word
                // ? assert(addr_lower_w==0)
                data_out = cache_data_out;
              end
              default: ;
            endcase
          end
        endcase
      end
    end
  end

  logic       uarttx_go;
  // enable to start sending and disable to acknowledge that data has been sent

  logic       uarttx_busy;
  // enabled when 'uarttx' is busy sending, low when done (assert with uarttx_go = 0)

  logic       uartrx_data_ready;

  logic [7:0] uartrx_data;
  // data being read by 'uartrx'

  logic       uartrx_go;
  // enable to start receiving
  //  disable to acknowledge that received data has been read from 'uartrx'

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      led <= 4'b1111;  // turn off all LEDs
      uarttx_data_sending <= -1;
      uarttx_go <= 0;
      uartrx_data_received <= -1;
      uartrx_go <= 1;
    end else begin
      // if read from UART then reset the read data to -1
      if (address == AddressUartIn && read_type != 0) begin
`ifdef DBG
        $display("%m: %0t: uart read  uartrx_data_received: 0x%h", $time, uartrx_data_received);
`endif
        uartrx_data_received <= -1;
      end

      if (uartrx_go && uartrx_data_ready) begin
`ifdef DBG
        $display("%m: %0t: uart data ready  uartrx_data_received: 0x%h", $time, uartrx_data);
`endif
        // if UART has data ready then copy the data and acknowledge (uartrx_go = 0)
        //  note: read data can be overrun
        uartrx_data_received <= {{24'h00}, uartrx_data};
        uartrx_go <= 0;
      end

      // if previous cycle acknowledged receiving data
      //  then start receiving next data (uartrx_go = 1)
      if (!uartrx_go) begin
        uartrx_go <= 1;
      end

      // if UART is done sending data then acknowledge (uarttx_go = 0)
      //  and set idle (0xffff'ffff)
      if (uarttx_go && !uarttx_busy) begin
        uarttx_go <= 0;
        uarttx_data_sending <= -1;
      end

      // if writing to UART out
      if (address == AddressUartOut && write_type != 0) begin
        uarttx_data_sending <= {24'b0, data_in[7:0]};
        uarttx_go <= 1;
      end

      // if writing to LEDs
      if (address == AddressLed && write_type != 0) begin
        led <= data_in[3:0];
      end
    end
  end

  cache #(
      .LineIndexBitwidth(CacheLineIndexBitwidth),
      .ColumnIndexBitwidth(CacheColumnIndexBitwidth),
      .RamAddressBitwidth(RamAddressBitwidth),
      .RamAddressingMode(RamAddressingMode),
      .AutoRefreshPeriodCycles(
        (SDRAMRefreshIntervalMs*1_000_000/SDRAMRefreshCountDuringInterval) // nano seconds per refresh
      / (1_000_000_000.0 / SDRAMClockFrequencyHz)  // nano seconds per cycle
      * (100 - SDRAMRefreshRequirementsMarginPercent) / 100  // margin in percent (0: none)
      )
  ) cache (
      .rst_n,
      .clk,

      .enable(cache_enable),
      .address(cache_address),
      .data_out(cache_data_out),
      .data_out_ready(cache_data_out_ready),
      .data_in(cache_data_in),
      .write_enable(cache_write_enable),
      .busy(cache_busy),

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

  uarttx #(
      .ClockFrequencyHz(ClockFrequencyHz),
      .BaudRate(BaudRate)
  ) uarttx (
      .rst_n,
      .clk,

      .tx(uart_tx),
      // UART tx wire

      .data(uarttx_data_sending[7:0]),
      // data to send

      .go(uarttx_go),
      // enable to start transmission, disable after 'data' has been read

      .busy(uarttx_busy)
      // enabled while sendng
  );

  uartrx #(
      .ClockFrequencyHz(ClockFrequencyHz),
      .BaudRate(BaudRate)
  ) uartrx (
      .rst_n,
      .clk,

      .rx(uart_rx),
      // UART rx wire

      .go(uartrx_go),
      // enable to start receiving, disable to acknowledge 'data_ready'

      .data(uartrx_data),
      // current data being received, is incomplete until 'data_ready' asserted

      .data_ready(uartrx_data_ready)
      // enabled when a full byte of 'data' has been received
  );

  sdcard #(
      .Simulate(SDCardSimulate),
      .ClockDivider(SDCardClockDivider)
  ) sdcard (
      .clk,
      .rst_n,

      // SD card signals
      .sd_cs_n,
      .sd_clk,
      .sd_mosi,
      .sd_miso,

      // interface
      .command(sdcard_command),
      .sector(sdcard_sector),
      .data_out(sdcard_data_out),
      .data_in(sdcard_data_in),
      .busy(sdcard_busy),
      .status(sdcard_status)
  );

endmodule

`undef DBG
`undef INFO
`default_nettype wire
