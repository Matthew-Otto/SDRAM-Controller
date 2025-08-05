SIM ?= verilator
TOPLEVEL_LANG = verilog

DUT ?= sdram
# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = $(DUT)
# MODULE is the basename of the Python test file
MODULE = test_$(DUT)
VERILOG_SOURCES += $(shell find ../rtl -name "*.sv")


# warnings
COMPILE_ARGS += -Wno-SELRANGE -Wno-WIDTH
# waveforms
EXTRA_ARGS += --trace --trace-fst --trace-threads 2 --trace-structs
EXTRA_ARGS += --threads 6

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: sdram waves

sdram: export COMPILE_ARGS := $(COMPILE_ARGS) -GFREQ=50000000
sdram:
	$(MAKE) -j10

axi:
	$(MAKE) DUT=sdram_axi_gpio -j10

waves:
	@test -f dump.fst || (echo "Error: dump.fst not found. Simulate a target first." && exit 1)
	surfer -s sdram_axi_gpio.surf.ron dump.fst

clean::
	rm -rf __pycache__
	rm -f results.xml
