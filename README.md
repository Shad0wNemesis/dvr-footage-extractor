# DVR Footage Extractor

A GUI tool for scanning and extracting surveillance footage from recovered Hikvision DVR hard drives. Identifies recordings by camera number and date range using OCR, then organizes them into folders — with zero-copy **Move to Folders** mode for full disks.

---

## Features

- Scans recovered MPG files from Hikvision DVR partitions
- OCR-based camera and date detection (handles both MM/DD and DD/MM DVR formats)
- Binary search narrows the date range before full scan (fast start)
- **Move to Folders** — instant, zero-disk-space sort via same-partition rename
- Multi-source support: two partitions scanned simultaneously, each sorted independently
- Live activity log with color-coded events
- Progress saved every 50 files — resumes after interruption
- ETA display during scan
- Camera filter, date filter, HTML/CSV report export
- No CMD popups; all child processes killed on stop/close

---

## Requirements

| Tool | Version | Notes |
|------|---------|-------|
| Python | 3.10+ | |
| [Tesseract OCR](https://github.com/UB-Mannheim/tesseract/wiki) | 5.x | Install to default path |
| FFmpeg | any | Auto-detected via `imageio-ffmpeg` or `C:\ffmpeg\` |
| Pillow | 9+ | `pip install pillow` |
| imageio-ffmpeg | latest | `pip install imageio-ffmpeg` |

Install Python dependencies:

```
pip install pillow imageio-ffmpeg pyinstaller
```

---

## Build EXE

```bat
build.bat
```

Or manually:

```
pyinstaller --onefile --windowed --name DVR_Extractor ^
  --collect-data imageio_ffmpeg ^
  --hidden-import PIL._tkinter_finder ^
  dvr_gui.py
```

Output: `dist\DVR_Extractor.exe`

---

## Usage

### 1. Configure sources

- **Source folder 1 / 2** — point to each recovered DVR partition folder (e.g. `G:\` or `G:\RecoveredFiles`)
- Leave Source 2 blank if only one partition

### 2. Set date range

Enter start/end dates in `MM/DD/YYYY` format.

### 3. Set camera filter

Comma-separated camera numbers, e.g. `5,8,9,12,13,15,16`.  
Leave blank to include all cameras.

### 4. Scan

Click **SCAN ALL FILES**. The scan runs in three phases:

| Phase | What happens |
|-------|-------------|
| 1 | Files discovered and counted |
| 2 | Binary search narrows to target date range (fast, ~3 min) |
| 3 | Full OCR scan of candidate files only |

Progress is saved automatically. If interrupted, restart and it resumes.

### 5. Move to Folders

After scan completes:

1. Ensure **Sort in Place — MOVE files** is checked (default)
2. The **Auto destinations** field shows where files will go (auto-derived from each source drive)
3. Click **MOVE TO FOLDERS**

Files are moved instantly using same-partition rename — no extra disk space needed.

**Output structure:**

```
G:\DVR_Sorted\
    Camera_05\
        2026-04-05\
            00001.mpg
            00002.mpg
        2026-04-06\
            ...
    Camera_16\
        ...

F:\DVR_Sorted\
    Camera_05\
        ...
```

---

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Workers | 8 | Parallel OCR threads (set to CPU core count) |
| Date subfolders | On | Creates `YYYY-MM-DD` subfolders inside each camera folder |
| Unknown cam → Review/ | On | Files with unreadable camera number go to `Review/` subfolder |
| Auto-copy after scan | Off | Starts move automatically when scan finishes |

---

## Notes

- Designed for **recovered** Hikvision MPEG-PS files (`.mpg`) from forensic HDD recovery tools
- DVR overlay timestamp OCR handles common digit misreads (0↔9, 1↔7, etc.)
- Both `MM/DD/YYYY` and `DD/MM/YYYY` date formats are detected automatically
- Camera numbers 1–64 supported

---

## License

MIT
