import random

import cocotb
from cocotb.triggers import Timer, ReadOnly, ReadWrite, ClockCycles, RisingEdge, FallingEdge
from cocotb.clock import Clock

random.seed(2)

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

@cocotb.test()
async def test1(dut):
    # start system clock
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())

    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    addr = addr_gen()

    for _ in range(1<<16):
        if 1:#random.randint(0,1):
            #dut.addr.value = random.getrandbits(26)
            dut.addr.value = next(addr)
            if random.randint(0,1):
                dut.write.value = 1
                dut.data_write.value = random.getrandbits(16)
            else:
                dut.read.value = 1
        await RisingEdge(dut.clk)
        while not dut.cmd_ready.value:
            await RisingEdge(dut.clk)
        
        dut.write.value = 0
        dut.read.value = 0
