import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, ReadOnly

ADDRW = 24
OPCODEW = 2
QDEPTH = 16


def pack_aes(opcode, key_addr, text_addr, dest_addr):
    # Matches Verilog:
    # {opcode, key_addr, text_addr, dest_addr}
    return ((opcode << (3 * ADDRW)) |
            (key_addr << (2 * ADDRW)) |
            (text_addr << ADDRW) |
            dest_addr)


def pack_sha(opcode, text_addr, dest_addr):
    # Matches Verilog:
    # {opcode, text_addr, dest_addr}
    return ((opcode << (2 * ADDRW)) |
            (text_addr << ADDRW) |
            dest_addr)

class ReqQueueDriver:
    def __init__(self, dut):
        self.dut = dut
    async def reset(self):
        self.dut.rst_n.value = 0
        self.dut.valid_in.value = 0
        self.dut.opcode.value = 0
        self.dut.key_addr.value = 0
        self.dut.text_addr.value = 0
        self.dut.dest_addr.value = 0
        self.dut.ready_in_aes.value = 0
        self.dut.ready_in_sha.value = 0

        await ClockCycles(self.dut.clk, 5)

        self.dut.rst_n.value = 1
        await ClockCycles(self.dut.clk, 2)

    async def send_req(self, opcode, key_addr, text_addr, dest_addr):
        # Wait until the correct destination queue has room
        if (opcode & 0b1) == 0:
            while self.dut.ready_out_aes.value == 0:
                await RisingEdge(self.dut.clk)
        else:
            while self.dut.ready_out_sha.value == 0:
                await RisingEdge(self.dut.clk)

        self.dut.valid_in.value = 1
        self.dut.opcode.value = opcode
        self.dut.key_addr.value = key_addr
        self.dut.text_addr.value = text_addr
        self.dut.dest_addr.value = dest_addr

        await RisingEdge(self.dut.clk)

        self.dut.valid_in.value = 0
        self.dut.opcode.value = 0
        self.dut.key_addr.value = 0
        self.dut.text_addr.value = 0
        self.dut.dest_addr.value = 0

    async def pop_aes(self):
        # Wait until AES queue actually has valid data
        while self.dut.valid_out_aes.value == 0:
            await RisingEdge(self.dut.clk)

        self.dut.ready_in_aes.value = 1
        await RisingEdge(self.dut.clk)
        self.dut.ready_in_aes.value = 0

    async def pop_sha(self):
        # Wait until SHA queue actually has valid data
        while self.dut.valid_out_sha.value == 0:
            await RisingEdge(self.dut.clk)

        self.dut.ready_in_sha.value = 1
        await RisingEdge(self.dut.clk)
        self.dut.ready_in_sha.value = 0


class ReqQueueMonitor:
    def __init__(self, dut):
        self.dut = dut
        self.samples = []
        self.aes_pops = []
        self.sha_pops = []
        self._running = False
        self._task = None

    async def start(self):
        if self._running:
            return
        self._running = True
        self._task = cocotb.start_soon(self._run())

    async def stop(self):
        if not self._running:
            return
        self._running = False
        if self._task is not None:
            await self._task
            self._task = None

    async def _run(self):
        while self._running:
            await RisingEdge(self.dut.clk)
            await ReadOnly()

            sample = {
                "valid_out_aes": int(self.dut.valid_out_aes.value),
                "ready_out_aes": int(self.dut.ready_out_aes.value),
                "instr_aes": int(self.dut.instr_aes.value),
                "ready_in_aes": int(self.dut.ready_in_aes.value),
                "valid_out_sha": int(self.dut.valid_out_sha.value),
                "ready_out_sha": int(self.dut.ready_out_sha.value),
                "instr_sha": int(self.dut.instr_sha.value),
                "ready_in_sha": int(self.dut.ready_in_sha.value),
            }
            self.samples.append(sample)

            # Record actual dequeue events
            if sample["valid_out_aes"] == 1 and sample["ready_in_aes"] == 1:
                self.aes_pops.append(sample["instr_aes"])

            if sample["valid_out_sha"] == 1 and sample["ready_in_sha"] == 1:
                self.sha_pops.append(sample["instr_sha"])


@cocotb.test()
async def test_reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    driver = ReqQueueDriver(dut)
    monitor = ReqQueueMonitor(dut)

    await monitor.start()
    await driver.reset()

    assert dut.valid_out_aes.value == 0, "AES queue should be empty after reset"
    assert dut.valid_out_sha.value == 0, "SHA queue should be empty after reset"
    assert dut.ready_out_aes.value == 1, "AES queue should be ready after reset"
    assert dut.ready_out_sha.value == 1, "SHA queue should be ready after reset"

    await monitor.stop()


