![alt text](https://github.com/mrchrisster/attract_mode/blob/main/Media/mister-sam-logo02.jpg)
![MiSTer_SAM](https://user-images.githubusercontent.com/81110968/117765392-8024d980-b1f3-11eb-8ecd-18f5e7c95bff.gif)
![alt text](https://github.com/mrchrisster/attract_mode/blob/main/Media/sam_menu.png)
(Thanks to [@HendrixTrog](https://twitter.com/HendrixTrog) for the video!)

# MiSTer Super Attract Mode (SAM)
**SAM puts all your games on display to enjoy whenever your MiSTer is idle!**

## What is it?
Like a screen saver, SAM comes on when your MiSTer is idle. It will launch a random game from your library every few minutes. If you like a game that's currently playing, just pick up your controller and push a button, press a key, or move the mouse. SAM will start another game once you return to the main menu. Then the gaming tour begins again!

## Installation
  
- The easiest way to install SAM is launch `update_all.sh` menu, select "0 Misc" and select "Mister SAM files". After running update_all, you will have a file called `update_MiSter_SAM.sh` in the Scripts folder. Run `update_MiSter_SAM.sh` and don't push any buttons until SAM is fully installed/updated. You can configure it from the menu by running `MiSTer_SAM_on.sh` and pushing up.
  
or  
  
- Copy `MiSTer_SAM_on.sh` to your MiSTer's `/media/fat/Scripts` directory - *that's it!* 
- From the main MiSTer menu navigate to **Scripts** and select **MiSTer_SAM_on.sh**.
- **NOTE** Additional files will be downloaded automatically the first time you run `MiSTer_SAM_on.sh`.
  
## Offline Installation  
If your MiSTer is not connected to the internet, click on "Code" -> "Download Zip" and download the project package.
- Copy `MiSTer_SAM_on.sh` and `MiSTer_SAM.ini` to `/media/fat/Scripts` on your MiSTer. 
- Additionally copy the entire `.MiSTer_SAM` directory to `/media/fat/Scripts/.MiSTer_SAM` on your MiSTer.
- To enable autoplay, launch `MiSTer_SAM_on.sh` - push up button to enter Menu. Now find enable autoplay in the menu.

## Update  
- Running `MiSTer_SAM_on.sh` will update your exisiting version to the newest version.
  
## Usage
Simply wait at the main MiSTer menu for 2 minutes (default setting) without touching the mouse, keyboard, or controller and SAM will start.

Don't want to wait? You can start SAM instantly by launching `MiSTer_SAM_on.sh` script in your MiSTer's Scripts folder! 

## Features
- **Autoplay** - MiSTer SAM autostarts by default when your MiSTer is idle in the main menu. If you want SAM to always autostart, no matter if in the main menu or not, you can do that by changing "menuonly" setting in `MiSTer_SAM.ini` .

- **Controller Detection** - MiSTer SAM will only start when no input has been received from your controllers for the amount of time set in `MiSTer_SAM.ini`  

- **Options Menu** - All options of SAM can be configured from a menu when launching `MiSTer_SAM_on.sh`.  
**NOTE** The menu does not work out of the box on CRT's . Please try adding the following settings to your `/media/fat/MiSTer.ini` and see if it will make the menu work for your CRT setup:  
```
[Menu]
vga_scaler=0
fb_terminal=0
vsync_adjust=1
video_mode=512,38,66,64,224,12,20,6,10689
```
  
- **Exclusion Lists** - You can exclude any amount of games in the ini that you don't want to have displayed.  
  
- **Whitelist Support** - Specify a list of games you would like to display (ignore all other games in the folder). E.g. set `gbawhitelist="/media/fat/Scripts/MiSTer_SAM_whitelist_gba.txt"` in MiSTer_SAM.ini
  
- **Custom Game Directory Support** - You can set a custom directory for your games in `MiSTer_SAM.ini` like `/media/usb0`.
  
  
  
## Reset to Defaults
This process can be used if you want to return MiSTer SAM to default settings or ensure you have the latest files.  
**Method 1**  
- Navigate to **Scripts** and select **MiSTer_SAM_on.sh**.  
- Press **Up Button** to open SAM's menu and select reset.  
  
**Method 2**  
- From the main MiSTer menu open the terminal (F9).
- Login (default user: `root` default password: `1`).
- `rm -fr /media/fat/Scripts/.MiSTer_SAM /media/fat/MiSTer_SAM /media/fat/Scripts/MiSTer_SAM.ini`
- Open the OSD (F12 or your controller's menu button).
- Navigate to **Scripts** and select **MiSTer_SAM_on.sh**.  
  

## Configuration
The script is highly customizable through the included ini file `MiSTer_SAM.ini` (details below).

## Supported Systems
Currently supported MiSTer cores:
* Amiga (MegaAGS.hdf)
* Arcade (all .MRA files)
* Atari2600/5200/7800 (.a26 .a52 .car .a78)
* Atari Lynx (.lnx)
* C64 (.prg and .crt)
* Famicom Disk System (.fds)
* Game Boy/ Game Boy Color (.gb and .gbc)   
* Game Boy Advance (.gba)
* Genesis (.md .gen)
* Game Gear (.gg)
* MegaCD AKA SegaCD (.chd .cue) - Highly recommend [Japanese region free Bios v2](https://mmmonkey.co.uk/downloads/#) for best compatibility.
* NeoGeo (.neo)
* NES (.nes)
* Genesis 32X (.32x)
* Sega Master System (.sms .sg)
* SNES (.sfc .smc)
* PSX (.chd .cue .exe)
* TurboGrafx-16 AKA PC Engine (.pce .sgx)
* TurboGrafx-16 CD AKA PC Engine CD (.chd .cue) - No autoboot bios required since SAM will autostart games for you.

## MiSTer Setup
The [Update-all](https://github.com/theypsilon/Update_All_MiSTer) script works great for putting system files in the right places.

## Attract Mode Configuration
### Arcade Horizontal or Vertical Only
Uncomment one of the "arcadepath" settings in the `MiSTer_SAM.ini` file to choose from only horizontal or vertical arcade games.

### Enhanced tty2oled output
![IMG_1029](https://user-images.githubusercontent.com/81110968/122233384-a3414980-ce81-11eb-93bc-300413af6dc1.gif)

[tty2oled](https://github.com/venice1200/MiSTer_tty2oled/) adds a 3" OLED screen to your MiSTer! By default, tty2oled displays the current core name. With SAM's enhanced tty2oled support you can see the core and game name!

Simply edit the `MiSTer_SAM.ini` and change the `ttyenable` setting to `ttyenable="Yes"`. If you need to use a non-standard device change it with `ttydevice="/dev/ttyUSB0"`.

### Exclude
Want to exclude certain arcade games? Just add them to `mraexclude` in the `MiSTer_SAM.ini` file.

## FAQs

### How does it work?
A Linux startup daemon runs in the background of your MiSTer's ARM CPU. It looks for any keyboard activity, mouse movement, or controller button presses via Linux. This is being achieved by monitoring the hardware devices on your MiSTer while using minimal resources - with only native tools (CPU load of >1%). When your MiSTer is displaying the main menu and it's idle for several minutes, SAM will start launching random games.

MiSTer arcade cores are launched via MRA files, all other cores are launched through generating MGL files. 
  
### Do you support SNAC?  
SNAC is not handled by the Linux kernel so unfortunately we wont be able to support SNAC devices.
  
### I don't like how SAM does something!
MiSTer SAM is designed to be highly configurable. Please check the `/media/fat/Scripts/MiSTer_SAM.ini` file to see if the behavior you want is configurable. If not, please [open an issue](https://github.com/mrchrisster/MiSTer_SAM/issues/new/choose)! We love feedback and feature requests.

### Will this break my MiSTer? Will attract mode reduce the life of the MiSTer cycling between cores if left on long term?
Short answer is no. FPGAs [don't have a limited number of writes](https://www.youtube.com/watch?v=gtxNu_BUL-w). They are solid state devices that are configured at boot up or - in the case of MiSTer - when a core is loaded. There is no wear from this configuration step.

Also, all files that SAM creates (with the exception of the startup file during first install) are written to RAM mounted storage so you don't need to worry about wearing out your SD card when using SAM.  
  
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
- We noticed that some MegaCD games that the script is trying to load also won't work when loaded through the MiSTer interface. 
- Make sure you are using the recommended folder structure, such as /media/fat/Games/SNES/. 
- The script supports zipped Everdrive packs or unzipped folders. For MegaCD and Turbografx16 CD games must be in CHD format.  
 
If you are still having trouble it could simply be that the rom failed to load, it seems to happen every now and then.  
  
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

- To enable more console messages: `samquiet="No"`
- Check the generated MGL file under `/tmp/SAM_game.mgl`. 

## SSH fetures  

Some commands to control SAM from the command line  
  
- `MiSTer_SAM_on.sh monitor` - This will attach MiSTer SAM to current shell (only works while autoplay is running)
- `MiSTer_SAM_on.sh start` - Start SAM immediately
- `MiSTer_SAM_on.sh skip | next` - Load next game - doesn't interrupt loop if running
- `MiSTer_SAM_on.sh stop` - Stop SAM immediately
- `MiSTer_SAM_on.sh update` - Update SAM
- `MiSTer_SAM_on.sh enable` - Enable SAM autoplay mode
- `MiSTer_SAM_on.sh disable` - Disable SAM autoplay
- `MiSTer_SAM_on.sh reset` - Reset SAM
- `MiSTer_SAM_on.sh arcade | psx | genesis | s32x | etc...` - Only launch specific system
- `MiSTer_SAM_on.sh favorite` - Copy the current game to "_Favorites" folder
   
   
## Release History
- 24 June 2022 - Added category exclusion mode, atari core support and BGM support
- 25 Apr 2022 - Added gb,gbc,gg and s32x support. SAM now uses game lists for faster load times and better exclusion options.
- 22 Mar 2022 - Added support for Famicom Disk System and `MiSTer_SAM_on.sh favorite`
- 17 Mar 2022 - SAM is now using MGL to launch games. Also added PSX support
- 30 Nov 2021 - @InquisitiveCoder added Whitelist support
- 16 May 2021 - Fixed hotplug detection, added ini editing feature through menu
- 10 May 2021 - "2.0" release! Menu, per-core exclusions, directory exclusion, timer until next game (ssh), custom game dir support (usb0), expanded controller detection, NeoGeo compatiblity improvements
- 28 Apr 2021 - Test branch support, added reboot to on to improve reliability, fixed confusing messages in on, fixed monitoring with no js devices
- 24 Apr 2021 - Controller detection and removal, launch SAM only from the main menu (configurable), allow controller/keyboard/mouse interrupts (configurable), fixed INI parsing, added SAM now to launch instantly, more bugs squashed.
- 23 Apr 2021 - Updated INI and data directory - [Reset to defaults](https://github.com/mrchrisster/MiSTer_SAM#reset-to-defaults) recommended!
- 21 Apr 2021 - Initial version
