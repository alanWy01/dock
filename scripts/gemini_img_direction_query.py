import os
import glob
import requests

# User: set your Gemini API key here or via GEMINI_API_KEY env var
API_KEY = os.getenv("GEMINI_API_KEY", "YOUR_GEMINI_API_KEY_HERE")
API_URL = "https://generativelanguage.googleapis.com/v1/models/gemini-pro-vision:generateContent?key=" + API_KEY
IMG_DIR = "demo_imgs"  # Change to your image directory
# Accept any .png or .jpg file, natural sort
IMG_PATTERN = "*.png"

# 1. Index images
def natural_sort_key(s):
    import re
    return [int(text) if text.isdigit() else text.lower() for text in re.split(r'(\\d+)', s)]

def get_image_files(img_dir, pattern):
    files = glob.glob(os.path.join(img_dir, pattern))
    files += glob.glob(os.path.join(img_dir, pattern.replace('.png', '.jpg')))
    files = sorted(files, key=natural_sort_key)
    return files

def encode_image_base64(path):
    import base64
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")

def build_gemini_payload(img_paths):
    # Gemini expects a list of content blocks: text, image, text, ...
    content = []
    for idx, path in enumerate(img_paths, 1):
        content.append({"text": f"Image {idx}: {os.path.basename(path)}"})
        content.append({
            "inlineData": {
                "mimeType": "image/jpeg",
                "data": encode_image_base64(path)
            }
        })
    # Add the main question
    content.append({
        "text": "Among these 8 images, which one shows both elements facing the same direction and their heads looking at the same place? Reply with the image index (1-8) and explain briefly."
    })
    return {"contents": [{"parts": content}]}

def call_gemini_api(payload):
    resp = requests.post(API_URL, json=payload)
    resp.raise_for_status()
    return resp.json()

def main():
    img_paths = get_image_files(IMG_DIR, IMG_PATTERN)
    if len(img_paths) < 2:
        print(f"Expected at least 2 images, found {len(img_paths)} in {IMG_DIR}.")
        return
    print("Indexed images:")
    for i, p in enumerate(img_paths, 1):
        print(f"  {i}: {os.path.basename(p)}")
    print("\nIndex mapping:")
    for i, p in enumerate(img_paths, 1):
        print(f"  {i}: {os.path.basename(p)}")
    payload = build_gemini_payload(img_paths)
    print("Sending images to Gemini API...")
    try:
        result = call_gemini_api(payload)
    except Exception as e:
        print(f"API error: {e}")
        return
    print("Gemini response:")
    print(result["candidates"][0]["content"]["parts"][0]["text"])

if __name__ == "__main__":
    main()
