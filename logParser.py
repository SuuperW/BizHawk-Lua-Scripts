# Yeah I know this isn't Lua.
# This script is meant to assist debugging NDS games run in BizHawk.
# It will parse a trace log file to find reads/writes.

# This script will assume that the log file is well-formed and has not been edited or corrupted in any way. If the file isn't correct you may get strange errors or behavior.
# Note that the trace logs do not contain everything, e.g. comparison and carry flags. So conditional instructions are assumed to always be executed.

def dprint(s):
	if False:
		print(s)

import sys

names_of_arm_registers = [
	'r0', 'r1', 'r2', 'r3',
	'r4', 'r5', 'r6', 'r7',
	'r8', 'r9', 'r10', 'r11',
	'r12', 'sp', 'lr', 'pc',
]

halfword_instructions = [
	'ldrh', 'ldrexh', 'ldrht', 'ldrsh',
	'ldrsht', 'strh', 'strexh', 'strht',
	'tbh',
]

byte_instructions = [
	'ldrb', 'ldrexb', 'ldrbt', 'ldrsb',
	'ldrsbt', 'strb', 'strexb', 'strbt',
	'swpb', 'tbb',
]

conditional_suffixes = [
	'eq', 'ne', 'cs', 'cc',
	'mi', 'pl', 'vs', 'vc',
	'hi', 'ls', 'ge', 'lt',
	'gt', 'le'
]

