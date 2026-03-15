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

    async def send_both(self, addr_aes, addr_sha):
        while self.dut.ready_out_aes.value == 0 or self.dut.ready_out_sha.value == 0:
            await RisingEdge(self.dut.clk)

        self.dut.dest_addr_aes.value = addr_aes
        self.dut.valid_in_aes.value = 1
        self.dut.dest_addr_sha.value = addr_sha
        self.dut.valid_in_sha.value = 1
        
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

        self.dut.valid_in_aes.value = 0
        self.dut.dest_addr_aes.value = 0
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


@cocotb.test()
async def test_sha_multi(dut):
    dut._log.info( "==================== AES MULTI TEST ====================")
    driver = CompQueueDriver(dut)
    monitor = CompQueueMonitor(dut)

    expected_transactions = []

    await monitor.start()
    await driver.reset()

    for _ in range(5):
        addr = random.randint(0, 10000)
        expected_transactions.append({"data_out": addr})
        await driver.send_sha(addr)

    for _ in range(5):
        await driver.dequeue()
        await ClockCycles(dut.clk, 1)

    await ClockCycles(dut.clk, 10)
    await monitor.stop()

    actual_transactions = monitor.transactions

    for i, (actual, expected) in enumerate(zip(actual_transactions, expected_transactions)):
        assert actual["data_out"] == expected["data_out"], f"Transaction {i} data_out mismatch: expected {expected['data_out']}, got {actual['data_out']}"


@cocotb.test()
async def test_round_robin(dut):
    dut._log.info( "==================== ROUND ROBIN TEST ====================")
    driver = CompQueueDriver(dut)
    monitor = CompQueueMonitor(dut)

    expected_transactions = []

    await monitor.start()
    await driver.reset()

    addr_aes = [0xAAAA, 0xBBBB, 0xCCCC, 0xDDDD, 0xEEEE]
    addr_sha = [0x1111, 0x2222, 0x3333, 0x4444, 0x5555]

    for i in range(5):
        await driver.send_aes(addr_aes[i])
    
    for i in range(5):
        await driver.send_sha(addr_sha[i])

    for i in range(5):
        aes = addr_aes[i]
        sha = addr_sha[i]
        expected_transactions.append({"data_out": aes})
        expected_transactions.append({"data_out": sha})
        
    for _ in range(10):
        await driver.dequeue()
        await ClockCycles(dut.clk, 1)

    await ClockCycles(dut.clk, 10)
    await monitor.stop()

    actual_transactions = monitor.transactions

    print("Actual transactions:")
    for t in actual_transactions:
        print(t)

    for i, (actual, expected) in enumerate(zip(actual_transactions, expected_transactions)):
        assert actual["data_out"] == expected["data_out"], f"Transaction {i} data_out mismatch: expected {expected['data_out']}, got {actual['data_out']}"

@cocotb.test()
async def test_enqueue_round_robin(dut):
    dut._log.info( "==================== BOTH ROUND ROBIN TEST ====================")
    driver = CompQueueDriver(dut)
    monitor = CompQueueMonitor(dut)

    expected_transactions = []

    await monitor.start()
    await driver.reset()

    aes = [0xAAAA, 0xBBBB, 0xCCCC, 0xDDDD, 0xEEEE]
    sha = [0x1111, 0x2222, 0x3333, 0x4444, 0x5555]

    for i in range(5):
        addr_aes = aes[i]
        addr_sha = sha[i]
        expected_transactions.append({"data_out": addr_aes})
        expected_transactions.append({"data_out": addr_sha})
        await driver.send_both(addr_aes, addr_sha)

    for _ in range(10):
        await driver.dequeue()
        await ClockCycles(dut.clk, 1)

    await ClockCycles(dut.clk, 10)
    await monitor.stop()

    actual_transactions = monitor.transactions

    for i, (actual, expected) in enumerate(zip(actual_transactions, expected_transactions)):
        assert actual["data_out"] == expected["data_out"], f"Transaction {i} data_out mismatch: expected {expected['data_out']}, got {actual['data_out']}"


