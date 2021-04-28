#!/usr/bin/env python

import struct
import time
import glob
import sys

packstring = "iiiiiiiiiiiiiiii"

infile_path = sys.argv[1]
EVENT_SIZE = struct.calcsize(packstring)
while True:
    try:
        file = open(infile_path, "rb")
        event = file.read(EVENT_SIZE)
        (a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p) = struct.unpack(packstring, event)
        b = b %10
        d = d %10
        f = f %10
        h = h %10
        j = j %10
        l = l %10
        n = n %10
        p = p %10
        if b != 4 or d != 0 or f != 6 or h != 2 or j != 8 or l != 4 or n != 0 or p != 6:
           f = open("/tmp/.SAM_Joy_Activity", "w")
           f.write("Button pushed")
           f.close()
        time.sleep(0.2)
    except FileNotFoundError:
        print("Joystick disconnected")
        sys.exit(1)
