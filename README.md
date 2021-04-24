![alt text](https://github.com/mrchrisster/attract_mode/blob/main/Media/mister-sam-logo02.jpg)
![alt text](https://i.ibb.co/DzjQDtH/Screenshot-22.png)


# MiSTer Super Attract Mode (SAM)
**MiSTer SAM puts all your games on display to enjoy whenever your MiSTer is idle!**

## What is it?
Like a screen saver, MiSTer SAM comes on when your MiSTer is idle. Then SAM will launch a random game from your library every few minutes. If you like a game that's currently playing, just pick up your controller and push a button, press a key, or move the mouse. SAM will wait until your MiSTer goes idle again. Then the gaming tour begins again!

## Installation
- Copy `MiSTer_SAM_on.sh` to your MiSTer's `/media/fat/Scripts` directory - *that's it!* 
- From the main MiSTer menu open the OSD (F12 or your controller's menu button).
- Navigate to **Scripts** and select **MiSTer_SAM_on.sh**.
- NOTE: Additional files will be downloaded automatically the first time you run `MiSTer_SAM_on.sh`.
  
## Offline Installation  
If your MiSTer is not connected to the internet, click on "Code" -> "Download Zip" and download the project package.
- Copy `MiSTer_SAM_on.sh` and `MiSTer_SAM.ini` to `/media/fat/Scripts` on your MiSTer. 
- Additionally copy the entire `MiSTer_SAM` directory to `/media/fat/Scripts/.MiSTer_SAM` on your MiSTer.
- Make sure you don't forget about adding the `.` in front of the MiSTer_SAM directory

## Usage
Simply wait at the main MiSTer menu for 5 minutes without touching the mouse, keyboard, or controller and SAM will start.

Don't want to wait? You can start SAM instantly with the `MiSTer_SAM_now.sh` script in your MiSTer's Scripts folder! Just be sure to run `MiSTer_SAM_on.sh` at least once.

## Updates
`MiSTer_SAM_on.sh` is not only enabling the script on your MiSTer but is also updating all your files to the latest release. It will overwrite all MiSTer_SAM files except your `MiSTer_SAM.ini`.
  
- From the main MiSTer menu open the OSD (F12 or your controller's menu button).
- Navigate to **Scripts** and select **MiSTer_SAM_on.sh**.

## Reset to Defaults
This process can be used if you want to return MiSTer SAM to default settings or ensure you have the latest files.
- From the main MiSTer menu open the terminal (F9).
- Login (default user: `root` default password: `1`).
- `rm -fr /media/fat/Scripts/.MiSTer_SAM /media/fat/MiSTer_SAM /media/fat/Scripts/MiSTer_SAM.ini`
- Open the OSD (F12 or your controller's menu button).
- Navigate to **Scripts** and select **MiSTer_SAM_on.sh**.
  
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

## MiSTer Setup
The [Update-all](https://github.com/theypsilon/Update_All_MiSTer) script works great for putting system files in the right places.

## Attract Mode Configuration
### Arcade Horizontal or Vertical Only
Change the "orientation" setting in the `MiSTer_SAM.ini` file to choose from only horizontal or vertical arcade games.

### Exclude
Want to exclude certain arcade games? Just add them to `mraexclude` in the `MiSTer_SAM.ini` file.

## FAQs

### How does it work?
A Linux startup daemon runs in the background of your MiSTer's ARM CPU. It looks for any keyboard activity, mouse movement, or controller button presses via Linux. This is being achieved by monitoring the hardware devices on your MiSTer while using minimal resources - with only native tools (CPU load of >1%). When SAM sees you are at the main menu and aren't using the MiSTer for several minutes, it launches random games.

MiSTer arcade cores are launched via a MiSTer command. For console games there is no official way to load individual games programmatically. SUper Attract Mode automates the process by sending simulated button presses to the MiSTer. This is done with a modified version of [pocomane's MiSTer Batch Control](https://github.com/pocomane/MiSTer_Batch_Control). 
 
### Do you support SNAC?  
SNAC is not handled by the Linux kernel so unfortunately we wont be able to support SNAC devices.
  
### I don't like how SAM does something!
MiSTer SAM is designed to be highly configurable. Please check the `/media/fat/Scripts/MiSTer_SAM.ini` file to see if the behavior you want is configurable. If not, please [open an issue](https://github.com/mrchrisster/MiSTer_SAM/issues/new/choose)! We love feedback and feature requests.

### Will this break my MiSTer? Will attract mode reduce the life of the MiSTer cycling between cores if left on long term?
Short answer is no. FPGAs [don't have a limited number of writes](https://www.youtube.com/watch?v=gtxNu_BUL-w). They are solid state devices that are configured at boot up or - in the case of MiSTer - when a core is loaded. There is no wear from this configuration step.

### How do I know what game is on?  
If you would like to know what game is currently playing, you can check the file `/tmp/SAM_Game.txt`. Some folks even use this with OBS to automatically change the game name for their Twitch stream!  
  
### Where'd this come from? What happened to the other attract mode projects?
The great work began with MrChrisster building a MiSTer Attract feature for the NES core. This begat Attract_Arcade after Mellified ~~kept opening issues~~ started helping. Once MrChrisster worked with mbc it unlocked the power to load ROMs for more MiSTer cores, resulting in Attract_Mode. We wanted to bring the project to the next level by automating the process. From this collaboration and passion was born SAM - Super Attract Mode! Since MiSTer SAM does everything the old projects did - and lots more! - we wanted to create a new name appropriate for its new superpowers.
 
## Troubleshooting
**- When I try to launch the script, it fails and says something about Document Type**  
You most likely didn't download the "raw" file.  
When downloading a file from github, click on the file, then click on "raw".  
Now push Ctrl+S to save  
  
**- Core is loaded but just hangs on the menu**  
Sometimes this happens (even on our test setups) and it could be for a variety of reasons.   
- Neogeo and GBA seem to have the most issues while SNES, NES and Genesis work pretty reliably.  
- We noticed that some MegaCD games that the script is trying to load also won't work when loaded through the MiSTer interface. 
- Make sure you are using the recommended folder structure, such as /media/fat/Games/SNES/. 
- The script supports zipped Everdrive packs or unzipped folders. For MegaCD and Turbografx16 CD games must be in CHD format.  
 
If you are still having trouble it could simply be that the rom failed to load, it seems to happen every now and then.  
  
**- Sometimes NeoGeo doesn't load a rom and hangs on the menu.**   
Still investigating why this is happening. It sometimes loads a game successfully but then shows corrupted sprites. It has something to do with the bios but so far we don't know why. The NeoGeo core is special in a lot of ways and we haven't unlocked all it's mysteries yet.
  
**- Turbografx16 CD just showing Run button but not starting into the game**  
Make sure you use a bios that auto launches the game.  

**- USB Storage**  
/media/usb is not well tested. Although care has been taken to use case-sensitive code, NTFS formatted drives may experience issues because (only) NTFS is case-sensitive on MiSTer.

**- Can I use a CIFS mount for my games?**  
CIFS is supported.
Here is an example of some values in `cifs_mount.sh` that should get you started. 
The idea is to mount The SMB `Games` folder over the MiSTer SD card `Games` folder:
  
```
SERVER="192.168.1.10"  
SHARE="Games/Mister/Games"  
LOCAL_DIR="*"  
BASE_PATH="/media/fat/Games" 
```

## Release History
- 26 Apr 2021 - Controller detection and removal, launch SAM only from the main menu (configurable), allow controller/keyboard/mouse interrupts (configurable), bugs squashed.
- 23 Apr 2021 - Updated INI and data directory - [Reset to defaults](https://github.com/mrchrisster/MiSTer_SAM#reset-to-defaults) recommended!
- 21 Apr 2021 - Initial version
