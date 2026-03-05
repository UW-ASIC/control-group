import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles


async def reset(dut):
    dut.rst_n.value = 0
    dut.spi_clk.value = 0
    dut.mosi.value = 0
    dut.cs_n.value = 1
    dut.aes_ready_in.value = 0
    dut.sha_ready_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

