import random

import cocotb
from cocotb.triggers import Timer, ReadOnly, ReadWrite, ClockCycles, RisingEdge, FallingEdge
from cocotb.clock import Clock

random.seed(2)

@cocotb.test()
async def test1(dut):
    # start system clock
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())

    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    for _ in range(10000):
        if random.randint(0,1):
            dut.addr.value = random.getrandbits(25)
            if random.randint(0,1):
                dut.write.value = 1
                dut.data_write.value = random.getrandbits(16)
            else:
                dut.read.value = 1
        await FallingEdge(dut.clk)
        while not dut.cmd_ready.value:
            await FallingEdge(dut.clk)
        
        dut.write.value = 0
        dut.read.value = 0
