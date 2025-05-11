### SDRAM Controller HS and testbench 3
* default configuration works on hardware but not in emulators (RP=2, RCD=2)
* RP=2 does not work in emulators failing to activate controller ACK, thus RP=3
* RCD=2 works but gives timing violation in Etrons emulator regarding RCD at every ACT and in Microns emulator regarding RAS when ACT after reading or writing 1, 2 or 4 values
* RCD=3 gives RAS violation in both emulators
* RCD=4 gives no timing violation in emulators

In the use case of cache, when reading or writing 8 values or more, RCD=3 does not give timing violation RAS or RCD in either emulators