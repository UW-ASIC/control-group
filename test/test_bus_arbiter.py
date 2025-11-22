import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.clock import Clock


async def reset_dut(dut):
    """Apply reset and initialize inputs"""
    dut.rst_n.value = 0
    dut.aes_req.value = 0
    dut.sha_req.value = 0
    dut.aes_data_in.value = 0
    dut.sha_data_in.value = 0
    dut.bus_ready.value = 1
    await Timer(100, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut._log.info("Reset complete.")


@cocotb.test()
async def test_basic_requests(dut):
    """Verify AES-only and SHA-only requests are granted properly."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    # ------------------ AES ONLY ------------------
    dut._log.info("=== TEST1: AES request only ===")
    dut.aes_data_in.value = 0xAABBCCDD
    dut.aes_req.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.aes_grant.value == 1, "AES grant should be high"
    assert dut.sha_grant.value == 0, "SHA grant should be low"
    assert dut.data_out.value == 0xDD, "Expected low byte of AES data"
    await RisingEdge(dut.clk)
    assert dut.data_out.value == 0xCC, "Expected second byte of AES data"
    # Clear request
    await reset_dut(dut)
    dut.aes_req.value = 0
    await Timer(40, units="ns")

    # ------------------ SHA ONLY ------------------
    dut._log.info("=== TEST2: SHA request only ===")
    dut.sha_data_in.value = 0x11223344
    dut.sha_req.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    print(f"Mode = {dut.curr_mode_top.value}")
    print(f"Counter = {dut.counter_top.value}")
    await RisingEdge(dut.clk)
    assert dut.aes_grant.value == 0, "AES grant should be low"
    assert dut.sha_grant.value == 1, "SHA grant should be high"
    assert dut.data_out.value == 0x44, "Expected low byte of SHA data"
    dut.sha_req.value = 0
    await Timer(40, units="ns")


@cocotb.test()
async def test_round_robin(dut):
    """Verify round-robin alternation between AES and SHA when both request simultaneously."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    # ---------------- Simultaneous Requests #1 ----------------
    dut._log.info("=== TEST3: Round-Robin Arbitration ===")
    dut.aes_req.value = 1
    dut.sha_req.value = 1
    dut.aes_data_in.value = 0xDEADBEEF
    dut.sha_data_in.value = 0xCAFEBABE

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    first_aes = bool(dut.aes_grant.value)
    first_sha = bool(dut.sha_grant.value)
    assert first_aes != first_sha, "Only one grant expected in RR arbitration"

    first_src = "AES" if first_aes else "SHA"
    dut._log.info(f"First grant: {first_src}")

    # Wait for one transfer burst (4 cycles)
    for _ in range(4):
        await RisingEdge(dut.clk)

    # ---------------- Simultaneous Requests #2 ----------------
    dut.aes_data_in.value = 0xFACEFEED
    dut.sha_data_in.value = 0x0BADF00D
    await RisingEdge(dut.clk)

    second_aes = bool(dut.aes_grant.value)
    second_src = "AES" if second_aes else "SHA"
    dut._log.info(f"Second grant: {second_src}")

    assert second_src != first_src, "Round-robin failed to alternate source"

    dut.aes_req.value = 0
    dut.sha_req.value = 0
    await Timer(40, units="ns")


@cocotb.test()
async def test_data_transfer(dut):
    """Verify correct byte sequencing for a granted source."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut._log.info("=== TEST4: Data transfer byte sequencing ===")
    dut.aes_req.value = 1
    dut.aes_data_in.value = 0x12345678

    observed = []
    await RisingEdge(dut.clk)
    for _ in range(4):
        await RisingEdge(dut.clk)
        if dut.valid_out.value:
            observed.append(int(dut.data_out.value))

    expected = [0x78, 0x56, 0x34, 0x12]
    dut._log.info(f"Observed bytes: {observed}, Expected: {expected}")
    assert observed == expected, "Byte order mismatch in data_out sequence"

    await RisingEdge(dut.clk)
    dut.aes_req.value = 0
    await Timer(40, units="ns")
