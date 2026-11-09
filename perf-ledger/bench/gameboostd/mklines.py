#!/usr/bin/env python3
"""corpus.argv -> processed cmdline per line, exactly as read_cmdline_fd
produces it (first 4095 bytes, NUL/newline -> space, blanks trimmed)."""
import sys
for l in open(sys.argv[1], 'rb'):
    raw = l.rstrip(b'\n').replace(b'\x1f', b'\0') + b'\0'
    raw = raw[:4095].replace(b'\0', b' ').replace(b'\n', b' ').strip(b' \t')
    sys.stdout.buffer.write(raw + b'\n')
