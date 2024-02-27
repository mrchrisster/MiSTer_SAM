# -------- NOTES --------
# Arcade core will work on most systems using Update_All

# For Console cores make sure you are using the recommended folder structure: /media/fat/games/SNES/ etc.
# The script supports zipped Everdrive packs or unzipped folders.
# For PSX, MegaCD and Turbografx16 CD your games need to be in CHD format.

# !!! Some settings will need a reboot to take effect !!!

# -------- GENERAL OPTIONS --------

# Time before Super Attract Mode starts in seconds. On reboot it will wait an additional minute for all services to load up.
# SAM comes on at 60s + samtimeout, so default is a 2 mins wait in main menu before SAM starts.
# 300 = 5 minutes, 600 = 10 minutes, 900 = 15 minutes
samtimeout=60

# Time before going to the next core in seconds
gametimer=180

# Start SAM only from MiSTer main menu
# If you change this to menuonly is set to "No", SAM will always start after you put down the controller. 
menuonly="Yes"

# Which systems would you like to display in Attract Mode?
# Valid options: amiga,ao486,arcade,atari2600,atari5200,atari7800,atarilynx,c64,fds,gb,gbc,gba,genesis,gg,megacd,n64,neogeo,nes,s32x,saturn,sgb,sms,snes,tgfx16,tgfx16cd,psx
corelist="amiga,ao486,arcade,atari2600,atari5200,atari7800,atarilynx,c64,fds,gb,gbc,gba,genesis,gg,megacd,n64,neogeo,nes,s32x,saturn,sgb,sms,snes,tgfx16,tgfx16cd,psx"

# When SAM starts, mute global or core volume. Core volume can't be muted completely.
# A reboot or stopping SAM will clear all volume settings and restore any volume settings you have set prior
# Options are Global (Mute global volume) No (to always play game sounds) or Core (to mute cores individually). "Yes" can also be set which is the same as core. 
# Please use "core" for BGM support or use the menu to configure BGM automatically
mute="No"

# How do we exit SAM?
# "No" - SAM will reboot to MiSTer Menu when a button is pushed. 
# NOTE - If you push Start on your controller it will play the current game, any other button quits SAM. Set this up in SAM's menu under "Configure Exit behavior"
# "Yes" - SAM will stay in the current game when exiting.
playcurrentgame="Yes" 

# How to handle duplicate roms. Can be "normal" or "strict". Strict will only keep one version of a game (so no betas, hacks etc..)
dupe_mode="normal"

# ---------- SPECIAL MODES --------------
# SAM game roulette is a mode available in the menu, where you only have a certain amount of time to play a game, before SAM shuffles to the next game.
# SAM will ignore any button inputs and shuffle to a new game after the set timer expires.
# While SAM is primarily meant as a way to enjoy the pixel art of random games, roulette mode let's you play those games while continuing to shuffle.
roulettetimer="500"

# The Amigavision image contains demos and games. Here you can select what Amiga content you want SAM to show. Options are "Demos", "Games" or "All"
amigaselect="All"

# Good to use if you have young children. Limits rom selection to ESRB rated games with the "All Ages" label
# Please update SAM after enabling this to download the ESRB game whitelists
# Some cores like MegaCD will only have very few games so it's best to use coreweight which you can find further down in this ini
kids_safe="no"

# Some cores require a bios message to be skipped, eg FDS and Saturn. Try a value higher than 10
skiptime="10"

# M82 mode. Edit /media/fat/Scripts/.MiSTer_SAM/SAM_Gamelists/m82_list.txt to customize the m82 list with your favorite games.
m82="yes"
m82timer="30"

# This is a curated list of games for different cores with great Attract Modes.
# Feel free to edit it to your liking at /media/fat/Scripts/.MiSTer_SAM/SAM_Gamelists/sam_goat_list.txt
sam_goat_list="no"

# Alternative way of selecting cores. Based on how many games a system has.
coreweight="No"

# --------- ARCADE ORIENTATION ---------
# Set Arcade orientation to "horizontal" "vertical" or leave empty
arcadeorient=""

# --------- PATH FILTER ---------
# If you would like to only play games from a subdirectory of your games folder, put it here
# Partial match is all you need. Can be part of the path or filename.
# Please reboot for path filter to take effect.
#
# nespathfilter="(Japan)"

amigapathfilter=""
arcadepathfilter=""
atari2600pathfilter=""
atari5200pathfilter=""
atari7800pathfilter=""
atarilynxpathfilter=""
c64pathfilter=""
fdspathfilter=""
gbpathfilter=""
gbcpathfilter=""
gbapathfilter=""
genesispathfilter=""
ggpathfilter=""
megacdpathfilter=""
neogeopathfilter=""
nespathfilter=""
s32xpathfilter=""
smspathfilter=""
snespathfilter=""
tgfx16pathfilter=""
tgfx16cdpathfilter=""
psxpathfilter=""

