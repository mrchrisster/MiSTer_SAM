![alt text](https://i.ibb.co/DzjQDtH/Screenshot-22.png)



# MiSTer Attract Mode
**Enjoy the wonderful pixel art and sounds from the games in your MiSTer library - automatically!**

## Usage
Attract Mode is a script which starts a random game on the MiSTer FPGA. The script is highly customizable through the included ini file (details below). Games can be played in Attract Mode, but the next game loads automatically after 2 minutes *unless you wiggle the mouse!* If you don't have a mouse connected to your MiSTer you'll need to ***cold reboot*** your MiSTer from the OSD (F12) menu, or use the power button.

## Installation
If your MiSTer is connected to the internet, the installation is straight forward:  
- Copy `Attract_Mode.sh` and `Attract_Mode.ini` to `/media/fat/Scripts` Directory, *that's it.*  
You will need no other files from here to get everything working.  
  

## Offline Installation  
If your MiSTer is not connected to the internet, you can install the two additional tools needed for correct operation of Attract Mode.  
Go to the subfolder `Tools` on this Github page and download `mbc` and `partun`  
Connect to your MiSTer's SD card and drop the two files into the `/media/fat/linux` directory.  
Now open Attract_Mode.sh and find the following lines
  
```
mbcpath=/tmp/mbc
partunpath=/tmp/partun
```
  
Change it to:  
  
```
mbcpath=/media/fat/linux/mbc
partunpath=/media/fat/linux/partun
```
  

## Supported Systems
Currently supported MiSTer cores:
* Arcade
* Game Boy Advance
* Genesis
* MegaCD AKA SegaCD
* NeoGeo
* NES
* SNES
* TurboGrafx-16 AKA PC Engine
* TurboGrafx-16 CD AKA PC Engine CD

## MiSTer Configuration
The [Update-all](https://github.com/theypsilon/Update_All_MiSTer) script works great for putting system files in the right places.

## Attract Mode Configuration
### Optional features
Included in `/Optional/` are several additional scripts. These require `Attract_Mode.sh` to run.

Each Attract_Mode_*system*.sh script cycles games from just that one system - not all of them.

Also included is `Lucky_Mode.sh` and corresponding system-specific Lucky_Mode_*system*.sh scripts. Lucky mode picks a random game and loads it - no timer to worry about! This is a great way to explore and play your collection.

To use these options just copy the optional script(s) you want into the same location as Attract_mode.sh - by default `/media/fat/Scripts/`.

### Arcade Horizontal or Vertical Only
Change the "orientation" setting in the `Attract_Mode.ini` file to choose from only horizontal or vertical arcade games.

### Exclude
Want to exclude certain arcade games? Just add them to `mraexclude` in the `Attract_Mode.ini` file.

## How it works
MiSTer arcade cores are launched via a MiSTer command. For console games there is no official way to load individual games programmatically. Attract Mode automates the process by sending simulated button presses to the MiSTer. This is done with a modified version of [pocomane's MiSTer Batch Control](https://github.com/pocomane/MiSTer_Batch_Control). 
  
If you would like to know what game is currently playing, you can either run the script through SSH or check the file `/tmp/Attract_Game.txt`. Some folks even use this with OBS to automatically change the game name in their Twitch stream!  
  
## Troubleshooting
**- Core is loaded but just hangs on the menu**  
Sometimes this happens (even on our test setups) and it could be for a variety of reasons. Make sure you are using the recommended folder structure, such as /media/fat/Games/SNES/. The script supports zipped Everdrive packs or unzipped folders. For MegaCD and Turbografx16 CD games must be in CHD format. We noticed that some MegaCD games that the script is trying to load also won't work when loaded through the MiSTer interface.  
  
If you are still having trouble it could simply be that the rom failed to load, it seems to happen every now and then.
  
  
**- Sometimes NeoGeo doesn't load a rom and hangs on the menu**   
Still investigating why this is happening.
  
**- USB Storage**  
/media/usb is not well tested. NTFS formatted drives may experience issues because NTFS is case-sensitive on MiSTer.

**- Turbografx16 CD just showing Run button but not starting into the game**  
Make sure you use a bios that auto launches the game  

**- Can I use a CIFS mount for my games?**  
CIFS is supported.
Here is an example of some values in `cifs_mount.sh` that should get you started:  
```
SERVER="192.168.1.10"  
SHARE="Games/Mister/Games"  
LOCAL_DIR="*"  
BASE_PATH="/media/fat/Games" 
```
