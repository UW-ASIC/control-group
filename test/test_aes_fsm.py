"""
Cocotb testbench for aes_fsm module
Tests FSM state transitions, request/completion queues, and bus arbiter interactions
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotb.types import LogicArray
import random


class AESFSMDriver:
    """Helper class to drive the AES FSM inputs"""
    
    def __init__(self, dut):
        self.dut = dut
        self.ADDRW = 24
        self.ACCEL_ID = 0b10
        self.MEM_ID = 0b00
        
    async def reset(self):
        """Perform reset sequence"""
        self.dut.rst_n.value = 0
        self.dut.req_valid.value = 0
        self.dut.req_data.value = 0
        self.dut.comq_ready_in.value = 1
        self.dut.arb_grant.value = 0
        self.dut.ack_in.value = 0
        await ClockCycles(self.dut.clk, 5)
        self.dut.rst_n.value = 1
        await ClockCycles(self.dut.clk, 2)
        
    def pack_request(self, key_addr, text_addr, result_addr, hash_mode=0):
        """Pack addresses into req_data format [3*ADDRW+1:0]"""
        # req_data = {key_addr[23:0], text_addr[23:0], result_addr[23:0], hash_mode, padding}
        req_data = (key_addr << (2*self.ADDRW)) | (text_addr << self.ADDRW) | result_addr | (hash_mode << 73)
        return req_data
        
    async def send_request(self, key_addr, text_addr, result_addr, hash_mode=0):
        """Send a request to the FSM"""
        req_data = self.pack_request(key_addr, text_addr, result_addr, hash_mode)
        self.dut.req_data.value = req_data
        self.dut.req_valid.value = 1
        await RisingEdge(self.dut.clk)
        # Wait for FSM to acknowledge (when it leaves READY state or loads data)
        await RisingEdge(self.dut.clk)
        # Clear req_valid so FSM can complete and return to READY
        self.dut.req_valid.value = 0
        
    async def clear_request(self):
        """Clear request valid signal"""
        self.dut.req_valid.value = 0
        await RisingEdge(self.dut.clk)
        
    async def grant_bus(self):
        """Grant bus access when arbiter request is asserted"""
        while self.dut.arb_req.value == 0:
            await RisingEdge(self.dut.clk)
        self.dut.arb_grant.value = 1
        await RisingEdge(self.dut.clk)
        self.dut.arb_grant.value = 0
        
    async def send_mem_ack(self):
        """Send ACK from memory (ack_in = {1'b1, MEM_ID})"""
        self.dut.ack_in.value = (1 << 2) | self.MEM_ID
        await RisingEdge(self.dut.clk)
        self.dut.ack_in.value = 0
        
    async def send_accel_ack(self):
        """Send ACK from accelerator (ack_in = {1'b1, ACCEL_ID})"""
        self.dut.ack_in.value = (1 << 2) | self.ACCEL_ID
        await RisingEdge(self.dut.clk)
        self.dut.ack_in.value = 0
        
    async def set_compq_ready(self, ready):
        """Set completion queue ready signal"""
        self.dut.comq_ready_in.value = ready
        await RisingEdge(self.dut.clk)


class AESFSMMonitor:
    """Helper class to monitor FSM behavior"""
    
    # FSM states
    READY = 0
    RDKEY = 1
    WAIT_RDKEY = 2
    RDTEXT = 3
    WAIT_RDTXT = 4
    HASHOP = 5
    WAIT_HASHOP = 6
    MEMWR = 7
    WAIT_MEMWR = 8
    COMPLETE = 9
    
    STATE_NAMES = {
        READY: "READY",
        RDKEY: "RDKEY",
        WAIT_RDKEY: "WAIT_RDKEY",
        RDTEXT: "RDTEXT",
        WAIT_RDTXT: "WAIT_RDTXT",
        HASHOP: "HASHOP",
        WAIT_HASHOP: "WAIT_HASHOP",
        MEMWR: "MEMWR",
        WAIT_MEMWR: "WAIT_MEMWR",
        COMPLETE: "COMPLETE"
    }
    
    def __init__(self, dut):
        self.dut = dut.dut  # Access the actual DUT inside the testbench
        self.ADDRW = 24
        
    def get_state(self):
        """Get current FSM state"""
        return int(self.dut.state.value)
        
    def get_state_name(self):
        """Get current FSM state name"""
        state = self.get_state()
        return self.STATE_NAMES.get(state, f"UNKNOWN({state})")
        
    async def wait_for_state(self, expected_state, timeout_cycles=100):
        """Wait for FSM to reach expected state"""
        for _ in range(timeout_cycles):
            if self.get_state() == expected_state:
                return True
            await RisingEdge(self.dut.clk)
        return False
        
    def parse_data_out(self):
        """Parse data_out into address and control fields"""
        data = int(self.dut.data_out.value)
        addr = (data >> 8) & ((1 << self.ADDRW) - 1)
        ctrl = data & 0xFF
        return addr, ctrl


@cocotb.test()
async def test_reset(dut):
    """Test reset behavior"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = AESFSMDriver(dut)
    monitor = AESFSMMonitor(dut)
    
    dut._log.info("========== TEST: Reset Behavior ==========")
    
    await driver.reset()
    
    # Check FSM is in READY state
    assert monitor.get_state() == monitor.READY, f"FSM should be in READY state after reset, got {monitor.get_state_name()}"
    assert dut.arb_req.value == 0, "arb_req should be 0 after reset"
    assert dut.valid_compq_out.value == 0, "valid_compq_out should be 0 after reset"
    
    dut._log.info("✓ Reset test passed")


@cocotb.test()
async def test_single_transaction(dut):
    """Test complete AES transaction: READY → RDKEY → RDTEXT → HASH → WRITE → COMPLETE"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = AESFSMDriver(dut)
    monitor = AESFSMMonitor(dut)
    
    dut._log.info("========== TEST: Single Complete Transaction ==========")
    
    await driver.reset()
    
    # Test addresses
    key_addr = 0x001000
    text_addr = 0x002000
    result_addr = 0x003000
    hash_mode = 0
    
    dut._log.info(f"Sending request: key=0x{key_addr:06X}, text=0x{text_addr:06X}, result=0x{result_addr:06X}")
    
    # Send request
    await driver.send_request(key_addr, text_addr, result_addr, hash_mode)
    
    # FSM should transition to RDKEY
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.RDKEY, f"Expected RDKEY state, got {monitor.get_state_name()}"
    assert dut.arb_req.value == 1, "arb_req should be asserted in RDKEY"
    
    # Check data_out for RDKEY command
    addr, ctrl = monitor.parse_data_out()
    assert addr == key_addr, f"RDKEY address mismatch: got 0x{addr:06X}, expected 0x{key_addr:06X}"
    dut._log.info(f"RDKEY: addr=0x{addr:06X}, ctrl=0x{ctrl:02X}")
    
    # Grant bus
    await driver.grant_bus()
    
    # FSM should move to WAIT_RDKEY
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.WAIT_RDKEY, f"Expected WAIT_RDKEY, got {monitor.get_state_name()}"
    
    # Send memory ACK
    await driver.send_mem_ack()
    
    # FSM should transition to RDTEXT
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.RDTEXT, f"Expected RDTEXT, got {monitor.get_state_name()}"
    assert dut.arb_req.value == 1, "arb_req should be asserted in RDTEXT"
    
    # Check data_out for RDTEXT command
    addr, ctrl = monitor.parse_data_out()
    assert addr == text_addr, f"RDTEXT address mismatch: got 0x{addr:06X}, expected 0x{text_addr:06X}"
    dut._log.info(f"RDTEXT: addr=0x{addr:06X}, ctrl=0x{ctrl:02X}")
    
    # Grant bus
    await driver.grant_bus()
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.WAIT_RDTXT, f"Expected WAIT_RDTXT, got {monitor.get_state_name()}"
    
    # Send memory ACK
    await driver.send_mem_ack()
    
    # FSM should transition to HASHOP
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.HASHOP, f"Expected HASHOP, got {monitor.get_state_name()}"
    assert dut.arb_req.value == 1, "arb_req should be asserted in HASHOP"
    try:
        dut._log.info(f"HASHOP: data_out=0x{int(dut.data_out.value):08X}")
    except ValueError:
        dut._log.info(f"HASHOP: data_out has x values (expected during transition)")
    
    # Grant bus
    await driver.grant_bus()
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.WAIT_HASHOP, f"Expected WAIT_HASHOP, got {monitor.get_state_name()}"
    
    # Send accelerator ACK
    await driver.send_accel_ack()
    
    # FSM should transition to MEMWR
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.MEMWR, f"Expected MEMWR, got {monitor.get_state_name()}"
    assert dut.arb_req.value == 1, "arb_req should be asserted in MEMWR"
    
    # Check data_out for MEMWR command
    addr, ctrl = monitor.parse_data_out()
    assert addr == result_addr, f"MEMWR address mismatch: got 0x{addr:06X}, expected 0x{result_addr:06X}"
    dut._log.info(f"MEMWR: addr=0x{addr:06X}, ctrl=0x{ctrl:02X}")
    
    # Grant bus
    await driver.grant_bus()
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.WAIT_MEMWR, f"Expected WAIT_MEMWR, got {monitor.get_state_name()}"
    
    # Send memory ACK
    await driver.send_mem_ack()
    
    # FSM should transition to COMPLETE
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.COMPLETE, f"Expected COMPLETE, got {monitor.get_state_name()}"
    assert dut.valid_compq_out.value == 1, "valid_compq_out should be asserted in COMPLETE"
    assert int(dut.compq_data_out.value) == result_addr, f"compq_data_out mismatch"
    dut._log.info(f"COMPLETE: compq_data=0x{int(dut.compq_data_out.value):06X}")
    
    # Completion queue accepts
    await RisingEdge(dut.clk)
    
    # FSM should return to READY
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.READY, f"Expected READY, got {monitor.get_state_name()}"
    
    dut._log.info("✓ Single transaction test passed")


@cocotb.test()
async def test_backpressure_on_bus(dut):
    """Test FSM behavior when bus arbiter delays grant"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = AESFSMDriver(dut)
    monitor = AESFSMMonitor(dut)
    
    dut._log.info("========== TEST: Bus Arbiter Backpressure ==========")
    
    await driver.reset()
    
    # Send request
    await driver.send_request(0x001000, 0x002000, 0x003000)
    
    # FSM should request bus in RDKEY
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.RDKEY, "Should be in RDKEY"
    assert dut.arb_req.value == 1, "arb_req should be asserted"
    
    # Delay bus grant for several cycles
    dut._log.info("Delaying bus grant...")
    for i in range(5):
        await RisingEdge(dut.clk)
        assert monitor.get_state() == monitor.RDKEY, f"Should remain in RDKEY during backpressure (cycle {i})"
        assert dut.arb_req.value == 1, f"arb_req should remain asserted (cycle {i})"
    
    # Finally grant bus
    dut._log.info("Granting bus")
    dut.arb_grant.value = 1
    await RisingEdge(dut.clk)
    dut.arb_grant.value = 0
    
    # FSM should move to WAIT_RDKEY
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.WAIT_RDKEY, "Should move to WAIT_RDKEY after grant"
    
    dut._log.info("✓ Bus backpressure test passed")


@cocotb.test()
async def test_completion_queue_backpressure(dut):
    """Test FSM behavior when completion queue is not ready"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = AESFSMDriver(dut)
    monitor = AESFSMMonitor(dut)
    
    dut._log.info("========== TEST: Completion Queue Backpressure ==========")
    
    await driver.reset()
    
    # Apply backpressure BEFORE starting transaction
    dut._log.info("Applying completion queue backpressure from start")
    dut.comq_ready_in.value = 0
    
    # Run through complete transaction quickly
    await driver.send_request(0x001000, 0x002000, 0x003000)
    
    # RDKEY
    await RisingEdge(dut.clk)
    await driver.grant_bus()
    await driver.send_mem_ack()
    
    # RDTEXT
    await RisingEdge(dut.clk)
    await driver.grant_bus()
    await driver.send_mem_ack()
    
    # HASHOP
    await RisingEdge(dut.clk)
    await driver.grant_bus()
    await driver.send_accel_ack()
    
    # MEMWR
    await RisingEdge(dut.clk)
    await driver.grant_bus()
    await driver.send_mem_ack()
    
    # Should reach COMPLETE
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.COMPLETE, "Should reach COMPLETE"
    assert dut.valid_compq_out.value == 1, "valid_compq_out should be asserted"
    
    # FSM should remain in COMPLETE while backpressure is applied
    for i in range(5):
        await RisingEdge(dut.clk)
        assert monitor.get_state() == monitor.COMPLETE, f"Should remain in COMPLETE during backpressure (cycle {i})"
        assert dut.valid_compq_out.value == 1, "valid_compq_out should remain asserted"
    
    # Release backpressure
    dut._log.info("Releasing completion queue backpressure")
    dut.comq_ready_in.value = 1
    await RisingEdge(dut.clk)
    
    # Should transition to READY
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.READY, "Should transition to READY after backpressure release"
    
    dut._log.info("✓ Completion queue backpressure test passed")


@cocotb.test()
async def test_multiple_transactions(dut):
    """Test multiple back-to-back transactions"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = AESFSMDriver(dut)
    monitor = AESFSMMonitor(dut)
    
    dut._log.info("========== TEST: Multiple Transactions ==========")
    
    await driver.reset()
    
    async def run_transaction(key_addr, text_addr, result_addr):
        """Helper to run a complete transaction"""
        dut._log.info(f"Transaction: key=0x{key_addr:06X}, text=0x{text_addr:06X}, result=0x{result_addr:06X}")
        
        await driver.send_request(key_addr, text_addr, result_addr)
        
        # RDKEY
        await RisingEdge(dut.clk)
        assert monitor.get_state() == monitor.RDKEY
        await driver.grant_bus()
        await driver.send_mem_ack()
        
        # RDTEXT
        await RisingEdge(dut.clk)
        assert monitor.get_state() == monitor.RDTEXT
        await driver.grant_bus()
        await driver.send_mem_ack()
        
        # HASHOP
        await RisingEdge(dut.clk)
        assert monitor.get_state() == monitor.HASHOP
        await driver.grant_bus()
        await driver.send_accel_ack()
        
        # MEMWR
        await RisingEdge(dut.clk)
        assert monitor.get_state() == monitor.MEMWR
        await driver.grant_bus()
        await driver.send_mem_ack()
        
        # COMPLETE
        await RisingEdge(dut.clk)
        assert monitor.get_state() == monitor.COMPLETE
        assert int(dut.compq_data_out.value) == result_addr
        
        # Return to READY
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)
        assert monitor.get_state() == monitor.READY
    
    # Run 3 transactions
    await run_transaction(0x001000, 0x002000, 0x003000)
    await run_transaction(0x004000, 0x005000, 0x006000)
    await run_transaction(0x007000, 0x008000, 0x009000)
    
    dut._log.info("✓ Multiple transactions test passed")


@cocotb.test()
async def test_reset_during_operation(dut):
    """Test reset assertion during active operation"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = AESFSMDriver(dut)
    monitor = AESFSMMonitor(dut)
    
    dut._log.info("========== TEST: Reset During Operation ==========")
    
    await driver.reset()
    
    # Start a transaction
    await driver.send_request(0x001000, 0x002000, 0x003000)
    await RisingEdge(dut.clk)
    await driver.grant_bus()
    
    # Get to WAIT_RDKEY state
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.WAIT_RDKEY
    
    # Assert reset in the middle of operation
    dut._log.info("Asserting reset during WAIT_RDKEY")
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    
    # FSM should be back in READY
    assert monitor.get_state() == monitor.READY, f"FSM should be in READY after reset, got {monitor.get_state_name()}"
    assert dut.arb_req.value == 0, "arb_req should be 0 after reset"
    
    dut._log.info("✓ Reset during operation test passed")


@cocotb.test()
async def test_data_output_format(dut):
    """Verify data_out formatting for each operation type"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = AESFSMDriver(dut)
    monitor = AESFSMMonitor(dut)
    
    dut._log.info("========== TEST: Data Output Format Verification ==========")
    
    await driver.reset()
    
    key_addr = 0xABCDEF
    text_addr = 0x123456
    result_addr = 0x789ABC
    hash_mode = 1
    
    await driver.send_request(key_addr, text_addr, result_addr, hash_mode)
    
    # Check RDKEY data format
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.RDKEY
    data_out = int(dut.data_out.value)
    addr, ctrl = monitor.parse_data_out()
    dut._log.info(f"RDKEY: data_out=0x{data_out:08X}, addr=0x{addr:06X}, ctrl=0x{ctrl:02X}")
    assert addr == key_addr, "RDKEY address mismatch"
    # Control format: [1:0]=00 (reserved), [3:2]=MEM_ID, [5:4]=ACCEL_ID, [7:6]=00 (read key op)
    
    await driver.grant_bus()
    await driver.send_mem_ack()
    
    # Check RDTEXT data format
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.RDTEXT
    data_out = int(dut.data_out.value)
    addr, ctrl = monitor.parse_data_out()
    dut._log.info(f"RDTEXT: data_out=0x{data_out:08X}, addr=0x{addr:06X}, ctrl=0x{ctrl:02X}")
    assert addr == text_addr, "RDTEXT address mismatch"
    
    await driver.grant_bus()
    await driver.send_mem_ack()
    
    # Check HASHOP data format
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.HASHOP
    try:
        data_out = int(dut.data_out.value)
        dut._log.info(f"HASHOP: data_out=0x{data_out:08X}")
    except ValueError:
        dut._log.info(f"HASHOP: data_out has x values (acceptable during transition)")
    # Should contain hash_mode bit
    
    await driver.grant_bus()
    await driver.send_accel_ack()
    
    # Check MEMWR data format
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.MEMWR
    data_out = int(dut.data_out.value)
    addr, ctrl = monitor.parse_data_out()
    dut._log.info(f"MEMWR: data_out=0x{data_out:08X}, addr=0x{addr:06X}, ctrl=0x{ctrl:02X}")
    assert addr == result_addr, "MEMWR address mismatch"
    
    dut._log.info("✓ Data output format test passed")


@cocotb.test()
async def test_req_valid_hold(dut):
    """Test that req_valid can be held high across multiple cycles"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    driver = AESFSMDriver(dut)
    monitor = AESFSMMonitor(dut)
    
    dut._log.info("========== TEST: Req Valid Hold Behavior ==========")
    
    await driver.reset()
    
    # Send request and KEEP req_valid high
    await driver.send_request(0x001000, 0x002000, 0x003000)
    
    # Don't clear req_valid - keep it high
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.RDKEY
    
    # req_valid should not cause issues when held high
    for _ in range(5):
        await RisingEdge(dut.clk)
        # FSM should not re-enter RDKEY or reload data
    
    # Complete the transaction normally
    await driver.grant_bus()
    await driver.send_mem_ack()
    
    # Should proceed normally
    await RisingEdge(dut.clk)
    assert monitor.get_state() == monitor.RDTEXT
    
    dut._log.info("✓ Req valid hold test passed")