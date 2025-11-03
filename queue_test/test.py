# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    dut._log.info("Test project behavior")

    dut.opcode.value = 0b01  # Adds SHA Instruction to queue
    dut.key_addr.value = 0x55AA55
    dut.text_addr.value = 0xAA55AA
    dut.dest_addr.value = 0x5A5A5A
    await ClockCycles(dut.clk, 10)
    dut.valid_in.value = 1
    await ClockCycles(dut.clk, 1)
    dut.valid_in.value = 0
    await ClockCycles(dut.clk, 10)
    assert dut.ready_out_sha == 1

    dut.key_addr.value = 0xAA55AA  # Adds different SHA Instruction to queue
    dut.text_addr.value = 0x55AA55
    dut.dest_addr.value = 0xA5A5A5
    dut.valid_in.value = 1
    await ClockCycles(dut.clk, 1)
    dut.valid_in.value = 0
    await ClockCycles(dut.clk, 10)
    assert dut.ready_out_sha == 1

    dut.opcode.value = 0b00  # Adds AES Instruction to queue and reads SHA instruction from queue
    dut.ready_in_sha.value = 1
    dut.valid_in.value = 1
    await ClockCycles(dut.clk, 1)
    dut.valid_in.value = 0
    await ClockCycles(dut.clk, 1)
    dut.ready_in_sha.value = 0
    assert int(str(dut.instr_sha.value), 2) == 0x155AA55AA55AA5A5A5A
    assert dut.valid_out_sha == 1
    assert dut.ready_out_aes == 1
    assert dut.ready_out_sha == 1
    await ClockCycles(dut.clk, 1)
    assert dut.valid_out_sha == 0

    dut.ready_in_aes.value = 1  # Reads AES instruction from queue
    await ClockCycles(dut.clk, 2)
    dut.ready_in_aes.value = 0
    assert int(str(dut.instr_aes.value), 2) == 0x0AA55AA55AA55A5A5A5
    assert dut.valid_out_aes == 1
    assert dut.ready_out_aes == 1
    await ClockCycles(dut.clk, 1)
    assert dut.valid_out_aes == 0
    await ClockCycles(dut.clk, 10)

    dut.key_addr.value = 0x010203  # Fill AES Instruction queue
    dut.text_addr.value = 0x040506
    dut.dest_addr.value = 0x070809
    await ClockCycles(dut.clk, 1)
    dut.valid_in.value = 1
    await ClockCycles(dut.clk, 18)
    assert dut.ready_out_aes == 0
    await ClockCycles(dut.clk, 2)

    dut.valid_in.value = 0  # Read AES Instruction from queue
    dut.ready_in_aes.value = 1
    await ClockCycles(dut.clk, 2)
    assert int(str(dut.instr_aes.value), 2) == 0x0010203040506070809
    assert dut.valid_out_aes.value == 1
    dut.ready_in_aes.value = 0
    await ClockCycles(dut.clk, 1)
    assert dut.ready_out_aes.value == 1
    assert dut.valid_out_aes.value == 0
    await ClockCycles(dut.clk, 10)
