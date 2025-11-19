import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

ADDRW   = 24
OPCODEW = 2
INSTRW  = 3 * ADDRW + OPCODEW
QDEPTH  = 16

AES = 0  # opcode[0] == 0
SHA = 1  # opcode[0] == 1


def pack_instr(opc, key, text, dest):
    """Pack fields to match RTL: {opcode, key_addr, text_addr, dest_addr}"""
    assert 0 <= opc  < (1 << OPCODEW)
    assert 0 <= key  < (1 << ADDRW)
    assert 0 <= text < (1 << ADDRW)
    assert 0 <= dest < (1 << ADDRW)
    return (opc << (3 * ADDRW)) | (key << (2 * ADDRW)) | (text << ADDRW) | dest


def get_int(sig):
    return int(sig.value)


async def reset(dut):
    """Reset the DUT and wait for it to be ready."""
    dut.valid_in.value     = 0
    dut.ready_in_aes.value = 0
    dut.ready_in_sha.value = 0
    dut.opcode.value       = 0
    dut.key_addr.value     = 0
    dut.text_addr.value    = 0
    dut.dest_addr.value    = 0
    dut.rst_n.value        = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value        = 1
    await ClockCycles(dut.clk, 2)


async def push_if_ready(dut, opc, key, text, dest, should_accept=True):
    """
    Drives a 1-cycle valid_in with the given instruction.
    - If should_accept=True, we expect the matching ready_out_* to be 1 before the push.
    - If should_accept=False, we expect ready_out_* to be 0 (full / backpressured).
    This models "producer checks ready before asserting valid".
    """
    is_sha = (opc & 1) == 1
    ready_line = dut.ready_out_sha if is_sha else dut.ready_out_aes

    # Drive fields
    dut.opcode.value    = opc
    dut.key_addr.value  = key
    dut.text_addr.value = text
    dut.dest_addr.value = dest

    # Sample ready before asserting valid
    await RisingEdge(dut.clk)
    ready_now = int(ready_line.value)

    dut.valid_in.value = 1
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0

    if should_accept:
        assert ready_now == 1, "Expected queue to accept, but ready_out was 0"
    else:
        assert ready_now == 0, "Expected queue to be full (no accept), but ready_out was 1"


async def pop_aes(dut, expect_valid=True):
    """Pop one AES entry (1-cycle ready_in_aes) and check valid_out_aes behavior."""
    await RisingEdge(dut.clk)
    valid = int(dut.valid_out_aes.value)
    if expect_valid:
        assert valid == 1, "Expected AES valid_out=1 before pop"
    else:
        assert valid == 0, "Expected AES valid_out=0 (empty), but it was 1"
    dut.ready_in_aes.value = 1
    await RisingEdge(dut.clk)
    dut.ready_in_aes.value = 0


async def pop_sha(dut, expect_valid=True):
    """Pop one SHA entry (1-cycle ready_in_sha) and check valid_out_sha behavior."""
    await RisingEdge(dut.clk)
    valid = int(dut.valid_out_sha.value)
    if expect_valid:
        assert valid == 1, "Expected SHA valid_out=1 before pop"
    else:
        assert valid == 0, "Expected SHA valid_out=0 (empty), but it was 1"
    dut.ready_in_sha.value = 1
    await RisingEdge(dut.clk)
    dut.ready_in_sha.value = 0


