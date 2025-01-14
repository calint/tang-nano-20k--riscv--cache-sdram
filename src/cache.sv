//
// Cache for SDRAM
// see: IPUG756-1.0.1E - Gowin SDRAM HS IP User Guide.pdf
//      SDRAM model used in simulation: MT48LC2M32B2.v
//
// reviewed 2024-06-07
// reviewed 2024-06-12
// reviewed 2024-06-14
//
`timescale 1ns / 1ps
//
`default_nettype none
// `define DBG
// `define INFO

module cache #(
    parameter int unsigned ColumnIndexBitwidth = 3,
    // 2 ^ 3 = 8 entries (32 B) per cache line

    parameter int unsigned LineIndexBitWidth = 6,
    // 2 ^ 6 * 32 B = 2 KB unified instruction and data cache

    parameter int unsigned RamAddressBitWidth = 10,
    // bits in the address of underlying burst RAM

    parameter int unsigned RamAddressingMode = 0,
    // amount of data stored per address
    //       0: 1 B (byte addressed)
    //       1: 2 B
    //       2: 4 B
    //       3: 8 B

    parameter int unsigned WaitsAfterBurstWrite = 4,
    // empirically found to not violate timing constraints (minimum 1)
    //  at 27 MHz: 4

    parameter int unsigned WaitsPriorToDataAtRead = 4
    // according to specification in: IPUG756-1.0.1E
    //  Gowin SDRAM HS IP User Guide page 11
) (
    input wire rst_n,
    input wire clk,

    input wire enable,
    // enabled for cache to operate

    input wire [31:0] address,
    // byte addressed; must be held while 'busy' + 1 cycle

    output logic [31:0] data_out,
    output logic data_out_ready,
    input wire [31:0] data_in,

    input wire [3:0] write_enable,
    // note: write enable bytes must be held while busy + 1 cycle

    output logic busy,
    // asserted when busy reading / writing cache line

    // SDRAM Controller
    // note: to preserve names for consistency, invert I_ and O_ to output and input
    // output logic I_sdrc_rst_n,
    // output logic I_sdrc_clk,
    // output logic I_sdram_clk,
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

  assign I_sdram_power_down = 0;
  assign I_sdram_selfrefresh = 0;
  assign I_sdrc_precharge_ctrl = 1;
  assign I_sdrc_dqm = 4'b0000;  // writing whole words, no data mask

`ifdef INFO
  initial begin
    $display("Cache");
    $display("      lines: %0d", LINE_COUNT);
    $display("    columns: %0d x 4 B", 2 ** ColumnIndexBitwidth);
    $display("        tag: %0d bits", TAG_BITWIDTH);
    $display(" cache size: %0d B", LINE_COUNT * (2 ** ColumnIndexBitwidth) * 4);
  end
`endif

  localparam int unsigned ZEROS_BITWIDTH = 2;  // leading zeros in the address
  localparam int unsigned COLUMN_COUNT = 2 ** ColumnIndexBitwidth;
  localparam int unsigned LINE_COUNT = 2 ** LineIndexBitWidth;
  localparam int unsigned TAG_BITWIDTH = 
    RamAddressBitWidth + RamAddressingMode - LineIndexBitWidth - ColumnIndexBitwidth - ZEROS_BITWIDTH;
  // note: assumes there are 2 bits free after 'TAG_BITWIDTH' for 'valid' and 'dirty' flags in storage

  localparam int unsigned LINE_VALID_BIT = TAG_BITWIDTH;
  localparam int unsigned LINE_DIRTY_BIT = TAG_BITWIDTH + 1;
  localparam int unsigned LINE_TO_RAM_ADDRESS_LEFT_SHIFT = ColumnIndexBitwidth + ZEROS_BITWIDTH - RamAddressingMode;

  // wires dividing the address into components
  // |tag|line| col |00| address
  //                |00| ignored (4-bytes word aligned)
  //          | col |    column_ix: index of the data in the cached line
  //     |line|          line_ix: index in array where tag and cached data is stored
  // |tag|               address_tag: upper bits followed by 'valid' and 'dirty' flag

  // extract cache line info from current address
  wire [ColumnIndexBitwidth-1:0] column_ix = address[
    ColumnIndexBitwidth+ZEROS_BITWIDTH-1
    -:ColumnIndexBitwidth
  ];
  wire [LineIndexBitWidth-1:0] line_ix =  address[
    LineIndexBitWidth+ColumnIndexBitwidth+ZEROS_BITWIDTH-1
    -:LineIndexBitWidth
  ];
  wire [TAG_BITWIDTH-1:0] address_tag = address[
    TAG_BITWIDTH+LineIndexBitWidth+ColumnIndexBitwidth+ZEROS_BITWIDTH-1
    -:TAG_BITWIDTH
  ];

  // starting address of cache line in RAM for current address
  wire [RamAddressBitWidth-1:0] burst_line_address = {
    address[TAG_BITWIDTH+LineIndexBitWidth+ColumnIndexBitwidth+ZEROS_BITWIDTH-1:ColumnIndexBitwidth+ZEROS_BITWIDTH],
    {LINE_TO_RAM_ADDRESS_LEFT_SHIFT{1'b0}}
  };

  logic burst_is_reading;  // true if in burst read operation
  logic [31:0] burst_data_in[COLUMN_COUNT];
  logic [3:0] burst_write_enable[COLUMN_COUNT];
  logic [3:0] burst_tag_write_enable;

  logic burst_is_writing;  // true if in burst write operation

  wire [31:0] cached_tag_and_flags;
  logic [3:0] tag_write_enable;  // true when cache hit; write to set line dirty
  logic [31:0] tag_data_in;  // tag and flags written when cache hit write

  bram #(
      .AddressBitWidth(LineIndexBitWidth)
  ) tag (
      .rst_n,
      .clk,
      .write_enable(tag_write_enable),
      .address(line_ix),
      .data_in(tag_data_in),
      .data_out(cached_tag_and_flags)
  );

  // extract portions of the combined tag, valid, dirty line info
  wire line_valid = cached_tag_and_flags[LINE_VALID_BIT];
  wire line_dirty = cached_tag_and_flags[LINE_DIRTY_BIT];
  wire [TAG_BITWIDTH-1:0] cached_tag = cached_tag_and_flags[TAG_BITWIDTH-1:0];

  // starting address in burst RAM for the cached line
  wire [RamAddressBitWidth-1:0] cached_line_address = {
    {cached_tag, line_ix}, {LINE_TO_RAM_ADDRESS_LEFT_SHIFT{1'b0}}
  };

  wire cache_line_hit = line_valid && address_tag == cached_tag;

  // counts the delay before first data is available at read
  logic [2:0] data_available_delay_counter;

  // which column is active during burst read and write
  logic [ColumnIndexBitwidth-1:0] write_column;

  assign busy = enable && !cache_line_hit;

  // select data from requested column
  assign data_out = column_data_out[column_ix];
  assign data_out_ready = write_enable != '0 ? 0 : enable && cache_line_hit;

  // 8 instances of byte enabled semi dual port RAM blocks
  // if cache hit at write then connect 'data_in' to the column
  // if cache miss connect to the state machine that loads a cache line
  logic [31:0] column_data_in[COLUMN_COUNT];
  logic [3:0] column_write_enable[COLUMN_COUNT];
  logic [31:0] column_data_out[COLUMN_COUNT];

  generate
    for (genvar i = 0; i < COLUMN_COUNT; i++) begin : column
      bram #(
          .AddressBitWidth(LineIndexBitWidth)
      ) column (
          .rst_n,
          .clk,
          .write_enable(column_write_enable[i]),
          .address(line_ix),
          .data_in(burst_is_reading ? burst_data_in[i] : column_data_in[i]),
          .data_out(column_data_out[i])
      );
    end
  endgenerate

  always_comb begin
    for (int i = 0; i < COLUMN_COUNT; i++) begin
      column_write_enable[i] = 0;
      column_data_in[i] = 0;
    end

    tag_write_enable = 0;
    tag_data_in = 0;

    if (burst_is_reading) begin
      // writing to the cache line in a burst read from RAM
      // select the write from burst registers
      for (int i = 0; i < COLUMN_COUNT; i++) begin
        column_write_enable[i] = burst_write_enable[i];
      end
      // write tag of the fetched cache line when burst is finished reading
      // the line
      tag_write_enable = burst_tag_write_enable;
      tag_data_in = {1'b0, 1'b1, address_tag};
      // note: {dirty, valid, upper address bits}
    end else if (burst_is_writing) begin
      //
    end else if (write_enable != '0) begin
`ifdef DBG
      $display("%m: %t: write 0x%h = 0x%h  mask: %b  line: %0d  column: %0d", $time, address,
               data_in, write_enable, line_ix, column_ix);
`endif
      if (cache_line_hit) begin
`ifdef DBG
        $display("%m: %t: cache hit, set dirty flag", $time);
`endif
        // enable write tag with dirty bit set
        tag_write_enable = 4'b1111;
        tag_data_in = {1'b1, 1'b1, address_tag};
        // note: { dirty, valid, tag }

        // connect 'column_data_in' to the input and set 'column_write_enable'
        //  for the addressed column in the cache line
        column_write_enable[column_ix] = write_enable;
        column_data_in[column_ix] = data_in;
`ifdef DBG
        $display("%m: %t: set column[%0d]=0x%h", $time, column_ix, data_in);
`endif
      end else begin  // not (cache_line_hit)
`ifdef DBG
        $display("%m: %t: cache miss", $time);
`endif
      end
    end else begin
`ifdef DBG
      $display("%m: %t: read 0x%h  data out: 0x%h  line: %0d  column: %0d  data ready: %0d", $time,
               address, data_out, line_ix, column_ix, data_out_ready);
`endif
    end
  end

  typedef enum {
    InitSDRAM1,
    InitSDRAM2,
    Idle,
    Write1,
    Write2,
    Write3,
    Write4,
    Write5,
    Read1,
    Read2,
    Read3,
    Read4,
    Read5,
    Read6
  } state_e;

  state_e state;

  logic [4:0] counter;  // used in read / write FSM

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      burst_tag_write_enable <= 0;
      for (int i = 0; i < COLUMN_COUNT; i++) begin
        burst_write_enable[i] <= 0;
      end
      burst_is_reading <= 0;
      burst_is_writing <= 0;
      write_column <= 0;
      state <= InitSDRAM1;
    end else begin
`ifdef DBG
      $display("%m: %t: state: %0d", $time, state);
`endif
      unique case (state)
        InitSDRAM1: begin
          I_sdrc_cmd_en <= 1;
          I_sdrc_cmd <= 3'b001;  // auto-refresh
          state <= InitSDRAM2;
        end
        InitSDRAM2: begin
          I_sdrc_cmd_en <= 0;
          if (O_sdrc_cmd_ack) begin
            state <= Idle;
          end
        end
        Idle: begin
          if (enable && !cache_line_hit) begin
            // cache miss, start reading the addressed cache line
`ifdef DBG
            $display("%m: %t: cache miss address 0x%h  line: %0d  write enable: %b", $time,
                     address, line_ix, write_enable);
`endif
            if (line_dirty) begin
`ifdef DBG
              $display("%m: %t: line %0d dirty, evict to RAM address 0x%h", $time, line_ix,
                       cached_line_address);
              $display("%m: %t: activating for write bank/row: 0x%h", $time, cached_line_address);
`endif
              I_sdrc_cmd_en <= 1;
              I_sdrc_cmd <= 3'b011;  // activate bank and row of cache line
              I_sdrc_addr <= cached_line_address;
              state <= Write1;
            end else begin  // not (write_enable && line_dirty)
`ifdef DBG
              if (write_enable && !line_dirty) begin
                $display("%m: %t: line %0d not dirty", $time, line_ix);
              end
              $display("%m: %t: read line from RAM address 0x%h", $time, burst_line_address);
              $display("%m: %t: activating for read bank/row: 0x%h", $time, burst_line_address);
`endif
              I_sdrc_cmd_en <= 1;
              I_sdrc_cmd <= 3'b011;  // activate bank and row of cache line
              I_sdrc_addr <= burst_line_address;  // activate bank 0 row 0
              burst_is_reading <= 1;
              state <= Read1;
            end
          end
        end

        Write1: begin
          // O_sdrc_cmd_ack == 1
          I_sdrc_cmd_en <= 0;
          state <= Write2;
        end

        Write2: begin
          I_sdrc_cmd_en <= 1;
          I_sdrc_cmd <= 3'b100;  // write
          I_sdrc_addr <= cached_line_address;
          I_sdrc_data_len <= COLUMN_COUNT - 1;
          I_sdrc_data <= column_data_out[0];
`ifdef DBG
          $display("%m: %t: flush column[0]=%h", $time, column_data_out[0]);
`endif
          state <= Write3;
        end

        Write3: begin
          I_sdrc_cmd_en <= 0;
          I_sdrc_data   <= column_data_out[1];
`ifdef DBG
          $display("%m: %t: flush column[1]=%h", $time, column_data_out[1]);
`endif
          write_column <= 2;
          state <= Write4;
        end

        Write4: begin
          I_sdrc_data <= column_data_out[write_column];
`ifdef DBG
          $display("%m: %t: flush column[%0d]=%h", $time, write_column,
                   column_data_out[write_column]);
`endif
          if (write_column == COLUMN_COUNT - 1) begin
            counter <= 1;
            state   <= Write5;
          end
          write_column <= write_column + 1'b1;
        end

        Write5: begin
          if (counter == WaitsAfterBurstWrite) begin
            burst_is_writing <= 0;
            burst_is_reading <= 1;
            I_sdrc_cmd_en <= 1;
            I_sdrc_cmd <= 3'b011;  // activate
            I_sdrc_addr <= burst_line_address;
            state <= Read1;
          end
          counter <= counter + 1'b1;
        end

        Read1: begin
          I_sdrc_cmd_en <= 0;
          state <= Read2;
        end

        Read2: begin
          I_sdrc_cmd_en <= 1;
          I_sdrc_cmd <= 3'b101;  // read
          I_sdrc_addr <= burst_line_address;
          I_sdrc_data_len <= COLUMN_COUNT - 1;
          counter <= 0;
          state <= Read3;
        end

        Read3: begin
          I_sdrc_cmd_en <= 0;
          counter <= counter + 1'b1;
          if (counter == WaitsPriorToDataAtRead) begin
            burst_write_enable[0] <= 4'b1111;
            burst_data_in[0] <= O_sdrc_data;
            counter <= 1;
            state <= Read4;
          end
        end

        Read4: begin
          burst_write_enable[counter-1] <= 0;
          burst_write_enable[counter] <= 4'b1111;
          burst_data_in[counter] <= O_sdrc_data;
          counter <= counter + 1'b1;
          if (counter == COLUMN_COUNT - 1) begin
            state <= Read5;
          end
        end

        Read5: begin
          // note: reading line can be initiated after a cache eviction
          //       'burst_write_enable' then high, set to low
          burst_write_enable[COLUMN_COUNT-1] <= 0;
          burst_tag_write_enable <= 4'b1111;
          state <= Read6;
        end

        Read6: begin
          // note: tag has been written after read data has settled
          burst_is_reading <= 0;
          burst_tag_write_enable <= 0;
          state <= Idle;
        end

        default: ;

      endcase
    end
  end

endmodule

`undef DBG
`undef INFO
`default_nettype wire
