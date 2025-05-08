# SDRAM
* Tang Nano 20K part name: EM638325GD
* emulator from manufacturer Etron: [`sdr2mx32.v`](https://github.com/calint/tang-nano-20k--riscv--cache-sdram/blob/main/notes/sdram-emulator/etron/sdr2mx32.v)
* note: very slow to reach initialized state at ~328 us
* faster emulator from Micron: [`MT48LC2M32B2.v`](https://github.com/calint/tang-nano-20k--riscv--cache-sdram/blob/main/notes/sdram-emulator/micron/MT48LC2M32B2.v)
* controller: [SDRAM controller configuration](https://github.com/calint/tang-nano-20k--riscv--cache-sdram/blob/main/notes/ip-blocks-gui-configuration/SDRAM-Controller-HS.png)
  
# SD card
* emulator: Read-only and does not work with controller: [sd\_fake.v](https://github.com/WangXuan95/FPGA-SDcard-Reader/blob/main/SIM/sd_fake.v)
* controller: [sd_controller.v](https://github.com/calint/tang-nano-20k--riscv--cache-sdram/blob/main/src/ip/regymm/sd_controller.v)

# Flash
* emulator: [spiflash.v](https://github.com/YosysHQ/picorv32/blob/main/picosoc/spiflash.v)