#!/usr/bin/env python
import struct
import time
import glob
import sys
import os
import errno

FIFO = sys.argv[2]

try:
    os.mkfifo(FIFO)
except OSError as oe:
    if oe.errno != errno.EEXIST:
        raise

packstring = "iiiiiiiiiiiiiiiiiiii"

infile_path = sys.argv[1]
EVENT_SIZE = struct.calcsize(packstring)
while True:
    try:
        file = open(infile_path, "rb")
        event = file.read(EVENT_SIZE)
        (a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t) = struct.unpack(packstring, event)
        if b != 8454144 or d != 25231360 or f != 42008576 or h != 58785792 or n != 109117440 or p != 125894656:
            f = open(FIFO, "w")
            f.write("Button pushed on Joystick")
            f.write("\n")
            f.close()
        time.sleep(0.2)
    except FileNotFoundError:
        print(" Joystick disconnected")
        sys.exit(1)
