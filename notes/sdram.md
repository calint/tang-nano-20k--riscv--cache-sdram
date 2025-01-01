## from https://www.anandtech.com/show/3851/everything-you-always-wanted-to-know-about-sdram-memory-but-were-afraid-to-ask/3

* The time to activate a bank is called the Row-Column (or Command) Delay and is denoted by the symbol `tRCD`.
* The time to read a byte of data from the open page is called the Column Address Strobe (CAS) Latency and is denoted by the symbol `CL` or `tCAS`. 
* Only one page per bank may be open at a time. This is done by either issuing a Precharge (PR) command to close the specified bank only or a Precharge All (PRA) command to close all open banks in the rank.
* Alternatively, the Precharge command can be effectively combined with the last read or write operation to the open bank by sending a Read with Auto-Precharge (RDA) or Write with Auto-Precharge (WRA) command in place of the final READ or WRI command. 
* The time to Precharge an open bank is called the Row Access Strobe (RAS) Precharge Delay and is denoted by the symbol `tRP`. 
* The minimum time interval between successive ACT commands to the same bank is determined by the Row Cycle Time of the device, `tRC`, found by simply summing `tRAS` and `tRP` (to be defined).
* The minimum time interval between ACT commands to different banks is the Read-to-Read Delay (`tRRD`).

## from gemini:

Writes vs. Reads: The Key Difference

The core reason for this difference lies in how SDRAM handles write and read operations internally:
Writes are Buffered: When you perform a write operation to SDRAM, the data is typically written into
a write buffer within the SDRAM chip. The actual writing to the memory array happens later,
asynchronously to the system clock. This buffering allows the controller to proceed with other 
operations without waiting for the actual memory write to complete. This is why you often don't
need explicit delays after the ACTIVE and WRITE commands in your testbench as long as you respect `tRCD`.
The SDRAM controller and the SDRAM itself handle the internal timing.

Reads are Direct (with Latency): When you perform a read operation, the data is read directly from the
memory array (after being loaded into the sense amplifiers by the ACTIVE command). This process takes 
time, and this is where the CAS Latency (`CL`) comes into play. The SDRAM needs time to access the data,
transfer it to the output buffers, and drive it onto the data bus. This is why you must wait for CL 
clock cycles after the READ command before sampling the data.

### CL (CAS Latency):

Stands for Column Address Strobe Latency.
This is the delay, measured in clock cycles, between issuing a READ command and the moment the data is available on the data bus.
A lower CL value means lower latency and better performance. For example, CL3 means the data will be available 3 clock cycles after the READ command.

### tRP (Row Precharge Time):

Stands for Row Precharge Time.
This is the minimum time, measured in clock cycles, required to "precharge" a bank of memory. Precharging essentially closes an active row in a bank, preparing it for access to a different row.
It's the time needed to deactivate the sense amplifiers and restore the memory cells to their idle state.

### tRFC (Row Refresh Cycle Time):

Stands for Row Refresh Cycle Time.
This is the minimum time, measured in clock cycles, required to perform a refresh operation on a bank of memory.
SDRAM requires periodic refresh cycles to prevent data loss due to capacitor discharge. `tRFC` specifies how long this refresh process takes.

### tMRD (Mode Register Set Command Time):

Stands for Mode Register Set Command Time.
This is the minimum time, measured in clock cycles, required to write to the SDRAM's mode registers.
The mode registers configure various SDRAM operating parameters, such as burst length, CAS latency, and operating mode.

### tRCD (Row to Column Delay):

Stands for Row to Column Delay.
This is the minimum time, measured in clock cycles, between activating a row (with an ACTIVE command) and issuing a READ or WRITE command to that row.
It allows time for the row to be activated and the data to be sensed before a column access can occur.

### tWR (Write Recovery Time):

Stands for Write Recovery Time.
This is the minimum time, measured in clock cycles, that must elapse after a WRITE operation before a precharge command can be issued to the same bank.
It allows the data to be fully written to the memory cells before the row is closed.