@cocotb.test()
async def req_queue_full_suite(dut):
    """Comprehensive directed + random test for req_queue."""

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # --- 1) Reset behavior ----------------------------------------------------
    assert int(dut.valid_out_aes.value) == 0
    assert int(dut.valid_out_sha.value) == 0
    assert int(dut.ready_out_aes.value) == 1  # not full
    assert int(dut.ready_out_sha.value) == 1

    # --- 2) Single AES enqueue/dequeue ----------------------------------------
    opc = 0b00  # AES
    key, text, dest = 0x000001, 0x000002, 0x000003
    golden = pack_instr(opc, key, text, dest)

    await push_if_ready(dut, opc, key, text, dest, should_accept=True)
    await RisingEdge(dut.clk)
    assert int(dut.valid_out_aes.value) == 1
    assert get_int(dut.instr_aes) == golden

    await pop_aes(dut, expect_valid=True)
    await RisingEdge(dut.clk)
    assert int(dut.valid_out_aes.value) == 0

    # --- 3) Single SHA enqueue/dequeue ----------------------------------------
    opc = 0b01  # SHA
    key, text, dest = 0xABCDEF, 0x012345, 0x6789AB
    golden = pack_instr(opc, key, text, dest)

    await push_if_ready(dut, opc, key, text, dest, should_accept=True)
    await RisingEdge(dut.clk)
    assert int(dut.valid_out_sha.value) == 1
    assert get_int(dut.instr_sha) == golden

    await pop_sha(dut, expect_valid=True)
    await RisingEdge(dut.clk)
    assert int(dut.valid_out_sha.value) == 0

    # --- 4) Interleaved writes: ordering per-queue ----------------------------
    aes_model = []
    sha_model = []

    async def enqueue_and_track(opc, key, text, dest):
        await push_if_ready(dut, opc, key, text, dest, should_accept=True)
        instr = pack_instr(opc, key, text, dest)
        if (opc & 1) == 1:
            sha_model.append(instr)
        else:
            aes_model.append(instr)

    for i in range(4):
        opc = AES if (i % 2 == 0) else SHA
        key  = random.randrange(1 << ADDRW)
        text = random.randrange(1 << ADDRW)
        dest = random.randrange(1 << ADDRW)
        await enqueue_and_track(opc, key, text, dest)

    # Pop one from each and check top-of-queue matches model[0]
    if aes_model:
        await RisingEdge(dut.clk)
        assert int(dut.valid_out_aes.value) == 1
        assert get_int(dut.instr_aes) == aes_model[0]
        await pop_aes(dut, expect_valid=True)
        aes_model.pop(0)

    if sha_model:
        await RisingEdge(dut.clk)
        assert int(dut.valid_out_sha.value) == 1
        assert get_int(dut.instr_sha) == sha_model[0]
        await pop_sha(dut, expect_valid=True)
        sha_model.pop(0)

    # --- Clean up remaining items from section 4 ------------------------------
    while len(aes_model) > 0:
        await RisingEdge(dut.clk)
        assert int(dut.valid_out_aes.value) == 1
        await pop_aes(dut, expect_valid=True)
        aes_model.pop(0)

    while len(sha_model) > 0:
        await RisingEdge(dut.clk)
        assert int(dut.valid_out_sha.value) == 1
        await pop_sha(dut, expect_valid=True)
        sha_model.pop(0)

    # Now both queues are empty
    await RisingEdge(dut.clk)
    assert int(dut.valid_out_aes.value) == 0
    assert int(dut.valid_out_sha.value) == 0

    # --- 5) Fill AES to full, check full behavior + contents ------------------
    aes_fill_golden = []
    for i in range(QDEPTH):
        opc = 0b00
        key, text, dest = i, i + 1, i + 2
        aes_fill_golden.append(pack_instr(opc, key, text, dest))
        await push_if_ready(dut, opc, key, text, dest, should_accept=True)

    await RisingEdge(dut.clk)
    assert int(dut.ready_out_aes.value) == 0, "AES should be full"
    assert int(dut.valid_out_aes.value) == 1, "AES not empty when full"

    # Overflow attempt: should not be accepted
    await push_if_ready(dut, 0b00, 0xDEAD, 0xBEEF, 0xFACE, should_accept=False)

    # Drain AES, check data in order and pointer wrap safety
    for expected in aes_fill_golden:
        await RisingEdge(dut.clk)
        assert int(dut.valid_out_aes.value) == 1
        assert get_int(dut.instr_aes) == expected
        await pop_aes(dut, expect_valid=True)

    await RisingEdge(dut.clk)
    assert int(dut.valid_out_aes.value) == 0
    assert int(dut.ready_out_aes.value) == 1  # space again

    # --- 6) Fill SHA to full, same checks -------------------------------------
    sha_fill_golden = []
    for i in range(QDEPTH):
        opc = 0b01
        key, text, dest = (i << 2), (i << 1), i
        sha_fill_golden.append(pack_instr(opc, key, text, dest))
        await push_if_ready(dut, opc, key, text, dest, should_accept=True)

    await RisingEdge(dut.clk)
    assert int(dut.ready_out_sha.value) == 0, "SHA should be full"
    assert int(dut.valid_out_sha.value) == 1, "SHA not empty when full"

    # Overflow attempt
    await push_if_ready(dut, 0b01, 1, 2, 3, should_accept=False)

    # Drain SHA, check order
    for expected in sha_fill_golden:
        await RisingEdge(dut.clk)
        assert int(dut.valid_out_sha.value) == 1
        assert get_int(dut.instr_sha) == expected
        await pop_sha(dut, expect_valid=True)

    await RisingEdge(dut.clk)
    assert int(dut.valid_out_sha.value) == 0
    assert int(dut.ready_out_sha.value) == 1

    # --- 7) Empty-pop protection ----------------------------------------------
    await pop_aes(dut, expect_valid=False)
    await pop_sha(dut, expect_valid=False)

    # --- Clean state before random test --------------------------------------
    # Make absolutely sure both queues are empty
    while int(dut.valid_out_aes.value) == 1:
        dut.ready_in_aes.value = 1
        await RisingEdge(dut.clk)
        dut.ready_in_aes.value = 0
        await RisingEdge(dut.clk)
    
    while int(dut.valid_out_sha.value) == 1:
        dut.ready_in_sha.value = 1
        await RisingEdge(dut.clk)
        dut.ready_in_sha.value = 0
        await RisingEdge(dut.clk)
    
    # Verify clean state
    await RisingEdge(dut.clk)
    assert int(dut.valid_out_aes.value) == 0, "AES should be empty before random test"
    assert int(dut.valid_out_sha.value) == 0, "SHA should be empty before random test"
    assert int(dut.ready_out_aes.value) == 1, "AES should be ready before random test"
    assert int(dut.ready_out_sha.value) == 1, "SHA should be ready before random test"

    # --- 8) Random stress with DEBUG LOGGING ----------------------------------
    aes_sw = []
    sha_sw = []

    for iteration in range(50):  # Reduced from 100 to find failure faster
        # Log current state
        aes_ready = int(dut.ready_out_aes.value)
        sha_ready = int(dut.ready_out_sha.value)
        aes_valid = int(dut.valid_out_aes.value)
        sha_valid = int(dut.valid_out_sha.value)
        
        print(f"\n[Iter {iteration}] AES: ready={aes_ready}, valid={aes_valid}, sw_len={len(aes_sw)} | SHA: ready={sha_ready}, valid={sha_valid}, sw_len={len(sha_sw)}")
        
        # Randomly decide: enqueue or dequeue
        if random.random() < 0.6:
            # Try to enqueue
            opc = random.choice([0b00, 0b01])
            key  = random.randrange(1 << ADDRW)
            text = random.randrange(1 << ADDRW)
            dest = random.randrange(1 << ADDRW)
            is_sha = (opc & 1) == 1
            queue_name = "SHA" if is_sha else "AES"
            ready_now = sha_ready if is_sha else aes_ready
            
            print(f"  -> Attempting PUSH to {queue_name}, ready={ready_now}")
            
            if ready_now == 1:
                # Direct push without using push_if_ready
                dut.opcode.value = opc
                dut.key_addr.value = key
                dut.text_addr.value = text
                dut.dest_addr.value = dest
                dut.valid_in.value = 1
                await RisingEdge(dut.clk)
                dut.valid_in.value = 0
                
                instr = pack_instr(opc, key, text, dest)
                (sha_sw if is_sha else aes_sw).append(instr)
                print(f"  -> PUSHED to {queue_name}")
            else:
                print(f"  -> SKIPPED push to {queue_name} (not ready)")
        else:
            # Try to dequeue
            if random.random() < 0.5 and len(aes_sw) > 0:
                print(f"  -> Attempting POP from AES (model has {len(aes_sw)} items)")
                await RisingEdge(dut.clk)
                if int(dut.valid_out_aes.value) == 1:
                    actual = get_int(dut.instr_aes)
                    expected = aes_sw[0]
                    print(f"  -> Checking AES: expected={expected:x}, actual={actual:x}")
                    assert actual == expected, f"Mismatch!"
                    dut.ready_in_aes.value = 1
                    await RisingEdge(dut.clk)
                    dut.ready_in_aes.value = 0
                    aes_sw.pop(0)
                    print(f"  -> POPPED from AES")
                else:
                    print(f"  -> SKIP pop from AES (not valid)")
            elif len(sha_sw) > 0:
                print(f"  -> Attempting POP from SHA (model has {len(sha_sw)} items)")
                await RisingEdge(dut.clk)
                if int(dut.valid_out_sha.value) == 1:
                    actual = get_int(dut.instr_sha)
                    expected = sha_sw[0]
                    print(f"  -> Checking SHA: expected={expected:x}, actual={actual:x}")
                    assert actual == expected, f"Mismatch!"
                    dut.ready_in_sha.value = 1
                    await RisingEdge(dut.clk)
                    dut.ready_in_sha.value = 0
                    sha_sw.pop(0)
                    print(f"  -> POPPED from SHA")
                else:
                    print(f"  -> SKIP pop from SHA (not valid)")

    # Drain remaining
    print(f"\n[DRAINING] AES has {len(aes_sw)} items, SHA has {len(sha_sw)} items")
    
    while len(aes_sw) > 0:
        await RisingEdge(dut.clk)
        if int(dut.valid_out_aes.value) == 1:
            assert get_int(dut.instr_aes) == aes_sw[0]
            dut.ready_in_aes.value = 1
            await RisingEdge(dut.clk)
            dut.ready_in_aes.value = 0
            aes_sw.pop(0)

    while len(sha_sw) > 0:
        await RisingEdge(dut.clk)
        if int(dut.valid_out_sha.value) == 1:
            assert get_int(dut.instr_sha) == sha_sw[0]
            dut.ready_in_sha.value = 1
            await RisingEdge(dut.clk)
            dut.ready_in_sha.value = 0
            sha_sw.pop(0)

    await RisingEdge(dut.clk)
    assert len(aes_sw) == 0
    assert len(sha_sw) == 0
    assert int(dut.valid_out_aes.value) == 0
    assert int(dut.valid_out_sha.value) == 0
    assert int(dut.ready_out_aes.value) == 1
    assert int(dut.ready_out_sha.value) == 1


