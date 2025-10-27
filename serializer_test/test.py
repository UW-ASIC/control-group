# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, FallingEdge, ReadWrite, Timer, with_timeout
from cocotb.result import SimTimeoutError
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
    dut.n_cs.value = 1
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

async def forced_error(dut, ADDRW, SHIFT_W, addr, opcodeRaw): #Force an error by randomly raising n_cs within 1-10 clock cycles of pulling ncs low

    errorclk = random.randint(1, 10)
    errorcnt = 0

    while int(dut.ready_out.value) == 0:
        await RisingEdge(dut.clk)

    # Load
    dut.n_cs.value     = 0
    dut.opcode.value   = opcodeRaw
    dut.addr.value     = addr
    dut.valid_in.value = 1

    while int(dut.ready_out.value) == 1:
        await RisingEdge(dut.spi_clk)
    dut.valid_in.value = 0

    for _ in range(random.randint(1, 9)):
        await RisingEdge(dut.spi_clk)
    dut.n_cs.value = 1

    # err should pulse for exactly 1 normal clock
    try:
        await with_timeout(RisingEdge(dut.err), 20, "us")
    except SimTimeoutError:
        raise AssertionError("ERR never asserted after forced abort (raise n_cs during busy)")

    await RisingEdge(dut.clk)
    print(f"DUT error value: {dut.err.value}")
    await RisingEdge(dut.clk)
    print(f"DUT error value: {dut.err.value}")
    await RisingEdge(dut.clk)
    print(f"DUT error value: {dut.err.value}")
    await RisingEdge(dut.clk)
    print(f"DUT error value: {dut.err.value}")

    # assert int(dut.err.value) == 0, "ERR did not clear after a pulse"

    while int(dut.ready_out.value) == 0:
        await RisingEdge(dut.spi_clk)

async def send_data(dut, ADDRW, SHIFT_W, addr, opcodeRaw):
    while int(dut.ready_out.value) == 0:
        await RisingEdge(dut.clk)

    # Load
    dut.n_cs.value     = 0
    dut.opcode.value   = opcodeRaw
    dut.addr.value     = addr
    dut.valid_in.value = 1

    # Must be busy during shifting
    while int(dut.ready_out.value) == 1:
        await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    
    # Check stream
    word     = (opcodeRaw << ADDRW) | addr
    expected = bitList(word, SHIFT_W)
    got      = await shift_and_capture(dut, SHIFT_W)

    while int(dut.ready_out.value) == 0:
        await RisingEdge(dut.clk)
    dut.n_cs.value = 1  

    print (f"Got: {got}, Expected: {expected}")
    assert got == expected, f"Frame mismatch exp={expected} got={got}"

async def glitch_ncs(dut): #just flick it on and off and see if ncs incorrectly enters low.
    dut.n_cs.value = 1
    await Timer(0.4, "us")
    dut.n_cs.value = 0

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (1000 KHz)
    clock = Clock(dut.clk, 1, units="us")
    #Slower SPI clocks (500 KHz), you could even randomize this...
    spiclk = Clock(dut.spi_clk, 2, units="us") 

    cocotb.start_soon(clock.start())
    cocotb.start_soon(spiclk.start())

    ADDRW   = len(dut.addr)
    OPCODEW = len(dut.opcode)
    SHIFT_W = ADDRW + OPCODEW

    # Reset
    await reset(dut)

    #TEST CONFIGS==========
    numberCycles = 30 #Test how many times
    #=======================
    for _ in range(numberCycles):
        addr = (random.randrange(1 << ADDRW))
        opcodeRaw = random.randrange(1 << OPCODEW)

        what_happens = random.randint(0,9)

        if what_happens < 6:    #send data
            print("Checking normal execution")
            await send_data(dut, ADDRW, SHIFT_W, addr, opcodeRaw)
        elif (what_happens >= 6 and(what_happens % 2 == 0)): #force error
            print("Checking errored execution")
            await forced_error(dut, ADDRW, SHIFT_W, addr, opcodeRaw)
        else:   #Sit 2-10 clock cycles and do nothing. Also test gitching by fiddling with ncs and seeing if anything loads.
            print("Do nothing")
            max = random.randint(2,10)
            test_ncs = random.randint(2, max)
            for i in range(max):
                await RisingEdge(dut.clk)
                if i == test_ncs:
                    await glitch_ncs(dut)

            

    #   .clk(clk),
    #   .rst_n(rst_n),
    #   .spi_clk(spi_clk),
    #   .valid_in(valid_in),
    #   .opcode(opcode),
    #   .addr(addr),
    #   .miso(miso),
    #   .ready_out(ready_out)
