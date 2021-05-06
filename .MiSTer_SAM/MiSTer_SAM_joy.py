#!/usr/bin/env python

import struct
import time
import glob
import sys

packstring = "iiiiiiiiiiiiiiiiiiii"

infile_path = sys.argv[1]
EVENT_SIZE = struct.calcsize(packstring)
while True:
    try:
        file = open(infile_path, "rb")
        event = file.read(EVENT_SIZE)
        (a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t) = struct.unpack(packstring, event)
        if b != 8454144 or d != 25231360 or f != 42008576 or h != 58785792 or n != 109117440 or p != 125894656:
           f = open("/tmp/.SAM_Joy_Activity", "w")
           f.write("Button pushed")
           f.close()
        time.sleep(0.2)
    except FileNotFoundError:
        print(" Joystick disconnected")
        sys.exit(1)
