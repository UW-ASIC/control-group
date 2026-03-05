import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles


async def reset(dut):
    dut.rst_n.value = 0
    dut.valid_in_aes.value = 0
    dut.valid_in_sha.value = 0
    dut.dest_addr_aes.value = 0
    dut.dest_addr_sha.value = 0
    dut.ready_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