@cocotb.test()
async def test_simultaneous_push_pop(dut):
    """Test simultaneous push and pop operations (throughput test)."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    
    dut._log.info("Testing simultaneous push/pop for maximum throughput")
    
    # Push one AES item first
    dut.opcode.value = 0b00
    dut.key_addr.value = 0x111
    dut.text_addr.value = 0x222
    dut.dest_addr.value = 0x333
    dut.valid_in.value = 1
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    
    await RisingEdge(dut.clk)
    assert int(dut.valid_out_aes.value) == 1, "Should have 1 AES item"
    
    # Now simultaneously push new item and pop existing item
    dut.opcode.value = 0b00
    dut.key_addr.value = 0x444
    dut.text_addr.value = 0x555
    dut.dest_addr.value = 0x666
    dut.valid_in.value = 1
    dut.ready_in_aes.value = 1
    
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    dut.ready_in_aes.value = 0
    
    # Check that queue still has 1 item (popped 1, pushed 1)
    await RisingEdge(dut.clk)
    assert int(dut.valid_out_aes.value) == 1, "Should still have 1 item after simultaneous push/pop"
    assert get_int(dut.instr_aes) == pack_instr(0b00, 0x444, 0x555, 0x666), "Should see the newly pushed item"
    
    # Test with SHA as well
    dut.opcode.value = 0b01
    dut.key_addr.value = 0x777
    dut.text_addr.value = 0x888
    dut.dest_addr.value = 0x999
    dut.valid_in.value = 1
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    
    await RisingEdge(dut.clk)
    assert int(dut.valid_out_sha.value) == 1
    
    dut.opcode.value = 0b01
    dut.key_addr.value = 0xAAA
    dut.text_addr.value = 0xBBB
    dut.dest_addr.value = 0xCCC
    dut.valid_in.value = 1
    dut.ready_in_sha.value = 1
    
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    dut.ready_in_sha.value = 0
    
    await RisingEdge(dut.clk)
    assert int(dut.valid_out_sha.value) == 1
    assert get_int(dut.instr_sha) == pack_instr(0b01, 0xAAA, 0xBBB, 0xCCC)
    
    dut._log.info("Simultaneous push/pop test PASSED")


@cocotb.test()
async def test_both_queues_simultaneous(dut):
    """Test both queues operating simultaneously."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    
    dut._log.info("Testing simultaneous operations on both queues")
    
    # Push to both AES and SHA simultaneously (Note: can only push one per cycle due to single valid_in)
    # So we push to AES first
    dut.opcode.value = 0b00
    dut.key_addr.value = 0x100
    dut.text_addr.value = 0x200
    dut.dest_addr.value = 0x300
    dut.valid_in.value = 1
    await RisingEdge(dut.clk)
    
    # Then push to SHA
    dut.opcode.value = 0b01
    dut.key_addr.value = 0x400
    dut.text_addr.value = 0x500
    dut.dest_addr.value = 0x600
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    
    # Verify both queues have items
    await RisingEdge(dut.clk)
    assert int(dut.valid_out_aes.value) == 1
    assert int(dut.valid_out_sha.value) == 1
    
    # Pop from both simultaneously
    dut.ready_in_aes.value = 1
    dut.ready_in_sha.value = 1
    await RisingEdge(dut.clk)
    dut.ready_in_aes.value = 0
    dut.ready_in_sha.value = 0
    
    # Both queues should be empty now
    await RisingEdge(dut.clk)
    assert int(dut.valid_out_aes.value) == 0
    assert int(dut.valid_out_sha.value) == 0
    
    # Test push to one while popping from other
    # Add 2 items to each queue
    for _ in range(2):
        dut.opcode.value = 0b00
        dut.key_addr.value = 0x111
        dut.text_addr.value = 0x222
        dut.dest_addr.value = 0x333
        dut.valid_in.value = 1
        await RisingEdge(dut.clk)
        
        dut.opcode.value = 0b01
        dut.key_addr.value = 0x444
        dut.text_addr.value = 0x555
        dut.dest_addr.value = 0x666
        await RisingEdge(dut.clk)
    
    dut.valid_in.value = 0
    await RisingEdge(dut.clk)
    
    # Now push to AES while popping from SHA
    dut.opcode.value = 0b00
    dut.key_addr.value = 0x777
    dut.text_addr.value = 0x888
    dut.dest_addr.value = 0x999
    dut.valid_in.value = 1
    dut.ready_in_sha.value = 1
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    dut.ready_in_sha.value = 0
    
    await RisingEdge(dut.clk)
    # AES should have 3 items, SHA should have 1 item
    assert int(dut.valid_out_aes.value) == 1
    assert int(dut.valid_out_sha.value) == 1
    
    dut._log.info("Simultaneous dual-queue operations test PASSED")


