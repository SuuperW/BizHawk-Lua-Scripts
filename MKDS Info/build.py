import sys
import os

def process_file(input_file, output_file):
	with open(input_file, 'r') as infile:
		lines = infile.readlines()

	new_lines = []
	for line in lines:
		if line.strip().startswith("dofile"):
			# Extract the file name
			start_idx = line.find('"') + 1
			end_idx = line.rfind('"')
			if start_idx == 0 or end_idx == -1:
				raise ValueError(f"Invalid dofile syntax in line: {line}")
			file_name = line[start_idx:end_idx]

			# Read the contents of the file
			if not os.path.isfile(file_name):
				raise FileNotFoundError(f"File not found: {file_name}")
			new_lines.append("local function _()\n")
			with open(file_name, 'r') as dofile:
				file_lines = dofile.readlines()
				for dfline in file_lines:
					if dfline[:4] != "--- ":
						new_lines.append(dfline)
			if new_lines[-1][-1] != "\n":
				new_lines[-1] = new_lines[-1] + "\n"
			new_lines.append("end\n")
			new_lines.append("_()\n")
		else:
			new_lines.append(line)

	with open(output_file, 'w') as outfile:
		outfile.writelines(new_lines)

if __name__ == "__main__":
	input_file = "MKDS Info Main.lua"
	output_file = "MKDS Info.lua"
	if len(sys.argv) == 3:
		input_file = sys.argv[1]
		output_file = sys.argv[2]
	else:
		print("Using default file names.")

	process_file(input_file, output_file)
