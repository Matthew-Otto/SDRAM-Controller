PROJECT_TITLE = SDRAM_test
QUARTUS_DIR = ./quartus/
SIM_DIR = ./sim/
RTL_DIR = ./rtl/
PROJECT = $(QUARTUS_DIR)$(PROJECT_TITLE)

# utilities
RM     = rm -rf
MKDIR  = @mkdir -p $(@D) #creates folders if not present
#QUARTUS_PATH = 
SYNTH  = quartus_map
P&R    = quartus_fit
ASM    = quartus_asm
TIMING = quartus_sta
PROG   = quartus_pgm

# build files
SOF = $(PROJECT).sof
CDF = $(PROJECT).cdf

# source files
VERILOG_SOURCES = $(QUARTUS_DIR)SDRAM_test.sv
VERILOG_SOURCES += $(shell find ./rtl -name "*.sv")


## DEPS
# make (duh)
# quartus (prime lite or prime pro)
# verilator
# cocotb
# python
# ...?



#############
### BUILD ###
#############
all: $(SOF)

program: $(SOF)
	$(PROG) $(CDF)

timing: $(SOF)
	$(TIMING) $(PROJECT) -c $(PROJECT)

$(SOF): $(VERILOG_SOURCES)
	$(SYNTH) --read_settings_files=on --write_settings_files=off $(PROJECT) -c $(PROJECT) --optimize=speed
	$(P&R) --read_settings_files=on --write_settings_files=off $(PROJECT) -c $(PROJECT_TITLE)
	$(ASM) --read_settings_files=on --write_settings_files=off $(PROJECT) -c $(PROJECT)

clean:
	$(RM) $(SOF)
	cd $(QUARTUS_DIR) && $(RM) *.sof *.pof *.srf *.cdl *.vcs *.rpt *.log
	$(RM) *.sof *.pof *.srf *.cdl *.vcs *.rpt *.log

##################
### SIMULATION ###
##################
.PHONY: sim waves

sim:
	$(MAKE) -C sim -f Makefile

waves:
	$(MAKE) -C sim -f Makefile waves