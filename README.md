![alt text](https://i.ibb.co/DzjQDtH/Screenshot-22.png)


# MiSTer Super Attract Mode (SAM)
**MiSTer SAM puts all your games on display to enjoy whenever your MiSTer is idle**

## About
Like a screen saver, MiSTer SAM comes on when your MiSTer is idle. That's when SAM will launch a random game from your library. After a short time SAM starts another. And another. If you like a game that's currently playing, just pick up your controller and push a button, press a key, or move the mouse. SAM will wait until your MiSTer goes idle again and then launch another game. And another. And another.

## Installation
- Copy `MiSTer_SAM_on.sh` to your MiSTer's `/media/fat/Scripts` directory - *that's it!* 
- Additional files will be downloaded automatically the first time you run `MiSTer_SAM_on.sh`. You can update your installation the same way.

## Offline Installation  
If your MiSTer is not connected to the internet, click on "Code" -> "Download Zip" and download the project package.
- Copy `MiSTer_SAM_on.sh` and `MiSTer_SAM.ini` to `/media/fat/Scripts` on your MiSTer. 
- Additionally copy the entire `MiSTer_SAM` directory to `/media/fat` on your MiSTer.
  
## Configuration
The script is highly customizable through the included ini file `MiSTer_SAM.ini` (details below).

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
### Arcade Horizontal or Vertical Only
Change the "orientation" setting in the `Attract_Mode.ini` file to choose from only horizontal or vertical arcade games.

### Exclude
Want to exclude certain arcade games? Just add them to `mraexclude` in the `Attract_Mode.ini` file.

## FAQs
### Where'd this come from? What happened to the other attract mode projects?
The great work began with MrChrisster building a MiSTer Attract feature for the NES core. This begat Attract_Arcade after Mellified ~~kept opening issues~~ started helping. Once MrChrisster worked with mbc it unlocked the power to load ROMs for more MiSTer cores, resulting in Attract_Mode. We wanted to bring the project to the next level by automating the process. From this collaboration and passion was born SAM - Super Attract Mode! Since MiSTer SAM does everything the old projects did - and lots more! - we wanted to create a new name on par with its superpowers.

### How does it work?
A Linux startup daemon runs in the background of your MiSTer's ARM CPU. It looks for any keyboard activity, mouse movement, or controller button presses via Linux. This is being achieved by monitoring the hardware devices on your MiSTer without using barely any ressources and only with native tools on your MiSTer (CPU load of >1%). When it sees you aren't using the MiSTer for several minutes, it launches random games.

MiSTer arcade cores are launched via a MiSTer command. For console games there is no official way to load individual games programmatically. SUper Attract Mode automates the process by sending simulated button presses to the MiSTer. This is done with a modified version of [pocomane's MiSTer Batch Control](https://github.com/pocomane/MiSTer_Batch_Control). 

### Will this break my MiSTer? Will attract mode reduce the life of the MiSTer cycling between cores if left on long term?
Short answer is No. FPGAs don't have a limited number of writes. They are solid state devices that are configured at boot up, or in this case, when a core is loaded.  
  
If you would like to know what game is currently playing, you can check the file `/tmp/SAM_Game.txt`. Some folks even use this with OBS to automatically change the game name in their Twitch stream!  
  
## Troubleshooting
**- Core is loaded but just hangs on the menu**  
Sometimes this happens (even on our test setups) and it could be for a variety of reasons.   
- Neogeo and GBA seem to have the most issues while SNES, NES and Genesis work pretty reliably.  
- We noticed that some MegaCD games that the script is trying to load also won't work when loaded through the MiSTer interface. 
- Make sure you are using the recommended folder structure, such as /media/fat/Games/SNES/. 
- The script supports zipped Everdrive packs or unzipped folders. For MegaCD and Turbografx16 CD games must be in CHD format.  
 
If you are still having trouble it could simply be that the rom failed to load, it seems to happen every now and then.  
  
**- Sometimes NeoGeo doesn't load a rom and hangs on the menu**   
Still investigating why this is happening.
  
**- Turbografx16 CD just showing Run button but not starting into the game**  
Make sure you use a bios that auto launches the game.  

**- USB Storage**  
/media/usb is not well tested. Although care has been taken to use case-sensitive code, NTFS formatted drives may experience issues because (only) NTFS is case-sensitive on MiSTer.

**- Can I use a CIFS mount for my games?**  
CIFS is supported.
Here is an example of some values in `cifs_mount.sh` that should get you started. 
The idea is to mount The SMB Games folder over the MiSTer SD card Games folder:
  
```
SERVER="192.168.1.10"  
SHARE="Games/Mister/Games"  
LOCAL_DIR="*"  
BASE_PATH="/media/fat/Games" 
```
