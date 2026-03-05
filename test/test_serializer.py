import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles


async def reset(dut):
    dut.rst_n.value = 0
    dut.n_cs.value = 1
    dut.spi_clk.value = 0
    dut.valid_in.value = 0
    dut.addr.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
