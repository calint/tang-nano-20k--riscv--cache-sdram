//
// cache
//
`timescale 1ns / 1ps
//
`default_nettype none

module testbench;

  localparam int unsigned RAM_ADDRESS_BIT_WIDTH = 8;

  logic rst_n;
  logic clk = 1;
  localparam int unsigned clk_tk = 36;
  always #(clk_tk / 2) clk = ~clk;

  // ----------------------------------------------------------
  // SDRAM wires
  logic O_sdram_clk;
  logic O_sdram_cke;
  logic O_sdram_cs_n;  // chip select
  logic O_sdram_cas_n;  // columns address select
  logic O_sdram_ras_n;  // row address select
  logic O_sdram_wen_n;  // write enable
  wire [31:0] IO_sdram_dq;  // 32 bit bidirectional data bus
  logic [10:0] O_sdram_addr;  // 11 bit multiplexed address bus
  logic [1:0] O_sdram_ba;  // two banks
  logic [3:0] O_sdram_dqm;  // 32/4

  // logics between 'sdram_controller' interface and 'cache'
  logic I_sdrc_rst_n = rst_n;
  logic I_sdrc_clk = clk;  // 27 MHz
  logic I_sdram_clk = clk;  // 66 MHz
  logic I_sdrc_cmd_en;
  logic [2:0] I_sdrc_cmd;
  logic I_sdrc_precharge_ctrl;
  logic I_sdram_power_down;
  logic I_sdram_selfrefresh;
  logic [20:0] I_sdrc_addr;
  logic [3:0] I_sdrc_dqm;
  logic [31:0] I_sdrc_data;
  logic [7:0] I_sdrc_data_len;
  logic [31:0] O_sdrc_data;
  logic O_sdrc_init_done;
  logic O_sdrc_cmd_ack;

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

  // ----------------------------------------------------------
  // logics to cache
  logic enable;
  logic [31:0] address;
  logic [31:0] data_out;
  logic data_out_ready;
  logic [31:0] data_in;
  logic [3:0] write_enable;
  logic busy;

  cache #(
      .LineIndexBitWidth (1),
      .RamAddressBitWidth(RAM_ADDRESS_BIT_WIDTH)
  ) cache (
      .rst_n(rst_n),
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

  //------------------------------------------------------------------------
  logic flash_clk;
  logic flash_miso;
  logic flash_mosi;
  logic flash_cs_n;

  flash #(
      .DataFilePath("ram.mem"),
      .AddressBitWidth(RAM_ADDRESS_BIT_WIDTH)
  ) flash (
      .rst_n,
      .clk (flash_clk),
      .miso(flash_miso),
      .mosi(flash_mosi),
      .cs_n(flash_cs_n)
  );

  //------------------------------------------------------------------------
  // variables used at transfer from flash to ram
  logic [23:0] flash_data_to_send;
  logic [4:0] flash_num_bits_to_send;
  logic [31:0] flash_counter;
  logic [7:0] flash_current_byte_out;
  logic [7:0] flash_current_byte_num;
  logic [7:0] flash_data_out[4];
  logic [31:0] address_next;

  typedef enum {
    BootInit,
    BootLoadCommandToSend,
    BootSend,
    BootLoadAddressToSend,
    BootReadData,
    BootStartWrite,
    BootWrite,
    Done
  } state_e;

  state_e state;
  state_e return_state;

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

    //-------------------------------------------
    // transfer data from flash to ram
    //-------------------------------------------
    enable <= 0;
    address <= 0;
    address_next <= 0;
    data_in <= 0;
    flash_counter <= 0;
    flash_clk <= 0;
    flash_mosi <= 0;
    flash_cs_n <= 1;
    state <= BootInit;
    #clk_tk;

    while (state != Done) begin
      case (state)
        BootInit: begin
          flash_counter <= flash_counter + 1;
          if (flash_counter >= 10) begin
            flash_counter <= 0;
            state = BootLoadCommandToSend;
          end
        end

        BootLoadCommandToSend: begin
          flash_cs_n <= 0;  // enable flash
          flash_data_to_send[23-:8] <= 3;  // command 3: read
          flash_num_bits_to_send <= 8;
          state = BootSend;
          return_state = BootLoadAddressToSend;
        end

        BootLoadAddressToSend: begin
          flash_data_to_send <= 0;
          flash_num_bits_to_send <= 24;
          flash_current_byte_num <= 0;
          state = BootSend;
          return_state = BootReadData;
        end

        BootSend: begin
          if (flash_counter == 0) begin
            flash_counter <= 1;
            flash_clk <= 0;
            flash_mosi <= flash_data_to_send[23];
            flash_data_to_send <= {flash_data_to_send[22:0], 1'b0};
            flash_num_bits_to_send = flash_num_bits_to_send - 1'b1;
          end else begin
            flash_counter <= 0;
            flash_clk <= 1;
            if (flash_num_bits_to_send == 0) begin
              state <= return_state;
            end
          end
        end

        BootReadData: begin
          if (!flash_counter[0]) begin
            flash_clk <= 0;
            if (flash_counter[3:0] == 0 && flash_counter > 0) begin
              // every 16'th clock cycle (8 to flash) read the current byte to data out
              flash_data_out[flash_current_byte_num] = flash_current_byte_out;
              if (flash_current_byte_num == 3) begin
                // every 4'th byte write to 'ramio'
                state <= BootStartWrite;
              end
              flash_current_byte_num <= flash_current_byte_num + 1'b1;
            end
          end else begin
            flash_clk <= 1;
            flash_current_byte_out <= {flash_current_byte_out[6:0], flash_miso};
          end
          flash_counter <= flash_counter + 1;
        end

        BootStartWrite: begin
          if (!busy) begin
            enable <= 1;
            read_type <= 0;
            write_type <= 2'b11;
            address <= address_next;
            address_next <= address_next + 4;
            data_in <= {flash_data_out[3], flash_data_out[2], flash_data_out[1], flash_data_out[0]};
            state <= BootWrite;
          end
        end

        BootWrite: begin
          if (!busy) begin
            enable <= 0;
            flash_current_byte_num <= 0;
            if (address_next < FLASH_TRANSFER_BYTE_COUNT) begin
              state <= BootReadData;
            end else begin
              flash_cs_n <= 1;  // disable flash
              state <= Done;  // Reset state machine
            end
          end
        end

        Done: begin
        end
      endcase

      #clk_tk;
    end

    while (state != Done) #clk_tk;

    enable <= 1;

    address <= 0;
    address_next <= 0;
    #clk_tk;

    // write some data
    write_enable <= 4'b1111;
    for (int i = 0; i < 2 ** RAM_ADDRESS_BIT_WIDTH; i = i + 1) begin
      address <= address_next;
      address_next <= address_next + 4;
      data_in = i;
      #clk_tk;
      while (busy) #clk_tk;
    end

    // read cache miss
    address <= 4;
    write_enable <= 0;
    #clk_tk;
    while (!data_out_ready) #clk_tk;
    assert (data_out == 1)
    else $fatal;

    // read cache hit
    address <= 8;
    write_enable <= 0;
    #clk_tk;
    while (!data_out_ready) #clk_tk;
    assert (data_out == 2)
    else $fatal;

    // write cache hit
    address <= 4;
    data_in <= 32'habcd_1234;
    write_enable <= 4'b1111;
    #clk_tk;

    // read cache hit
    address <= 4;
    write_enable <= 0;
    #clk_tk;
    assert (data_out_ready)
    else $fatal;
    assert (data_out == 32'habcd_1234)
    else $fatal;

    // read cache miss
    address <= 64;
    write_enable <= 0;
    #clk_tk;
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

    // read cache hit
    address <= 64;
    write_enable <= 0;
    #clk_tk;
    assert (data_out_ready)
    else $fatal;
    assert (data_out == 32'hf55e_1234)
    else $fatal;

    // read cache miss -> evict dirty
    address <= 4;
    write_enable <= 0;
    #clk_tk;
    while (!data_out_ready) #clk_tk;
    assert (data_out == 1)
    else $fatal;

    // read cache miss -> evict not dirty
    address <= 64;
    write_enable <= 0;
    #clk_tk;
    assert (data_out_ready)
    else $fatal;
    assert (data_out == 32'hf55e_1234)
    else $fatal;

    $finish;
  end

endmodule

`default_nettype wire
