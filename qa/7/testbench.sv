//
// core  (bug fix #1)
//
`timescale 1ns / 1ps
//
`default_nettype none

module testbench;

  localparam int unsigned RAM_ADDRESS_BITWIDTH = 10;  // 2 ^ 10 * 4 B = 4 KB

  logic rst_n;
  logic clk = 1;
  localparam int unsigned clk_tk = 10;
  always #(clk_tk / 2) clk = ~clk;

  wire  [ 5:0] led;
  wire         uart_tx;
  logic        uart_rx;

  //------------------------------------------------------------------------
  // sdram_controller
  //------------------------------------------------------------------------

  // wires between 'sdram' and 'sdram_controller'
  wire         O_sdram_clk = clk;
  wire         O_sdram_cke;
  wire         O_sdram_cs_n;  // chip select
  wire         O_sdram_cas_n;  // columns address select
  wire         O_sdram_ras_n;  // row address select
  wire         O_sdram_wen_n;  // write enable
  wire  [31:0] IO_sdram_dq;  // 32 bit bidirectional data bus
  wire  [10:0] O_sdram_addr;  // 11 bit multiplexed address bus
  wire  [ 1:0] O_sdram_ba;  // two banks
  wire  [ 3:0] O_sdram_dqm;  // 32/4

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
  // sdram_controller
  //------------------------------------------------------------------------

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

  //------------------------------------------------------------------------
  // ramio
  //------------------------------------------------------------------------

  // wires between 'ramio' and 'core'
  wire ramio_enable;
  wire [1:0] ramio_write_type;
  wire [2:0] ramio_read_type;
  wire [31:0] ramio_address;
  wire [31:0] ramio_data_out;
  wire ramio_data_out_ready;
  wire [31:0] ramio_data_in;
  wire ramio_busy;

  ramio #(
      .RamAddressBitwidth(RAM_ADDRESS_BITWIDTH),
      .RamAddressingMode(2),  // 32 bits word per address in RAM 
      .CacheLineIndexBitwidth(1),
      .ClockFrequencyHz(20_250_000),
      .BaudRate(20_250_000),
      .SDCardSimulate(1),
      .SDCardClockDivider(0)  // at 30 MHz this works
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
  // flash
  //------------------------------------------------------------------------

  // wires between 'flash' and 'core'
  wire flash_clk;
  wire flash_miso;
  wire flash_mosi;
  wire flash_cs_n;

  flash #(
      .DataFilePath("ram.mem"),
      .AddressBitwidth(RAM_ADDRESS_BITWIDTH + 2)  // in bytes 2 ^ 12 = 4096 B
  ) flash (
      .rst_n,
      .clk (flash_clk),
      .miso(flash_miso),
      .mosi(flash_mosi),
      .cs_n(flash_cs_n)
  );

  //------------------------------------------------------------------------
  // core
  //------------------------------------------------------------------------

  core #(
      .StartupWaitCycles(0),
      .FlashTransferByteCount(2048)
  ) core (
      .rst_n(rst_n && O_sdrc_init_done),
      .clk,
      .led  (led[4]),

      .ramio_enable,
      .ramio_write_type,
      .ramio_read_type,
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

  //------------------------------------------------------------------------

  assign led[5] = ~ramio_busy;

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

    // 0:	00010137          	lui	x2,0x10
    while (core.state != core.CpuExecute) #clk_tk;
    #clk_tk;
    #clk_tk;
    assert (core.registers.data[2] == 32'h0001_0000)
    else $fatal;

    // 4:	004000ef          	jal	x1,8 <run>
    while (core.state != core.CpuExecute) #clk_tk;
    #clk_tk;
    assert (core.pc == 8)
    else $fatal;

    // 8:	ff010113          	addi	x2,x2,-16 # fff0 <__global_pointer$+0xd75c>
    while (core.state != core.CpuExecute) #clk_tk;
    #clk_tk;
    #clk_tk;
    assert (core.registers.data[2] == 32'h0000_fff0)
    else $fatal;

    // c:	00112623          	sw	x1,12(x2) # [0xfff0+12] = x1
    while (core.state != core.CpuExecute) #clk_tk;
    while (core.state != core.CpuFetch) #clk_tk;

    // 10:	00812423          	sw	x8,8(x2)  # [0xfff0+8] = x8
    while (core.state != core.CpuExecute) #clk_tk;
    while (core.state != core.CpuFetch) #clk_tk;

    // 14:	01010413          	addi	x8,x2,16  # 0xfff0 + 16
    while (core.state != core.CpuExecute) #clk_tk;
    #clk_tk;
    #clk_tk;
    assert (core.registers.data[8] == 32'h0001_0000)
    else $fatal;

    // 18:	00000513          	addi	x10,x0,0
    while (core.state != core.CpuExecute) #clk_tk;
    #clk_tk;
    #clk_tk;
    assert (core.registers.data[10] == 0)
    else $fatal;

    // 1c:	00000097          	auipc	x1,0x0
    while (core.state != core.CpuExecute) #clk_tk;
    #clk_tk;
    #clk_tk;
    assert (core.registers.data[1] == 32'h0000_001c)
    else $fatal;

    // 20:	01c080e7          	jalr	x1,28(x1) # 38 <run+0x30>
    while (core.state != core.CpuExecute) #clk_tk;
    #clk_tk;
    assert (core.pc == 32'h0000_0038)
    else $fatal;

    // 38:	fd010113          	addi	x2,x2,-48 # 0xffc0
    while (core.state != core.CpuExecute) #clk_tk;
    #clk_tk;
    #clk_tk;
    assert (core.registers.data[2] == 32'h0000_ffc0)
    else $fatal;

    // 3c:	02812623          	sw	x8,44(x2) #   [0xffec] = 0x1'0000
    while (core.state != core.CpuExecute) #clk_tk;
    #clk_tk;
    while (core.state != core.CpuFetch) #clk_tk;

    // 40:	03010413          	addi	x8,x2,48 # 0xffc0 + 48
    while (core.state != core.CpuExecute) #clk_tk;
    #clk_tk;
    #clk_tk;
    assert (core.registers.data[8] == 32'h0000_fff0)
    else $fatal;

    // 44:	fca42e23          	sw	x10,-36(x8) # [0xfff0 - 36] = [0xffcc] = 0
    while (core.state != core.CpuExecute) #clk_tk;
    #clk_tk;

    // 48:	fdc42783          	lw	x15,-36(x8) # x15 = [0xfff0 - 36] = [0xffcc] = 0
    while (core.state != core.CpuExecute) #clk_tk;
    #clk_tk;
    while (core.state != core.CpuExecute) #clk_tk;
    assert (core.registers.data[15] == 32'h0000_0000)
    else $fatal;

    $display("");
    $display("PASSED");
    $display("");
    $finish;

  end

endmodule

`default_nettype wire
