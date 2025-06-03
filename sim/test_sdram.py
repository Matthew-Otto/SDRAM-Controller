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

    dut.write.value = 1
    dut.addr.value = 0x22beef
    dut.data_write.value = 0x1337
    await RisingEdge(dut.clk)

    await Timer(time=7.8, units="us")