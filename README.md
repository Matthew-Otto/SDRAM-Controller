# SDRAM-Controller

A SystemVerilog module to control two Alliance Memory AS4C32M16SB modules connected to a Terasic DE10-nano (Cyclone-V) FPGA board via GPIO.
\
(this is (one of) the SDRAM module used with the MiSTer FPGA project)

This controller currently targets 50MHz.

## Features
This controller currently supports:
* Continuous (1 per cycle) single word writes
* 8 word burst (BL8) reads
* Full 128 MB support

## Viewing example waveforms
Example IO can be viewed by simulating the supplied testbench.
The testbench is written using [cocotb](https://github.com/cocotb/cocotb) for [Verilator](https://github.com/verilator/verilator). If you have these applications installed you can run the simulation by executing `make` in the `sim/` directory. 
\
Waveforms are written to `sim/dump.fst`. If you have [Surfer](https://gitlab.com/surfer-project/surfer) installed, you can view the waves by running `make waves` in the `sim/` directory.

Note: the SDRAM module is not simulated. The waveforms will only contain the output from the memory controller.