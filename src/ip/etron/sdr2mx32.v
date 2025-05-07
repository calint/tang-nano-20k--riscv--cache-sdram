/******************************************************************************
*
*
*      File Name:  sdr2mx32.v
*        Version:  1.1
*           Date:  05/11/2015
*
*
*        Company:  Etron Technology, Inc.
*          Model:  sdr2mx32   (2Meg x 32 / 4 Banks)
*
*    Description:  Etron 64Mb SDRAM Verilog model
*    tCK option:   /-5/-6/-7/
*
*    Note:  - Set simulator resolution to "ps" accuracy
*                - Set Debug = 0 to disable $display messages
*                - Doesn't model for 4096 cycle refresh
*
*                Copyright Etron Technology, Inc.
*                All rights reserved
*
*
* Rev       Date              Change
* ----   -----------       ----------------------------------------
* 1.0    11/Sep/2013         First Version 
* 1.1    05/Nov/2015         added sg5
********************************************************************************/

//  Speed Grade Selection  (Default: tCK= 6.0ns(166MHz))
    
    `define sg5                     //Speed Grand tCK = 5.0ns(200MHz)  
//  `define sg6                    // Speed Grade tCK = 6.0ns(166MHz)
//  `define sg7                    // Speed Grade tCK = 7.0ns(143MHz)

/**********************************************************
*    The verilog compiler directive "`define" must be used to choose between
*
*    multiple speed grades supported by the memory model.
*
*    The following is an example of defining the speed grade:
*
*    Example for Choosing Speed Grade(sg):
*
*
*    //`define sg33                   // Speed Grade tCK = 3.3ns(300MHz)
*    //`define sg36                   // Speed Grade tCK = 3.6ns(277MHz)
*    //`define sg4                    // Speed Grade tCK = 4.0ns(250MHz)
*      `define sg5                    // Speed Grade tCK = 5.0ns(200MHz)
*
*
*    -->  Select Timing parameter tCK= 5.0ns(200MHz).
*
*
***********************************************************/

`timescale 1ps / 1ps

module sdr2mx32 (Dq, Addr, Ba, Clk, Cke, Cs_n, Ras_n, Cas_n, We_n, Dqm);

`ifdef sg7
    parameter tAC2 =  6500;
    parameter tAC3 =  5400;
    parameter tHZ  =  5400;
    parameter tOH  =  2500;
    parameter tMRD =   2.0;    // 2 Clk Cycles
    parameter tRAS = 42000;
    parameter tRC  = 63000;
    parameter tRCD = 21000;
    parameter tRP  = 21000;
    parameter tRRD = 14000;
    parameter tWR  = 14000;
    parameter tRFC = 63000;
`else `ifdef sg6
    parameter tAC2 =  6000;
    parameter tAC3 =  5400;
    parameter tHZ  =  5400;
    parameter tOH  =  2500;
    parameter tMRD =   2.0;    // 2 Clk Cycles
    parameter tRAS = 42000;
    parameter tRC  = 60000;
    parameter tRCD = 18000;
    parameter tRP  = 18000;
    parameter tRRD = 12000;
    parameter tWR  = 12000;
    parameter tRFC = 60000;
`else `ifdef sg5
    parameter tAC3 =  5000;
    parameter tHZ  =  5000;
    parameter tOH  =  2000;
    parameter tMRD =   2.0;    // 2 Clk Cycles
    parameter tRAS = 40000;
    parameter tRC  = 55000;
    parameter tRCD = 15000;
    parameter tRP  = 15000;
    parameter tRRD = 10000;
    parameter tWR  = 10000;
    parameter tRFC = 55000;
