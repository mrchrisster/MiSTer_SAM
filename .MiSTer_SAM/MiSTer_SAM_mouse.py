#!/usr/bin/env python

import struct
import time
import glob
import sys

packstring = "i"

infile_path = sys.argv[1]
EVENT_SIZE = struct.calcsize(packstring)
while True:
    try:
        file = open(infile_path, "rb")
        event = file.read(EVENT_SIZE)
        (a) = struct.unpack(packstring, event)
        if a != 111 :
           f = open("/tmp/.SAM_Mouse_Activity", "w")
           f.write("Mouse moved")
           f.close()
        time.sleep(0.4)
    except FileNotFoundError:
        print(" Mouse disconnected")
        sys.exit(1)