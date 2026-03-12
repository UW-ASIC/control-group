import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, ReadOnly


class CompQueueDriver:
    
    def __init__(self, dut):
        self.dut = dut
    
    async def reset(self):
        self.dut.rst_n.value = 0
        self.dut.valid_in_aes.value = 0
        self.dut.valid_in_sha.value = 0
        self.dut.dest_addr_aes.value = 0
        self.dut.dest_addr_sha.value = 0
        self.dut.ready_in.value = 0
        await ClockCycles(self.dut.clk, 5)
        self.dut.rst_n.value = 1
        await ClockCycles(self.dut.clk, 2)
    
    async def send_aes(self, addr):
        while self.dut.ready_out_aes.value == 0:
            await RisingEdge(self.dut.clk)

        self.dut.dest_addr_aes.value = addr
        self.dut.valid_in_aes.value = 1
        
        await RisingEdge(self.dut.clk)
        
        self.dut.valid_in_aes.value = 0
        self.dut.dest_addr_aes.value = 0
    
    async def send_sha(self, addr):
        while self.dut.ready_out_sha.value == 0:
            await RisingEdge(self.dut.clk)
        
        self.dut.dest_addr_sha.value = addr
        self.dut.valid_in_sha.value = 1
        
        await RisingEdge(self.dut.clk)
        
        self.dut.valid_in_sha.value = 0
        self.dut.dest_addr_sha.value = 0
    
    async def dequeue(self):
        while self.dut.valid_out.value == 0:
            await RisingEdge(self.dut.clk)
        
        self.dut.ready_in.value = 1

        await RisingEdge(self.dut.clk)
        
        self.dut.ready_in.value = 0



class CompQueueMonitor:

    def __init__(self, dut):
        self.dut = dut
        self.transactions = []
        self.samples = []
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

    def clear(self):
        self.transactions.clear()

    async def _run(self):
        while self._running:
            await RisingEdge(self.dut.clk)
            await ReadOnly()

            sample = {
                    "time": int(cocotb.utils.get_sim_time(units="ns")),
                    "ready_out_aes": int(self.dut.ready_out_aes.value),
                    "ready_out_sha": int(self.dut.ready_out_sha.value),
                    "valid_out": int(self.dut.valid_out.value),
                    "data_out": int(self.dut.data_out.value),
                }
            
            self.samples.append(sample);

            
            if int(self.dut.valid_out.value) == 1 and int(self.dut.ready_in.value) == 1:
                
                self.transactions.append(sample.copy())


@cocotb.test()
async def test_reset(dut):

    dut._log.info( "==================== RESET TEST ====================")
    driver = CompQueueDriver(dut)
    monitor = CompQueueMonitor(dut)

    await monitor.start()
    await driver.reset()

    await ClockCycles(dut.clk, 1)

    await monitor.stop()

    actual = monitor.samples[-1] if monitor.samples else None
    expected = {
        "ready_out_aes": 1,
        "ready_out_sha": 1,
        "valid_out": 0,
        "data_out": 0
    }

    assert actual is not None, "No samples captured during reset"
    assert actual["ready_out_aes"] == expected["ready_out_aes"], f"ready_out_aes mismatch: expected {expected['ready_out_aes']}, got {actual['ready_out_aes']}"
    assert actual["ready_out_sha"] == expected["ready_out_sha"], f"ready_out_sha mismatch: expected {expected['ready_out_sha']}, got {actual['ready_out_sha']}"
    assert actual["valid_out"] == expected["valid_out"], f"valid_out mismatch: expected {expected['valid_out']}, got {actual['valid_out']}"
    assert actual["data_out"] == expected["data_out"], f"data_out mismatch: expected {expected['data_out']}, got {actual['data_out']}"


@cocotb.test()
async def test_aes_multi(dut):
    dut._log.info( "==================== AES MULTI TEST ====================")
    driver = CompQueueDriver(dut)
    monitor = CompQueueMonitor(dut)

    expected_transactions = []

    await monitor.start()
    await driver.reset()

    for _ in range(5):
        addr = random.randint(0, 10000)
        expected_transactions.append({"data_out": addr})
        await driver.send_aes(addr)

    for _ in range(5):
        await driver.dequeue()
        await ClockCycles(dut.clk, 1)

    await ClockCycles(dut.clk, 10)
    await monitor.stop()

    actual_transactions = monitor.transactions

    # print("Actual transactions:")
    # for t in actual_transactions:
    #     print(t)

    # assert len(actual_transactions) == len(expected_transactions), f"Expected {len(expected_transactions)} transactions, got {len(actual_transactions)}"
    
    for i, (actual, expected) in enumerate(zip(actual_transactions, expected_transactions)):
        assert actual["data_out"] == expected["data_out"], f"Transaction {i} data_out mismatch: expected {expected['data_out']}, got {actual['data_out']}"