@cocotb.test()
async def test_single_aes_request(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    driver = ReqQueueDriver(dut)
    monitor = ReqQueueMonitor(dut)

    await monitor.start()
    await driver.reset()

    opcode = 0b00
    key_addr = 0x111111
    text_addr = 0x222222
    dest_addr = 0x333333

    await driver.send_req(opcode, key_addr, text_addr, dest_addr)
    await ClockCycles(dut.clk, 1)

    expected = pack_aes(opcode, key_addr, text_addr, dest_addr)

    assert dut.valid_out_aes.value == 1, "AES queue should contain one entry"
    assert dut.valid_out_sha.value == 0, "SHA queue should still be empty"
    assert dut.instr_aes.value.integer == expected, "AES output mismatch"

    await driver.pop_aes()
    await ClockCycles(dut.clk, 1)

    assert dut.valid_out_aes.value == 0, "AES queue should be empty after pop"
    assert monitor.aes_pops == [expected], "AES popped transaction mismatch"

    await monitor.stop()


@cocotb.test()
async def test_single_sha_request(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    driver = ReqQueueDriver(dut)
    monitor = ReqQueueMonitor(dut)

    await monitor.start()
    await driver.reset()

    opcode = 0b01
    key_addr = 0xAAAAAA   # ignored by SHA packing
    text_addr = 0x123456
    dest_addr = 0x654321

    await driver.send_req(opcode, key_addr, text_addr, dest_addr)
    await ClockCycles(dut.clk, 1)

    expected = pack_sha(opcode, text_addr, dest_addr)

    assert dut.valid_out_sha.value == 1, "SHA queue should contain one entry"
    assert dut.valid_out_aes.value == 0, "AES queue should still be empty"
    assert dut.instr_sha.value.integer == expected, "SHA output mismatch"

    await driver.pop_sha()
    await ClockCycles(dut.clk, 1)

    assert dut.valid_out_sha.value == 0, "SHA queue should be empty after pop"
    assert monitor.sha_pops == [expected], "SHA popped transaction mismatch"

    await monitor.stop()


@cocotb.test()
async def test_aes_fifo_order(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    driver = ReqQueueDriver(dut)
    monitor = ReqQueueMonitor(dut)

    await monitor.start()
    await driver.reset()

    reqs = [
        (0b00, 0x000001, 0x000002, 0x000003),
        (0b10, 0x000004, 0x000005, 0x000006),
        (0b00, 0x000007, 0x000008, 0x000009),
    ]

    expected = [pack_aes(*r) for r in reqs]

    for r in reqs:
        await driver.send_req(*r)

    await ClockCycles(dut.clk, 1)

    for exp in expected:
        assert dut.valid_out_aes.value == 1, "AES queue should have valid data"
        assert dut.instr_aes.value.integer == exp, "AES FIFO order incorrect"
        await driver.pop_aes()
        await ClockCycles(dut.clk, 1)

    assert dut.valid_out_aes.value == 0, "AES queue should be empty at end"
    assert monitor.aes_pops == expected, "AES popped order mismatch"

    await monitor.stop()


@cocotb.test()
async def test_sha_fifo_order(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    driver = ReqQueueDriver(dut)
    monitor = ReqQueueMonitor(dut)

    await monitor.start()
    await driver.reset()

    reqs = [
        (0b01, 0x000000, 0x111111, 0xAAAAAA),
        (0b11, 0x000000, 0x222222, 0xBBBBBB),
        (0b01, 0x000000, 0x333333, 0xCCCCCC),
    ]

    expected = [pack_sha(op, txt, dst) for op, _, txt, dst in reqs]

    for r in reqs:
        await driver.send_req(*r)

    await ClockCycles(dut.clk, 1)

    for exp in expected:
        assert dut.valid_out_sha.value == 1, "SHA queue should have valid data"
        assert dut.instr_sha.value.integer == exp, "SHA FIFO order incorrect"
        await driver.pop_sha()
        await ClockCycles(dut.clk, 1)

    assert dut.valid_out_sha.value == 0, "SHA queue should be empty at end"
    assert monitor.sha_pops == expected, "SHA popped order mismatch"

    await monitor.stop()


@cocotb.test()
async def test_mixed_requests(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    driver = ReqQueueDriver(dut)
    monitor = ReqQueueMonitor(dut)

    await monitor.start()
    await driver.reset()

    aes_reqs = [
        (0b00, 0x010101, 0x020202, 0x030303),
        (0b10, 0x040404, 0x050505, 0x060606),
    ]
    sha_reqs = [
        (0b01, 0x000000, 0x111111, 0xAAAAAA),
        (0b11, 0x000000, 0x222222, 0xBBBBBB),
    ]

    await driver.send_req(*aes_reqs[0])
    await driver.send_req(*sha_reqs[0])
    await driver.send_req(*aes_reqs[1])
    await driver.send_req(*sha_reqs[1])

    await ClockCycles(dut.clk, 1)

    aes_expected = [pack_aes(*r) for r in aes_reqs]
    sha_expected = [pack_sha(op, txt, dst) for op, _, txt, dst in sha_reqs]

    for exp in aes_expected:
        assert dut.valid_out_aes.value == 1, "AES queue should have data"
        assert dut.instr_aes.value.integer == exp, "AES mixed request order mismatch"
        await driver.pop_aes()
        await ClockCycles(dut.clk, 1)

    for exp in sha_expected:
        assert dut.valid_out_sha.value == 1, "SHA queue should have data"
        assert dut.instr_sha.value.integer == exp, "SHA mixed request order mismatch"
        await driver.pop_sha()
        await ClockCycles(dut.clk, 1)

    assert monitor.aes_pops == aes_expected, "AES mixed popped order mismatch"
    assert monitor.sha_pops == sha_expected, "SHA mixed popped order mismatch"

    await monitor.stop()


@cocotb.test()
async def test_aes_full(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    driver = ReqQueueDriver(dut)
    await driver.reset()

    for i in range(QDEPTH):
        assert dut.ready_out_aes.value == 1, f"AES should have space before entry {i}"
        await driver.send_req(0b00, i, i + 1, i + 2)

    await ClockCycles(dut.clk, 1)

    assert dut.ready_out_aes.value == 0, "AES queue should be full"
    assert dut.valid_out_aes.value == 1, "AES queue should still contain data"

    await driver.pop_aes()
    await ClockCycles(dut.clk, 1)

    assert dut.ready_out_aes.value == 1, "AES queue should have space after one pop"


@cocotb.test()
async def test_sha_full(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    driver = ReqQueueDriver(dut)
    await driver.reset()

    for i in range(QDEPTH):
        assert dut.ready_out_sha.value == 1, f"SHA should have space before entry {i}"
        await driver.send_req(0b01, 0, i + 10, i + 20)

    await ClockCycles(dut.clk, 1)

    assert dut.ready_out_sha.value == 0, "SHA queue should be full"
    assert dut.valid_out_sha.value == 1, "SHA queue should still contain data"

    await driver.pop_sha()
    await ClockCycles(dut.clk, 1)

    assert dut.ready_out_sha.value == 1, "SHA queue should have space after one pop"


@cocotb.test()
async def test_output_stable_when_not_popped(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    driver = ReqQueueDriver(dut)
    await driver.reset()

    opcode = 0b00
    key_addr = 0xABCDEF
    text_addr = 0x123456
    dest_addr = 0x654321

    await driver.send_req(opcode, key_addr, text_addr, dest_addr)
    await ClockCycles(dut.clk, 1)

    expected = pack_aes(opcode, key_addr, text_addr, dest_addr)

    for _ in range(5):
        assert dut.valid_out_aes.value == 1, "AES output should remain valid"
        assert dut.instr_aes.value.integer == expected, "AES output should remain stable"
        await ClockCycles(dut.clk, 1)


@cocotb.test()
async def test_empty_pop_behavior(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    driver = ReqQueueDriver(dut)
    await driver.reset()

    assert dut.valid_out_aes.value == 0, "AES queue should start empty"
    assert dut.valid_out_sha.value == 0, "SHA queue should start empty"

    # These may expose a bug in the RTL because the read pointer
    # increments even if the queue is empty.
    dut.ready_in_aes.value = 1
    await RisingEdge(dut.clk)
    dut.ready_in_aes.value = 0
    await ClockCycles(dut.clk, 1)

    dut.ready_in_sha.value = 1
    await RisingEdge(dut.clk)
    dut.ready_in_sha.value = 0
    await ClockCycles(dut.clk, 1)

    # This checks observable outputs only
    assert dut.valid_out_aes.value == 0, "AES queue should still appear empty"
    assert dut.valid_out_sha.value == 0, "SHA queue should still appear empty"