# FOLDER AND FILE EXCLUSION
# Folders and files you would like to exlude, like NSF (Audio files for NES) for example. You don't need to include the full path or file name.
# Partial names with case insensitive spelling will suffice.

exclude=( readme unsupported bios )


# -------- SAMVIDEO SETTINGS -------
# Play videos in SAM (eg old video game commercials)
# ATTENTION: In order for SAMVIDEO to work, we will modify MiSTer.ini (adding a video_mode for menu core). Please check MiSTer.ini if you experience any issues.
samvideo="No"
# Choose the video output, either HDMI or CRT. Note that only archive playback is supported for "samvideo_source" if using CRT mode.
samvideo_output="HDMI"
# Change the following setting if you can only hear the audio of the video and SAM shows the Menu core. Some displays need more time.
# Setting should be 2 or more. Try higher values if you encounter issues
samvideo_displaywait="3"
# Alternate with every core played, play video like another core or only play videos - Options are alternate, core or only
samvideo_freq="alternate"
#Play videos from youtube, archive or local. Lists are auto generated. Just setting youtube or archive is enough to have videos play from there.
samvideo_source="archive"
# Play a TV commercial of eg SNES and than show the corresponding SNES game. Only works for archive.org list.
samvideo_tvc="no"
# For HDMI playback if your device shows black bars, try setting sv_aspectfix_vmode to yes. 
sv_aspectfix_vmode="no"
# For CRT playback on archive playback we use 640x240
samvideo_crtmode640="video_mode=640,16,64,80,240,1,3,14,12380"
# For CRT playback on youtube playback we use 320x240
samvideo_crtmode320="video_mode=320,-16,32,32,240,1,3,13,5670"
# Customize lists for youtube, archive or local playback
# Due to the MiSTer CPU not being very powerful
# Recommended video codec is XVID in 640x480 for HDMI or 640x240 for CRT
samvideo_path="/media/fat/video"
sv_archive_hdmilist="https://archive.org/download/640x480_videogame_commercials/640x480_videogame_commercials_files.xml"
sv_archive_crtlist="https://archive.org/download/640x240_videogame_commercials/640x240_videogame_commercials_files.xml"
sv_youtube_hdmilist="/media/fat/Scripts/.MiSTer_SAM/sv_yt360_list.txt"
sv_youtube_crtlist="/media/fat/Scripts/.MiSTer_SAM/sv_yt240_list.txt"

# -------- TTY2OLED SETTINGS -------
# Options for https://github.com/venice1200/MiSTer_tty2oled - a Hardware Add-On display for MiSTer
# "Yes" shows the text name of the game being played
ttyenable="No"

# -------- BGM SETTINGS -------
# SAM supports BGM ( https://github.com/wizzomafizzo/MiSTer_BGM ). 
# It's best practice to set up BGM through the SAM menu (Select "Background Music Player")
bgm="No"
# Change bgmplay to no if songs play twice in BGM
bgmplay="Yes"
# Stop BGM when SAM stops
bgmstop="Yes"
# BGM playback tends to be louder than most cores. We can adjust bgm's volume here (value 1-7) 
# Once you play a game, global volume will be back to it's original level
# Note - bgmstop must be set to yes since bgm also does it's own volume management
# NOTE - This feature will write to the SD card on start and stop of SAM so by default it's off
gvoladjust="0"

# SAM will play every game on your system once before starting from the beginning. Change this to disable SAM's no repeat feature.
norepeat="Yes"

# -------- ADVANCED (HANDLE WITH CARE) --------

# -------- BUTTON DETECTION --------
# When you push a button or move the mouse, interrupt SAM

# SAM tries to listen for controller buttons, mouse movement, mouse buttons, and keyboard input
# SAM attempts to detect newly added controllers and mice for monitoring
# Note: Not all devices will be recognized - notably BlisSTer controllers in LLAPI mode, some BT controllers and SNAC devices
listenmouse="Yes"
listenkeyboard="Yes"
listenjoy="Yes"


# -------- TTY2OLED ADVCANCED SETTINGS -------
# All needed values are read from the tty2oled INI files

ttysystemini="/media/fat/tty2oled/tty2oled-system.ini"
ttyuserini="/media/fat/tty2oled/tty2oled-user.ini"
# How long to show the core logo for in seconds
ttycoresleep="10"
# How many seconds until core logo is shown again (default is "gametimer / 3")
ttycoreshow=""
# How often to show the core logo
ttydisplayswitch="2"
# Display scrolling text with bigger font, omit system info 
ttybig="no"
# A lot of games have info in brackets. This will remove brackets from tty2oled output
ttyname_cleanup="no"
# How fast the scrolling speed should be. Options are slower, normal or faster
ttyscroll_speed="normal"

# -------- DEBUG --------
samdebug="Yes"
# Write debug message to file at /tmp/samdebug.log
samdebuglog="No"

# GitHub branch to download updates from
# Valid choices are: "main" or "test"
branch="main"
