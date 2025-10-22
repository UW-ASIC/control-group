# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, FallingEdge, ReadWrite, Timer
import random

def bitList(value: int, width: int):
    """Return a list of bits [MSB..LSB]."""
    return [ (value >> i) & 1 for i in range(width-1, -1, -1) ]

async def reset(dut, cycles=2):
    """Active-low rst_n."""
    dut.rst_n.value = 0
    # clear inputs
    dut.valid_in.value = 0
    dut.opcode.value = 0
    dut.addr.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await ReadOnly()
    await Timer(1, "ps")      # <<< advance time; now safe to drive afterwards
    await ReadWrite()

async def shift_and_capture(dut, width):
    out_bits = []
    for _ in range(width):
        await FallingEdge(dut.spi_clk) 
        await RisingEdge(dut.clk)        
        await ReadOnly()                 
        await Timer(1, "ps")      # <<< advance time; now safe to drive afterwards
        await ReadWrite()
        out_bits.append(int(dut.miso.value))
    return out_bits

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (1000 KHz)
    clock = Clock(dut.clk, 1, units="us")
    #Slower SPI clocks (100 KHz)
    spiclk = Clock(dut.spi_clk, 10, units="us") 

    cocotb.start_soon(clock.start())
    cocotb.start_soon(spiclk.start())

    ADDRW   = len(dut.addr)
    OPCODEW = len(dut.opcode)
    SHIFT_W = ADDRW + OPCODEW

    # Reset
    await reset(dut)

    #TEST CONFIGS==========
    numberCycles = 20 #Test how many times
    #=======================
    for _ in range(numberCycles):
        addr = (random.randrange(1 << ADDRW))
        opcodeRaw = random.randrange(1 << OPCODEW)

        if random.randint(0,9) < 6: #Send something
            while int(dut.ready_out.value) == 0:
                await RisingEdge(dut.clk)

            # Load
            dut.opcode.value   = opcodeRaw
            dut.addr.value     = addr
            dut.valid_in.value = 1
            await RisingEdge(dut.clk)
            dut.valid_in.value = 0

            # Must be busy during shifting
            await ReadOnly()
            assert int(dut.ready_out.value) == 0

            # Check stream
            word     = (opcodeRaw << ADDRW) | addr
            expected = bitList(word, SHIFT_W)
            got      = await shift_and_capture(dut, SHIFT_W)
            print (f"Got: {got}, Expected: {expected}")
            assert got == expected, f"Frame mismatch exp={expected} got={got}"

        else: #Do nothing (wait signal)
            while int(dut.ready_out.value) == 0:
                await RisingEdge(dut.clk)

    #   .clk(clk),
    #   .rst_n(rst_n),
    #   .spi_clk(spi_clk),
    #   .valid_in(valid_in),
    #   .opcode(opcode),
    #   .addr(addr),
    #   .miso(miso),
    #   .ready_out(ready_out)
