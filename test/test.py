# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, First


# NOTE This testbench was developed based on top level template
# It may not work correctly with finalized top level file



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
    dut.cs_n.value = 0
    bits = f"{cpu_test_in:074b}"
    for bit in bits:
        dut.mosi.value = int(bit)
        await RisingEdge(dut.spi_clk)
    dut._log.info(f"Bits collected by module: {bits}")
    dut.cs_n.value = 1

# collect values over spi

async def get_spi_out(dut):
    dut.cs_n.value = 0
    bits = ""
    for _ in range(24):
        await RisingEdge(dut.spi_clk)
        bits += str(int(dut.miso.value))
    dut.cs_n.value = 1
    dut._log.info(f"Bits collected by CPU: {bits}")
    return bits


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Resetting top inputs")
    await reset_top(dut)

    # Send test value in
    testval_in = 0
    await send_spi_in(testval_in)
    await RisingEdge(dut.valid)

    assert dut.key_addr == (testval_in >> 48) & 0xFFFFFF
    assert dut.text_addr == (testval_in >> 24) & 0xFFFFFF
    assert dut.dest_addr == testval_in & 0xFFFFFF


    # Check expected behavior based on 'AES/SHA' bit
    await First(
        RisingEdge(dut.valid_out_aes),
        RisingEdge(dut.valid_out_sha)
    )
    opcode_is_sha = (testval_in >> 72) & 0x1
    if opcode_is_sha:
        assert dut.valid_out_aes.value == 0
        assert dut.valid_out_sha.value == 1
    else:
        assert dut.valid_out_aes.value == 1
        assert dut.valid_out_sha.value == 0
        

    # Wait for operation to finish and check comp queue behavior
    await RisingEdge(dut.compq_valid_out)
    assert dut.compq_data == testval_in & 0xFFFFFF
    await RisingEdge(dut.compq_ready_in)
    
    # Get test value out
    result = await int(get_spi_out(dut))
    dut._log.info(f"Final collected result: {result}")

    # Verify destination address reaches CPU 
    assert (testval_in & 0xFFFFFF) == (result & 0xFFFFFF), \
        f"Destination address {(testval_in & 0xFFFFFF)} expected to match address of completed data text: {(result & 0xFFFFFF)}"
        