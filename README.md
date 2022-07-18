![alt text](https://github.com/mrchrisster/attract_mode/blob/main/Media/mister-sam-logo02.jpg)
![MiSTer_SAM](https://user-images.githubusercontent.com/81110968/117765392-8024d980-b1f3-11eb-8ecd-18f5e7c95bff.gif)
![alt text](https://github.com/mrchrisster/attract_mode/blob/main/Media/SAM_menu.png)
(Thanks to [@HendrixTrog](https://twitter.com/HendrixTrog) for the video!)

# MiSTer Super Attract Mode (SAM)
**MiSTer SAM puts all your games on display to enjoy whenever your MiSTer is idle!**

## What is it?
Like a screen saver, MiSTer SAM comes on when your MiSTer is idle. Then SAM will launch a random game from your library every few minutes. If you like a game that's currently playing, just pick up your controller and push a button, press a key, or move the mouse. SAM will wait until your **MiSTer goes idle in the menu** again. Then the gaming tour begins again!

## Installation
- Copy `Super_Attract_Mode.sh` to your MiSTer's `/media/fat/Scripts` directory - *that's it!* 
- From the main MiSTer menu navigate to **Scripts** and select **Super_Attract_Mode.sh**.
- NOTE: Additional files will be downloaded automatically the first time you run `Super_Attract_Mode.sh`.
  
## Offline Installation  
If your MiSTer is not connected to the internet, click on "Code" -> "Download Zip" and download the project package.
- Copy `Super_Attract_Mode.sh` and `Super_Attract_Mode.ini` to `/media/fat/Scripts` on your MiSTer. 
- Additionally copy the entire `.SuperAttractMode` directory to `/media/fat/Scripts/.SuperAttractMode` on your MiSTer.
- To enable autoplay, launch `Super_Attract_Mode.sh` - push up button to enter Menu. Now find enable autoplay in the menu.

## Update  
- Running `Super_Attract_Mode.sh` will update your exisiting version to the newest version.
- Backup `Super_Attract_Mode.ini` and delete (recommended). Since we constantly add new features, it is advised to backup your custom settings and start with a fresh `Super_Attract_Mode.ini`. 
  
## Usage
Simply wait at the main MiSTer menu for 2 minutes (default setting) without touching the mouse, keyboard, or controller and SAM will start.
- ** NOTE ** When you set the startup time to 60 seconds, it will actually wait 2 minutes since there is a default 60 second wait after boot (to let all processes start up).

Don't want to wait? You can start SAM instantly by launching `Super_Attract_Mode.sh` script in your MiSTer's Scripts folder! 

## Features
- **Autoplay** - MiSTer SAM autostarts by default when your MiSTer is idle in the main menu. If you want SAM to always autostart, no matter if in the main menu or not, you can do that by changing "menuonly" setting in `Super_Attract_Mode.ini` .

- **Controller Detection** - MiSTer SAM will only start when no input has been received from your controllers for the amount of time set in `Super_Attract_Mode.ini`  

- **Options Menu** - All options of SAM can be configured from a menu when launching `Super_Attract_Mode.sh`. 
**NOTE** The menu does not work out of the box on CRT's . Please try adding the following settings to your `/media/fat/MiSTer.ini` and see if it will make the menu work for your CRT setup:  
```
[Menu]
vga_scaler=0
fb_terminal=0
vsync_adjust=1
video_mode=512,38,66,64,224,12,20,6,10689
```
  
- **Exclusion Lists** - You can exclude any amount of games in the ini that you don't want to have displayed.  
  
- **Custom Game Directory Support** - You can set a custom directory for your games in `Super_Attract_Mode.ini` like `/media/usb0`.
  
  
  
## Reset to Defaults
This process can be used if you want to return MiSTer SAM to default settings or ensure you have the latest files.
- From the main MiSTer menu open the terminal (F9).
- Login (default user: `root` default password: `1`).
- `rm -fr /media/fat/Scripts/.SuperAttractMode /media/fat/Scripts/Super_Attract_Mode.ini`
- Open the OSD (F12 or your controller's menu button).
- Navigate to **Scripts** and select **Super_Attract_Mode.sh**.
  
## Configuration
The script is highly customizable through the included ini file `Super_Attract_Mode.ini` (details below).

## Supported Systems
Currently supported MiSTer cores:
* Arcade
* Game Boy Advance (.gba)
* Genesis (.md)
* MegaCD AKA SegaCD (.chd)
* NeoGeo (.neo)
* NES (.nes)
* SNES (.sfc)
* TurboGrafx-16 AKA PC Engine (.pce)
* TurboGrafx-16 CD AKA PC Engine CD (only .chd) (currently not working with mgl)
* PSX (.chd)

## MiSTer Setup
The [Update-all](https://github.com/theypsilon/Update_All_MiSTer) script works great for putting system files in the right places.

## Attract Mode Configuration
### Arcade Horizontal or Vertical Only
Change the "orientation" setting in the `Super_Attract_Mode.ini` file to choose from only horizontal or vertical arcade games.

### Exclude
Want to exclude certain arcade games? Just add them to `mraexclude` in the `Super_Attract_Mode.ini` file.

## FAQs

### How does it work?
A Linux startup daemon runs in the background of your MiSTer's ARM CPU. It looks for any keyboard activity, mouse movement, or controller button presses via Linux. This is being achieved by monitoring the hardware devices on your MiSTer while using minimal resources - with only native tools (CPU load of >1%). When SAM sees you are at the main menu and aren't using the MiSTer for several minutes, it launches random games.

MiSTer arcade cores are launched via a MiSTer command. For console games we are using .mgl files. For arcade games, we're using mra files.
 
### Do you support SNAC?  
SNAC is not handled by the Linux kernel so unfortunately we wont be able to support SNAC devices.
  
### I don't like how SAM does something!
MiSTer SAM is designed to be highly configurable. Please check the `/media/fat/Scripts/Super_Attract_Mode.ini` file to see if the behavior you want is configurable. If not, please [open an issue](https://github.com/mrchrisster/MiSTer_SAM/issues/new/choose)! We love feedback and feature requests.

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
This used to be a problem with the original version of SAM. SInce we now have official game loading support, this shouldn't be an issue anymore.
  
**- Turbografx16 CD and MegaCD just showing Run/Start button but not starting into the game**  
Make sure you use a bios that auto launches the game.  

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

## Advanced Usage
For technical users here are a few handy tricks to observe and debug SAM.
- To update the daemon from local files:
    `cp /media/fat/Scripts/.SuperAttractMode/SuperAttractMode_init /etc/init.d/S93mistersam && /etc/init.d/S93mistersam start &`
- To disable the daemon startup delay add to your INI: `startupsleep="No"`
- To enable more console messages: `samquiet="No"`
  
   
## Release History
- 9 March 2022 - Implemented the new and exciting mgl file loading technique which makes mbc obsolete. Thanks to pocomane for providing a tool to load games while there was no official way of doing so. We're very excited that there is now a way to load games directly from command line officially.
- 10 May 2021 - "2.0" release! Menu, per-core exclusions, directory exclusion, timer until next game (ssh), custom game dir support (usb0), expanded controller detection, NeoGeo compatiblity improvements
- 28 Apr 2021 - Test branch support, added reboot to on to improve reliability, fixed confusing messages in on, fixed monitoring with no js devices
- 24 Apr 2021 - Controller detection and removal, launch SAM only from the main menu (configurable), allow controller/keyboard/mouse interrupts (configurable), fixed INI parsing, added SAM now to launch instantly, more bugs squashed.
- 23 Apr 2021 - Updated INI and data directory - [Reset to defaults](https://github.com/mrchrisster/MiSTer_SAM#reset-to-defaults) recommended!
- 21 Apr 2021 - Initial version