def remove_condition(instruction: str):
	if len(instruction) < 3:
		return instruction
	suffix = instruction[-2:]
	if suffix in conditional_suffixes:
		return instruction[:-2]
	else:
		return instruction

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
		raise Exception('Invalid asm integer literal: ' + string)
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
	inst_hex: int
	inst_disasm: str
	inst_operation: str
	inst_operands: str
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
		op_end = self.inst_disasm.index(' ')
		self.inst_operation = self.inst_disasm[:op_end]
		self.inst_operands = self.inst_disasm[op_end + 1:].strip()
		self.inst_disasm = self.inst_disasm.strip()

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
			if remove_condition(self.inst_operation) in halfword_instructions:
				mask = mask | 2
			elif remove_condition(self.inst_operation) in byte_instructions:
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

	def get_register_value(self, register):
		return value_of_register(self.input_string, register)

	def accesses(self, address):
		address = address & self.mask
		for a in self.access_addresses:
			if a == address:
				return True
		return False

	def is_exception_return(self):
		return self.inst_disasm.startswith('subs pc, lr') \
			or self.inst_disasm == 'movs pc, lr'

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
	
	def did_jump(self, entry_id):
		if entry_id == len(self.log_entrys) - 1:
			return False
		addr1 = self.log_entrys[entry_id].inst_address
		addr2 = self.log_entrys[entry_id + 1].inst_address
		diff = addr2 - addr1
		return diff != 2 and diff != 4

	def _find_return(self, entry_id) -> None | int:
		"""returns the index after returning from the current function"""
		# This will fail if:
		# 1) Thumb. Return will be a bx register preceeded by a pop to that register, or a pop directly to pc.
		# 2) Various unexpected jump/return strategies?

		started_in_exception = self.log_entrys[entry_id].inst_address >> 16 == 0xffff

		# Find next unmatched bx[cond] lr
		current_index = entry_id
		inner_calls = 0
		while inner_calls >= 0:
			if current_index == len(self.log_entrys):
				dprint("found end of log")
				return None
			if self.log_entrys[current_index].inst_address >> 16 == 0xffff:
				# interrupt (Are interrupt handlers always at 0xffffxxxx or is that just MKDS?)
				# Values of LR based on exception type and processor mode: pages 1171-1172
				# Instructions that return from address: page 1195 (subs pc, lr [const] or movs pc, lr)

				# 1) Entering this logic needs to validate that the prior instruction was not a branch to exception handling code. (Is branch, and is value of lr something else?)
				# 2) Possibly also skip this logic if prior instruction was also exception? Idk.
				# 3) We need to look for the exception return.
				# 4) How can we detect exceptions/interrupts inside exception code? We might just not, since this should be rare.

				# Find exception return (for simplicity, we assume there will not be an exception within an exception)
				# In order to detect exception within exception, we'd need to inspect sites that branch to exception handling code. These are expected to not be branch instructions, but they might be.
				while not self.log_entrys[current_index].is_exception_return():
					current_index += 1
					if current_index == len(self.log_entrys):
						return None
				if started_in_exception:
					return current_index + 1

			# Is this a bx lr or bl, and if so validate it was taken.
			entry = self.log_entrys[current_index]
			operation = remove_condition(entry.inst_operation)
			if operation == 'bx' and entry.inst_operands == 'lr':
				if self.did_jump(current_index):
					inner_calls -= 1
					dprint(f"returned at {current_index}, {entry.inst_address:x}")
				else:
					dprint(f"did not do return at {current_index}, {entry.inst_address:x}")
			elif operation == 'bl' or operation == 'blx':
				if self.did_jump(current_index):
					inner_calls += 1
					dprint(f"called at {current_index}, {entry.inst_address:x}")
				else:
					dprint(f"did not do call at {current_index}, {entry.inst_address:x}")
			current_index += 1
		return current_index

	def _find_call(self, entry_id) -> None | int:
		"""returns the index which called the current function"""
		raise Exception('This function does not work when exceptions/interrupts are present.')
		# This will fail if:
		# 1) Thumb. Return will be a bx register preceeded by a pop to that register, or a pop directly to pc.
		# 2) Various unexpected jump/return strategies?

		started_in_exception = self.log_entrys[entry_id].inst_address >> 16 == 0xffff

		# Find next unmatched bl
		current_index = entry_id
		inner_calls = 0
		while inner_calls <= 0:
			current_index -= 1
			if current_index < 0:
				dprint("found start of log")
				return None
			if self.log_entrys[current_index].inst_address >> 16 == 0xffff:
				# Exceptions.... uhg, this is all wrong for finding calls! I probably should be writing this as a Ghidra script.
				# Find exception return (for simplicity, we assume there will not be an exception within an exception)
				# In order to detect exception within exception, we'd need to inspect sites that branch to exception handling code. These are expected to not be branch instructions, but they might be.
				while not self.log_entrys[current_index].is_exception_return():
					current_index += 1
					if current_index == len(self.log_entrys):
						return None
				if started_in_exception:
					return current_index + 1

			# Is this a bx lr or bl, and if so validate it was taken.
			entry = self.log_entrys[current_index]
			operation = remove_condition(entry.inst_operation)
			if operation == 'bx' and entry.inst_operands == 'lr':
				if self.did_jump(current_index):
					inner_calls -= 1
					dprint(f"returned at {current_index}, {entry.inst_address:x}")
				else:
					dprint(f"did not do return at {current_index}, {entry.inst_address:x}")
			elif operation == 'bl' or operation == 'blx':
				if self.did_jump(current_index):
					inner_calls += 1
					dprint(f"called at {current_index}, {entry.inst_address:x}")
				else:
					dprint(f"did not do call at {current_index}, {entry.inst_address:x}")
		return current_index

	def trace(self, entry_id, id2 = None):
		#entry_id and id2 are expected to be in the same function call, at the same level in the stack trace
		assert(id2 == None or self.log_entrys[entry_id].get_register_value('sp') == self.log_entrys[id2].get_register_value('sp'))
		
		# Find where it returns to (next instr, or get the lr value)
		ret_index = self._find_return(id2 or entry_id)
		if ret_index == None:
			return None
		ret_addr = self.log_entrys[ret_index].inst_address
		# Go backwards to find the most recent instruction at -4
		print(f"looking for {ret_addr - 4:x}")
		current_index = entry_id - 1
		while self.log_entrys[current_index].inst_address != ret_addr - 4:
			current_index -= 1
			if current_index == -1:
				print("found beginning of log")
				return None
		# trace again
		prior = self.trace(current_index)
		if prior == None:
			return [current_index]
		else:
			return prior + [current_index]

if __name__ == '__main__':
	file_name = sys.argv[1]
	log = TraceLog(file_name)

	kind = sys.argv[2]
	if kind == 'trace':
		idx = int(sys.argv[3], 10)
		lines_found = log.trace(idx)
		if lines_found == None:
			print("No return address found.")
		else:
			for line_number in lines_found:
				print(f'{line_number}: {log.log_entrys[line_number].inst_address:x}')
	elif kind == 'write':
		address = int(sys.argv[3], 16)
		lines_found = log.find_write(address)
		print(lines_found)
		for line_number in lines_found:
			print(log.log_entrys[line_number].input_string)
	elif kind == 'read':
		address = int(sys.argv[3], 16)
		lines_found = log.find_read(address)
		print(lines_found)
		for line_number in lines_found:
			print(log.log_entrys[line_number].input_string)
	else:
		# access
		address = int(sys.argv[2], 16)
		lines_found = log.find_access(address)
		print(lines_found)
		for line_number in lines_found:
			print(log.log_entrys[line_number].input_string)
