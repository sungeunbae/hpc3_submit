import argparse
import os

def split_file_by_lines(input_file, lines_per_file=30):
    with open(input_file, 'r') as infile:
        file_count = 1
        lines = []

        for line_number, line in enumerate(infile, start=1):
            lines.append(line)
            if line_number % lines_per_file == 0:
                output_filename = f"{os.path.splitext(input_file)[0]}_part{file_count}.txt"
                with open(output_filename, 'w') as outfile:
                    outfile.writelines(lines)
                lines = []
                file_count += 1

        # Write remaining lines if any
        if lines:
            output_filename = f"{os.path.splitext(input_file)[0]}_part{file_count}.txt"
            with open(output_filename, 'w') as outfile:
                outfile.writelines(lines)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Split a text file into smaller files with a fixed number of lines.")
    parser.add_argument("input_file", help="Path to the input text file")
    parser.add_argument("-n", "--lines", type=int, default=30, help="Number of lines per output file (default: 30)")
    args = parser.parse_args()

    split_file_by_lines(args.input_file, args.lines)

