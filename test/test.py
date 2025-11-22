# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, First


# NOTE This testbench was developed based on top level template
# It may not work correctly with finalized top level file



# helper function to build instructions to test

def build_instr(valid, encdec, aes_sha, key, text, dest):
    instr = 0
    instr |= (valid & 1) << 73
    instr |= (encdec & 1) << 72
    instr |= (aes_sha & 1) << 71
    instr |= (key  & 0xFFFFFF) << 48
    instr |= (text & 0xFFFFFF) << 24
    instr |= (dest & 0xFFFFFF)
    return instr

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


async def deserializer_test(dut, testval):
    assert dut.key_addr.value == (testval >> 48) & 0xFFFFFF, \
        f"Expected key_addr: {(testval >> 48) & 0xFFFFFF} Actual key_addr: {dut.key_addr.value}"
    assert dut.text_addr.value == (testval >> 24) & 0xFFFFFF, \
        f"Expected text_addr: {(testval >> 24) & 0xFFFFFF} Actual text_addr: {dut.text_addr.value}"
    assert dut.dest_addr.value  == testval & 0xFFFFFF, \
        f"Expected dest_addr: {testval & 0xFFFFFF} Actual dest_addr: {dut.dest_addr.value}"
    dut._log.info("Deserializer test passed")


async def req_queue_test(dut, testval):
    await First(
        RisingEdge(dut.valid_out_aes),
        RisingEdge(dut.valid_out_sha)
    )
    opcode_is_sha = (testval >> 72) & 0x1
    if opcode_is_sha:
        assert dut.valid_out_aes.value == 0, "AES value is 1 when expected to be 0"
        assert dut.valid_out_sha.value == 1, "SHA value is 0 when expected to be 1"
    else:
        assert dut.valid_out_aes.value == 1, "AES value is 0 when expected to be 1"
        assert dut.valid_out_sha.value == 0, "SHA value is 1 when expected to be 0"
    dut._log.info(f"AES/SHA routing test passed, AES/SHA bit: {opcode_is_sha}")
        
async def completion_queue_test(dut, testval):
    dut.compq_aes_valid.value = 1
    dut.compq_aes_data.value = testval

    await RisingEdge(dut.clk)
    assert dut.compq_valid_out.value == 1
    assert dut.compq_data.value == testval

    dut.compq_ready_in.value = 1
    await RisingEdge(dut.clk)

    assert dut.compq_valid_out.value == 0

async def serializer_test(dut, testval):
    result_bits = await get_spi_out(dut)
    result = int(result_bits)
    dut._log.info(f"Final collected result: {result}")

    assert (testval & 0xFFFFFF) == (result & 0xFFFFFF), \
        f"Destination address {(testval & 0xFFFFFF)} expected to match address of completed data text: {(result & 0xFFFFFF)}"
        



@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, units="us")
    spi_clock = Clock(dut.spi_clk, 10, units="us")
    cocotb.start_soon(clock.start())
    cocotb.start_soon(spi_clock.start())

    # Reset
    dut._log.info("Resetting top inputs")
    await reset_top(dut)

    # TEST Deserialize and AES routing
    testval_in = build_instr(0x1, 0x0, 0x0, 0x112233, 0x445566, 0x778899)
    await send_spi_in(testval_in)
    await RisingEdge(dut.valid)
    await deserializer_test(dut, testval_in)
    await req_queue_test(dut, testval_in) # should use AES

    # TEST Deserialize and SHA routing
    await reset_top(dut)
    testval_in = build_instr(0x1, 0x0, 0x1, 0x112233, 0x445566, 0x778899)
    await send_spi_in(testval_in)
    await RisingEdge(dut.valid)
    await deserializer_test(dut, testval_in)
    await req_queue_test(dut, testval_in) # should use SHA

    # TEST Completion queue and serializer (continues from previosu test)
    await RisingEdge(dut.compq_valid_out)
    assert dut.compq_data == testval_in & 0xFFFFFF
    await RisingEdge(dut.compq_ready_in)
    await serializer_test(dut, testval_in)

    # TEST fake completion queue values
    await reset_top(dut)
    completion_queue_test(dut, 0xABCDEF)
    await reset_top(dut)
    completion_queue_test(dut, 0x000000)
    await reset_top(dut)
    completion_queue_test(dut, 0xFFFFFF)