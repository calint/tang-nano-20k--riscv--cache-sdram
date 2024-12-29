//
// a partial emulator of flash circuit (P25Q32U) used in simulation
//  mock IP component
//
// reviewed 2024-06-26
//
`timescale 1ns / 1ps
//
`default_nettype none
//`define DBG
//`define INFO

module flash #(
    parameter string DataFilePath = "",
    // initial RAM content; one byte per line in hex text

    parameter int unsigned AddressBitWidth = 8,
    // size of stored data in bit width; 2 ^ 8 = 256 B

    parameter int unsigned AddressOffset = 0
    // adjust requested address to the address space of data
    // example: -10 translates requested address 10 to 0
) (
    input wire rst_n,
    input wire clk,

    output logic miso,
    input  wire  mosi,
    input  wire  cs_n
);

  localparam int unsigned DEPTH = 2 ** AddressBitWidth;

  logic [7:0] data[DEPTH];

  logic [AddressBitWidth-1:0] address;
  logic [7:0] current_byte;
  logic [8:0] counter;
  // note: one extra bit to decrement into negative for more efficient comparison

  typedef enum {
    ReceiveCommand,
    ReceiveAddress,
    SendData
  } state_e;

  state_e state, next_state;

  initial begin
`ifdef INFO
    $display("----------------------------------------");
    $display("  flash");
    $display("----------------------------------------");
    $display("      data file: %s", DataFilePath);
    $display("           size: %0d B", DEPTH);
    $display(" address offset: %0h", AddressOffset);
    $display("----------------------------------------");
`endif
    if (DataFilePath != "") begin
      $readmemh(DataFilePath, data);
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      counter <= 8;  // -1 because decrementing into negative
      address <= 0;
      current_byte <= 0;
      miso <= 0;
      state <= ReceiveCommand;
    end else begin
      state <= next_state;
    end
  end

  always_comb begin
`ifdef DBG
    $display("state: %0d  counter: %0d  address: %h", state, counter, address);
`endif

    next_state = state;

    unique case (state)

      ReceiveCommand: begin
        if (!cs_n && !clk) begin
          // note: assumes 'read', the only command implemented
          counter = counter - 1'b1;
          if (counter[8]) begin
            counter = 24 - 1;
            // 24 is size of address and -1 because decrementing into negative
            next_state = ReceiveAddress;
          end
        end
      end

      ReceiveAddress: begin
        if (!cs_n && !clk) begin
          address = {address[22:0], mosi};
          counter = counter - 1'b1;
          if (counter[8]) begin
            current_byte = data[address];
            miso = current_byte[7];
            current_byte = {current_byte[6:0], 1'b0};
            counter = 7 - 1;
            // 7 because first bit is sent in this cycle
            // -1 because decrementing into negative
            next_state = SendData;
          end
        end
      end

      SendData: begin
        if (!cs_n && !clk) begin
          miso = current_byte[7];
          current_byte = {current_byte[6:0], 1'b0};
          counter = counter - 1'b1;
          if (counter[8]) begin
            address = address + 1'b1;
            current_byte = data[address];
            counter = 8 - 1;  // -1 because decrementing into negative
          end
        end
      end

    endcase
  end
endmodule

`undef DBG
`undef INFO
`default_nettype wire
