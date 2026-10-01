"""Make the App Store QR code used on the gym flyer.

Usage: python3 make_qr.py "https://apps.apple.com/app/apple-store/id6809208501?pt=TOKEN&ct=gym_flyer&mt=8"
Needs: pip install qrcode
Replace the default URL with an App Store campaign link so flyer installs are attributed.
"""
import sys
import qrcode
import qrcode.image.svg

url = sys.argv[1] if len(sys.argv) > 1 else "https://apps.apple.com/us/app/cave-cals-ai-calorie-tracker/id6809208501"
img = qrcode.make(url, image_factory=qrcode.image.svg.SvgPathImage, box_size=10, border=2,
                  error_correction=qrcode.constants.ERROR_CORRECT_M)
img.save("brand/app-store-qr.svg")
print("Wrote brand/app-store-qr.svg for", url)