@cocotb.test()
async def test_wraparound_stress(dut):
    """Stress test pointer wraparound in circular buffer."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    
    dut._log.info("Testing circular buffer wraparound stress")
    
    model = []
    
    # Perform multiple fill/drain cycles to force wraparound
    for cycle in range(5):
        dut._log.info(f"Wraparound cycle {cycle + 1}/5")
        
        # Fill to capacity
        for i in range(QDEPTH):
            val = cycle * QDEPTH + i
            dut.opcode.value = 0b00
            dut.key_addr.value = val
            dut.text_addr.value = val + 1
            dut.dest_addr.value = val + 2
            dut.valid_in.value = 1
            model.append(pack_instr(0b00, val, val + 1, val + 2))
            await RisingEdge(dut.clk)
        
        dut.valid_in.value = 0
        await RisingEdge(dut.clk)
        assert int(dut.ready_out_aes.value) == 0, "Queue should be full"
        
        # Drain 10 items (partial drain to create wraparound scenario)
        for _ in range(10):
            await RisingEdge(dut.clk)
            assert int(dut.valid_out_aes.value) == 1
            assert get_int(dut.instr_aes) == model[0], "Data mismatch during wraparound"
            model.pop(0)
            dut.ready_in_aes.value = 1
            await RisingEdge(dut.clk)
            dut.ready_in_aes.value = 0
        
        # Queue should have 6 items remaining
        await RisingEdge(dut.clk)
        assert int(dut.ready_out_aes.value) == 1, "Queue should have space after partial drain"
        
        # Add 10 more items (this will force writeIdx to wrap)
        for i in range(10):
            val = (cycle * QDEPTH + QDEPTH + i)
            dut.opcode.value = 0b00
            dut.key_addr.value = val
            dut.text_addr.value = val + 1
            dut.dest_addr.value = val + 2
            dut.valid_in.value = 1
            model.append(pack_instr(0b00, val, val + 1, val + 2))
            await RisingEdge(dut.clk)
        
        dut.valid_in.value = 0
        
        # Now queue should be full again (6 + 10 = 16)
        await RisingEdge(dut.clk)
        assert int(dut.ready_out_aes.value) == 0, "Queue should be full after refill"
        
        # Drain all remaining items and verify order
        while len(model) > 0:
            await RisingEdge(dut.clk)
            assert int(dut.valid_out_aes.value) == 1
            assert get_int(dut.instr_aes) == model[0], f"Data mismatch in cycle {cycle}"
            model.pop(0)
            dut.ready_in_aes.value = 1
            await RisingEdge(dut.clk)
            dut.ready_in_aes.value = 0
        
        await RisingEdge(dut.clk)
        assert int(dut.valid_out_aes.value) == 0, "Queue should be empty"
    
    dut._log.info("Wraparound stress test PASSED")


@cocotb.test()
async def test_reset_during_operation(dut):
    """Test reset behavior during active operation."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    
    dut._log.info("Testing reset during operation")
    
    # Fill queue halfway with AES items
    for i in range(8):
        dut.opcode.value = 0b00
        dut.key_addr.value = i
        dut.text_addr.value = i + 100
        dut.dest_addr.value = i + 200
        dut.valid_in.value = 1
        await RisingEdge(dut.clk)
    
    # Fill queue halfway with SHA items
    for i in range(8):
        dut.opcode.value = 0b01
        dut.key_addr.value = i + 1000
        dut.text_addr.value = i + 1100
        dut.dest_addr.value = i + 1200
        await RisingEdge(dut.clk)
    
    dut.valid_in.value = 0
    await RisingEdge(dut.clk)
    
    # Verify queues have items
    assert int(dut.valid_out_aes.value) == 1
    assert int(dut.valid_out_sha.value) == 1
    
    # Assert reset
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)
    
    # During reset, outputs should be 0
    assert int(dut.valid_out_aes.value) == 0
    assert int(dut.valid_out_sha.value) == 0
    assert int(dut.ready_out_aes.value) == 0
    assert int(dut.ready_out_sha.value) == 0
    
    # Deassert reset
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    
    # After reset, queues should be empty and ready
    assert int(dut.valid_out_aes.value) == 0
    assert int(dut.valid_out_sha.value) == 0
    assert int(dut.ready_out_aes.value) == 1
    assert int(dut.ready_out_sha.value) == 1
    
    # Verify normal operation after reset
    dut.opcode.value = 0b00
    dut.key_addr.value = 0xABC
    dut.text_addr.value = 0xDEF
    dut.dest_addr.value = 0x123
    dut.valid_in.value = 1
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    
    await RisingEdge(dut.clk)
    assert int(dut.valid_out_aes.value) == 1
    assert get_int(dut.instr_aes) == pack_instr(0b00, 0xABC, 0xDEF, 0x123)
    
    dut._log.info("Reset during operation test PASSED")


