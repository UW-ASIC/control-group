"""
Cocotb testbench for bus_arbiter module
Tests round-robin arbitration, data transfer, and backpressure handling
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotb.types import LogicArray
import random


class BusArbiterDriver:
    """Helper class to drive the bus arbiter inputs"""
    
    def __init__(self, dut):
        self.dut = dut
        self.ADDRW = 24
        
    async def reset(self):
        """Perform reset sequence"""
        self.dut.rst_n.value = 0
        self.dut.sha_req.value = 0
        self.dut.aes_req.value = 0
        self.dut.sha_data_in.value = 0
        self.dut.aes_data_in.value = 0
        self.dut.bus_ready.value = 1
        await ClockCycles(self.dut.clk, 5)
        self.dut.rst_n.value = 1
        await ClockCycles(self.dut.clk, 2)
        
    async def send_aes_request(self, data_word):
        """Send a request from AES with 32-bit data"""
        self.dut.aes_data_in.value = data_word
        self.dut.aes_req.value = 1
        await RisingEdge(self.dut.clk)
        
    async def send_sha_request(self, data_word):
        """Send a request from SHA with 32-bit data"""
        self.dut.sha_data_in.value = data_word
        self.dut.sha_req.value = 1
        await RisingEdge(self.dut.clk)
        
    async def clear_aes_request(self):
        """Clear AES request signal"""
        self.dut.aes_req.value = 0
        await RisingEdge(self.dut.clk)
        
    async def clear_sha_request(self):
        """Clear SHA request signal"""
        self.dut.sha_req.value = 0
        await RisingEdge(self.dut.clk)
        
    async def set_bus_ready(self, ready):
        """Set bus_ready signal"""
        self.dut.bus_ready.value = ready
        await RisingEdge(self.dut.clk)


class BusArbiterMonitor:
    """Helper class to monitor bus arbiter outputs"""
    
    def __init__(self, dut):
        self.dut = dut
        self.received_bytes = []
        
    async def collect_transaction(self):
        """Collect all 4 bytes of a transaction"""
        bytes_collected = []
        
        # Wait for valid_out to go high
        while self.dut.valid_out.value == 0:
            await RisingEdge(self.dut.clk)
        
        # Collect 4 bytes
        for i in range(4):
            await RisingEdge(self.dut.clk)
            if self.dut.valid_out.value == 1:
                bytes_collected.append(int(self.dut.data_out.value))
            else:
                raise AssertionError(f"valid_out deasserted during byte {i}")
                
        # Reconstruct 32-bit word (little-endian: byte0 is LSB)
        word = (bytes_collected[3] << 24) | (bytes_collected[2] << 16) | \
               (bytes_collected[1] << 8) | bytes_collected[0]
        
        self.received_bytes.append(bytes_collected)
        return word
    
    def clear_received(self):
        """Clear received bytes buffer"""
        self.received_bytes = []


@cocotb.test()
async def test_reset(dut):
    """Test reset behavior"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = BusArbiterDriver(dut)
    
    dut._log.info("========== TEST: Reset Behavior ==========")
    
    # Apply reset
    await driver.reset()
    
    # Check initial state
    assert dut.aes_grant.value == 0, "AES grant should be 0 after reset"
    assert dut.sha_grant.value == 0, "SHA grant should be 0 after reset"
    assert dut.valid_out.value == 0, "valid_out should be 0 after reset"
    
    dut._log.info("✓ Reset test passed")


