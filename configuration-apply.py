#!/bin/python3
# generates configuration files for Verilog source, 'os' and 'emulator'
import configuration as cfg
import os

script_dir = os.path.dirname(os.path.realpath(__file__))
os.chdir(script_dir)

memory_end_address = 2**(cfg.RAM_ADDRESS_BITWIDTH+cfg.RAM_ADDRESSING_MODE)

with open('os/src/os_start.S', 'w') as file:
    file.write('# generated - do not edit (see `configuration.py`)\n')
    file.write('.global _start\n')
    file.write('_start:\n')
    file.write('    li sp, {}\n'.format(
        hex(memory_end_address)))
    file.write('    j run\n')

with open('os/src/os_config.hpp', 'w') as file:
    file.write('// generated - do not edit (see `configuration.py`)\n')
    file.write('#pragma once\n')
    file.write('#define LED ((char volatile *)0xffff\'ffff)\n')
    file.write('#define UART_OUT ((char volatile *)0xffff\'fffe)\n')
    file.write('#define UART_IN ((char volatile *)0xffff\'fffd)\n')
    file.write('#define MEMORY_END {}\n'.format(hex(
        memory_end_address)))

with open('emulator/src/main_config.hpp', 'w') as file:
    file.write('// generated - do not edit (see `configuration.py`)\n')
    file.write('#pragma once\n')
    file.write('#include <cstdint>\n\n')
    file.write('namespace osqa {\n\n')
    file.write('// memory map\n')
    file.write('std::uint32_t constexpr led = 0xffff\'ffff;\n')
    file.write('std::uint32_t constexpr uart_out = 0xffff\'fffe;\n')
    file.write('std::uint32_t constexpr uart_in = 0xffff\'fffd;\n')
    file.write('std::uint32_t constexpr memory_end = {};\n'.format(hex(
        memory_end_address)))
    file.write('\n} // namespace osqa\n')


with open('src/configuration.sv', 'w') as file:
    file.write('// generated - do not edit (see `configuration.py`)\n')
    # file.write(
    #     '//  note: "localparam" not "parameter" to avoid warnings in Gowin EDA\n')
    file.write('\n')
    file.write('package configuration;\n')
    file.write('\n')
    file.write('  parameter int unsigned CLOCK_FREQUENCY_HZ = {};\n'.format(
        cfg.CLOCK_FREQUENCY_HZ))
    file.write('  parameter int unsigned RAM_ADDRESS_BITWIDTH = {};\n'.format(
        cfg.RAM_ADDRESS_BITWIDTH))
    file.write('  parameter int unsigned RAM_ADDRESSING_MODE = {};\n'.format(
        cfg.RAM_ADDRESSING_MODE))
    file.write('  parameter int unsigned CACHE_COLUMN_INDEX_BITWIDTH = {};\n'.format(
        cfg.CACHE_COLUMN_INDEX_BITWIDTH))
    file.write('  parameter int unsigned CACHE_LINE_INDEX_BITWIDTH = {};\n'.format(
        cfg.CACHE_LINE_INDEX_BITWIDTH))
    file.write('  parameter int unsigned UART_BAUD_RATE = {};\n'.format(
        cfg.UART_BAUD_RATE))
    file.write('  parameter int unsigned FLASH_TRANSFER_FROM_ADDRESS = 32\'h{};\n'.format(
        f'{cfg.FLASH_TRANSFER_FROM_ADDRESS:08x}'))
    file.write('  parameter int unsigned FLASH_TRANSFER_BYTE_COUNT = 32\'h{};\n'.format(
        f'{cfg.FLASH_TRANSFER_BYTE_COUNT:08x}'))
    file.write('  parameter int unsigned STARTUP_WAIT_CYCLES = {};\n'.format(
        cfg.STARTUP_WAIT_CYCLES))

    file.write('\n')
    file.write('endpackage\n')

print("generated: src/configuration.sv, os/src/os_start.S, os/src/os_config.hpp. emulator/src/main_config.hpp")
