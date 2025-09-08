//
// Cache for SDRAM
// see: IPUG756-1.0.1E - Gowin SDRAM HS IP User Guide.pdf
//      SDRAM model used in simulation: MT48LC2M32B2.v
//
`timescale 1ns / 1ps
//
`default_nettype none
//`define DBG
//`define INFO

module cache #(
    parameter int unsigned ColumnIndexBitwidth = 3,
    // 2 ^ 3 = 8 entries (32 B) per cache line

    parameter int unsigned LineIndexBitwidth = 6,
    // 2 ^ 6 * 32 B = 2 KB unified instruction and data cache

    parameter int unsigned RamAddressBitwidth = 10,
    // bits in the address of underlying burst RAM

    parameter int unsigned RamAddressingMode = 0,
    // amount of data stored per address
    //       0: 1 B (byte addressed)
    //       1: 2 B
    //       2: 4 B
    //       3: 8 B

    parameter int unsigned WaitsPriorToDataAtRead = 4,
    // according to specification in: IPUG756-1.0.1E
    //  Gowin SDRAM HS IP User Guide page 11
    //  note: default for CL=2
    //        when CL=3 then 5

    parameter int unsigned AutoRefreshPeriodCycles = 600
    // number of cycles before issuing an auto refresh to SDRAM
    //  note: at 54 MHz with Tang Nano 20K SDRAM (EM638325GD):
    //        4096 times in 64 ms (according to the spec)
    //        at 54 MHz gives 843 cycles before refresh
) (
    input wire rst_n,
    input wire clk,

    input wire enable,
    // enabled for cache to operate

    input wire [31:0] address,
    // byte addressed
    // note: must be held while 'busy' + 1 cycle

    output logic [31:0] data_out,
    output logic data_out_ready,
    input wire [31:0] data_in,

    input wire [3:0] write_enable,
    // write enable bytes mask
    // note: must be held while 'busy' + 1 cycle

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
    $display("    refresh: %0d cycles", AutoRefreshPeriodCycles);
    $display(" waits read: %0d cycles", WaitsPriorToDataAtRead);
  end
`endif

  localparam int unsigned ZEROS_BITWIDTH = 2;  // leading zeros in the address
  localparam int unsigned COLUMN_COUNT = 2 ** ColumnIndexBitwidth;
  localparam int unsigned LINE_COUNT = 2 ** LineIndexBitwidth;
  localparam int unsigned TAG_BITWIDTH = 
    RamAddressBitwidth + RamAddressingMode - LineIndexBitwidth - ColumnIndexBitwidth - ZEROS_BITWIDTH;
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
  wire [LineIndexBitwidth-1:0] line_ix =  address[
    LineIndexBitwidth+ColumnIndexBitwidth+ZEROS_BITWIDTH-1
    -:LineIndexBitwidth
  ];
  wire [TAG_BITWIDTH-1:0] address_tag = address[
    TAG_BITWIDTH+LineIndexBitwidth+ColumnIndexBitwidth+ZEROS_BITWIDTH-1
    -:TAG_BITWIDTH
  ];

  // starting address of cache line in RAM for current address
  wire [RamAddressBitwidth-1:0] burst_line_address = {
    address[TAG_BITWIDTH+LineIndexBitwidth+ColumnIndexBitwidth+ZEROS_BITWIDTH-1:ColumnIndexBitwidth+ZEROS_BITWIDTH],
    {LINE_TO_RAM_ADDRESS_LEFT_SHIFT{1'b0}}
  };

  logic burst_is_reading;  // true if in burst read operation
  logic [31:0] burst_data_in;  // current data to write to cache line column
  logic burst_write_enable[COLUMN_COUNT];  // which column(s) to write enable 'burst_data_in'
  logic burst_tag_write_enable;  // true if write tag - done at the end of reading a cache line

  logic burst_is_writing;  // true if in burst write operation

  wire [31:0] cached_tag_and_flags;
  logic tag_write_enable;  // true when cache hit; write to set line dirty
  logic [31:0] tag_data_in;  // tag and flags written when cache hit write

  bram #(
      .AddressBitwidth(LineIndexBitwidth)
  ) tag (
      .clk,
      .write_enable({4{tag_write_enable}}),
      .address(line_ix),
      .data_in(tag_data_in),
      .data_out(cached_tag_and_flags)
  );

  // extract portions of the combined tag, valid, dirty line info
  wire line_valid = cached_tag_and_flags[LINE_VALID_BIT];
  wire line_dirty = cached_tag_and_flags[LINE_DIRTY_BIT];
  wire [TAG_BITWIDTH-1:0] cached_tag = cached_tag_and_flags[TAG_BITWIDTH-1:0];

  // starting address in burst RAM for the cached line
  wire [RamAddressBitwidth-1:0] cached_line_address = {
    {cached_tag, line_ix}, {LINE_TO_RAM_ADDRESS_LEFT_SHIFT{1'b0}}
  };

  wire cache_line_hit = line_valid && address_tag == cached_tag;

  assign busy = enable && !cache_line_hit;

  // select data from requested column
  assign data_out = column_data_out[column_ix];
  assign data_out_ready = write_enable != 0 ? 0 : enable && cache_line_hit;

  // 8 instances of byte enabled semi dual port RAM blocks
  // if cache miss then connect to the state machine that loads a cache line
  logic [3:0] column_write_enable[COLUMN_COUNT];
  logic [31:0] column_data_out[COLUMN_COUNT];

  // counter that keeps track of auto refresh interval
  logic [$clog2(AutoRefreshPeriodCycles+2)-1:0] refresh_cycle_counter;
  // note: +2 because counter is compared using >AutoRefreshPeriodCycles

  // counter used in FSM at read and write cache line
  localparam int unsigned MAX_COUNTER_VALUE = 
    (COLUMN_COUNT>(WaitsPriorToDataAtRead+1))?COLUMN_COUNT:(WaitsPriorToDataAtRead+1);
  // note: +1 because counter is compared using ==WaitsPriorToDataAtSend
  // note: Gowin EDA 1.9.11.02 does not support `$max(...)`
  logic [$clog2(MAX_COUNTER_VALUE)-1:0] counter;

  generate
    for (genvar i = 0; i < COLUMN_COUNT; i++) begin : column
      bram #(
          .AddressBitwidth(LineIndexBitwidth)
      ) column (
          .clk,
          .write_enable(column_write_enable[i]),
          .address(line_ix),
          .data_in(burst_is_reading ? burst_data_in : data_in),
          .data_out(column_data_out[i])
      );
    end
  endgenerate

  always_comb begin
    for (int i = 0; i < COLUMN_COUNT; i++) begin
      column_write_enable[i] = 0;
    end

    tag_write_enable = 0;
    tag_data_in = 0;

    if (burst_is_reading) begin
      // writing to the cache line in a burst read from RAM
      // select the write from burst registers
      for (int i = 0; i < COLUMN_COUNT; i++) begin
        column_write_enable[i] = {4{burst_write_enable[i]}};
      end
      // write tag of the fetched cache line when burst is finished reading
      // the line
      tag_write_enable = burst_tag_write_enable;
      tag_data_in = {1'b0, 1'b1, address_tag};
      // note: {dirty, valid, upper address bits}
    end else if (burst_is_writing) begin
      // do nothing while writing to ram
    end else if (write_enable != 0) begin
`ifdef DBG
      $display("%m: %t: write 0x%h = 0x%h  mask: %b  line: %0d  column: %0d", $time, address,
               data_in, write_enable, line_ix, column_ix);
`endif
      if (cache_line_hit) begin
`ifdef DBG
        $display("%m: %t: cache hit, set dirty flag", $time);
`endif
        // enable write tag with dirty bit set
        tag_write_enable = 1;
        tag_data_in = {1'b1, 1'b1, address_tag};
        // note: { dirty, valid, tag }

        // write enable the addressed column in the cache line
        column_write_enable[column_ix] = write_enable;
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
    Idle,
    Refresh,
    Write1,
    Write2,
    Write3,
    Read1,
    Read2,
    Read3,
    Read4
  } state_e;

  state_e state;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      burst_tag_write_enable <= 0;
      for (int i = 0; i < COLUMN_COUNT; i++) begin
        burst_write_enable[i] <= 0;
      end
      burst_is_reading <= 0;
      burst_is_writing <= 0;
      refresh_cycle_counter <= AutoRefreshPeriodCycles + 1;
      // note: +1 to trigger a refresh at first Idle state
      state <= Idle;
    end else begin
`ifdef DBG
      $display("%m: %t: state: %0d", $time, state);
`endif
      unique case (state)
        Idle: begin
          refresh_cycle_counter <= refresh_cycle_counter + 1'b1;
          if (refresh_cycle_counter > AutoRefreshPeriodCycles) begin
`ifdef DBG
            $display("%m: %t: auto refresh at cycle counter: %0d", $time, refresh_cycle_counter);
`endif
            I_sdrc_cmd_en <= 1;
            I_sdrc_cmd <= 3'b001;  // auto-refresh
            state <= Refresh;
          end else begin
            if (enable && !cache_line_hit) begin
              // cache miss, start reading the addressed cache line and evict current if dirty
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
              end else begin  // not line_dirty
`ifdef DBG
                if (write_enable && !line_dirty) begin
                  $display("%m: %t: line %0d not dirty", $time, line_ix);
                end
                $display("%m: %t: read line from RAM address 0x%h", $time, burst_line_address);
                $display("%m: %t: activating for read bank/row: 0x%h", $time, burst_line_address);
`endif
                I_sdrc_cmd_en <= 1;
                I_sdrc_cmd <= 3'b011;  // activate bank and row of cache line
                I_sdrc_addr <= burst_line_address;
                burst_is_reading <= 1;
                state <= Read1;
              end
            end
          end
        end

        Refresh: begin
          I_sdrc_cmd_en <= 0;
          if (O_sdrc_cmd_ack) begin
            refresh_cycle_counter <= 0;
            state <= Idle;
          end
        end

        Write1: begin
          I_sdrc_cmd_en <= 0;
`ifdef DBG
          $display("%m: %t: wait for ACTIVE to complete before write", $time);
`endif
          // wait for ACTIVE command to complete
          if (O_sdrc_cmd_ack) begin
            I_sdrc_cmd_en <= 1;
            I_sdrc_cmd <= 3'b100;  // write
            I_sdrc_addr <= cached_line_address;
            I_sdrc_data_len <= COLUMN_COUNT - 1;
            I_sdrc_data <= column_data_out[0];
`ifdef DBG
            $display("%m: %t: write column[0]=0x%h", $time, column_data_out[0]);
`endif
            counter <= 1;
            state   <= Write2;
          end
        end

        Write2: begin
          I_sdrc_cmd_en <= 0;
          I_sdrc_data   <= column_data_out[counter];
`ifdef DBG
          $display("%m: %t: write column[%0d]=0x%h", $time, counter, column_data_out[counter]);
`endif
          if (counter == COLUMN_COUNT - 1) begin
            // note: this was the last column
            state <= Write3;
          end
          counter <= counter + 1'b1;
        end

        Write3: begin
          if (O_sdrc_cmd_ack) begin
            // ! note: in the manual ACK arrives 2 cycles after command issued
            // !       in simulation ACK arrives 3 cycles after data has been written
            burst_is_writing <= 0;
            burst_is_reading <= 1;
            I_sdrc_cmd_en <= 1;
            I_sdrc_cmd <= 3'b011;  // activate
            I_sdrc_addr <= burst_line_address;
            state <= Read1;
          end
        end

        Read1: begin
          I_sdrc_cmd_en <= 0;
          // wait for ACTIVE command to complete
`ifdef DBG
          $display("%m: %t: wait for ACTIVE to complete before read", $time);
`endif
          if (O_sdrc_cmd_ack) begin
            I_sdrc_cmd_en <= 1;
            I_sdrc_cmd <= 3'b101;  // read
            I_sdrc_addr <= burst_line_address;
            I_sdrc_data_len <= COLUMN_COUNT - 1;
            counter <= 0;
            state <= Read2;
          end
        end

        Read2: begin
          I_sdrc_cmd_en <= 0;
          counter <= counter + 1'b1;
          if (counter == WaitsPriorToDataAtRead) begin
            burst_write_enable[0] <= 1;  // enable write to first column
            burst_data_in <= O_sdrc_data;  // data to write to first column
`ifdef DBG
            $display("%m: %t: data 0 from SDRAM 0x%h", $time, O_sdrc_data);
`endif
            counter <= 1;
            state   <= Read3;
          end
        end

        Read3: begin
          burst_write_enable[counter-1] <= 0;  // disable write to previous column
          burst_write_enable[counter] <= 1;  // enable write to current column
          burst_data_in <= O_sdrc_data;  // data to write to current column
`ifdef DBG
          $display("%m: %t: data %0d from SDRAM 0x%h", $time, counter, O_sdrc_data);
`endif
          counter <= counter + 1'b1;
          if (counter == COLUMN_COUNT - 1) begin
            // note: this is the last column, will be written during next cycle
            burst_tag_write_enable <= 1;  // also write tag during next cycle
            state <= Read4;
          end
        end

        Read4: begin
          // note: last column is being written during this cycle
          burst_write_enable[COLUMN_COUNT-1] <= 0;  // disable write to last column
          burst_is_reading <= 0;  // done burst reading, enable cache next cycle
          burst_tag_write_enable <= 0;  // disable write to tag
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
