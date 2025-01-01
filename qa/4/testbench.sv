//
// ramio + sdram + uartrx + uarttx
//
`timescale 1ns / 1ps
//
`default_nettype none

module testbench;

  localparam int unsigned RAM_ADDRESS_BIT_WIDTH = 12;  // 2 ^ 12 * 4 KB
  localparam int unsigned FLASH_TRANSFER_BYTE_COUNT = 256;
  localparam int unsigned UART_OUT_ADDRESS = 32'hffff_fff8;
  localparam int unsigned UART_IN_ADDRESS = 32'hffff_fff4;

  logic rst_n;
  logic clk = 1;
  localparam int unsigned clk_tk = 10;
  always #(clk_tk / 2) clk = ~clk;

  //------------------------------------------------------------------------
  // SDRAM and controller
  //------------------------------------------------------------------------
  // SDRAM wires
  wire        O_sdram_clk;
  wire        O_sdram_cke;
  wire        O_sdram_cs_n;  // chip select
  wire        O_sdram_cas_n;  // columns address select
  wire        O_sdram_ras_n;  // row address select
  wire        O_sdram_wen_n;  // write enable
  wire [31:0] IO_sdram_dq;  // 32 bit bidirectional data bus
  wire [10:0] O_sdram_addr;  // 11 bit multiplexed address bus
  wire [ 1:0] O_sdram_ba;  // two banks
  wire [ 3:0] O_sdram_dqm;  // 32/4

  // wires between 'sdram_controller' interface and 'ramio'
  wire        I_sdrc_rst_n = rst_n;
  wire        I_sdrc_clk = clk;
  wire        I_sdram_clk = clk;
  wire        I_sdrc_cmd_en;
  wire [ 2:0] I_sdrc_cmd;
  wire        I_sdrc_precharge_ctrl;
  wire        I_sdram_power_down;
  wire        I_sdram_selfrefresh;
  wire [20:0] I_sdrc_addr;
  wire [ 3:0] I_sdrc_dqm;
  wire [31:0] I_sdrc_data;
  wire [ 7:0] I_sdrc_data_len;
  wire [31:0] O_sdrc_data;
  wire        O_sdrc_init_done;
  wire        O_sdrc_cmd_ack;

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
  logic ramio_enable;
  logic [1:0] ramio_write_type;
  logic [2:0] ramio_read_type;
  logic [31:0] ramio_address;
  wire [31:0] ramio_data_out;
  wire ramio_data_out_ready;
  wire ramio_busy;
  logic [31:0] ramio_data_in;
  wire ramio_uart_tx;
  logic ramio_uart_rx;
  logic [3:0] ramio_led;

  ramio #(
      .RamAddressBitWidth(RAM_ADDRESS_BIT_WIDTH),
      .RamAddressingMode(2),  // 32 bits word per address in RAM 
      .CacheLineIndexBitWidth(1),
      .ClockFrequencyHz(20_250_000),
      .BaudRate(20_250_000)
  ) ramio (
      .rst_n(rst_n && O_sdrc_init_done),
      .clk,
      .enable(ramio_enable),
      .write_type(ramio_write_type),
      .read_type(ramio_read_type),
      .address(ramio_address),
      .data_in(ramio_data_in),
      .data_out(ramio_data_out),
      .data_out_ready(ramio_data_out_ready),
      .busy(ramio_busy),
      .led(ramio_led),
      .uart_tx(ramio_uart_tx),
      .uart_rx(ramio_uart_rx),

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
  // wires and logic to 'flash'
  logic flash_clk;
  wire  flash_miso;
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
  // copy from 'flash' to 'ramio' task
  //------------------------------------------------------------------------
  typedef enum {
    LoadCommandToSend,
    Send,
    LoadAddressToSend,
    ReadData,
    StartWrite,
    Write,
    Done
  } state_e;

  task copy_flash_to_ram();
    logic [23:0] flash_data_to_send;
    logic [4:0] flash_num_bits_to_send;
    logic [31:0] flash_counter;
    logic [7:0] flash_current_byte_out;
    logic [7:0] flash_current_byte_num;
    logic [7:0] flash_data_out[4];
    logic [31:0] address_next;

    state_e state;
    state_e return_state;

    // init
    ramio_enable <= 0;
    ramio_read_type <= 0;
    ramio_write_type <= 0;
    address_next <= 0;
    ramio_data_in <= 0;
    flash_counter <= 0;
    flash_clk <= 0;
    flash_mosi <= 0;
    flash_cs_n <= 1;

    state <= LoadCommandToSend;
    #clk_tk;

    // start state machine
    while (state != Done) begin
      unique case (state)

        LoadCommandToSend: begin
          flash_cs_n <= 0;  // enable flash
          flash_data_to_send[23-:8] <= 3;  // command 3: read
          flash_num_bits_to_send <= 8;
          state = Send;
          return_state = LoadAddressToSend;
        end

        LoadAddressToSend: begin
          flash_data_to_send <= 0;
          flash_num_bits_to_send <= 24;
          flash_current_byte_num <= 0;
          state = Send;
          return_state = ReadData;
        end

        Send: begin
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

        ReadData: begin
          if (!flash_counter[0]) begin
            flash_clk <= 0;
            if (flash_counter[3:0] == 0 && flash_counter > 0) begin
              // every 16'th clock cycle (8 to flash) read the current byte to data out
              flash_data_out[flash_current_byte_num] = flash_current_byte_out;
              if (flash_current_byte_num == 3) begin
                // every 4'th byte write to 'ramio'
                state <= StartWrite;
              end
              flash_current_byte_num <= flash_current_byte_num + 1'b1;
            end
          end else begin
            flash_clk <= 1;
            flash_current_byte_out <= {flash_current_byte_out[6:0], flash_miso};
          end
          flash_counter <= flash_counter + 1;
        end

        StartWrite: begin
          if (!ramio_busy) begin
            ramio_enable <= 1;
            ramio_read_type <= 0;
            ramio_write_type <= 2'b11;
            ramio_address <= address_next;
            address_next <= address_next + 4;
            ramio_data_in <= {
              flash_data_out[3], flash_data_out[2], flash_data_out[1], flash_data_out[0]
            };
            state <= Write;
          end
        end

        Write: begin
          if (!ramio_busy) begin
            ramio_enable <= 0;
            flash_current_byte_num <= 0;
            if (address_next < FLASH_TRANSFER_BYTE_COUNT) begin
              state <= ReadData;
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
  endtask

  //------------------------------------------------------------------------

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

    copy_flash_to_ram();

    ramio_data_in <= 0;

    // read; cache miss
    ramio_address <= 16;
    ramio_read_type <= 3'b111;  // read full word
    ramio_write_type <= 2'b00;  // disable write
    ramio_enable <= 1;
    #clk_tk;

    while (!ramio_data_out_ready) #clk_tk;

    assert (ramio_data_out == 32'hD5B8A9C4)
    else $fatal;

    // read unsigned byte; cache hit
    ramio_address <= 17;
    ramio_read_type <= 3'b001;
    ramio_write_type <= 2'b00;
    ramio_enable <= 1;
    #clk_tk;

    while (!ramio_data_out_ready) #clk_tk;

    assert (ramio_data_out == 32'h0000_00A9)
    else $fatal;

    // read unsigned short; cache hit
    ramio_address <= 18;
    ramio_read_type <= 3'b010;
    ramio_write_type <= 2'b00;
    ramio_enable <= 1;
    #clk_tk;

    while (!ramio_data_out_ready) #clk_tk;

    assert (ramio_data_out == 32'h0000_D5B8)
    else $fatal;

    // write unsigned byte; cache hit
    ramio_enable <= 1;
    ramio_read_type <= 0;
    ramio_write_type <= 2'b01;
    ramio_address <= 17;
    ramio_data_in <= 32'hab;
    #clk_tk;
    while (ramio_busy) #clk_tk;

    // read unsigned byte; cache hit
    ramio_enable <= 1;
    ramio_address <= 17;
    ramio_read_type <= 3'b001;
    ramio_write_type <= 0;
    #clk_tk;

    while (!ramio_data_out_ready) #clk_tk;

    assert (ramio_data_out == 32'h0000_00ab)
    else $fatal;

    // write half-word; cache hit
    ramio_enable <= 1;
    ramio_read_type <= 0;
    ramio_write_type <= 2'b10;
    ramio_address <= 18;
    ramio_data_in <= 32'h1234;
    #clk_tk;
    while (ramio_busy) #clk_tk;

    // read unsigned half-word; cache hit
    ramio_enable <= 1;
    ramio_address <= 18;
    ramio_read_type <= 3'b010;
    ramio_write_type <= 0;
    #clk_tk;

    while (!ramio_data_out_ready) #clk_tk;

    assert (ramio_data_out == 32'h0000_1234)
    else $fatal;

    // write word; cache hit
    ramio_enable <= 1;
    ramio_read_type <= 0;
    ramio_write_type <= 2'b11;
    ramio_address <= 20;
    ramio_data_in <= 32'habcd_1234;
    #clk_tk;
    while (ramio_busy) #clk_tk;

    // read word; cache hit
    ramio_enable <= 1;
    ramio_address <= 20;
    ramio_read_type <= 3'b111;
    ramio_write_type <= 0;
    #clk_tk;

    while (!ramio_data_out_ready) #clk_tk;

    assert (ramio_data_out == 32'habcd_1234)
    else $fatal;

    // write to UART
    ramio_enable <= 1;
    ramio_address <= UART_OUT_ADDRESS;
    ramio_read_type <= 0;
    ramio_write_type <= 3'b111;
    ramio_data_in <= 8'b1010_1010;
    #clk_tk;

    // poll UART tx for done
    ramio_enable <= 1;
    ramio_address <= UART_OUT_ADDRESS;
    ramio_read_type <= 3'b111;
    ramio_write_type <= 0;
    #clk_tk;
    assert (ramio_data_out == 8'b1010_1010)
    else $fatal;

    // start bit
    #clk_tk;
    assert (ramio_uart_tx == 0)
    else $fatal;
    // bit 1
    #clk_tk;
    assert (ramio_uart_tx == 0)
    else $fatal;
    // bit 2
    #clk_tk;
    assert (ramio_uart_tx == 1)
    else $fatal;
    // bit 3
    #clk_tk;
    assert (ramio_uart_tx == 0)
    else $fatal;
    // bit 4
    #clk_tk;
    assert (ramio_uart_tx == 1)
    else $fatal;
    // bit 5
    #clk_tk;
    assert (ramio_uart_tx == 0)
    else $fatal;
    // bit 6
    #clk_tk;
    assert (ramio_uart_tx == 1)
    else $fatal;
    // bit 7
    #clk_tk;
    assert (ramio_uart_tx == 0)
    else $fatal;

    assert (ramio_data_out != 0)
    else $fatal;

    // stop bit
    #clk_tk;
    assert (ramio_uart_tx == 1)
    else $fatal;

    assert (ramio_data_out == 8'b1010_1010)
    else $fatal;

    #clk_tk;
    assert (ramio_uart_tx == 1)
    else $fatal;

    #clk_tk;

    assert (ramio.uarttx.bsy == 0)
    else $fatal;

    #clk_tk;
    assert (ramio.uarttx_data_sending == -1)
    else $fatal;

    assert (ramio_data_out == -1)
    else $fatal;

    // start bit
    ramio_uart_rx <= 0;
    #clk_tk;
    // bit 0
    ramio_uart_rx <= 0;
    #clk_tk;
    // bit 1
    ramio_uart_rx <= 1;
    #clk_tk;
    // bit 2
    ramio_uart_rx <= 0;
    #clk_tk;
    // bit 3
    ramio_uart_rx <= 1;
    #clk_tk;
    // bit 4
    ramio_uart_rx <= 0;
    #clk_tk;
    // bit 5
    ramio_uart_rx <= 1;
    #clk_tk;
    // bit 6
    ramio_uart_rx <= 0;
    #clk_tk;
    // bit 7
    ramio_uart_rx <= 1;
    #clk_tk;
    // stop bit
    ramio_uart_rx <= 1;
    #clk_tk;

    assert (ramio_data_out == -1)
    else $fatal;

    #clk_tk;  // 'ramio' transfers data from 'uartrx'

    assert (ramio.uartrx_data_ready && ramio.uartrx_data == 8'haa)
    else $fatal;

    // read from UART
    ramio_enable <= 1;
    ramio_address <= UART_IN_ADDRESS;
    ramio_read_type <= 3'b111;
    ramio_write_type <= 0;
    #clk_tk;

    assert (ramio_data_out == 8'haa)
    else $fatal;

    #clk_tk;  // 'ramio' clears data from 'uartrx'

    // read from UART again, should be 0
    ramio_enable <= 1;
    ramio_address <= UART_IN_ADDRESS;
    ramio_read_type <= 3'b111;
    ramio_write_type <= 0;
    #clk_tk;

    assert (ramio_data_out == -1)
    else $fatal;

    // write unsigned byte; cache miss, eviction
    ramio_enable <= 1;
    ramio_read_type <= 0;
    ramio_write_type <= 2'b01;
    ramio_address <= 81;
    ramio_data_in <= 32'hab;
    #clk_tk;
    while (ramio_busy) #clk_tk;

    // read unsigned byte; cache hit
    ramio_enable <= 1;
    ramio_address <= 81;
    ramio_read_type <= 3'b001;
    ramio_write_type <= 0;
    #clk_tk;

    while (!ramio_data_out_ready) #clk_tk;

    assert (ramio_data_out == 32'h0000_00ab)
    else $fatal;

    // write half-word; cache hit
    ramio_enable <= 1;
    ramio_read_type <= 0;
    ramio_write_type <= 2'b10;
    ramio_address <= 82;
    ramio_data_in <= 32'h1234;
    #clk_tk;
    while (ramio_busy) #clk_tk;

    // read unsigned half-word; cache hit
    ramio_enable <= 1;
    ramio_address <= 82;
    ramio_read_type <= 3'b010;
    ramio_write_type <= 0;
    #clk_tk;

    while (!ramio_data_out_ready) #clk_tk;

    assert (ramio_data_out == 32'h0000_1234)
    else $fatal;

    // write word; cache hit
    ramio_enable <= 1;
    ramio_read_type <= 0;
    ramio_write_type <= 2'b11;
    ramio_address <= 84;
    ramio_data_in <= 32'habcd_1234;
    #clk_tk;
    while (ramio_busy) #clk_tk;

    // read word; cache hit
    ramio_enable <= 1;
    ramio_address <= 84;
    ramio_read_type <= 3'b111;
    ramio_write_type <= 0;
    #clk_tk;

    while (!ramio_data_out_ready) #clk_tk;

    assert (ramio_data_out == 32'habcd_1234)
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
