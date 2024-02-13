import json
import subprocess
import re
from pathlib import Path

def get_scene_threshold(system_name):
    scene_threshold = "0.1"
    if system_name == "arcade":
        scene_threshold = "0.005"
    return scene_threshold

def run_ffmpeg(video_path, scene_threshold):
    print(f"Running FFmpeg for {video_path} with scene threshold {scene_threshold}...")
    cmd = [
        "ffmpeg", "-i", str(video_path),
        f"-filter:v", f"select='gt(scene,{scene_threshold})',showinfo",
        "-f", "null", "-", "-nostdin"
    ]
    result = subprocess.run(cmd, text=True, stderr=subprocess.PIPE)
    
    scene_changes = extract_scene_changes(result.stderr)
    print(f"Extracted scene changes for {video_path.name}: {scene_changes}")
    
    return scene_changes

def extract_scene_changes(ffmpeg_output):
    scene_changes = set()
    pts_time_pattern = re.compile(r"pts_time:(\d+\.\d+)")
    for line in ffmpeg_output.split("\n"):
        match = pts_time_pattern.search(line)
        if match:
            time = round(float(match.group(1)))
            if time > 5:  # Filter out changes in the first 5 seconds
                scene_changes.add(time)
    return sorted(scene_changes)

def filter_consecutive_scene_changes(scene_changes):
    filtered_changes = []
    for i in range(len(scene_changes)):
        if i == 0 or scene_changes[i] - scene_changes[i-1] > 1:
            filtered_changes.append(scene_changes[i])
    return filtered_changes

def update_json_file(json_file_path, video_folder_path, scene_threshold):
    if json_file_path.exists():
        with open(json_file_path, 'r', encoding='utf-8') as file:
            data = json.load(file)
    else:
        data = []

    existing_files = {entry['filename'] for entry in data}
    new_files_processed = False

    for video_file in video_folder_path.iterdir():
        if video_file.name not in existing_files:
            print(f"Processing {video_file.name}...")
            scene_changes = run_ffmpeg(video_file, scene_threshold)
            scene_changes = filter_consecutive_scene_changes(scene_changes)

            data.append({
                "filename": video_file.name,
                "sceneChanges": scene_changes,
                "blacklisted": len(scene_changes) < 2
            })

            new_files_processed = True

    if new_files_processed:
        with open(json_file_path, 'w', encoding='utf-8') as file:
            json.dump(data, file, indent=4, ensure_ascii=False)
        print("JSON file updated.")
    else:
        print("No new files to process.")
        


def update_blacklist_file(json_file_path, blacklist_folder_path, system_name):
    if not json_file_path.exists():
        print("JSON database does not exist. No blacklist file created.")
        return

    with open(json_file_path, 'r', encoding='utf-8') as file:
        data = json.load(file)
    
    # Initialize a list to hold blacklisted game titles without the .mp4 extension
    blacklisted_games = []
    for entry in data:
        if entry.get('blacklisted'):
            # Directly remove .mp4 extension, preserving any special characters
            filename_without_extension = Path(entry['filename']).stem
            blacklisted_games.append(filename_without_extension)

    if blacklisted_games:
        blacklist_file_path = blacklist_folder_path / f"{system_name}_blacklist.txt"
        with open(blacklist_file_path, 'w', encoding='utf-8') as file:
            for game in blacklisted_games:
                file.write(game + '\n')
        print(f"Blacklist file updated at {blacklist_file_path}")
    else:
        print("No blacklisted games found. No blacklist file updated.")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        system_name = sys.argv[1]
    else:
        system_name = input("Enter the system name: ")
    system_name = input("Enter the system name: ")
    scene_threshold = get_scene_threshold(system_name)
    json_file_path = Path(f"/mnt/c/SAM/json/{system_name}.json")
    video_folder_path = Path(f"/mnt/c/SAM/system_mp4s/{system_name}")
    blacklist_folder_path = Path(f"/mnt/c/SAM/blacklists")
    
    # Ensure the blacklist folder exists
    blacklist_folder_path.mkdir(parents=True, exist_ok=True)
    
    # Update the JSON database and the blacklist file
    update_json_file(json_file_path, video_folder_path, scene_threshold)
    update_blacklist_file(json_file_path, blacklist_folder_path, system_name)
