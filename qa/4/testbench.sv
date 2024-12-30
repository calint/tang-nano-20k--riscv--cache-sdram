//
// ramio + sdram + uartrx + uarttx
//
`timescale 1ns / 1ps
//
`default_nettype none

module testbench;

  localparam int unsigned RAM_ADDRESS_BIT_WIDTH = 12;  // 2 ^ 12 * 4 B
  localparam int unsigned FLASH_TRANSFER_BYTE_COUNT = 32'h0000_0100;

  logic rst_n;
  logic clk = 1;
  localparam int unsigned clk_tk = 10;
  always #(clk_tk / 2) clk = ~clk;

  //------------------------------------------------------------------------
  // SDRAM and controller
  //------------------------------------------------------------------------
  // SDRAM wires
  wire                              O_sdram_clk;
  wire                              O_sdram_cke;
  wire                              O_sdram_cs_n;  // chip select
  wire                              O_sdram_cas_n;  // columns address select
  wire                              O_sdram_ras_n;  // row address select
  wire                              O_sdram_wen_n;  // write enable
  wire                       [31:0] IO_sdram_dq;  // 32 bit bidirectional data bus
  wire                       [10:0] O_sdram_addr;  // 11 bit multiplexed address bus
  wire                       [ 1:0] O_sdram_ba;  // two banks
  wire                       [ 3:0] O_sdram_dqm;  // 32/4

  // wires between 'sdram_controller' interface and 'ramio'
  wire I_sdrc_rst_n = rst_n;
  wire I_sdrc_clk = clk;
  wire I_sdram_clk = clk;
  logic                             I_sdrc_cmd_en;
  logic                      [ 2:0] I_sdrc_cmd;
  logic                             I_sdrc_precharge_ctrl;
  logic                             I_sdram_power_down;
  logic                             I_sdram_selfrefresh;
  logic                      [20:0] I_sdrc_addr;
  logic                      [ 3:0] I_sdrc_dqm;
  logic                      [31:0] I_sdrc_data;
  logic                      [ 7:0] I_sdrc_data_len;
  wire                       [31:0] O_sdrc_data;
  wire                              O_sdrc_init_done;
  wire                              O_sdrc_cmd_ack;

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

  //------------------------------------------------------------------------
  // ramio
  //------------------------------------------------------------------------
  logic enable;
  logic [1:0] write_type;
  logic [2:0] read_type;
  logic [31:0] address;
  logic [31:0] data_out;
  logic data_out_ready;
  logic [31:0] data_in;
  logic busy;
  logic uart_tx;
  logic uart_rx;
  logic [3:0] led;

  ramio #(
      .RamAddressBitWidth(RAM_ADDRESS_BIT_WIDTH),
      .RamAddressingMode(2),  // 32 bits word per address in RAM 
      .CacheLineIndexBitWidth(1),
      .ClockFrequencyHz(20_250_000),
      .BaudRate(20_250_000)
  ) ramio (
      .rst_n(rst_n && O_sdrc_init_done),
      .clk,
      .enable(enable),
      .write_type(write_type),
      .read_type(read_type),
      .address(address),
      .data_in(data_in),
      .data_out(data_out),
      .data_out_ready(data_out_ready),
      .busy(busy),
      .led(led[3:0]),
      .uart_tx,
      .uart_rx,

      // wires from sdram controller
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

  // Internal variables
  logic [2:0] state;
  logic [2:0] return_state;
  logic [23:0] flash_data_to_send;
  logic [4:0] flash_num_bits_to_send;
  logic [31:0] flash_counter;
  logic [7:0] flash_current_byte_out;
  logic [7:0] flash_current_byte_num;
  logic [7:0] flash_data_out[4];
  logic [31:0] address_next;

  localparam BootInit = 0;
  localparam BootLoadCommandToSend = 1;
  localparam BootSend = 2;
  localparam BootLoadAddressToSend = 3;
  localparam BootReadData = 4;
  localparam BootStartWrite = 5;
  localparam BootWrite = 6;
  localparam Done = 7;


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

    enable = 0;
    read_type = 0;
    write_type = 0;
    address = 0;
    address_next = 0;
    data_in = 0;

    flash_counter = 0;
    flash_clk = 0;
    flash_mosi = 0;
    flash_cs_n = 1;

    state = BootInit;

    while (state != Done) begin
      #clk_tk;

      case (state)
        BootInit: begin
          flash_counter = flash_counter + 1;
          if (flash_counter >= 10) begin
            flash_counter = 0;
            state = BootLoadCommandToSend;
          end
        end

        BootLoadCommandToSend: begin
          flash_cs_n = 0;  // enable flash
          flash_data_to_send[23-:8] = 3;  // command 3: read
          flash_num_bits_to_send = 8;
          state = BootSend;
          return_state = BootLoadAddressToSend;
        end

        BootLoadAddressToSend: begin
          flash_data_to_send = 0;
          flash_num_bits_to_send = 24;
          flash_current_byte_num = 0;
          state = BootSend;
          return_state = BootReadData;
        end

        BootSend: begin
          if (flash_counter == 0) begin
            flash_counter = 1;
            flash_clk = 0;
            flash_mosi = flash_data_to_send[23];
            flash_data_to_send = {flash_data_to_send[22:0], 1'b0};
            flash_num_bits_to_send = flash_num_bits_to_send - 1'b1;
          end else begin
            flash_counter = 0;
            flash_clk = 1;
            if (flash_num_bits_to_send == 0) begin
              state = return_state;
            end
          end
        end

        BootReadData: begin
          if (!flash_counter[0]) begin
            flash_clk = 0;
            if (flash_counter[3:0] == 0 && flash_counter > 0) begin
              // every 16'th clock cycle (8 to flash) read the current byte to data out
              flash_data_out[flash_current_byte_num] = flash_current_byte_out;
              if (flash_current_byte_num == 3) begin
                // every 4'th byte write to 'ramio'
                state = BootStartWrite;
              end
              flash_current_byte_num = flash_current_byte_num + 1'b1;
            end
          end else begin
            flash_clk = 1;
            flash_current_byte_out = {flash_current_byte_out[6:0], flash_miso};
          end
          flash_counter = flash_counter + 1;
        end

        BootStartWrite: begin
          if (!busy) begin
            enable = 1;
            read_type = 0;
            write_type = 2'b11;
            address = address_next;
            address_next = address_next + 4;
            data_in = {flash_data_out[3], flash_data_out[2], flash_data_out[1], flash_data_out[0]};
            state = BootWrite;
          end
        end

        BootWrite: begin
          if (!busy) begin
            enable = 0;
            flash_current_byte_num = 0;
            if (address_next < FLASH_TRANSFER_BYTE_COUNT) begin
              state = BootReadData;
            end else begin
              flash_cs_n = 1;  // disable flash
              state = Done;  // Reset state machine
            end
          end
        end

        Done: begin
        end
      endcase
    end

    while (state != Done) #clk_tk;

    data_in <= 0;

    // read; cache miss
    address <= 16;
    read_type <= 3'b111;  // read full word
    write_type <= 2'b00;  // disable write
    enable <= 1;
    #clk_tk;

    while (!data_out_ready) #clk_tk;

    assert (data_out == 32'hD5B8A9C4)
    else $fatal;

    // read unsigned byte; cache hit
    address <= 17;
    read_type <= 3'b001;
    write_type <= 2'b00;
    enable <= 1;
    #clk_tk;

    while (!data_out_ready) #clk_tk;

    assert (data_out == 32'h0000_00A9)
    else $fatal;

    // read unsigned short; cache hit
    address <= 18;
    read_type <= 3'b010;
    write_type <= 2'b00;
    enable <= 1;
    #clk_tk;

    while (!data_out_ready) #clk_tk;

    assert (data_out == 32'h0000_D5B8)
    else $fatal;

    // write unsigned byte; cache hit
    enable <= 1;
    read_type <= 0;
    write_type <= 2'b01;
    address <= 17;
    data_in <= 32'hab;
    #clk_tk;
    while (busy) #clk_tk;

    // read unsigned byte; cache hit
    enable <= 1;
    address <= 17;
    read_type <= 3'b001;
    write_type <= 0;
    #clk_tk;

    while (!data_out_ready) #clk_tk;

    assert (data_out == 32'h0000_00ab)
    else $fatal;

    // write half-word; cache hit
    enable <= 1;
    read_type <= 0;
    write_type <= 2'b10;
    address <= 18;
    data_in <= 32'h1234;
    #clk_tk;
    while (busy) #clk_tk;

    // read unsigned half-word; cache hit
    enable <= 1;
    address <= 18;
    read_type <= 3'b010;
    write_type <= 0;
    #clk_tk;

    while (!data_out_ready) #clk_tk;

    assert (data_out == 32'h0000_1234)
    else $fatal;

    // write word; cache hit
    enable <= 1;
    read_type <= 0;
    write_type <= 2'b11;
    address <= 20;
    data_in <= 32'habcd_1234;
    #clk_tk;
    while (busy) #clk_tk;

    // read word; cache hit
    enable <= 1;
    address <= 20;
    read_type <= 3'b111;
    write_type <= 0;
    #clk_tk;

    while (!data_out_ready) #clk_tk;

    assert (data_out == 32'habcd_1234)
    else $fatal;

    // write to UART
    enable <= 1;
    address <= 32'hffff_fffe;
    read_type <= 0;
    write_type <= 2'b01;
    data_in <= 8'b1010_1010;
    #clk_tk;

    // poll UART tx for done
    enable <= 1;
    address <= 32'hffff_fffe;
    read_type <= 3'b001;
    write_type <= 0;
    #clk_tk;

    // start bit
    #clk_tk;
    assert (uart_tx == 0)
    else $fatal;
    // bit 1
    #clk_tk;
    assert (uart_tx == 0)
    else $fatal;
    // bit 2
    #clk_tk;
    assert (uart_tx == 1)
    else $fatal;
    // bit 3
    #clk_tk;
    assert (uart_tx == 0)
    else $fatal;
    // bit 4
    #clk_tk;
    assert (uart_tx == 1)
    else $fatal;
    // bit 5
    #clk_tk;
    assert (uart_tx == 0)
    else $fatal;
    // bit 6
    #clk_tk;
    assert (uart_tx == 1)
    else $fatal;
    // bit 7
    #clk_tk;
    assert (uart_tx == 0)
    else $fatal;

    assert (data_out != 0)
    else $fatal;

    // stop bit
    #clk_tk;
    assert (uart_tx == 1)
    else $fatal;

    assert (data_out != 0)
    else $fatal;

    #clk_tk;
    assert (uart_tx == 1)
    else $fatal;

    #clk_tk;

    assert (ramio.uarttx.bsy == 0)
    else $fatal;

    #clk_tk;
    assert (ramio.uarttx_data_sending == -1)
    else $fatal;

    assert (data_out == -1)
    else $fatal;

    // start bit
    uart_rx <= 0;
    #clk_tk;
    // bit 0
    uart_rx <= 0;
    #clk_tk;
    // bit 1
    uart_rx <= 1;
    #clk_tk;
    // bit 2
    uart_rx <= 0;
    #clk_tk;
    // bit 3
    uart_rx <= 1;
    #clk_tk;
    // bit 4
    uart_rx <= 0;
    #clk_tk;
    // bit 5
    uart_rx <= 1;
    #clk_tk;
    // bit 6
    uart_rx <= 0;
    #clk_tk;
    // bit 7
    uart_rx <= 1;
    #clk_tk;
    // stop bit
    uart_rx <= 1;
    #clk_tk;

    assert (data_out == -1)
    else $fatal;

    #clk_tk;  // 'ramio' transfers data from 'uartrx'

    assert (ramio.uartrx_data_ready && ramio.uartrx_data == 8'haa)
    else $fatal;

    // read from UART
    enable <= 1;
    address <= 32'hffff_fffd;
    read_type <= 3'b001;
    write_type <= 0;
    #clk_tk;

    assert (data_out == 8'haa)
    else $fatal;

    #clk_tk;  // 'ramio' clears data from 'uartrx'

    // read from UART again, should be 0
    enable <= 1;
    address <= 32'hffff_fffd;
    read_type <= 3'b001;
    write_type <= 0;
    #clk_tk;

    assert (data_out == -1)
    else $fatal;

    // write unsigned byte; cache miss, eviction
    enable <= 1;
    read_type <= 0;
    write_type <= 2'b01;
    address <= 81;
    data_in <= 32'hab;
    #clk_tk;
    while (busy) #clk_tk;

    // read unsigned byte; cache hit
    enable <= 1;
    address <= 81;
    read_type <= 3'b001;
    write_type <= 0;
    #clk_tk;

    while (!data_out_ready) #clk_tk;

    assert (data_out == 32'h0000_00ab)
    else $fatal;

    // write half-word; cache hit
    enable <= 1;
    read_type <= 0;
    write_type <= 2'b10;
    address <= 82;
    data_in <= 32'h1234;
    #clk_tk;
    while (busy) #clk_tk;

    // read unsigned half-word; cache hit
    enable <= 1;
    address <= 82;
    read_type <= 3'b010;
    write_type <= 0;
    #clk_tk;

    while (!data_out_ready) #clk_tk;

    assert (data_out == 32'h0000_1234)
    else $fatal;

    // write word; cache hit
    enable <= 1;
    read_type <= 0;
    write_type <= 2'b11;
    address <= 84;
    data_in <= 32'habcd_1234;
    #clk_tk;
    while (busy) #clk_tk;

    // read word; cache hit
    enable <= 1;
    address <= 84;
    read_type <= 3'b111;
    write_type <= 0;
    #clk_tk;

    while (!data_out_ready) #clk_tk;

    assert (data_out == 32'habcd_1234)
    else $fatal;

    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;

    $display("");
    $display("PASSED");
    $display("");
    $finish;

  end

endmodule

`default_nettype wire
