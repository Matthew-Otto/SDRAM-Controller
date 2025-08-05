import os
import random
import sys
import time
from queue import Queue

import cocotb
from cocotb.triggers import Timer, ReadOnly, ReadWrite, ClockCycles, RisingEdge, FallingEdge
from cocotb.clock import Clock

utils_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../cocotbext-dram'))
sys.path.insert(0, utils_dir)
from sdram_bus import SDRAM

ref_mem = []

def addr_gen():
    lfsr = 1
    while True:
        feedback = lfsr & 0x1
        for t in [1, 5, 25]:
            feedback ^= (lfsr >> t) & 0x1
        lfsr = ((lfsr << 1) & 0x3FFFFFF) | feedback
        if lfsr == 1:
            break
        yield lfsr


@cocotb.coroutine
async def reset(dut):
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    print("DUT reset")


@cocotb.coroutine
async def get_read_data(dut, read_q):
    while True:
        await RisingEdge(dut.clk)
        if dut.data_read_val.value:
            ref = read_q.get()
            print(f"read {hex(int(dut.data_read.value))}")
            assert ref == int(dut.data_read.value), "read invalid data from SDRAM"



#@cocotb.test()
async def test(dut):
    seed = 12345 #int(time.time())
    random.seed(seed)
    print(f"using seed: {seed}")

    # start system clock
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())
    sdram = SDRAM(dut, "sdram", dut.clk)
    read_q = Queue()
    await reset(dut)


    # write random data to virtual memory
    sdram.mem = [random.getrandbits(16) for _ in range(2**26)]

    ref_mem = sdram.mem

    addr = addr_gen()

    for _ in range(1<<27): # every address twice
        if 1:#random.randint(0,1):
            #dut.addr.value = random.getrandbits(26)
            dut.addr.value = next(addr)
            if random.randint(0,1):
                dut.write.value = 1
                dut.data_write.value = random.getrandbits(16)
                ref_mem[int(dut.addr.value)] = int(dut.data_write.value)
                print(f"writing {hex(int(dut.data_write.value))} to addr {hex(int(dut.addr.value))}")
            else:
                dut.read.value = 1
                read_q.put(dut.addr.value)
                print(f"reading from addr {hex(int(dut.addr.value))}")
        await RisingEdge(dut.clk)
        while not dut.cmd_ready.value:
            await RisingEdge(dut.clk)
        
        dut.write.value = 0
        dut.read.value = 0


@cocotb.test()
async def test_byte_addr(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())
    sdram = SDRAM(dut, "sdram", dut.clk)
    await reset(dut)

    read_q = Queue()

    dut.write.value = 1
    dut.wr_strb.value = 0
    dut.addr.value = 0x0
    dut.data_write.value = 0xffff
    read_q.put(0xffff)
    while not dut.cmd_ready.value:
        await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.wr_strb.value = 0b01
    dut.addr.value = 0x1
    read_q.put(0xff00)
    await FallingEdge(dut.clk)
    while not dut.cmd_ready.value:
        await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.wr_strb.value = 0b10
    dut.addr.value = 0x2
    read_q.put(0x00ff)
    await FallingEdge(dut.clk)
    while not dut.cmd_ready.value:
        await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.wr_strb.value = 0b11
    dut.addr.value = 0x3
    read_q.put(0x0000)
    await FallingEdge(dut.clk)
    while not dut.cmd_ready.value:
        await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    dut.wr_strb.value = 0b00
    dut.addr.value = 0x4
    read_q.put(0xffff)
    await FallingEdge(dut.clk)
    while not dut.cmd_ready.value:
        await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.write.value = 0

    cocotb.start_soon(get_read_data(dut, read_q))
    await ClockCycles(dut.clk,5)
    print(sdram.mem[0:10])

    
    dut.read.value = 1
    dut.addr.value = 0x0
    await FallingEdge(dut.clk)
    while not dut.cmd_ready.value:
        await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.addr.value = 0x1
    await FallingEdge(dut.clk)
    while not dut.cmd_ready.value:
        await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.addr.value = 0x2
    await FallingEdge(dut.clk)
    while not dut.cmd_ready.value:
        await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.addr.value = 0x3
    await FallingEdge(dut.clk)
    while not dut.cmd_ready.value:
        await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.addr.value = 0x4
    await FallingEdge(dut.clk)
    while not dut.cmd_ready.value:
        await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.read.value = 0

    await ClockCycles(dut.clk, 20)