@cocotb.test()
async def test_enqueue_full(dut):
    dut._log.info( "==================== ENQUEUE FULL TEST ====================")
    driver = CompQueueDriver(dut)
    monitor = CompQueueMonitor(dut)

    await driver.reset()
    await monitor.start()

    queueDepth = 32
    expected = []

    for i in range(queueDepth):
        aes_addr = random.randint(0, 10000)
        expected.append({"data_out": aes_addr})
        await driver.send_aes(aes_addr)

    driver.send_aes(0xDEAD)  
    driver.send_aes(0xBEEF)

    await ClockCycles(dut.clk, 1)

    assert int(dut.ready_out_aes.value) == 0, f"ready_out_aes should be 0 after {queueDepth} enqueues, got {int(dut.ready_out_aes.value)}"
    assert int(dut.ready_out_sha.value) == 0, f"ready_out_sha should be 0 after {queueDepth} enqueues, got {int(dut.ready_out_sha.value)}"

    for i in range(queueDepth):
        await driver.dequeue()
        await ClockCycles(dut.clk, 1)
        assert int(dut.ready_out_aes.value) == 1, f"ready_out_aes should be 1 during dequeue of transaction {i}, got {int(dut.ready_out_aes.value)}"
        assert int(dut.ready_out_sha.value) == 1, f"ready_out_sha should be 1 during dequeue of transaction {i}, got {int(dut.ready_out_sha.value)}"

    actual = monitor.transactions

    for i, (actual, expected) in enumerate(zip(actual, expected)):
        assert actual["data_out"] == expected["data_out"], f"Transaction {i} data_out mismatch: expected {expected['data_out']}, got {actual['data_out']}"
    

@cocotb.test()
async def test_not_ready_dequeue(dut):
    dut._log.info( "==================== NOT READY DEQUEUE TEST ====================")
    driver = CompQueueDriver(dut)
    monitor = CompQueueMonitor(dut)

    await driver.reset()
    await monitor.start()
    
    dut.ready_in.value = 0

    headAddr = random.randint(0, 10000)

    await driver.send_aes(headAddr)

    for _ in range(5): 
        await driver.send_aes(random.randint(0, 10000))

    await ClockCycles(dut.clk, 1)

    assert int(dut.valid_out.value) == 1, f"valid_out should be 1 after enqueue, got {int(dut.valid_out.value)}"
    
    for _ in range(5): #check that data is not being dequeued
        await ClockCycles(dut.clk, 1)
        assert int(dut.data_out.value) == headAddr, f"data_out should be {headAddr}, got {int(dut.data_out.value)}"

    dut.ready_in.value = 1

    await driver.dequeue()

    assert int(dut.data_out.value) != headAddr, f"data_out should have changed after dequeue, got {int(dut.data_out.value)}"


@cocotb.test()
async def test_concurrent_enqueue_dequeue(dut):
    dut._log.info( "==================== CONCURRENT ENQUEUE DEQUEUE TEST ====================")
    driver = CompQueueDriver(dut)
    monitor = CompQueueMonitor(dut)

    await driver.reset()
    await monitor.start()

    expected = []

    addr1 = random.randint(0, 10000)
    addr2 = random.randint(0, 10000)
    expected.append({"data_out": addr1})

    while dut.ready_out_aes.value == 0:
        await RisingEdge(dut.clk)
    
    dut.dest_addr_aes.value = addr1
    dut.valid_in_aes.value = 1

    await RisingEdge(dut.clk)

    dut.dest_addr_aes.value = addr2
    dut.valid_in_aes.value = 1

    await driver.dequeue()

    await monitor.stop()

    acutal = monitor.transactions

    assert acutal[0]["data_out"] == expected[0]["data_out"], f"Transaction 0 data_out mismatch: expected {expected[0]['data_out']}, got {acutal[0]['data_out']}"


@cocotb.test()
async def test_large_quantity(dut):
    dut._log.info( "==================== LARGE QUANTITY TEST ====================")
    driver = CompQueueDriver(dut)
    monitor = CompQueueMonitor(dut)

    await driver.reset()
    await monitor.start()

    queueDepth = 32
    expected = []

    for i in range(queueDepth):
        # aes_addr = random.randint(0, 10000)
        aes_addr = i
        await driver.send_aes(aes_addr)

    for i in range(queueDepth):
        await driver.dequeue()
        await ClockCycles(dut.clk, 1)

    for i in range(5):
        # addr = random.randint(0, 10000)
        addr = i
        expected.append({"data_out": addr})
        await driver.send_aes(addr)

    for _ in range(5):
        await driver.dequeue()
        await ClockCycles(dut.clk, 1)
    
    actual = monitor.transactions[-5:]

    for i in range(len(expected)):
        assert actual[i]["data_out"] == expected[i]["data_out"], f"Transaction {i} data_out mismatch: expected {expected[i]['data_out']}, got {actual[i]['data_out']}"

  