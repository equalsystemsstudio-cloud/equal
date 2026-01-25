
import os

file_path = r'c:\equal\lib\screens\create_post_screen.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Line numbers are 1-based in the tool output, so 0-based index is line_num - 1.
# We want to remove from line 1785 to 3271 (inclusive of the gap before 3272).
# Start index: 1785 - 1 = 1784
# End index: 3272 - 1 = 3271 (start of _selectVideoFromFiles)

# Verify start
if 'Future<void> _publishPostOld() async {' not in lines[1784]:
    print(f"Error: Line 1785 content mismatch: {lines[1784]}")
    # Search for it nearby
    for i in range(1780, 1800):
        if 'Future<void> _publishPostOld() async {' in lines[i]:
            print(f"Found at {i+1}")
            start_idx = i
            break
else:
    start_idx = 1784

# Verify end
if 'Future<void> _selectVideoFromFiles() async {' not in lines[3271]:
    print(f"Error: Line 3272 content mismatch: {lines[3271]}")
    # Search for it nearby
    for i in range(3260, 3280):
        if 'Future<void> _selectVideoFromFiles() async {' in lines[i]:
            print(f"Found at {i+1}")
            end_idx = i
            break
else:
    end_idx = 3271

if 'start_idx' in locals() and 'end_idx' in locals():
    new_lines = lines[:start_idx] + lines[end_idx:]
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
    print("File updated successfully.")
else:
    print("Could not locate start or end lines exactly. Aborting.")
