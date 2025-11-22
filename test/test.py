# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


# reset top level values

async def reset_top(dut):
    dut.rst_n = 0
    dut.miso.value = 0
    dut.cs_n = 0
    dut.ack_in = 0
    dut.bus_ready = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n = 1
    await ClockCycles(dut.clk, 2)
    dut._log.info("Reset complete")

# send values over spi

async def send_spi_in(dut, cpu_test_in):
    dut.cs.n.value = 0
    bits = f"{cpu_test_in:074b}"
    for bit in bits:
        dut.mosi.value = int(bit)
        await RisingEdge(dut.spi_clk)
    dut._log.info(f"Bits collected by module: {bits}")
    dut.cs_n.value = 1

# collect values over spi

async def get_spi_out(dut):
    await RisingEdge(dut.valid)
    dut.cs_n.value = 0
    bits = ""
    for _ in range(24):
        await RisingEdge(dut.spi_clk)
        bits += str(int(dut.miso_value))
    dut.cs_n.value = 1
    dut._log.info(f"Bits collected by CPU: {bits}")
    return int(bits)


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Resetting top inputs")
    reset_top(dut)

    # Send test value in
    testval_in = 0
    send_spi_in(testval_in)

    # Check expected behavior based on 'Valid' bit

    # Check expected behavior based on 'Encrypt/Decrypt' bit

    # Check expected behavior based on 'AES/SHA' bit

    # Wait for operation to finish
    await RisingEdge(dut.compq_valid_out)

    # Get test value out
    result = get_spi_out(dut)
    dut._log.info(f"Final collected result: {result}")

    # Verify test value out

