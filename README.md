![alt text](https://github.com/mrchrisster/attract_mode/blob/main/Media/mister-sam-logo02.jpg)
![MiSTer_SAM](https://user-images.githubusercontent.com/81110968/117765392-8024d980-b1f3-11eb-8ecd-18f5e7c95bff.gif)
(Thanks to [@HendrixTrog](https://twitter.com/HendrixTrog) for the video!)
![Main_Menu](https://github.com/mrchrisster/MiSTer_SAM/blob/main/Media/2023-04-sam_menu1.png)

# MiSTer Super Attract Mode (SAM)

## What is it?
**Super Attract Mode puts all your games on display to enjoy whenever your MiSTer is idle.**  
Like a screen saver, SAM comes on when your MiSTer is idle. Just wait a couple of minutes in the main menu and SAM will launch a random game from your library. Every few minutes it will randomly select and load a new game. If you like a game that's currently playing, just pick up your controller and push a button, press a key, or move the mouse. Back in the main menu, wait another two minutes and the gaming tour begins again!

## Installation
  
- The easiest way to install SAM is launch `update_all.sh` menu, select "Tools & Scripts" and select "Mister Super Attract Mode". After running update_all, you will have a file called `MiSter_SAM_on.sh` in the Scripts folder. Run `MiSter_SAM_on.sh` and wait until SAM is fully installed/updated. You can configure SAM from the menu by running `MiSTer_SAM_on.sh` and pushing up.
  
or  
  
- Copy `MiSTer_SAM_on.sh` to your MiSTer's `/media/fat/Scripts` directory
- From the main MiSTer menu navigate to **Scripts** and select **MiSTer_SAM_on.sh**.
- **NOTE** Additional files will be downloaded automatically the first time you run `MiSTer_SAM_on.sh`.

or

- Issue the following command in ssh
  `cd /media/fat/Scripts && curl -kLO https://raw.githubusercontent.com/mrchrisster/MiSTer_SAM/main/MiSTer_SAM_on.sh`
- Run `/media/fat/Scripts/MiSTer_SAM_on.sh` and let SAM do the auto install to download the other installation files.
  
## Offline Installation  
If your MiSTer is not connected to the internet, click on "Code" -> "Download Zip" and download the project package.
- Copy `MiSTer_SAM_on.sh` and `MiSTer_SAM.ini` to `/media/fat/Scripts` on your MiSTer. 
- Additionally copy the entire `.MiSTer_SAM` directory to `/media/fat/Scripts/.MiSTer_SAM` on your MiSTer.
- To enable autoplay, launch `MiSTer_SAM_on.sh` - push up button to enter Menu. Now find enable autoplay in the menu under Settings.

## Update  
- Running `MiSTer_SAM_on.sh` will update your existing version to the newest version.
  
## Usage
Simply wait at the main MiSTer menu for 2 minutes (default setting) without touching the mouse, keyboard, or controller and SAM will start.

Don't want to wait? You can start SAM instantly by launching `MiSTer_SAM_on.sh` script in your MiSTer's Scripts folder! 

## Features
- **Autoplay** - MiSTer SAM autostarts by default when your MiSTer is idle in the main menu. If you want SAM to always autostart, no matter if in the main menu or not, you can do that by changing "menuonly" setting in `MiSTer_SAM.ini` .

- **Controller Detection** - MiSTer SAM will only start when no input has been received from your controllers for the amount of time set in `MiSTer_SAM.ini`.

- **Controller Mapping** - SAM can have custom button assignments for "Show next game" or "Start game". Check in SAM's menu under "Configure Gamepad" or try out if the default mapping works for you. Select button goes to next game and start button will play the current game.

- **Options Menu** - All options of SAM can be configured from a menu when launching `MiSTer_SAM_on.sh`. Push UP button after launching `MiSTer_SAM_on.sh` script. 
**NOTE** The menu does not work out of the box on CRT's . Please try adding the following settings to your `/media/fat/MiSTer.ini` and see if it will make the menu work for your CRT setup:  
```
[Menu]
video_mode=640,16,64,80,240,1,3,14,12380
vga_scaler=1
```
or 
```
[Menu]
video_mode=640,-16,56,56,240,1,3,13,11350
vga_scaler=1
```
  
- **Exclusion Lists** - You can exclude any amount of games that you don't want to have displayed by adding a file called for example `snes_excludelist.txt` in /media/fat/Scripts/.MiSTer_SAM/SAM_Gamelists folder. One line per game, can be full file path or just the game name. Or just launch the game you want to exclude and type `/media/fat/Scripts/MiSTer_SAM_on.sh ignore` in SSH. SAM will create the exclude list for you.
  
- **Auto Folder Detection** - No matter if your games are on SD or USB, SAM will find your default game folders.
  
- **Curated Blacklists** - The SAM Team is currently recording every game's attract mode to short videos that we capture through HDMi so we can detect if a game is worthy to be shown or should be blacklisted (like Disc 2 for MegaCD, load error FDS games or games with a static screen)
  
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
* AO486 (Drop screensaver vhd's in /media/fat/games/AO486/screensaver - created by flynnsbit)
* Arcade (all .MRA files)
* Atari2600/5200/7800 (.a26 .a52 .car .a78)
* Atari Lynx (.lnx)
* C64 (.prg and .crt)
* Famicom Disk System (.fds)
* Game Boy/ Game Boy Color (.gb and .gbc)   
* Game Boy Advance (.gba)
* Genesis (.md .gen)
* Game Gear (.gg)
* MegaCD AKA SegaCD (.chd .cue) - Highly recommend `JP Mega-CD 2 (Region Free) 921222 l_oliveira.bin` for best compatibility. Find it in MegaCD folder, google `htgdb-gamepacks`
* NeoGeo (.neo)
* NES (.nes)
* Nintendo N64 (.z64)
* Genesis 32X (.32x)
* Sega 32x (.s32)
* Sega Saturn (.chd .cue)
* Sega Master System (.sms .sg)
* Super GameBoy (.gb .gbc)
* SNES (.sfc .smc)
* PSX (.chd .cue .exe)
* TurboGrafx-16 AKA PC Engine (.pce .sgx)
* TurboGrafx-16 CD AKA PC Engine CD (.chd .cue) - No autoboot bios required since SAM will autostart games for you.

## MiSTer Setup
The [Update-all](https://github.com/theypsilon/Update_All_MiSTer) script works great for putting system files in the right places.
Make sure you have Arcade Organizer enabled for some of SAM's advanced features.

## Attract Mode Configuration
### Arcade Horizontal or Vertical Only
Uncomment one of the "arcadepath" settings in the `MiSTer_SAM.ini` file to choose from only horizontal or vertical arcade games.

### BGM Support
You can set up BGM from SAM's menu. It will lower the core volume while showing games and reset the core volume when SAM exits.  
Currently BGM support is broken for N64 and PSX core  
  
  
### Enhanced tty2oled output
![IMG_1029](https://github.com/mrchrisster/MiSTer_SAM/blob/main/Media/tty2oled-moving.gif)

[tty2oled](https://github.com/venice1200/MiSTer_tty2oled/) adds a 3" OLED screen to your MiSTer! By default, tty2oled displays the current core name. With SAM's enhanced tty2oled support you can see the core and game name!

Simply edit the `MiSTer_SAM.ini` and change the `ttyenable` setting to `ttyenable="Yes"`. If you need to use a non-standard device change it with `ttydevice="/dev/ttyUSB0"`.

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
If SAM's auto start feature fails for whatever reason, you can try and use a bios that auto launches the game.  

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

- To enable more console messages: `samdebug="Yes"`
- Check the generated MGL file under `/tmp/SAM_game.mgl`. 

## SSH features  

Some commands to control SAM from the command line  
  
- `MiSTer_SAM_on.sh monitor` - This will show you which game is currently playing
- `MiSTer_SAM_on.sh start` - Start SAM immediately
- `MiSTer_SAM_on.sh skip | next` - Load next game - doesn't interrupt loop if running
- `MiSTer_SAM_on.sh stop` - Stop SAM immediately
- `MiSTer_SAM_on.sh update` - Update SAM
- `MiSTer_SAM_on.sh enable` - Enable SAM autoplay mode
- `MiSTer_SAM_on.sh disable` - Disable SAM autoplay
- `MiSTer_SAM_on.sh reset` - Reset SAM
- `MiSTer_SAM_on.sh sshconfig` - Quick access to SAM's SSH features. Now you can type eg. `m update` in Terminal to update SAM.
- `MiSTer_SAM_on.sh arcade | psx | genesis | s32x | etc...` - Only launch specific system
- `MiSTer_SAM_on.sh favorite` - Copy the current game to "_Favorites" folder

## Credits
SAM has been a joined effort from the start. Huge thanks to Mellified and all other supporters!  
Original concept and implementation: mrchrisster  
Script layout & watchdog functionality: Mellified   
tty2oled submodule: Paradox  
Indexing tool & input detection: wizzomafizzo  
   
## Release History
- 4 Feb 2025 - Added amigacd32, neogeocd and various bugfixes
- 26 Feb 2024 - Saturn, N64 and video mode implemented. Watch game commercials from back in the day and then play those games.
- 02 Feb 2023 - ao486 integration, Kids Safe Mode, Dynamically finding new roms, Adjust global volume for BGM
- 10 Aug 2022 - tty2oled and gamelist updates. Default blacklists now filter out static screens.
- 24 Jun 2022 - Added category exclusion mode, atari core support and BGM support
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