`endif `endif `endif


    // Constant Parameters
    parameter addr_bits =      11;
    parameter data_bits =      32;
    parameter cols_bits =       8;
    parameter mem_sizes =  524288;


    inout     [data_bits - 1 : 0] Dq;
    input     [addr_bits - 1 : 0] Addr;
    input      [1 : 0] Ba;
    input              Clk;
    input              Cke;
    input              Cs_n;
    input              Ras_n;
    input              Cas_n;
    input              We_n;
    input      [3 : 0] Dqm;

    reg       [data_bits - 1 : 0] Bank0 [0 : mem_sizes - 1];
    reg       [data_bits - 1 : 0] Bank1 [0 : mem_sizes - 1];
    reg       [data_bits - 1 : 0] Bank2 [0 : mem_sizes - 1];
    reg       [data_bits - 1 : 0] Bank3 [0 : mem_sizes - 1];
    reg        [1 : 0] Bank_addr [0 : 3];                // Bank Address Pipeline
    reg        [cols_bits - 1 : 0] Col_addr [0 : 3];     // Column Address Pipeline
    reg        [3 : 0] Cmd_pipe [0 : 3];                 // Command Operation Pipeline
    reg        [3 : 0] Dqm_reg0, Dqm_reg1;               // DQM Operation Pipeline
    reg       [addr_bits - 1 : 0] B0_row_addr, B1_row_addr, B2_row_addr, B3_row_addr;

    reg       [addr_bits - 1 : 0] Mode_reg;
    reg       [data_bits - 1 : 0] Dq_reg, Dq_dqm;
    reg        [cols_bits - 1 : 0] Col_temp;
    reg        [3 : 0] BC;
    reg                Rba0, Rba1, Rba2, Rba3;           // Bank Activate
    reg                Pc_b0, Pc_b1, Pc_b2, Pc_b3;       // Bank Precharge
    reg        [1 : 0] PRE                [0 : 3];       // Precharge Command
    reg                PREA               [0 : 3];       // Precharge All banks
    reg                Auto_PC            [0 : 3];       // RW AutoPrecharge (Bank)
    reg                ReadA              [0 : 3];       // R  AutoPrecharge
    reg                WriteA             [0 : 3];       // W  AutoPrecharge
    reg                RW_interrupt_read  [0 : 3];       // RW Interrupt Read with Auto Precharge
    reg                RW_interrupt_write [0 : 3];       // RW Interrupt Write with Auto Precharge
    reg        [1 : 0] RW_interrupt_bank;                // RW interrupt Bank
    time               Count_time         [0 : 3];       // RW AutoPrecharge (time after tWR = 1)
    integer            Count_PC           [0 : 3];       // RW AutoPrecharge (Counter)

    reg                Data_in_en         ;
    reg                Data_out_en        ;

    reg        [1 : 0] Bank, Pre_bank;
    reg       [addr_bits - 1 : 0] Row;
    reg        [cols_bits - 1 : 0] Col, Col_brst;

    // Internal system clock
    reg                CkeZ, Sys_clk, RAS_clk;
    // Internal burst stop 
    reg         Col_act;

    // Commands Decode
    wire      column_en = ~((Ba == 2'b00 && Pc_b0 == 1'b1) ||
                            (Ba == 2'b01 && Pc_b1 == 1'b1) ||
                            (Ba == 2'b10 && Pc_b2 == 1'b1) ||
                            (Ba == 2'b11 && Pc_b3 == 1'b1));
    wire      Act_en       = ~Cs_n & ~Ras_n &  Cas_n &  We_n;
    wire      Aref_en      = ~Cs_n & ~Ras_n & ~Cas_n &  We_n & Cke;
    wire      BStop        = ~Cs_n &  Ras_n &  Cas_n & ~We_n;
    wire      Mode_reg_en  = ~Cs_n & ~Ras_n & ~Cas_n & ~We_n & ~Ba[1] & ~Ba[0];
    wire      Prech_en     = ~Cs_n & ~Ras_n &  Cas_n & ~We_n;
    wire      Read_cmd     = ~Cs_n &  Ras_n & ~Cas_n &  We_n;
    wire      Write_cmd    = ~Cs_n &  Ras_n & ~Cas_n & ~We_n;
    wire      Read_en      = (~Cs_n &  Ras_n & ~Cas_n &  We_n) & column_en;
    wire      Write_en     = (~Cs_n &  Ras_n & ~Cas_n & ~We_n) & column_en;

    // Burst Length Decode
    wire      BL1   = ~Mode_reg[2] & ~Mode_reg[1] & ~Mode_reg[0];
    wire      BL2   = ~Mode_reg[2] & ~Mode_reg[1] &  Mode_reg[0];
    wire      BL4   = ~Mode_reg[2] &  Mode_reg[1] & ~Mode_reg[0];
    wire      BL8   = ~Mode_reg[2] &  Mode_reg[1] &  Mode_reg[0];
    wire      BLF   = ~Mode_reg[3] &  Mode_reg[2] &  Mode_reg[1] &  Mode_reg[0];

    // CAS Latency Decode
    wire      CL2   = ~Mode_reg[6] &  Mode_reg[5] & ~Mode_reg[4];
    wire      CL3   = ~Mode_reg[6] &  Mode_reg[5] &  Mode_reg[4];

    // Write Burst Mode
    wire      Write_burst_mode = Mode_reg[9];

    wire      Debug     = 1'b1;                      // Debug messages : 1 = On
    //wire      Debug     = 1'b0;                      // Debug messages : 0 = Off
    wire      Dq_chk    = Sys_clk & Data_in_en;      // Check setup/hold time for DQ


    assign    Dq        = Dq_reg;                    // DQ buffer

    //Commands Operation
    `define   ACT       0
    `define   NOP       1
    `define   READ      2
    `define   READ_A    3
    `define   WRITE     4
    `define   WRITE_A   5
    `define   PRECH     6
    `define   A_REF     7
    `define   BST       8
    `define   LMR       9


    // Timing Check variable
    integer   MRD_chk;
    integer   WR_counter [0 : 3];
    time      WR_time [0 : 3];
    time      WR_chkp [0 : 3];
    time      RC_chk, RRD_chk;
    time      RC_chk0, RC_chk1, RC_chk2, RC_chk3;
    time      RAS_chk0, RAS_chk1, RAS_chk2, RAS_chk3;
    time      RCD_chk0, RCD_chk1, RCD_chk2, RCD_chk3;
    time      RP_chk0, RP_chk1, RP_chk2, RP_chk3;

    initial begin
        Dq_reg = {data_bits{1'bz}};
        {Data_in_en         , Data_out_en         } = 0;
        {Rba0, Rba1, Rba2, Rba3} = 4'b0000;
        {Pc_b0, Pc_b1, Pc_b2, Pc_b3} = 4'b0000;
        {WR_chkp[0], WR_chkp[1], WR_chkp[2], WR_chkp[3]} = 0;
        {WR_counter[0], WR_counter[1], WR_counter[2], WR_counter[3]} = 0;
        {WR_time[0], WR_time[1], WR_time[2], WR_time[3]} = 0;
        {RW_interrupt_read[0], RW_interrupt_read[1], RW_interrupt_read[2], RW_interrupt_read[3]} = 0;
        {RW_interrupt_write[0], RW_interrupt_write[1], RW_interrupt_write[2], RW_interrupt_write[3]} = 0;
        {MRD_chk, RC_chk, RRD_chk} = 0;
        {RAS_chk0, RAS_chk1, RAS_chk2, RAS_chk3} = 0;
        {RCD_chk0, RCD_chk1, RCD_chk2, RCD_chk3} = 0;
        {RC_chk0, RC_chk1, RC_chk2, RC_chk3} = 0;
        {RP_chk0, RP_chk1, RP_chk2, RP_chk3} = 0;
        $timeformat (-9, 3, " ns", 12);
        RAS_clk = 1'b0;
    end

    // RAS Clk for checking tWR
    always RAS_clk = #0.5 ~RAS_clk;

    // System clock generator
    always begin
        @ (posedge Clk) begin
            Sys_clk = CkeZ;
            CkeZ = Cke;
        end
        @ (negedge Clk) begin
            Sys_clk = 1'b0;
        end
    end

    always @ (posedge Sys_clk) begin
        // Internal Commamd Pipelined
        Cmd_pipe[0] = Cmd_pipe[1];
        Cmd_pipe[1] = Cmd_pipe[2];
        Cmd_pipe[2] = Cmd_pipe[3];
        Cmd_pipe[3] = `NOP;

        Col_addr[0] = Col_addr[1];
        Col_addr[1] = Col_addr[2];
        Col_addr[2] = Col_addr[3];
        Col_addr[3] = {cols_bits{1'b0}};

        Bank_addr[0] = Bank_addr[1];
        Bank_addr[1] = Bank_addr[2];
        Bank_addr[2] = Bank_addr[3];
        Bank_addr[3] = 1'b0;

        PRE[0] = PRE[1];
        PRE[1] = PRE[2];
        PRE[2] = PRE[3];
        PRE[3] = 1'b0;

        PREA[0] = PREA[1];
        PREA[1] = PREA[2];
        PREA[2] = PREA[3];
        PREA[3] = 1'b0;

        // Dqm pipeline for Read
        Dqm_reg0 = Dqm_reg1;
        Dqm_reg1 = Dqm;

        // Read or Write with Auto Precharge Counter
        if (Auto_PC[0] == 1'b1) begin
            Count_PC[0] = Count_PC[0] + 1;
        end
        if (Auto_PC[1] == 1'b1) begin
            Count_PC[1] = Count_PC[1] + 1;
        end
        if (Auto_PC[2] == 1'b1) begin
            Count_PC[2] = Count_PC[2] + 1;
        end
        if (Auto_PC[3] == 1'b1) begin
            Count_PC[3] = Count_PC[3] + 1;
        end

        // Auto Precharge Timer for tWR
        if (BL2 == 1'b1) begin
            if (Count_PC[0] == 1) begin
                Count_time[0] = $time;
            end
            if (Count_PC[1] == 1) begin
                Count_time[1] = $time;
            end
            if (Count_PC[2] == 1) begin
                Count_time[2] = $time;
            end
            if (Count_PC[3] == 1) begin
                Count_time[3] = $time;
            end
        end else if (BL4 == 1'b1) begin
            if (Count_PC[0] == 3) begin
                Count_time[0] = $time;
            end
            if (Count_PC[1] == 3) begin
                Count_time[1] = $time;
            end
            if (Count_PC[2] == 3) begin
                Count_time[2] = $time;
            end
            if (Count_PC[3] == 3) begin
                Count_time[3] = $time;
            end
        end else if (BL8 == 1'b1) begin
            if (Count_PC[0] == 7) begin
                Count_time[0] = $time;
            end
            if (Count_PC[1] == 7) begin
                Count_time[1] = $time;
            end
            if (Count_PC[2] == 7) begin
                Count_time[2] = $time;
            end
            if (Count_PC[3] == 7) begin
                Count_time[3] = $time;
            end
        end

        // tMRD Counter
        MRD_chk = MRD_chk + 1;

        // tWR Counter for Write
        WR_counter[0] = WR_counter[0] + 1;
        WR_counter[1] = WR_counter[1] + 1;
        WR_counter[2] = WR_counter[2] + 1;
        WR_counter[3] = WR_counter[3] + 1;

        // Auto Refresh
        if (Aref_en          == 1'b1) begin
            if (Debug) $display ("at time %t AREF : Auto Refresh", $time);
            // Auto Refresh to Auto Refresh
            if ($time - RC_chk < tRFC) begin
                $display ("at time %t ERROR: tRFC violation during Auto Refresh", $time);
            end
            // Precharge to Auto Refresh
            if ($time - RP_chk0 < tRP || $time - RP_chk1 < tRP || $time - RP_chk2 < tRP || $time - RP_chk3 < tRP) begin
                $display ("at time %t ERROR: tRP violation during Auto Refresh", $time);
            end
            // Precharge to Refresh
            if (Pc_b0 == 1'b0 || Pc_b1 == 1'b0 || Pc_b2 == 1'b0 || Pc_b3 == 1'b0) begin
                $display ("at time %t ERROR: All banks must be Precharge before Auto Refresh", $time);
            end
            // Record Current tRFC time
            RC_chk = $time;
            // LMR to REF
            if (MRD_chk < tMRD) begin
                $display ("at time %t ERROR: tMRD violation during Auto Refresh", $time);
            end
        end
        
        // Load Mode Register
        if (Mode_reg_en          == 1'b1) begin
            // Decode CAS Latency, Burst Length, Burst Type, and Write Burst Mode
            if (Pc_b0 == 1'b1 && Pc_b1 == 1'b1 && Pc_b2 == 1'b1 && Pc_b3 == 1'b1) begin
                Mode_reg = Addr;
                if (Debug) begin
                    $display ("at time %t LMR  : Load Mode Register", $time);
                    // CAS Latency
                    if (Addr[6 : 4] == 3'b010)
                        $display ("                            CAS Latency      = 2");
                    else if (Addr[6 : 4] == 3'b011)
                        $display ("                            CAS Latency      = 3");
                    else
                        $display ("                            CAS Latency      = Reserved");
                    // Burst Length
                    if (Addr[2 : 0] == 3'b000)
                        $display ("                            Burst Length     = 1");
                    else if (Addr[2 : 0] == 3'b001)
                        $display ("                            Burst Length     = 2");
                    else if (Addr[2 : 0] == 3'b010)
                        $display ("                            Burst Length     = 4");
                    else if (Addr[2 : 0] == 3'b011)
                        $display ("                            Burst Length     = 8");
                    else if (Addr[3 : 0] == 4'b0111)
                        $display ("                            Burst Length     = Full");
                    else
                        $display ("                            Burst Length     = Reserved");
                    // Burst Type
                    if (Addr[3] == 1'b0)
                        $display ("                            Burst Type       = Sequential");
                    else if (Addr[3] == 1'b1)
                        $display ("                            Burst Type       = Interleaved");
                    else
                        $display ("                            Burst Type       = Reserved");
                    // Write Burst Mode
                    if (Addr[9] == 1'b0)
                        $display ("                            Write Burst Mode = Programmed Burst Length");
                    else if (Addr[9] == 1'b1)
                        $display ("                            Write Burst Mode = Single Location Access");
                    else
                        $display ("                            Write Burst Mode = Reserved");
                end
            end else begin
                $display ("at time %t ERROR: all banks must be Precharge before Load Mode Register", $time);
            end
            // REF to LMR
            if ($time - RC_chk < tRFC) begin
                $display ("at time %t ERROR: tRFC violation during Load Mode Register", $time);
            end
            // LMR to LMR
            if (MRD_chk < tMRD) begin
                $display ("at time %t ERROR: tMRD violation during Load Mode Register", $time);
            end
            MRD_chk = 0;
            // Precharge to LMR
            if (($time - RP_chk0 < tRP) || ($time - RP_chk1 < tRP) ||
                ($time - RP_chk2 < tRP) || ($time - RP_chk3 < tRP)) begin
                $display ("At time %t ERROR: tRP violation during Load Mode Register", $time);
            end
        end

        // Active Block (Latch Bank Address and Row Address)
        if (Act_en             == 1'b1) begin
            if (Ba == 2'b00 && Pc_b0 == 1'b1) begin
                {Rba0, Pc_b0} = 2'b10;
                B0_row_addr = Addr [addr_bits - 1 : 0];
                RCD_chk0 = $time;
                RAS_chk0 = $time;
                if (Debug) $display ("at time %t ACT  : Bank = 0 Row = %d",$time, Addr);
                // Precharge to Activate Bank 0
                if ($time - RP_chk0 < tRP) begin
                    $display ("at time %t ERROR: tRP violation during Activate bank 0", $time);
                end
                // Activate to Activate (same bank)
                if ($time - RC_chk0 < tRC) begin
                    $display ("At time %t ERROR: tRC violation during Activate bank %d", $time, Ba);
                end
                RC_chk0  = $time;
            end else if (Ba == 2'b01 && Pc_b1 == 1'b1) begin
                {Rba1, Pc_b1} = 2'b10;
                B1_row_addr = Addr [addr_bits - 1 : 0];
                RCD_chk1 = $time;
                RAS_chk1 = $time;
                if (Debug) $display ("at time %t ACT  : Bank = 1 Row = %d",$time, Addr);
                // Precharge to Activate Bank 1
                if ($time - RP_chk1 < tRP) begin
                    $display ("at time %t ERROR: tRP violation during Activate bank 1", $time);
                end
                // Activate to Activate (same bank)
                if ($time - RC_chk1 < tRC) begin
                    $display ("At time %t ERROR: tRC violation during Activate bank %d", $time, Ba);
                end
                RC_chk1  = $time;
            end else if (Ba == 2'b10 && Pc_b2 == 1'b1) begin
                {Rba2, Pc_b2} = 2'b10;
                B2_row_addr = Addr [addr_bits - 1 : 0];
                RCD_chk2 = $time;
                RAS_chk2 = $time;
                if (Debug) $display ("at time %t ACT  : Bank = 2 Row = %d",$time, Addr);
                // Precharge to Activate Bank 2
                if ($time - RP_chk2 < tRP) begin
                    $display ("at time %t ERROR: tRP violation during Activate bank 2", $time);
                end
                // Activate to Activate (same bank)
                if ($time - RC_chk2 < tRC) begin
                    $display ("At time %t ERROR: tRC violation during Activate bank %d", $time, Ba);
                end
                RC_chk2  = $time;
            end else if (Ba == 2'b11 && Pc_b3 == 1'b1) begin
                {Rba3, Pc_b3} = 2'b10;
                B3_row_addr = Addr [addr_bits - 1 : 0];
                RCD_chk3 = $time;
                RAS_chk3 = $time;
                if (Debug) $display ("at time %t ACT  : Bank = 3 Row = %d",$time, Addr);
                // Precharge to Activate Bank 3
                if ($time - RP_chk3 < tRP) begin
                    $display ("at time %t ERROR: tRP violation during Activate bank 3", $time);
                end
                // Activate to Activate (same bank)
                if ($time - RC_chk3 < tRC) begin
                    $display ("At time %t ERROR: tRC violation during Activate bank %d", $time, Ba);
                end
                RC_chk3  = $time;
            end else if (Ba == 2'b00 && Pc_b0 == 1'b0) begin
                $display ("at time %t ERROR: Bank 0 is already Activated (not Precharged)", $time);
            end else if (Ba == 2'b01 && Pc_b1 == 1'b0) begin
                $display ("at time %t ERROR: Bank 1 is already Activated (not Precharged)", $time);
            end else if (Ba == 2'b10 && Pc_b2 == 1'b0) begin
                $display ("at time %t ERROR: Bank 2 is already Activated (not Precharged)", $time);
            end else if (Ba == 2'b11 && Pc_b3 == 1'b0) begin
                $display ("at time %t ERROR: Bank 3 is already Activated (not Precharged)", $time);
            end
            // Active Bank A to Active Bank B
            if ((Pre_bank != Ba) && ($time - RRD_chk < tRRD)) begin
                $display ("at time %t ERROR: tRRD violation during Activate bank = %d", $time, Ba);
            end
            // Load Mode Register to Active
            if (MRD_chk < tMRD ) begin
                $display ("at time %t ERROR: tMRD violation during Activate bank = %d", $time, Ba);
            end
            // Auto Refresh to Activate
            if ($time - RC_chk < tRFC) begin
                $display ("at time %t ERROR: tRFC violation during Activate bank = %d", $time, Ba);
            end
            // Record variables for checking violation
            RRD_chk = $time;
            Pre_bank = Ba;
        end
        
        // Precharge Block
        if (Prech_en          == 1'b1) begin
                // LMR to PRE
                if (MRD_chk < tMRD) begin
                    $display ("at time %t ERROR: tMRD violation during Precharge", $time);
                end
            if (Addr[10] == 1'b1) begin
                {Pc_b0, Pc_b1, Pc_b2, Pc_b3} = 4'b1111;
                {Rba0, Rba1, Rba2, Rba3} = 4'b0000;
                RP_chk0 = $time;
                RP_chk1 = $time;
                RP_chk2 = $time;
                RP_chk3 = $time;
                if (Debug) $display ("at time %t PRE  : Bank = ALL",$time);
                // Activate to Precharge all banks
                if (($time - RAS_chk0 < tRAS) || ($time - RAS_chk1 < tRAS) ||
                    ($time - RAS_chk2 < tRAS) || ($time - RAS_chk3 < tRAS)) begin
                    $display ("at time %t ERROR: tRAS violation during Precharge all bank", $time);
                end
                // tWR violation check for write
                if (($time - WR_chkp[0] < tWR) || ($time - WR_chkp[1] < tWR) ||
                    ($time - WR_chkp[2] < tWR) || ($time - WR_chkp[3] < tWR)) begin
                    $display ("at time %t ERROR: tWR violation during Precharge all bank", $time);
                end
            end else if (Addr[10] == 1'b0) begin
                if (Ba == 2'b00) begin
                    {Pc_b0, Rba0} = 2'b10;
                    RP_chk0 = $time;
                    if (Debug) $display ("at time %t PRE  : Bank = 0",$time);
                    // Activate to Precharge Bank 0
                    if ($time - RAS_chk0 < tRAS) begin
                        $display ("at time %t ERROR: tRAS violation during Precharge bank 0", $time);
                    end
                end else if (Ba == 2'b01) begin
                    {Pc_b1, Rba1} = 2'b10;
                    RP_chk1 = $time;
                    if (Debug) $display ("at time %t PRE  : Bank = 1",$time);
                    // Activate to Precharge Bank 1
                    if ($time - RAS_chk1 < tRAS) begin
                        $display ("at time %t ERROR: tRAS violation during Precharge bank 1", $time);
                    end
                end else if (Ba == 2'b10) begin
                    {Pc_b2, Rba2} = 2'b10;
                    RP_chk2 = $time;
                    if (Debug) $display ("at time %t PRE  : Bank = 2",$time);
                    // Activate to Precharge Bank 2
                    if ($time - RAS_chk2 < tRAS) begin
                        $display ("at time %t ERROR: tRAS violation during Precharge bank 2", $time);
                    end
                end else if (Ba == 2'b11) begin
                    {Pc_b3, Rba3} = 2'b10;
                    RP_chk3 = $time;
                    if (Debug) $display ("at time %t PRE  : Bank = 3",$time);
                    // Activate to Precharge Bank 3
                    if ($time - RAS_chk3 < tRAS) begin
                        $display ("at time %t ERROR: tRAS violation during Precharge bank 3", $time);
                    end
                end
                // tWR violation check for write
                if ($time - WR_chkp[Ba] < tWR) begin
                    $display ("at time %t ERROR: tWR violation during Precharge bank %d", $time, Ba);
                end
            end

            // Terminate a Write Immediately (if same bank or all banks)
            if (Data_in_en          == 1'b1 && (Bank == Ba || Addr[10] == 1'b1)) begin
                Data_in_en          = 1'b0;
                Col_act             = 1'b0;
            end

            // Precharge Command Pipeline for Read
            if (CL3 == 1'b1) begin
                Cmd_pipe[2] = `PRECH;
                PRE[2] = Ba;
                PREA[2] = Addr[10];
            end else if (CL2 == 1'b1) begin
                Cmd_pipe[1] = `PRECH;
                PRE[1] = Ba;
                PREA[1] = Addr[10];
            end
        end
        
        // Burst terminate
        if (BStop == 1'b1) begin
          if (~Col_act && (Cmd_pipe[0] != `READ) && (Cmd_pipe[1] != `READ)) begin
            if (Debug) $display ("at time %t Burst Terminate command is illegal",$time);
          end else begin
            // Terminate a Write Immediately
            if (Data_in_en          == 1'b1) begin
                Data_in_en          = 1'b0;
                Col_act  = 1'b0;
            end
            // Terminate a Read Depend on CAS Latency
            if (CL3 == 1'b1) begin
                Cmd_pipe[2] = `BST;
            end else if (CL2 == 1'b1) begin
                Cmd_pipe[1] = `BST;
            end
            if (Debug) $display ("at time %t BST  : Burst Terminate",$time);
          end
        end
        
        // Read, Write, Column Latch
        if (Read_cmd         == 1'b1 || Write_cmd          == 1'b1) begin
            // Check to see if bank is open (ACT)
            if (~column_en) begin
                $display("at time %t ERROR: Cannot Read or Write - Bank %d is not Activated", $time, Ba);
            end
            // Activate to Read or Write
            if ((Ba == 2'b00) && ($time - RCD_chk0 < tRCD))
                $display("at time %t ERROR: tRCD violation during Read or Write to Bank 0", $time);
            if ((Ba == 2'b01) && ($time - RCD_chk1 < tRCD))
                $display("at time %t ERROR: tRCD violation during Read or Write to Bank 1", $time);
            if ((Ba == 2'b10) && ($time - RCD_chk2 < tRCD))
                $display("at time %t ERROR: tRCD violation during Read or Write to Bank 2", $time);
            if ((Ba == 2'b11) && ($time - RCD_chk3 < tRCD))
                $display("at time %t ERROR: tRCD violation during Read or Write to Bank 3", $time);
            // Read Command
            if (Read_en          == 1'b1) begin
                // CAS Latency pipeline
                if (CL3 == 1'b1) begin
                    if (Addr[10] == 1'b1) begin
                        Cmd_pipe[2] = `READ_A;
                    end else begin
                        Cmd_pipe[2] = `READ;
                    end
                    Col_addr[2] = Addr;
                    Bank_addr[2] = Ba;
                end else if (CL2 == 1'b1) begin
                    if (Addr[10] == 1'b1) begin
                        Cmd_pipe[1] = `READ_A;
                    end else begin
                        Cmd_pipe[1] = `READ;
                    end
                    Col_addr[1] = Addr;
                    Bank_addr[1] = Ba;
                end

                // Read interrupt Write (terminate Write immediately)
                if (Data_in_en          == 1'b1) begin
                    Data_in_en          = 1'b0;
                end

            // Write Command
            end else if (Write_en          == 1'b1) begin
                if (Addr[10] == 1'b1) begin
                    Cmd_pipe[0] = `WRITE_A;
                end else begin
                    Cmd_pipe[0] = `WRITE;
                end
                Col_addr[0] = Addr;
                Bank_addr[0] = Ba;
                Burst; 
                // Write interrupt Write (terminate Write immediately)
                if (Data_in_en          == 1'b1) begin
                    Data_in_en          = 1'b0;
                end

                // Write interrupt Read (terminate Read immediately)
                if (Data_out_en          == 1'b1) begin
                    Data_out_en          = 1'b0;
                end
            end

            // Interrupting a Write with Autoprecharge
            if (Auto_PC[RW_interrupt_bank] == 1'b1 && WriteA[RW_interrupt_bank] == 1'b1) begin
                RW_interrupt_write[RW_interrupt_bank] = 1'b1;
                WR_time[RW_interrupt_bank] = $time;
                if (Debug) $display ("at time %t NOTE : Read/Write Bank %d interrupt Write Bank %d with Autoprecharge", $time, Ba, RW_interrupt_bank);
            end

            // Interrupting a Read with Autoprecharge
            if (Auto_PC[RW_interrupt_bank] == 1'b1 && ReadA[RW_interrupt_bank] == 1'b1) begin
                RW_interrupt_read[RW_interrupt_bank] = 1'b1;
                if (Debug) $display ("at time %t NOTE : Read/Write Bank %d interrupt Read Bank %d with Autoprecharge", $time, Ba, RW_interrupt_bank);
            end

            // Read or Write with Auto Precharge
            if (Addr[10] == 1'b1) begin
                Auto_PC[Ba] = 1'b1;
                Count_PC[Ba] = 0;
                RW_interrupt_bank = Ba;
                if (Read_en          == 1'b1) begin
                    ReadA[Ba] = 1'b1;
                end else if (Write_en          == 1'b1) begin
                    WriteA[Ba] = 1'b1;
                    if (BL1 == 1'b1 || Write_burst_mode == 1'b1) begin
                        Count_time[Ba] = $time;
                    end
                end
            end
        end

        //  Read with Auto Precharge Calculation
        //      The device start internal precharge:
        //          1.  CAS Latency - 1 cycles before last burst
        //      and 2.  Meet minimum tRAS requirement
        //       or 3.  Interrupt by a Read or Write (with or without AutoPrecharge)
        if ((Auto_PC[0] == 1'b1) && (ReadA[0] == 1'b1)) begin
            if ((($time - RAS_chk0 >= tRAS) &&                                    // Case 2
                ((BL1 == 1'b1 && Count_PC[0] >= 1) ||                             // Case 1
                 (BL2 == 1'b1 && Count_PC[0] >= 2) ||
                 (BL4 == 1'b1 && Count_PC[0] >= 4) ||
                 (BL8 == 1'b1 && Count_PC[0] >= 8))) ||
                 (RW_interrupt_read[0] == 1'b1)) begin                            // Case 3
                    Pc_b0 = 1'b1;
                    Rba0 = 1'b0;
                    RP_chk0 = $time;
                    Auto_PC[0] = 1'b0;
                    ReadA[0] = 1'b0;
                    RW_interrupt_read[0] = 1'b0;
                    if (Debug) $display ("at time %t NOTE : Start Internal Auto Precharge for Bank 0", $time);
            end
        end
        if ((Auto_PC[1] == 1'b1) && (ReadA[1] == 1'b1)) begin
            if ((($time - RAS_chk1 >= tRAS) &&
                ((BL1 == 1'b1 && Count_PC[1] >= 1) || 
                 (BL2 == 1'b1 && Count_PC[1] >= 2) ||
                 (BL4 == 1'b1 && Count_PC[1] >= 4) ||
                 (BL8 == 1'b1 && Count_PC[1] >= 8))) ||
                 (RW_interrupt_read[1] == 1'b1)) begin
                    Pc_b1 = 1'b1;
                    Rba1 = 1'b0;
                    RP_chk1 = $time;
                    Auto_PC[1] = 1'b0;
                    ReadA[1] = 1'b0;
                    RW_interrupt_read[1] = 1'b0;
                    if (Debug) $display ("at time %t NOTE : Start Internal Auto Precharge for Bank 1", $time);
            end
        end
        if ((Auto_PC[2] == 1'b1) && (ReadA[2] == 1'b1)) begin
            if ((($time - RAS_chk2 >= tRAS) &&
                ((BL1 == 1'b1 && Count_PC[2] >= 1) || 
                 (BL2 == 1'b1 && Count_PC[2] >= 2) ||
                 (BL4 == 1'b1 && Count_PC[2] >= 4) ||
                 (BL8 == 1'b1 && Count_PC[2] >= 8))) ||
                 (RW_interrupt_read[2] == 1'b1)) begin
                    Pc_b2 = 1'b1;
                    Rba2 = 1'b0;
                    RP_chk2 = $time;
                    Auto_PC[2] = 1'b0;
                    ReadA[2] = 1'b0;
                    RW_interrupt_read[2] = 1'b0;
                    if (Debug) $display ("at time %t NOTE : Start Internal Auto Precharge for Bank 2", $time);
            end
        end
        if ((Auto_PC[3] == 1'b1) && (ReadA[3] == 1'b1)) begin
            if ((($time - RAS_chk3 >= tRAS) &&
                ((BL1 == 1'b1 && Count_PC[3] >= 1) || 
                 (BL2 == 1'b1 && Count_PC[3] >= 2) ||
                 (BL4 == 1'b1 && Count_PC[3] >= 4) ||
                 (BL8 == 1'b1 && Count_PC[3] >= 8))) ||
                 (RW_interrupt_read[3] == 1'b1)) begin
                    Pc_b3 = 1'b1;
                    Rba3 = 1'b0;
                    RP_chk3 = $time;
                    Auto_PC[3] = 1'b0;
                    ReadA[3] = 1'b0;
                    RW_interrupt_read[3] = 1'b0;
                    if (Debug) $display ("at time %t NOTE : Start Internal Auto Precharge for Bank 3", $time);
            end
        end

        // Internal Precharge or Bst
        if (Cmd_pipe[0] == `PRECH) begin                         // Precharge terminate a read with same bank or all banks
            if (PRE[0] == Bank || PREA[0] == 1'b1) begin
                if (Data_out_en          == 1'b1) begin
                    Data_out_en          = 1'b0;
                    Col_act              = 1'b0;
                end
            end
        end else if (Cmd_pipe[0] == `BST) begin                  // BST terminate a read to current bank
            if (Data_out_en          == 1'b1) begin
                Data_out_en          = 1'b0;
                Col_act  = 1'b0;
            end
        end

        if (Data_out_en          == 1'b0) begin
            Dq_reg <= #tOH {data_bits{1'bz}};
        end

        // Detect Read or Write command
        if (Cmd_pipe[0] == `READ || Cmd_pipe[0] == `READ_A) begin
            Bank = Bank_addr[0];
            Col = Col_addr[0];
            Col_brst = Col_addr[0];
            if (Bank_addr[0] == 2'b00) begin
                Row = B0_row_addr;
            end else if (Bank_addr[0] == 2'b01) begin
                Row = B1_row_addr;
            end else if (Bank_addr[0] == 2'b10) begin
                Row = B2_row_addr;
            end else if (Bank_addr[0] == 2'b11) begin
                Row = B3_row_addr;
            end
            BC = 0;
            Data_in_en          = 1'b0;
            Data_out_en          = 1'b1;
        end else if (Cmd_pipe[0] == `WRITE || Cmd_pipe[0] == `WRITE_A) begin
            Bank = Bank_addr[0];
            Col = Col_addr[0];
            Col_brst = Col_addr[0];
            if (Bank_addr[0] == 2'b00) begin
                Row = B0_row_addr;
            end else if (Bank_addr[0] == 2'b01) begin
                Row = B1_row_addr;
            end else if (Bank_addr[0] == 2'b10) begin
                Row = B2_row_addr;
            end else if (Bank_addr[0] == 2'b11) begin
                Row = B3_row_addr;
            end
            BC = 0;
            Data_in_en          = 1'b1;
            Data_out_en         = 1'b0;
        end

        // DQ buffer (Driver/Receiver)
        if (Data_in_en          == 1'b1) begin                                   // Writing Data to Memory
            // Array buffer
            if (Bank == 2'b00) Dq_dqm [data_bits - 1 : 0] = Bank0 [{Row, Col}];
            if (Bank == 2'b01) Dq_dqm [data_bits - 1 : 0] = Bank1 [{Row, Col}];
            if (Bank == 2'b10) Dq_dqm [data_bits - 1 : 0] = Bank2 [{Row, Col}];
            if (Bank == 2'b11) Dq_dqm [data_bits - 1 : 0] = Bank3 [{Row, Col}];
            // Dqm operation
            if (Dqm[0] == 1'b0) Dq_dqm [ 7 :  0] = Dq [ 7 :  0];
            if (Dqm[1] == 1'b0) Dq_dqm [15 :  8] = Dq [15 :  8];
            if (Dqm[2] == 1'b0) Dq_dqm [23 : 16] = Dq [23 : 16];
            if (Dqm[3] == 1'b0) Dq_dqm [31 : 24] = Dq [31 : 24];
            // Write to memory
            if (Bank == 2'b00) Bank0 [{Row, Col}] = Dq_dqm;
            if (Bank == 2'b01) Bank1 [{Row, Col}] = Dq_dqm;
            if (Bank == 2'b10) Bank2 [{Row, Col}] = Dq_dqm;
            if (Bank == 2'b11) Bank3 [{Row, Col}] = Dq_dqm;
            // Last data Write time
            if (Dqm == {(data_bits/8){1'b1}}) begin
                if (Debug) $display("at time %t WRITE : Bank = %d Row = %d, Col = %d, Data = Hi-Z due to DQM", $time, Bank, Row, Col);
            end else begin
                WR_chkp [Bank] = $time;
                if (Debug) $display("at time %t WRITE : Bank = %d Row = %d, Col = %d, Data = %d, Dqm = %b", $time, Bank, Row, Col, Dq_dqm, Dqm);
            end
            // Output result
            // Advance burst counter subroutine
            #1 Burst;
        end else if (Data_out_en          == 1'b1) begin                         // Reading Data from Memory
            // Array Buffer
            if (Bank == 2'b00) Dq_dqm = Bank0[{Row, Col}];
            if (Bank == 2'b01) Dq_dqm = Bank1[{Row, Col}];
            if (Bank == 2'b10) Dq_dqm = Bank2[{Row, Col}];
            if (Bank == 2'b11) Dq_dqm = Bank3[{Row, Col}];
            // Dqm operation
            if (Dqm_reg0[0] == 1'b1) Dq_dqm [ 7 :  0] = 8'bz;
            if (Dqm_reg0[1] == 1'b1) Dq_dqm [15 :  8] = 8'bz;
            if (Dqm_reg0[2] == 1'b1) Dq_dqm [23 : 16] = 8'bz;
            if (Dqm_reg0[3] == 1'b1) Dq_dqm [31 : 24] = 8'bz;
            // Display Result
           if(CL3) begin
              Dq_reg [data_bits - 1 : 0] = #tAC3 Dq_dqm [data_bits - 1 : 0];
            end else if(CL2) begin
              `ifdef sg7
                Dq_reg [data_bits - 1 : 0] = #tAC2 Dq_dqm [data_bits - 1 : 0];
              `endif
              `ifdef sg6
                Dq_reg [data_bits - 1 : 0] = #tAC2 Dq_dqm [data_bits - 1 : 0];
              `endif
            end

            if (Dqm_reg0 == {(data_bits/8){1'b1}}) begin
                if (Debug) $display("at time %t READ : Bank = %d Row = %d, Col = %d, Data = Hi-Z due to DQM", $time, Bank, Row, Col);
            end else begin
                if (Debug) $display("at time %t READ : Bank = %d Row = %d, Col = %d, Data = %d, Dqm = %b", $time, Bank, Row, Col, Dq_reg, Dqm_reg0);
            end
            // Advance burst counter subroutine
            Burst;
        end
    end

    //  Write with Auto Precharge Calculation
    //      The device start internal precharge:
    //          1.  tWR Clock after last burst
    //      and 2.  Meet minimum tRAS requirement
    //       or 3.  Interrupt by a Read or Write (with or without AutoPrecharge)
    always @ (RAS_clk) begin
        if ((Auto_PC[0] == 1'b1) && (WriteA[0] == 1'b1)) begin
            if ((($time - RAS_chk0 >= tRAS) &&                                                          // Case 2
               (((BL1 == 1'b1 || Write_burst_mode == 1'b1) && Count_PC [0] >= 1 && $time - Count_time[0] >= tWR) ||   // Case 1
                 (BL2 == 1'b1 && Count_PC [0] >= 2 && $time - Count_time[0] >= tWR) ||
                 (BL4 == 1'b1 && Count_PC [0] >= 4 && $time - Count_time[0] >= tWR) ||
                 (BL8 == 1'b1 && Count_PC [0] >= 8 && $time - Count_time[0] >= tWR))) ||
                 (RW_interrupt_write[0] == 1'b1 && WR_counter[0] >= 1 && $time - WR_time[0] >= tWR)) begin                           // Case 3 (stop count when interrupt)
                    Auto_PC[0] = 1'b0;
                    WriteA[0] = 1'b0;
                    RW_interrupt_write[0] = 1'b0;
                    Pc_b0 = 1'b1;
                    Rba0 = 1'b0;
                    RP_chk0 = $time;
                    if (Debug) $display ("at time %t NOTE : Start Internal Auto Precharge for Bank 0", $time);
            end
        end
        if ((Auto_PC[1] == 1'b1) && (WriteA[1] == 1'b1)) begin
            if ((($time - RAS_chk1 >= tRAS) &&
               (((BL1 == 1'b1 || Write_burst_mode == 1'b1) && Count_PC [1] >= 1 && $time - Count_time[1] >= tWR) || 
                 (BL2 == 1'b1 && Count_PC [1] >= 2 && $time - Count_time[1] >= tWR) ||
                 (BL4 == 1'b1 && Count_PC [1] >= 4 && $time - Count_time[1] >= tWR) ||
                 (BL8 == 1'b1 && Count_PC [1] >= 8 && $time - Count_time[1] >= tWR))) ||
                 (RW_interrupt_write[1] == 1'b1 && WR_counter[1] >= 1 && $time - WR_time[1] >= tWR)) begin
                    Auto_PC[1] = 1'b0;
                    WriteA[1] = 1'b0;
                    RW_interrupt_write[1] = 1'b0;
                    Pc_b1 = 1'b1;
                    Rba1 = 1'b0;
                    RP_chk1 = $time;
                    if (Debug) $display ("at time %t NOTE : Start Internal Auto Precharge for Bank 1", $time);
            end
        end
        if ((Auto_PC[2] == 1'b1) && (WriteA[2] == 1'b1)) begin
            if ((($time - RAS_chk2 >= tRAS) &&
               (((BL1 == 1'b1 || Write_burst_mode == 1'b1) && Count_PC [2] >= 1 && $time - Count_time[2] >= tWR) || 
                 (BL2 == 1'b1 && Count_PC [2] >= 2 && $time - Count_time[2] >= tWR) ||
                 (BL4 == 1'b1 && Count_PC [2] >= 4 && $time - Count_time[2] >= tWR) ||
                 (BL8 == 1'b1 && Count_PC [2] >= 8 && $time - Count_time[2] >= tWR))) ||
                 (RW_interrupt_write[2] == 1'b1 && WR_counter[2] >= 1 && $time - WR_time[2] >= tWR)) begin
                    Auto_PC[2] = 1'b0;
                    WriteA[2] = 1'b0;
                    RW_interrupt_write[2] = 1'b0;
                    Pc_b2 = 1'b1;
                    Rba2 = 1'b0;
                    RP_chk2 = $time;
                    if (Debug) $display ("at time %t NOTE : Start Internal Auto Precharge for Bank 2", $time);
            end
        end
        if ((Auto_PC[3] == 1'b1) && (WriteA[3] == 1'b1)) begin
            if ((($time - RAS_chk3 >= tRAS) &&
               (((BL1 == 1'b1 || Write_burst_mode == 1'b1) && Count_PC [3] >= 1 && $time - Count_time[3] >= tWR) || 
                 (BL2 == 1'b1 && Count_PC [3] >= 2 && $time - Count_time[3] >= tWR) ||
                 (BL4 == 1'b1 && Count_PC [3] >= 4 && $time - Count_time[3] >= tWR) ||
                 (BL8 == 1'b1 && Count_PC [3] >= 8 && $time - Count_time[3] >= tWR))) ||
                 (RW_interrupt_write[3] == 1'b1 && WR_counter[3] >= 1 && $time - WR_time[3] >= tWR)) begin
                    Auto_PC[3] = 1'b0;
                    WriteA[3] = 1'b0;
                    RW_interrupt_write[3] = 1'b0;
                    Pc_b3 = 1'b1;
                    Rba3 = 1'b0;
                    RP_chk3 = $time;
                    if (Debug) $display ("at time %t NOTE : Start Internal Auto Precharge for Bank 3", $time);
            end
        end
    end

    task Burst;
        begin
            // Advance Burst Counter
            BC = BC + 1;

            // Burst Type
            if (Mode_reg[3] == 1'b0) begin                        // Sequential Burst
                Col_temp = Col + 1;
            end else if (Mode_reg[3] == 1'b1) begin               // Interleaved Burst
                Col_temp[2] =  BC[2] ^  Col_brst[2];
                Col_temp[1] =  BC[1] ^  Col_brst[1];
                Col_temp[0] =  BC[0] ^  Col_brst[0];
            end

            // Burst Length
            if (BL2) begin                                       // Burst Length = 2
                Col [0] = Col_temp [0];
            end else if (BL4) begin                              // Burst Length = 4
                Col [1 : 0] = Col_temp [1 : 0];
            end else if (BL8) begin                              // Burst Length = 8
                Col [2 : 0] = Col_temp [2 : 0];
            end else begin                                       // Burst Length = FULL
                Col = Col_temp;
            end

            // Burst Read Single Write
            if (Write_burst_mode == 1'b1) begin
                Data_in_en          = 1'b0;
            end

            Col_act = 1'b1;
            // Data Counter
            if (BL1 == 1'b1) begin
                if (BC >= 1) begin
                    Data_in_en          = 1'b0;
                    Data_out_en         = 1'b0;
                    Col_act = 1'b0;
                end
            end else if (BL2 == 1'b1) begin
                if (BC >= 2) begin
                    Data_in_en          = 1'b0;
                    Data_out_en         = 1'b0;
                    Col_act = 1'b0;
                end
            end else if (BL4 == 1'b1) begin
                if (BC >= 4) begin
                    Data_in_en          = 1'b0;
                    Data_out_en         = 1'b0;
                    Col_act = 1'b0;
                end
            end else if (BL8 == 1'b1) begin
                if (BC >= 8) begin
                    Data_in_en          = 1'b0;
                    Data_out_en         = 1'b0;
                    Col_act = 1'b0;
                end
            end
        end
    endtask

    specify
        specparam
        `ifdef sg7
            // tCK = -7
            tCH  =  2500,                   // Clock High-Level Width
            tCL  =  2500,                   // Clock Low-Level Width
            tCK  =  7000,
            tIH  =  1000,                   // Addr, data, control Hold Time
            tIS  =  1500;                   // Addr, data, control Setup Time
        `else `ifdef sg6
            // tCK = -6
            tCH  =  2500,                   // Clock High-Level Width
            tCL  =  2500,                   // Clock Low-Level Width
            tCK  =  6000,
            tIH  =  1000,                   // Addr, data, control Hold Time
            tIS  =  1500;                   // Addr, data, control Setup Time
        `else `ifdef sg5   
            // tCK = -5
            tCH  =  2000,
            tCL  =  2000,
            tCK  =  5000,
            tIH  =  1000,
            tIS  =  1500;
        `endif `endif `endif

        $width    (posedge Clk,    tCH); 
        $width    (negedge Clk,    tCL);
        $period   (negedge Clk,    tCK);
        $period   (posedge Clk,    tCK);
        $setuphold(posedge Clk,    Cke,   tIS, tIH);
        $setuphold(posedge Clk,    Cs_n,  tIS, tIH);
        $setuphold(posedge Clk,    Cas_n, tIS, tIH);
        $setuphold(posedge Clk,    Ras_n, tIS, tIH);
        $setuphold(posedge Clk,    We_n,  tIS, tIH);
        $setuphold(posedge Clk,    Addr,  tIS, tIH);
        $setuphold(posedge Clk,    Ba,    tIS, tIH);
        $setuphold(posedge Clk,    Dqm,   tIS, tIH);
        $setuphold(posedge Dq_chk, Dq,    tIS, tIH);
    endspecify
endmodule

