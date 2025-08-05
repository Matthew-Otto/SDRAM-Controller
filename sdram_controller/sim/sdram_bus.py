import cocotb
from cocotb_bus.bus import Bus
from cocotb.triggers import RisingEdge, FallingEdge, Timer

cmd_map = {
    0b111 : "CMD_NOP",
    0b110 : "CMD_STOP",
    0b011 : "CMD_ACTIVE",
    0b101 : "CMD_READ",
    0b100 : "CMD_WRITE",
    0b010 : "CMD_PRECHG",
    0b001 : "CMD_AUTOREF",
    0b000 : "CMD_MRS",
}


class SDRAM(Bus):
    _signals = [
        "cs",
        "bank",
        "addr",
        "ras",
        "cas",
        "we",
        "data_in",
        "data_out",
        "drive_data",
    ]

    def __init__(self, entity, name, clock, mem_size = 2**26, **kwargs):
        super().__init__(entity, name, self._signals, **kwargs)
        self.clk = clock
        self.mem = [0] * mem_size
        self.bank_row = [None] * 4

        cocotb.start_soon(self.process_cmd())


    def calculate_cmd(self):
        cmd = 0
        cmd += int(self.ras.value) << 2
        cmd += int(self.cas.value) << 1
        cmd += int(self.we.value)
        return cmd_map[cmd]

    def calculate_address(self):
        addr = 0
        addr += int(self.cs.value) << 25
        addr += int(self.bank.value) << 23
        addr += int(self.bank_row[self.bank.value]) << 10
        addr += int(self.addr.value)
        return addr

    async def process_cmd(self):
        while True:
            await FallingEdge(self.clk)

            cmd = self.calculate_cmd()

            # open row
            if cmd == "CMD_ACTIVE":
                cocotb.log.info(f"opening row {int(self.addr.value):#x} in bank {int(self.bank.value):#x}")
                self.bank_row[self.bank.value] = self.addr.value
                continue

            if cmd == "CMD_READ":
                addr = self.calculate_address()
                self.data_in.value = self.mem[addr]
                cocotb.log.info(f"Read: {addr:#x} => {self.mem[addr]:#x}")

            if cmd == "CMD_WRITE":
                addr = self.calculate_address()
                data = int(self.data_out.value)
                self.mem[addr] = data
                cocotb.log.info(f"Write: {addr:#x} <= {data:#x}")

            