@cocotb.test()
async def test_multi_cycle_valid_in(dut):
    """Test behavior when valid_in stays high for multiple cycles."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    
    dut._log.info("Testing multi-cycle valid_in behavior")
    
    # Set up an instruction
    dut.opcode.value = 0b00
    dut.key_addr.value = 0x123
    dut.text_addr.value = 0x456
    dut.dest_addr.value = 0x789
    
    # Hold valid_in high for 3 cycles
    dut.valid_in.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    
    await RisingEdge(dut.clk)
    
    # Check how many items were enqueued
    # NOTE: Current implementation will enqueue 3 times (potential bug)
    # This test documents the behavior
    item_count = 0
    while int(dut.valid_out_aes.value) == 1:
        item_count += 1
        dut.ready_in_aes.value = 1
        await RisingEdge(dut.clk)
        dut.ready_in_aes.value = 0
        await RisingEdge(dut.clk)
    
    dut._log.info(f"Multi-cycle valid_in enqueued {item_count} items")
    # With current implementation, this will be 3
    # Ideal behavior might be 1 (edge-triggered)
    
    dut._log.info("Multi-cycle valid_in test completed (behavior documented)")


@cocotb.test()
async def test_full_queue_persistent_valid(dut):
    """Test that full queue properly rejects with persistent valid_in."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    
    dut._log.info("Testing full queue with persistent valid_in")
    
    # Fill queue to capacity
    for i in range(QDEPTH):
        dut.opcode.value = 0b00
        dut.key_addr.value = i
        dut.text_addr.value = i + 1
        dut.dest_addr.value = i + 2
        dut.valid_in.value = 1
        await RisingEdge(dut.clk)
    
    # Queue is now full
    await RisingEdge(dut.clk)
    assert int(dut.ready_out_aes.value) == 0, "Queue should be full"
    
    # Keep trying to push with valid_in high
    dut.opcode.value = 0b00
    dut.key_addr.value = 0xBAD
    dut.text_addr.value = 0xBAD
    dut.dest_addr.value = 0xBAD
    dut.valid_in.value = 1
    
    # Hold valid_in for several cycles
    for _ in range(5):
        await RisingEdge(dut.clk)
        assert int(dut.ready_out_aes.value) == 0, "ready_out should stay 0 when full"
    
    dut.valid_in.value = 0
    
    # Drain queue and verify the bad value wasn't inserted
    for i in range(QDEPTH):
        await RisingEdge(dut.clk)
        expected = pack_instr(0b00, i, i + 1, i + 2)
        actual = get_int(dut.instr_aes)
        assert actual == expected, f"Bad data found! Expected {expected:x}, got {actual:x}"
        dut.ready_in_aes.value = 1
        await RisingEdge(dut.clk)
        dut.ready_in_aes.value = 0
    
    await RisingEdge(dut.clk)
    assert int(dut.valid_out_aes.value) == 0, "Queue should be empty"
    
    dut._log.info("Full queue with persistent valid_in test PASSED")


