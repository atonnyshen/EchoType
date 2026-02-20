from PIL import Image, ImageDraw
import sys

def create_squircle_mask(size):
    # Standard macOS squircle shape
    # We use a high-quality sampling method or a drawn path
    
    # Create a large intermediate image for anti-aliasing
    scale = 4
    mask_size = size * scale
    mask = Image.new('L', (mask_size, mask_size), 0)
    draw = ImageDraw.Draw(mask)
    
    # Draw rounded rectangle (Apple-like curvature)
    # The radius is typically ~22% of the icon size
    radius = mask_size * 0.223
    
    # Draw white filled rounded rect on black background
    draw.rounded_rectangle([(0,0), (mask_size, mask_size)], radius=radius, fill=255)
    
    # Resize down with high quality resampling to get smooth edges
    mask = mask.resize((size, size), Image.Resampling.LANCZOS)
    return mask

def process_icon(input_path, output_path):
    print(f"Applying Squircle Mask: {input_path} -> {output_path}...")
    try:
        img = Image.open(input_path).convert("RGBA")
        
        # 1. Do NOT remove white color. Keep the "White Card".
        # 2. Just apply the mask to the alpha channel.
        
        # Create the mask matches the image size
        size = img.size[0]
        # Ensure image is square to avoid size mismatch bugs
        if img.size[0] != img.size[1]:
            print("Warning: Input image is not square. Resizing/Padding...")
            # Ideally center crop or pad. For now, resize.
            img = img.resize((size, size))
            
        squircle_mask = create_squircle_mask(size)
        
        # Verify sizes match
        if img.size != squircle_mask.size:
            print(f"Size mismatch: Image {img.size} vs Mask {squircle_mask.size}")
            squircle_mask = squircle_mask.resize(img.size) # Force match
        
        # Apply mask
        img.putalpha(squircle_mask)
        
        img.save(output_path, "PNG")
        print("Squircle mask applied successfully.")
        
    except Exception as e:
        print(f"Error processing image: {e}")
        sys.exit(1)

if __name__ == "__main__":
    process_icon("icon_master.png", "icon_no_bg.png")