@cocotb.test()
async def test_single_aes_request(dut):
    """Test single AES request"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = BusArbiterDriver(dut)
    monitor = BusArbiterMonitor(dut)
    
    dut._log.info("========== TEST: Single AES Request ==========")
    
    await driver.reset()
    
    test_data = 0xDEADBEEF
    dut._log.info(f"Sending AES request with data: 0x{test_data:08X}")
    
    # Send AES request
    await driver.send_aes_request(test_data)
    
    # Wait for grant
    await RisingEdge(dut.clk)
    assert dut.aes_grant.value == 1, "AES should be granted"
    
    # Clear request after grant
    await driver.clear_aes_request()
    
    # Collect the transaction
    received = await monitor.collect_transaction()
    
    assert received == test_data, f"Data mismatch: got 0x{received:08X}, expected 0x{test_data:08X}"
    
    # Check grant is released
    await ClockCycles(dut.clk, 2)
    assert dut.aes_grant.value == 0, "AES grant should be released after transaction"
    
    dut._log.info("✓ Single AES request test passed")


@cocotb.test()
async def test_single_sha_request(dut):
    """Test single SHA request"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = BusArbiterDriver(dut)
    monitor = BusArbiterMonitor(dut)
    
    dut._log.info("========== TEST: Single SHA Request ==========")
    
    await driver.reset()
    
    test_data = 0xCAFEBABE
    dut._log.info(f"Sending SHA request with data: 0x{test_data:08X}")
    
    # Send SHA request
    await driver.send_sha_request(test_data)
    
    # Wait for grant
    await RisingEdge(dut.clk)
    assert dut.sha_grant.value == 1, "SHA should be granted"
    
    # Clear request after grant
    await driver.clear_sha_request()
    
    # Collect the transaction
    received = await monitor.collect_transaction()
    
    assert received == test_data, f"Data mismatch: got 0x{received:08X}, expected 0x{test_data:08X}"
    
    # Check grant is released
    await ClockCycles(dut.clk, 2)
    assert dut.sha_grant.value == 0, "SHA grant should be released after transaction"
    
    dut._log.info("✓ Single SHA request test passed")


@cocotb.test()
async def test_round_robin_arbitration(dut):
    """Test round-robin arbitration when both request simultaneously"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = BusArbiterDriver(dut)
    monitor = BusArbiterMonitor(dut)
    
    dut._log.info("========== TEST: Round-Robin Arbitration ==========")
    
    await driver.reset()
    
    aes_data = 0x11111111
    sha_data = 0x22222222
    
    # Send both requests simultaneously
    dut.aes_data_in.value = aes_data
    dut.sha_data_in.value = sha_data
    dut.aes_req.value = 1
    dut.sha_req.value = 1
    await RisingEdge(dut.clk)
    
    # One should be granted (AES should win first since last_serviced=0 initially)
    await RisingEdge(dut.clk)
    first_grant = "AES" if dut.aes_grant.value == 1 else "SHA"
    dut._log.info(f"First grant: {first_grant}")
    
    if first_grant == "AES":
        assert dut.sha_grant.value == 0, "SHA should not be granted when AES is granted"
        received1 = await monitor.collect_transaction()
        assert received1 == aes_data, f"First transaction mismatch"
        
        # SHA should be granted next
        await ClockCycles(dut.clk, 2)
        assert dut.sha_grant.value == 1, "SHA should be granted after AES completes"
        received2 = await monitor.collect_transaction()
        assert received2 == sha_data, f"Second transaction mismatch"
    else:
        assert dut.aes_grant.value == 0, "AES should not be granted when SHA is granted"
        received1 = await monitor.collect_transaction()
        assert received1 == sha_data, f"First transaction mismatch"
        
        # AES should be granted next
        await ClockCycles(dut.clk, 2)
        assert dut.aes_grant.value == 1, "AES should be granted after SHA completes"
        received2 = await monitor.collect_transaction()
        assert received2 == aes_data, f"Second transaction mismatch"
    
    dut._log.info("✓ Round-robin arbitration test passed")


@cocotb.test()
async def test_back_to_back_requests(dut):
    """Test back-to-back requests from same source"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = BusArbiterDriver(dut)
    monitor = BusArbiterMonitor(dut)
    
    dut._log.info("========== TEST: Back-to-Back Requests ==========")
    
    await driver.reset()
    
    test_values = [0x11111111, 0x22222222, 0x33333333]
    
    for i, data in enumerate(test_values):
        dut._log.info(f"Sending AES request {i+1} with data: 0x{data:08X}")
        
        # Send request
        await driver.send_aes_request(data)
        await RisingEdge(dut.clk)
        
        # Clear request after grant
        await driver.clear_aes_request()
        
        # Collect transaction
        received = await monitor.collect_transaction()
        assert received == data, f"Transaction {i+1} mismatch: got 0x{received:08X}, expected 0x{data:08X}"
        
        # Small gap between transactions
        await ClockCycles(dut.clk, 2)
    
    dut._log.info("✓ Back-to-back requests test passed")


