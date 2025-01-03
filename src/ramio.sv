//
// Interface to RAM, UART and LEDs
//
// reviewed 2024-06-25
//
`timescale 1ns / 1ps
//
`default_nettype none
// `define DBG
// `define INFO

module ramio #(
    parameter int unsigned RamAddressBitWidth = 10,
    // passed to 'cache': backing burst RAM depth

    parameter int unsigned RamAddressingMode = 3,
    // passed to 'cache': address refers to:
    //  0: byte, 1: half word, 2: word, 3: double word

    parameter int unsigned CacheLineIndexBitWidth = 1,
    // passed to 'cache': 2 ^ value * 32 B cache size

    parameter int unsigned CacheColumnIndexBitWidth = 3,
    // passed to 'cache': 2 ^ value entries per cache line

    parameter int unsigned AddressBitWidth = 32,
    // client address bit width

    parameter int unsigned DataBitWidth = 32,
    // client data bit width

    parameter int unsigned ClockFrequencyHz = 20_250_000,
    // passed to 'uartrx' and 'uarttx'

    parameter int unsigned BaudRate = 9600,
    // passed to 'uartrx' and 'uarttx'

    parameter int unsigned TopAddress = {AddressBitWidth{1'b1}},
    // last addressable byte

    parameter int unsigned AddressLed = 32'hffff_fffc,
    // 4 LEDs in the lower nibble of the int
    // note: 0 is led on, 1 is led off

    parameter int unsigned AddressUartOut = 32'hffff_fff8,
    // note: returns -1 if idle

    parameter int unsigned AddressUartIn = 32'hffff_fff4
    // note: is set to -1 after read
) (
    input wire rst_n,
    input wire clk,

    input wire enable,

    input wire [2:0] read_type,
    // b000 not a read; bit[2] flags sign extended or not, b01: byte, b10: half word, b11: word

    input wire [1:0] write_type,
    // b00 not a write; b01: byte, b10: half word, b11: word

    input wire [AddressBitWidth-1:0] address,
    // byte address (type aligned)

    input wire [DataBitWidth-1:0] data_in,
    // byte, half word, word

    output logic [DataBitWidth-1:0] data_out,
    // data at 'address' according to 'read_type'

    output logic data_out_ready,

    output logic busy,

    output logic [3:0] led,
    // I/O mapping of LEDs

    output logic uart_tx,
    input  wire  uart_rx,

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

  wire [DataBitWidth-1:0] cache_data_out;
  wire cache_data_out_ready;
  wire cache_busy;

  logic [AddressBitWidth-1:0] cache_address;
  // 4-byte aligned address to RAM data

  logic [DataBitWidth-1:0] cache_data_in;
  // data for byte enabled write of 4-byte word

  logic [3:0] cache_write_enable;
  // bytes in the word enabled for writing; default 4-bytes in a word

  // forward 'busy' and 'data ready' signals from cache unless it is I/O
  assign busy = address == AddressUartOut || 
                address == AddressUartIn || 
                address == AddressLed 
                ? 0 : cache_busy;

  assign data_out_ready = address == AddressUartOut || 
                          address == AddressUartIn ||
                          address == AddressLed
                          ? 1 : cache_data_out_ready;

  //
  // cache write
  //  convert 'data_in' using 'write_type' to byte enabled 4-bytes word write to cache
  // 
  always_comb begin
    // convert address to 4-byte word aligned addressing in RAM
    cache_address = {address[AddressBitWidth-1:2], 2'b00};

    // initiate result
    cache_enable = 0;
    cache_write_enable = 0;
    cache_data_in = 0;

    if (enable) begin
      if (address == AddressUartOut || address == AddressUartIn || address == AddressLed) begin
        // don't trigger cache when accessing I/O
      end else begin
        cache_enable = 1;
        // note: could be done in either 'always_comb', however this block checks
        //  address with both UART and LED

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
    end
  end

  logic [31:0] uarttx_data_sending;
  // data being sent by 'uarttx'
  //  -1 if idle

  logic [31:0] uartrx_data_received;
  // data copied from 'uartrx_data' when 'uartrx_data_ready' asserted
  //  -1 if none available

  // 
  // cache read
  //  convert 'cache_data_out' according to 'read_type' and handle UART read requests
  //
  always_comb begin
`ifdef DBG
    $display("address: %h  read_type: %b", address, read_type);
`endif
    // create the 'data_out' based on the 'address'
    data_out = 0;
    if (enable) begin
      if (address == AddressUartOut && read_type != '0) begin
        // any read from 'uarttx' returns signed word
        data_out = uarttx_data_sending;

      end else if (address == AddressUartIn && read_type != '0) begin
        // any read from 'uartrx' returns signed word
        data_out = uartrx_data_received;

      end else begin
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
    end
  end

  logic       uarttx_go;
  // enable to start sending and disable to acknowledge that data has been sent

  logic       uarttx_bsy;
  // enabled when 'uarttx' is busy sending, low when done (assert with uarttx_go = 0)

  logic       uartrx_data_ready;

  logic [7:0] uartrx_data;
  // data being read by 'uartrx'

  logic       uartrx_go;
  // enable to start receiving
  //  disable to acknowledge that received data has been read from 'uartrx'

  logic       prev_cycle_uarttx_go;
  // true when previous cycle enabled 'uarttx_go'
  //  need to wait one cycle for 'uarttx' to assert 'uarttx_bsy'

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      led <= 4'b1111;  // turn off all LEDs
      uarttx_data_sending <= -1;
      uarttx_go <= 0;
      uartrx_data_received <= -1;
      uartrx_go <= 1;
    end else begin
      prev_cycle_uarttx_go <= 0;

      // if read from UART then reset the read data to -1
      if (address == AddressUartIn && read_type != '0) begin
        uartrx_data_received <= -1;
      end

      if (uartrx_go && uartrx_data_ready) begin
        // !!! unclear why necessary for this to be in an 'else if' instead 
        // !!!  of stand-alone 'if' to avoid characters being dropped from 'uartrx'
        // !!! note: issue does not happen in Gowin 19.10.03 as often
        // !!! note: continuous read of UART will block updating received data

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
      if (uarttx_go && !uarttx_bsy && !prev_cycle_uarttx_go) begin
        uarttx_go <= 0;
        uarttx_data_sending <= -1;
      end

      // if writing to UART out
      if (address == AddressUartOut && write_type != '0) begin
        uarttx_data_sending <= {24'h00, data_in[7:0]};
        uarttx_go <= 1;
        prev_cycle_uarttx_go <= 1;
      end

      // if writing to LEDs
      if (address == AddressLed && write_type != '0) begin
        led <= data_in[3:0];
      end
    end
  end

  cache #(
      .LineIndexBitWidth  (CacheLineIndexBitWidth),
      .ColumnIndexBitwidth(CacheColumnIndexBitWidth),
      .RamAddressBitWidth (RamAddressBitWidth),
      .RamAddressingMode  (RamAddressingMode)
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

      .bsy(uarttx_bsy)
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

endmodule

`undef DBG
`undef INFO
`default_nettype wire