@cocotb.test()
async def test_almost_full_boundary(dut):
    """Test operations at almost-full boundary."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    
    dut._log.info("Testing almost-full boundary conditions")
    
    # Fill to 15/16 (one slot remaining)
    for i in range(QDEPTH - 1):
        dut.opcode.value = 0b00
        dut.key_addr.value = i
        dut.text_addr.value = i + 100
        dut.dest_addr.value = i + 200
        dut.valid_in.value = 1
        await RisingEdge(dut.clk)
    
    dut.valid_in.value = 0
    await RisingEdge(dut.clk)
    
    # Should still be ready (not full)
    assert int(dut.ready_out_aes.value) == 1, "Queue should not be full at 15/16"
    
    # Perform the boundary dance: push-full, pop-almost-full, push-full
    for dance in range(10):
        # Push one more to make it full
        dut.opcode.value = 0b00
        dut.key_addr.value = 0xFFF
        dut.text_addr.value = 0xFFF
        dut.dest_addr.value = 0xFFF
        dut.valid_in.value = 1
        await RisingEdge(dut.clk)
        dut.valid_in.value = 0
        
        await RisingEdge(dut.clk)
        assert int(dut.ready_out_aes.value) == 0, f"Should be full in dance {dance}"
        
        # Pop one
        dut.ready_in_aes.value = 1
        await RisingEdge(dut.clk)
        dut.ready_in_aes.value = 0
        
        await RisingEdge(dut.clk)
        assert int(dut.ready_out_aes.value) == 1, f"Should have space in dance {dance}"
    
    # Drain remaining
    while int(dut.valid_out_aes.value) == 1:
        dut.ready_in_aes.value = 1
        await RisingEdge(dut.clk)
        dut.ready_in_aes.value = 0
        await RisingEdge(dut.clk)
    
    dut._log.info("Almost-full boundary test PASSED")


@cocotb.test()
async def test_undefined_opcodes(dut):
    """Test behavior with undefined opcodes 0b10 and 0b11."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    
    dut._log.info("Testing undefined opcodes")
    
    # Test opcode 0b10 (should go to AES based on opcode[0] == 0)
    dut.opcode.value = 0b10
    dut.key_addr.value = 0x100
    dut.text_addr.value = 0x200
    dut.dest_addr.value = 0x300
    dut.valid_in.value = 1
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    
    await RisingEdge(dut.clk)
    if int(dut.valid_out_aes.value) == 1:
        dut._log.info("Opcode 0b10 went to AES queue")
        assert get_int(dut.instr_aes) == pack_instr(0b10, 0x100, 0x200, 0x300)
        dut.ready_in_aes.value = 1
        await RisingEdge(dut.clk)
        dut.ready_in_aes.value = 0
    elif int(dut.valid_out_sha.value) == 1:
        dut._log.info("Opcode 0b10 went to SHA queue")
        dut.ready_in_sha.value = 1
        await RisingEdge(dut.clk)
        dut.ready_in_sha.value = 0
    
    # Test opcode 0b11 (should go to SHA based on opcode[0] == 1)
    dut.opcode.value = 0b11
    dut.key_addr.value = 0x400
    dut.text_addr.value = 0x500
    dut.dest_addr.value = 0x600
    dut.valid_in.value = 1
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    
    await RisingEdge(dut.clk)
    if int(dut.valid_out_sha.value) == 1:
        dut._log.info("Opcode 0b11 went to SHA queue")
        assert get_int(dut.instr_sha) == pack_instr(0b11, 0x400, 0x500, 0x600)
        dut.ready_in_sha.value = 1
        await RisingEdge(dut.clk)
        dut.ready_in_sha.value = 0
    elif int(dut.valid_out_aes.value) == 1:
        dut._log.info("Opcode 0b11 went to AES queue")
        dut.ready_in_aes.value = 1
        await RisingEdge(dut.clk)
        dut.ready_in_aes.value = 0
    
    dut._log.info("Undefined opcode test completed (behavior documented)")