@cocotb.test()
async def test_backpressure(dut):
    """Test backpressure handling with bus_ready"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = BusArbiterDriver(dut)
    
    dut._log.info("========== TEST: Backpressure Handling ==========")
    
    await driver.reset()
    
    test_data = 0xABCDEF01
    
    # Send AES request
    await driver.send_aes_request(test_data)
    await RisingEdge(dut.clk)
    assert dut.aes_grant.value == 1, "AES should be granted"
    
    # Wait for first byte to be valid
    while dut.valid_out.value == 0:
        await RisingEdge(dut.clk)
    
    byte0 = int(dut.data_out.value)
    dut._log.info(f"Byte 0: 0x{byte0:02X}")
    
    # Apply backpressure after first byte
    dut.bus_ready.value = 0
    await RisingEdge(dut.clk)
    
    # Counter should not advance during backpressure
    await ClockCycles(dut.clk, 3)
    # Note: data_out might still show byte 1, but counter shouldn't advance
    
    # Release backpressure
    dut._log.info("Releasing backpressure")
    dut.bus_ready.value = 1
    await RisingEdge(dut.clk)
    
    # Collect remaining bytes
    bytes_collected = [byte0]
    for i in range(3):
        await RisingEdge(dut.clk)
        if dut.valid_out.value == 1:
            bytes_collected.append(int(dut.data_out.value))
            dut._log.info(f"Byte {i+1}: 0x{bytes_collected[-1]:02X}")
    
    # Reconstruct word
    received = (bytes_collected[3] << 24) | (bytes_collected[2] << 16) | \
               (bytes_collected[1] << 8) | bytes_collected[0]
    
    assert received == test_data, f"Data mismatch after backpressure: got 0x{received:08X}, expected 0x{test_data:08X}"
    
    dut._log.info("✓ Backpressure handling test passed")


@cocotb.test()
async def test_interleaved_requests(dut):
    """Test interleaved AES and SHA requests"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = BusArbiterDriver(dut)
    monitor = BusArbiterMonitor(dut)
    
    dut._log.info("========== TEST: Interleaved Requests ==========")
    
    await driver.reset()
    
    test_sequence = [
        ("AES", 0xAAAAAAAA),
        ("SHA", 0xBBBBBBBB),
        ("AES", 0xCCCCCCCC),
        ("SHA", 0xDDDDDDDD),
        ("AES", 0xEEEEEEEE),
    ]
    
    for source, data in test_sequence:
        dut._log.info(f"Sending {source} request with data: 0x{data:08X}")
        
        if source == "AES":
            await driver.send_aes_request(data)
        else:
            await driver.send_sha_request(data)
        
        await RisingEdge(dut.clk)
        
        # Clear request
        if source == "AES":
            await driver.clear_aes_request()
        else:
            await driver.clear_sha_request()
        
        # Collect transaction
        received = await monitor.collect_transaction()
        assert received == data, f"{source} transaction mismatch: got 0x{received:08X}, expected 0x{data:08X}"
        
        await ClockCycles(dut.clk, 1)
    
    dut._log.info("✓ Interleaved requests test passed")


