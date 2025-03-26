# Yeah I know this isn't Lua.
# This script is meant to assist debugging NDS games run in BizHawk.
# It will parse a trace log file to find reads/writes.

# This script will assume that the log file is well-formed and has not been edited or corrupted in any way. If the file isn't correct you may get strange errors or behavior.
# Note that the trace logs do not contain everything, e.g. comparison and carry flags. So conditional instructions are assumed to always be executed.

import sys

names_of_arm_registers = [
	'r0', 'r1', 'r2', 'r3',
	'r4', 'r5', 'r6', 'r7',
	'r8', 'r9', 'r10', 'r11',
	'r12', 'sp', 'lr', 'pc',
]

def index(string: str, search_for: str, start = None):
	try:
		return string.index(search_for, start)
	except:
		return -1
	
def get_operands(string: str):
	parts = string.split(',')
	for i in range(len(parts)):
		parts[i] = parts[i].strip()
	return parts

def parse_asm_integer_literal(string: str):
	if string[0] != '#':
		raise 'Invalid asm integer literal: ' + string
	offset_sign = 1
	if string[1] == '-':
		offset_sign = -1
	hex_begin = index(string, '0x')
	if hex_begin != -1:
		return int(string[hex_begin+2:], 16) * offset_sign
	else:
		dec_begin = 1
		if string[1] == '-' or string[1] == '+':
			dec_begin = 2
		return int(string[dec_begin:], 10)
	
def value_of_register(line: str, register_name: str):
	register_index = line.lower().index(register_name.lower() + ':')
	indx = register_index + 1 + len(register_name)
	return int(line[indx:indx+8], 16)

def count_in_range(register_range: str):
	if '-' in register_range:
		names = register_range.split('-')
		start = names_of_arm_registers.index(names[0].lower())
		end = names_of_arm_registers.index(names[0].lower())
		return end - start + 1
	else:
		return 1
def count_registers(string: str):
	#{r4-r9,lr}
	begin = string.index('{') + 1
	end = string.index('}')
	register_list = string[begin:end]
	register_groups = register_list.split(',')
	total = 0
	for group in register_groups:
		total += count_in_range(group)
	return total

class LogEntry:
	input_string: str
	inst_address: int
	inst_hex: str
	inst_disasm: str
	is_read: bool
	is_write: bool
	access_addresses: list[int]
	mask: int
	registers: list[int]

	def __init__(self, log_string: str):
		self.input_string = log_string
		self.inst_address = int(log_string[0:8], 16)
		self.inst_hex = int(log_string[11:11+8], 16)
		self.inst_disasm = log_string[20:56]
		registers_begin = log_string.index('r', 56)
		registers_string = log_string[registers_begin:]
		colon_index = index(registers_string, ':')
		self.registers = []
		while colon_index != -1:
			name = registers_string[:colon_index]
			value = int(registers_string[colon_index+1:colon_index+9], 16)
			self.registers.append(value)
			colon_index = index(registers_string, ':', colon_index+1)
			# We ignore the name here.
		# I'm not sure if this is reliable
		inst3 = self.inst_disasm[0:3]
		if inst3 == 'ldr' or inst3 == 'str':
			self.is_read = inst3 == 'ldr'
			self.is_write = inst3 == 'str'
			register_index = self.inst_disasm.index('[') + 1
			
			# Offsets can come in several forms
			# Simple: [r0, #+0x0]
			# Or: [r0, #-0x4]
			# Or even no offset: [sp], #+0x4
			# But also can be: [r1, r0, lsl #2]
			end_index = self.inst_disasm.index(']', register_index)
			ops_string = self.inst_disasm[register_index:end_index]
			operands = get_operands(ops_string)
			offset = None
			name = operands[0].lower()
			value = value_of_register(log_string, name)
			if len(operands) == 1:
				offset = 0
			elif operands[1][0] == '#':
				offset = parse_asm_integer_literal(operands[1])
			else:
				# The operand must be a register?
				second_name = operands[1].lower()
				# It can be negative!
				isNegative = second_name[0] == '-'
				if isNegative:
					second_name = second_name[1:]
				second_value = value_of_register(log_string, second_name)
				if isNegative:
					second_value = -second_value
				if len(operands) == 2:
					offset = second_value
				elif operands[2].startswith('lsl') or operands[2].startswith('asl'):
					shift_begin = operands[2].index('#')
					shift = parse_asm_integer_literal(operands[2][shift_begin:])
					offset = second_value << shift
				elif operands[2].startswith('lsr') or operands[2].startswith('asr'):
					shift_begin = operands[2].index('#')
					shift = parse_asm_integer_literal(operands[2][shift_begin:])
					offset = second_value >> shift
				else:
					raise Exception('Unknown memory access pattern: ' + self.inst_disasm)

			base_address = value + offset
			mask = 0xffffffff & ~3
			if self.inst_disasm[3] == 'h':
				mask = mask | 2
			elif self.inst_disasm[3] == 'b':
				mask = mask | 3
			self.access_addresses = [base_address & mask] # Is this accurate?
			self.mask = mask
		# And the multiple-register variants such as stmia r3, {r0-r2} and stmdb sp!, {r4-r9,lr}
		elif inst3 == 'stm' or inst3 == 'ldm':
			self.is_read = inst3[0] == 'l'
			self.is_write = inst3[0] == 's'
			space_index = self.inst_disasm.index(' ')
			comma_index = self.inst_disasm.index(',')
			address_register = self.inst_disasm[space_index+1:comma_index]
			if address_register[-1] == '!':
				address_register = address_register[:-1]
			self.mask = 0xffffffff & ~3
			base_address = value_of_register(log_string, address_register) & self.mask
			add = None
			if self.inst_disasm[3] == 'i':
				add = 4
			elif self.inst_disasm[3] == 'd':
				add = 4
			else:
				raise Exception('Unknown opcode')
			if self.inst_disasm[4] == 'b':
				base_address += add
			
			count = count_registers(self.inst_disasm)
			addresses = []
			for _ in range(count):
				addresses.append(base_address)
				base_address += add
			self.access_addresses = addresses
		else:
			self.access_addresses = []
			self.mask = 0

	def accesses(self, address):
		address = address & self.mask
		for a in self.access_addresses:
			if a == address:
				return True
		return False

class TraceLog:
	log_entrys: list[LogEntry] = []

	def __init__(self, file_name):
		lines = None
		with open(file_name, 'r') as fs:
			lines = fs.readlines()
		for line in lines:
			if not line.startswith('ARM') and len(line) > 2:
				self.log_entrys.append(LogEntry(line.strip()))

	def find_access(self, address):
		accesses = []
		for i in range(len(self.log_entrys)):
			log = self.log_entrys[i]
			if log.accesses(address):
				accesses.append(i)
		return accesses
	def find_write(self, address):
		writes = []
		for i in range(len(self.log_entrys)):
			log = self.log_entrys[i]
			if log.accesses(address) and log.is_write:
				writes.append(i)
		return writes
	def find_read(self, address):
		reads = []
		for i in range(len(self.log_entrys)):
			log = self.log_entrys[i]
			if log.accesses(address) and log.is_read:
				reads.append(i)
		return reads

if __name__ == '__main__':
	file_name = sys.argv[1]
	access = int(sys.argv[2], 16)
	log = TraceLog(file_name)
	
	lines_found = log.find_read(access)
	print(lines_found)
	for line_number in lines_found:
		print(log.log_entrys[line_number].input_string)
