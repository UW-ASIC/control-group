# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start control_top smoke test")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    dut._log.info("Check top-level wiring invariants")
    await ClockCycles(dut.clk, 5)

    # uio_oe is tied low in this design
    assert int(dut.uio_oe.value) == 0, f"Expected uio_oe=0, got {dut.uio_oe.value}"

    # uo_out and uio_out are both driven from the same out_bus signal
    assert dut.uo_out.value.is_resolvable, f"uo_out has X/Z: {dut.uo_out.value}"
    assert dut.uio_out.value.is_resolvable, f"uio_out has X/Z: {dut.uio_out.value}"
    assert int(dut.uo_out.value) == int(dut.uio_out.value), (
        f"Expected mirrored outputs, got uo_out={dut.uo_out.value}, uio_out={dut.uio_out.value}"
    )

    # Drive a non-zero pattern and re-check mirrored outputs.
    dut.ui_in.value = 0xA5
    dut.uio_in.value = 0x3C
    await ClockCycles(dut.clk, 5)
    assert dut.uo_out.value.is_resolvable, f"uo_out has X/Z after stimulus: {dut.uo_out.value}"
    assert dut.uio_out.value.is_resolvable, f"uio_out has X/Z after stimulus: {dut.uio_out.value}"
    assert int(dut.uo_out.value) == int(dut.uio_out.value), (
        f"Expected mirrored outputs after stimulus, got "
        f"uo_out={dut.uo_out.value}, uio_out={dut.uio_out.value}"
    )

    dut._log.info("Smoke test passed")
