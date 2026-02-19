import os
import shutil
import subprocess
from PIL import Image

# Settings
source_image = "/Users/atonny/.gemini/antigravity/brain/265d718d-1789-480e-a339-3bdfb3119f23/echotype_app_icon_1771498194880.png"
project_root = "/Users/atonny/工作區/EchoType"
icons_dir = os.path.join(project_root, "desktop/src-tauri/icons")

def run_command(cmd):
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error running command {cmd}: {e}")
        raise e

def main():
    print(f"Generating icons in {icons_dir}...")
    
    if not os.path.exists(icons_dir):
        os.makedirs(icons_dir)

    # 1. Copy Main Icon (as PNG) and ensure RGBA
    main_icon_path = os.path.join(icons_dir, "icon.png")
    print("Converting master icon to RGBA PNG...")
    img = Image.open(source_image).convert('RGBA')
    img.save(main_icon_path, 'PNG')

    # 2. Generate PNGs for Tauri config
    # "icon": ["icons/32x32.png", "icons/128x128.png", "icons/128x128@2x.png", "icons/icon.icns"]
    png_sizes = [
        (32, "32x32.png"),
        (128, "128x128.png"),
        (256, "128x128@2x.png")
    ]
    
    for size, name in png_sizes:
        out_path = os.path.join(icons_dir, name)
        # Use PIL to ensure RGBA format
        img = Image.open(main_icon_path).convert('RGBA')
        img = img.resize((size, size), Image.Resampling.LANCZOS)
        img.save(out_path, 'PNG')
    
    print("Generated standard PNGs.")

    # 3. Generate .icns (Require .iconset folder)
    iconset_dir = os.path.join(icons_dir, "icon.iconset")
    if os.path.exists(iconset_dir):
        shutil.rmtree(iconset_dir)
    os.makedirs(iconset_dir)
    
    icns_sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png")
    ]
    
    for size, name in icns_sizes:
        out_path = os.path.join(iconset_dir, name)
        run_command(["sips", "-z", str(size), str(size), "-s", "format", "png", main_icon_path, "--out", out_path])
        
    icns_path = os.path.join(icons_dir, "icon.icns")
    run_command(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path])
    
    # Cleanup
    shutil.rmtree(iconset_dir)
    print("Generated icon.icns.")

if __name__ == "__main__":
    main()
