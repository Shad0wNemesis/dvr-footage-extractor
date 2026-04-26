@echo off
echo Installing dependencies...
pip install pillow imageio-ffmpeg pyinstaller

echo Building DVR_Extractor.exe...
pyinstaller --onefile --windowed --name DVR_Extractor ^
  --collect-data imageio_ffmpeg ^
  --hidden-import PIL._tkinter_finder ^
  dvr_gui.py

echo.
echo Done. EXE is at: dist\DVR_Extractor.exe
pause
