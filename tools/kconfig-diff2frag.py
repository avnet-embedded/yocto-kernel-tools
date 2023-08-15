#! /usr/bin/env python3
#
## Copyright (C) 2023  Trevor Woerner <twoerner@gmail.com>
## SPDX-License-Identifier: OSLv3
## vim: sw=4 ts=4 sts=4 expandtab

# This tool takes a unified diff (diff -u <before> <after>) of two kconfig
# files and generates a kconfig fragment from the differences.
# It reads the diff on stdin and outputs the fragment on stdout.
#
# Example usage:
#    $ diff -u config-before config-after | ./kconfig-diff2frag.py

import sys

def main():
    for LINE in sys.stdin:
        # if a line starts with '+CONFIG_*'
        # then output the line without the leading '+'
        if LINE.find('+CONFIG_') == 0:
            print(LINE[1:],end='')

        # if a line starts with '+# CONFIG_* is not set'
        # then output the line as: CONFIG_*=n
        if LINE.find('+# CONFIG_') == 0:
            print(LINE.split()[1].strip(),'=n',sep='')

        # ignore any other lines

if __name__ == "__main__":
    main()