@cocotb.test()
async def test_fairness(dut):
    """Test round-robin fairness over multiple cycles"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = BusArbiterDriver(dut)
    monitor = BusArbiterMonitor(dut)
    
    dut._log.info("========== TEST: Round-Robin Fairness ==========")
    
    await driver.reset()
    
    aes_count = 0
    sha_count = 0
    
    # Keep both requesting and verify they alternate
    for cycle in range(6):
        aes_data = 0xA0000000 | (cycle << 16)
        sha_data = 0xB0000000 | (cycle << 16)
        
        # Both request simultaneously
        dut.aes_data_in.value = aes_data
        dut.sha_data_in.value = sha_data
        dut.aes_req.value = 1
        dut.sha_req.value = 1
        await RisingEdge(dut.clk)
        
        # Check who gets grant
        await RisingEdge(dut.clk)
        if dut.aes_grant.value == 1:
            aes_count += 1
            granted = "AES"
            expected_data = aes_data
        else:
            sha_count += 1
            granted = "SHA"
            expected_data = sha_data
        
        dut._log.info(f"Cycle {cycle}: {granted} granted (AES={aes_count}, SHA={sha_count})")
        
        # Collect transaction
        received = await monitor.collect_transaction()
        assert received == expected_data, f"Data mismatch in cycle {cycle}"
        
        await ClockCycles(dut.clk, 1)
    
    # Check fairness (should be roughly equal)
    dut._log.info(f"Final counts: AES={aes_count}, SHA={sha_count}")
    assert abs(aes_count - sha_count) <= 1, f"Unfair arbitration: AES={aes_count}, SHA={sha_count}"
    
    dut._log.info("✓ Fairness test passed")


@cocotb.test()
async def test_random_requests(dut):
    """Random stress test"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = BusArbiterDriver(dut)
    monitor = BusArbiterMonitor(dut)
    
    dut._log.info("========== TEST: Random Stress Test ==========")
    
    await driver.reset()
    
    random.seed(42)
    num_transactions = 20
    
    for i in range(num_transactions):
        requester = random.choice(["AES", "SHA", "BOTH"])
        aes_data = random.randint(0, 0xFFFFFFFF)
        sha_data = random.randint(0, 0xFFFFFFFF)
        
        if requester == "AES":
            await driver.send_aes_request(aes_data)
            await RisingEdge(dut.clk)
            await driver.clear_aes_request()
            received = await monitor.collect_transaction()
            assert received == aes_data, f"AES mismatch at iteration {i}"
            
        elif requester == "SHA":
            await driver.send_sha_request(sha_data)
            await RisingEdge(dut.clk)
            await driver.clear_sha_request()
            received = await monitor.collect_transaction()
            assert received == sha_data, f"SHA mismatch at iteration {i}"
            
        else:  # BOTH
            dut.aes_data_in.value = aes_data
            dut.sha_data_in.value = sha_data
            dut.aes_req.value = 1
            dut.sha_req.value = 1
            await RisingEdge(dut.clk)
            
            # One will be granted first
            await RisingEdge(dut.clk)
            if dut.aes_grant.value == 1:
                received1 = await monitor.collect_transaction()
                assert received1 == aes_data, f"AES mismatch in BOTH at iteration {i}"
                await ClockCycles(dut.clk, 1)
                received2 = await monitor.collect_transaction()
                assert received2 == sha_data, f"SHA mismatch in BOTH at iteration {i}"
            else:
                received1 = await monitor.collect_transaction()
                assert received1 == sha_data, f"SHA mismatch in BOTH at iteration {i}"
                await ClockCycles(dut.clk, 1)
                received2 = await monitor.collect_transaction()
                assert received2 == aes_data, f"AES mismatch in BOTH at iteration {i}"
        
        # Small gap between transactions
        await ClockCycles(dut.clk, random.randint(1, 3))
    
    dut._log.info(f"✓ Random stress test passed ({num_transactions} transactions)")


@cocotb.test()
async def test_data_integrity(dut):
    """Verify all 4 bytes are transmitted correctly"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = BusArbiterDriver(dut)
    
    dut._log.info("========== TEST: Data Integrity ==========")
    
    await driver.reset()
    
    # Test with specific byte pattern
    test_data = 0x01234567
    
    await driver.send_aes_request(test_data)
    await RisingEdge(dut.clk)
    await driver.clear_aes_request()
    
    # Wait for valid_out
    while dut.valid_out.value == 0:
        await RisingEdge(dut.clk)
    
    # Collect bytes in order
    bytes_received = []
    for i in range(4):
        await RisingEdge(dut.clk)
        byte_val = int(dut.data_out.value)
        bytes_received.append(byte_val)
        dut._log.info(f"Byte {i}: 0x{byte_val:02X} (expected: 0x{(test_data >> (i*8)) & 0xFF:02X})")
    
    # Verify byte order (little-endian)
    expected_bytes = [
        (test_data >> 0) & 0xFF,   # Byte 0: 0x67
        (test_data >> 8) & 0xFF,   # Byte 1: 0x45
        (test_data >> 16) & 0xFF,  # Byte 2: 0x23
        (test_data >> 24) & 0xFF,  # Byte 3: 0x01
    ]
    
    assert bytes_received == expected_bytes, f"Byte order mismatch: got {[hex(b) for b in bytes_received]}, expected {[hex(b) for b in expected_bytes]}"
    
    dut._log.info("✓ Data integrity test passed")
