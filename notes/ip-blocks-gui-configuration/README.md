### Use case cache
* default configuration works on hardware but not in emulators (RP=2, RCD=2)
* RP=2 does not work in emulator, thus RP=3
* RCD=2 does work but gives timing violation in emulators when reading or writing 1, 2 or 4 values at a time
* RCD=3 gives timing violation in emulators regarding RAS
* RCD=4 gives no timing violation in emulators

Thus, in the use case of cache when reading or writing 8 values or more does not give timing violation for RAS or RCD.