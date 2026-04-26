#!/usr/bin/env python3
"""
DVR Footage Extractor
=====================
GUI tool for scanning recovered Hikvision DVR footage and extracting
recordings by camera and date range — with optional camera subfolders.

Build EXE (run build.bat or):
  pip install pyinstaller pillow imageio-ffmpeg
  pyinstaller --onefile --windowed --name DVR_Extractor dvr_gui.py
"""

import os, re, csv, json, hashlib, shutil, subprocess, tempfile, sys, time
import queue, threading, concurrent.futures
from datetime import datetime, date
from pathlib import Path
from collections import defaultdict

import tkinter as tk
from tkinter import ttk, filedialog, messagebox

# Suppress CMD popup windows on Windows for all subprocess calls
_NO_WIN = 0x08000000 if sys.platform == "win32" else 0
_SI = None
if sys.platform == "win32":
    _SI = subprocess.STARTUPINFO()
    _SI.dwFlags |= subprocess.STARTF_USESHOWWINDOW

# ─────────────────────────────────────────────────────────────────────────────
#  Auto-detect tools
# ─────────────────────────────────────────────────────────────────────────────

def _find_ffmpeg():
    try:
        import imageio_ffmpeg
        p = imageio_ffmpeg.get_ffmpeg_exe()
        if p and os.path.exists(p):
            return p
    except ImportError:
        pass
    for p in [r"C:\ffmpeg\ffmpeg.exe", r"C:\ffmpeg\bin\ffmpeg.exe"]:
        if os.path.exists(p):
            return p
    return shutil.which("ffmpeg") or "ffmpeg"

def _find_tesseract():
    for p in [
        r"C:\Program Files\Tesseract-OCR\tesseract.exe",
        r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
        r"C:\Tesseract-OCR\tesseract.exe",
    ]:
        if os.path.exists(p):
            return p
    return shutil.which("tesseract") or r"C:\Program Files\Tesseract-OCR\tesseract.exe"

def _find_mpc():
    """Find Media Player Classic from K-Lite Codec Pack installation."""
    candidates = [
        # K-Lite standard paths (64-bit and 32-bit MPC-HC)
        r"C:\Program Files (x86)\K-Lite Codec Pack\MPC-HC64\mpc-hc64.exe",
        r"C:\Program Files (x86)\K-Lite Codec Pack\MPC-HC\mpc-hc.exe",
        r"C:\Program Files\K-Lite Codec Pack\MPC-HC64\mpc-hc64.exe",
        r"C:\Program Files\K-Lite Codec Pack\MPC-HC\mpc-hc.exe",
        # Standalone MPC-HC
        r"C:\Program Files\MPC-HC\mpc-hc64.exe",
        r"C:\Program Files (x86)\MPC-HC\mpc-hc.exe",
        r"C:\Program Files\MPC-BE\mpc-be64.exe",
        r"C:\Program Files (x86)\MPC-BE\mpc-be.exe",
    ]
    for p in candidates:
        if os.path.exists(p):
            return p
    # Search K-Lite start menu folder for MPC shortcut target
    klite_menu = r"C:\ProgramData\Microsoft\Windows\Start Menu\Programs\K-Lite Codec Pack"
    if os.path.isdir(klite_menu):
        for f in Path(klite_menu).rglob("*.lnk"):
            name = f.stem.lower()
            if "media player" in name or "mpc" in name:
                # Try to resolve .lnk via shell (Windows only)
                try:
                    import win32com.client
                    sh  = win32com.client.Dispatch("WScript.Shell")
                    tgt = sh.CreateShortCut(str(f)).Targetpath
                    if tgt and os.path.exists(tgt):
                        return tgt
                except Exception:
                    pass
    return None

FFMPEG    = _find_ffmpeg()
TESSERACT = _find_tesseract()
MPC       = _find_mpc()

INDEX_FILE    = "dvr_index.csv"
PROGRESS_FILE = "dvr_progress.json"

# ─────────────────────────────────────────────────────────────────────────────
#  OCR engine  (identical to extract_cam1.py)
# ─────────────────────────────────────────────────────────────────────────────

OCR_FIXES = {
    "@":"0","O":"0","o":"0","l":"1","I":"1","|":"1",
    "G":"0","g":"9","b":"6","S":"5","Z":"2","z":"2","B":"8","q":"9",
}

def _fix_ocr(text):
    chars = list(text)
    for i, ch in enumerate(chars):
        if ch in OCR_FIXES:
            prev = i > 0 and (chars[i-1].isdigit() or chars[i-1] in "-:/ ")
            nxt  = i < len(chars)-1 and (chars[i+1].isdigit() or chars[i+1] in "-:/ ")
            if prev or nxt:
                chars[i] = OCR_FIXES[ch]
    return "".join(chars)

def _coerce_date_parts(mm, dd, yyyy):
    m, d, y = int(mm), int(dd), int(yyyy)
    if not (1 <= m <= 12) and mm[0] in "96":
        m = int("0" + mm[1:])
    if not (1 <= d <= 31) and dd[0] in "96":
        d = int("0" + dd[1:])
    if not (2020 <= y <= 2030):
        y_str = list(yyyy)
        if y_str[1] in "69":
            y_str[1] = "0"
            try: y = int("".join(y_str))
            except ValueError: pass
    return m, d, y

def _coerce_time_parts(hh, mm, ss):
    """
    Fix OCR digit misreads in 24-hour time fields.
    Common misreads on DVR overlay fonts:
      '0' read as '9' or '6'  → 9x/6x → 0x   (e.g. 96:xx → 06:xx)
      '1' read as '7'         → 7x    → 1x   (e.g. 74:xx → 14:xx)
      '2' read as '8'         → 8x    → 2x   (e.g. 82:xx → 22:xx, valid in 24h)
    """
    h, m, s = int(hh), int(mm), int(ss)
    # ── hours (0-23) ──
    if h > 23:
        if hh[0] in "96": h = int("0" + hh[1:])  # 0→9/6 misread
        elif hh[0] == "7": h = int("1" + hh[1:])  # 1→7 misread
        elif hh[0] == "8":                          # 2→8 misread
            c = int("2" + hh[1:])
            if c <= 23: h = c
    # ── minutes (0-59) ──
    if m > 59:
        if mm[0] in "96": m = int("0" + mm[1:])
        elif mm[0] == "7": m = int("1" + mm[1:])
    # ── seconds (0-59) ──
    if s > 59:
        if ss[0] in "96": s = int("0" + ss[1:])
        elif ss[0] == "7": s = int("1" + ss[1:])
    return h, m, s

def _try_date(a, b, yyyy):
    """Try to build a valid date from two fields — tries both MM/DD and DD/MM."""
    candidates = [(a, b), (b, a)]  # (month_candidate, day_candidate)
    for mc, dc in candidates:
        try:
            mo, dy, yr = _coerce_date_parts(mc, dc, yyyy)
            if not (2020 <= yr <= 2030): continue
            if not (1 <= mo <= 12):      continue
            if not (1 <= dy <= 31):      continue
            datetime(yr, mo, dy)         # validate calendar (e.g. no Feb 30)
            return mo, dy, yr
        except (ValueError, IndexError):
            continue
    return None, None, None

def _parse_datetime(text):
    text = _fix_ocr(text)
    for pat in [
        r'(\d{2})[-/.](\d{2})[-/.](\d{4})\s+\w*\s*(\d{2}):(\d{2}):(\d{2})',
        r'(\d{2})[-/.](\d{2})[-/.](\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
        r'(\d{2})[-/.](\d{2})[-/.](\d{4})\s+\w*\s*(\d{2}):(\d{2})',
        r'(\d{2})[-/.](\d{2})[-/.](\d{4})',
    ]:
        m = re.search(pat, text)
        if m:
            g = m.groups()
            try:
                mo, dy, yr = _try_date(g[0], g[1], g[2])
                if mo is None: continue
                hr, mi, sc = _coerce_time_parts(
                    g[3] if len(g) > 3 else "00",
                    g[4] if len(g) > 4 else "00",
                    g[5] if len(g) > 5 else "00",
                )
                if hr > 23 or mi > 59 or sc > 59: continue
                dt = datetime(yr, mo, dy, hr, mi, sc)
                return dt, dt.strftime("%Y-%m-%d %H:%M:%S")
            except (ValueError, IndexError): continue
    return None, None

def _parse_camera(text, from_cam_crop=False):
    text = _fix_ocr(text)
    for pat in [r'Camera\s+0*(\d+)', r'Cam\s*0*(\d+)', r'CAM\s*0*(\d+)']:
        m = re.search(pat, text, re.IGNORECASE)
        if m:
            n = int(m.group(1))
            if 1 <= n <= 64: return n
    m = re.search(r'[Cc][a-z]{1,5}\s+[a-z]*\s*0*(\d{1,2})\b', text)
    if m:
        n = int(m.group(1))
        if 1 <= n <= 64: return n
    if from_cam_crop:
        nums = re.findall(r'\b0*(\d{1,2})\b', text)
        valid = [int(n) for n in nums if 1 <= int(n) <= 64]
        if len(valid) == 1: return valid[0]
        if len(valid) > 1: return valid[-1]
    return None

def _frame_is_real(tmp_path):
    from PIL import Image
    if not os.path.exists(tmp_path): return None
    if os.path.getsize(tmp_path) < 30_000: return None
    img = Image.open(tmp_path)
    gray = img.convert("L")
    avg = sum(gray.get_flattened_data()) / (img.width * img.height)
    if avg < 10: return None
    return img.copy()

def _extract_frame(video_path, seconds, timeout=8):
    ts  = f"00:00:{seconds:02d}"
    tmp = tempfile.mktemp(suffix=".png")
    try:
        subprocess.run(
            [FFMPEG, "-ss", ts, "-i", video_path, "-vframes","1","-update","1","-y", tmp],
            capture_output=True, timeout=timeout, encoding="utf-8", errors="ignore",
            stdin=subprocess.DEVNULL,
            creationflags=_NO_WIN, startupinfo=_SI,
        )
        return _frame_is_real(tmp)
    except Exception:
        return None
    finally:
        try: os.unlink(tmp)
        except OSError: pass

def _date_only_from_frame(img):
    """OCR date strip only — no camera detection, used by binary search."""
    w, h = img.size
    date_tight = img.crop((0, int(h*.06), int(w*.65), int(h*.10)))
    date_wide  = img.crop((0, 0,          int(w*.65), int(h*.09)))
    dt, dt_str = _parse_datetime(_run_tess(_enhance_wt(date_tight), psm=7))
    if not dt:
        dt, dt_str = _parse_datetime(_run_tess(_enhance_wt(date_wide), psm=11))
    return dt, dt_str

def _analyze_file_fast(filepath):
    for sec in [5, 10, 30]:
        img = _extract_frame(filepath, sec, timeout=6)
        if img is None: continue
        try:
            dt, dt_str = _date_only_from_frame(img)
            if dt:
                return {"date": dt.strftime("%Y-%m-%d")}
        except Exception: pass
    return None

def _run_tess(image, psm=11):
    tmp_in  = tempfile.mktemp(suffix=".png")
    tmp_out = tempfile.mktemp()
    try:
        image.save(tmp_in)
        subprocess.run(
            [TESSERACT, tmp_in, tmp_out, "-l", "eng", "--psm", str(psm)],
            capture_output=True, timeout=5, encoding="utf-8", errors="ignore",
            creationflags=_NO_WIN, startupinfo=_SI,
        )
        rf = tmp_out + ".txt"
        if os.path.exists(rf):
            with open(rf, encoding="utf-8", errors="ignore") as f:
                return f.read().strip()
    except Exception: pass
    finally:
        for p in [tmp_in, tmp_out+".txt"]:
            try: os.unlink(p)
            except OSError: pass
    return ""

def _enhance(img):
    from PIL import Image, ImageFilter, ImageEnhance
    img = img.resize((img.width*3, img.height*3), Image.LANCZOS)
    img = ImageEnhance.Contrast(img).enhance(3.0)
    return img.filter(ImageFilter.SHARPEN)

def _enhance_wt(img, threshold=160):
    from PIL import Image, ImageFilter
    img  = img.resize((img.width*3, img.height*3), Image.LANCZOS)
    gray = img.convert("L")
    t    = gray.point(lambda p: 0 if p > threshold else 255)
    return t.filter(ImageFilter.MinFilter(3))

def _ocr_frame(img):
    w, h = img.size
    date_wide  = img.crop((0,            0,           int(w*.65), int(h*.09)))
    date_tight = img.crop((0,            int(h*.06),  int(w*.65), int(h*.10)))
    cam_right  = img.crop((int(w*.35),   int(h*.85),  w,          h))
    cam_full   = img.crop((0,            int(h*.85),  w,          h))
    cam_left   = img.crop((0,            int(h*.85),  int(w*.65), h))

    dt = dt_str = cam = None

    # ── Strategy 1: white-threshold, three brightness levels for camera ──
    tw = _run_tess(_enhance_wt(date_tight), psm=7)
    ww = _run_tess(_enhance_wt(date_wide),  psm=11)
    for thr in (160, 120, 200):
        cr = _run_tess(_enhance_wt(cam_right, thr), psm=11)
        cf = _run_tess(_enhance_wt(cam_full,  thr), psm=11)
        cl = _run_tess(_enhance_wt(cam_left,  thr), psm=11)
        cam = (_parse_camera(cr, True) or _parse_camera(cf, True) or _parse_camera(cl, True))
        if cam: break
    dt, dt_str = _parse_datetime(tw)
    if not dt: dt, dt_str = _parse_datetime(ww)
    if dt and cam: return dt, dt_str, cam

    # ── Strategy 2: contrast enhance ──
    tc = _run_tess(_enhance(date_tight), psm=7)
    wc = _run_tess(_enhance(date_wide),  psm=11)
    cr = _run_tess(_enhance(cam_right),  psm=11)
    cf = _run_tess(_enhance(cam_full),   psm=11)
    cl = _run_tess(_enhance(cam_left),   psm=11)
    if not dt: dt, dt_str = _parse_datetime(tc)
    if not dt: dt, dt_str = _parse_datetime(wc)
    if not cam:
        cam = (_parse_camera(cr, True) or _parse_camera(cf, True) or _parse_camera(cl, True)
               or _parse_camera(tc) or _parse_camera(wc))
    if dt and cam: return dt, dt_str, cam

    # ── Strategy 3: full frame fallback ──
    full = _run_tess(_enhance(img), psm=11)
    if not dt: dt, dt_str = _parse_datetime(full)
    if not cam: cam = _parse_camera(full)
    return dt, dt_str, cam

def _analyze_file(filepath):
    offsets = [5, 15, 60]
    for sec in offsets:
        img = _extract_frame(filepath, sec)
        if img is None: continue
        try:
            dt, dt_str, cam = _ocr_frame(img)
            if dt:
                return {
                    "filename": Path(filepath).name,
                    "filepath": filepath,
                    "camera":   cam,
                    "date":     dt.strftime("%Y-%m-%d"),
                    "time":     dt.strftime("%H:%M:%S"),
                    "datetime": dt_str,
                }
        except Exception: pass
    return None


def _find_date_range(files, start_date, end_date,
                     status_cb=None, progress_cb=None, workers=4):
    """
    Binary-search sorted file list for the slice covering start_date..end_date.
    Returns (lo_idx, hi_idx) with a safety margin of 300 files on each side.
    progress_cb(current_idx, total) is called after each probe for live progress.
    """
    n = len(files)

    def probe(idx, phase_label):
        for off in [0, 3, -3, 8, -8]:
            i = idx + off
            if 0 <= i < n:
                r = _analyze_file_fast(str(files[i]))
                if progress_cb: progress_cb(i, n, phase_label)
                if r:
                    return datetime.strptime(r["date"], "%Y-%m-%d").date(), i
        return None, idx

    # ── Find left boundary ──
    if status_cb: status_cb("Locating start of target date range…")
    lo, hi = 0, n - 1
    left = 0
    while lo <= hi:
        mid = (lo + hi) // 2
        d, actual = probe(mid, "Finding start")
        if d is None:
            lo = mid + 1
            continue
        if d >= start_date:
            left = actual
            hi = mid - 1
        else:
            lo = mid + 1

    # ── Find right boundary ──
    if status_cb: status_cb("Locating end of target date range…")
    lo, hi = 0, n - 1
    right = n - 1
    while lo <= hi:
        mid = (lo + hi) // 2
        d, actual = probe(mid, "Finding end")
        if d is None:
            hi = mid - 1
            continue
        if d <= end_date:
            right = actual
            lo = mid + 1
        else:
            hi = mid - 1

    margin = 300
    lo_idx = max(0,   left  - margin)
    hi_idx = min(n-1, right + margin)
    count  = hi_idx - lo_idx + 1
    if status_cb: status_cb(
        f"Range found — scanning {count:,} candidate files (of {n:,} total)…"
    )
    return lo_idx, hi_idx

# ─────────────────────────────────────────────────────────────────────────────
#  GUI
# ─────────────────────────────────────────────────────────────────────────────

class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("DVR Footage Extractor")
        self.geometry("1050x720")
        self.minsize(880, 580)

        self._q              = queue.Queue()
        self._stop           = threading.Event()
        self._results        = []
        self._processed      = set()
        self._all_rows       = []
        self._sort_col       = None
        self._sort_rev       = False
        self._executor       = None
        self._scan_start_t   = None
        self._log_lines      = 0

        self._build_ui()
        self._on_sort_inplace_toggle()   # apply default state (sort-in-place on)
        self.protocol("WM_DELETE_WINDOW", self._on_close)
        self._load_index_silent()
        self._poll()

    # ── UI construction ───────────────────────────────────────────────────────

    def _build_ui(self):
        s = ttk.Style(self)
        s.theme_use("clam")
        BG = "#f4f6f9"
        self.configure(bg=BG)
        s.configure("TFrame",       background=BG)
        s.configure("TLabelframe",  background=BG)
        s.configure("TLabelframe.Label", background=BG, font=("Segoe UI", 9, "bold"), foreground="#334155")
        s.configure("TLabel",       background=BG, font=("Segoe UI", 9))
        s.configure("TEntry",       font=("Segoe UI", 9))
        s.configure("TButton",      font=("Segoe UI", 9))
        s.configure("TCheckbutton", background=BG, font=("Segoe UI", 9))
        s.configure("Treeview",     font=("Consolas", 9), rowheight=21, background="white",
                                    fieldbackground="white")
        s.configure("Treeview.Heading", font=("Segoe UI", 9, "bold"))
        s.map("Treeview", background=[("selected", "#bfdbfe")])

        # ── Config panel ──────────────────────────────────────────────────────
        cfg = ttk.LabelFrame(self, text=" Configuration ", padding=(10, 6))
        cfg.pack(fill="x", padx=10, pady=(8, 4))
        cfg.columnconfigure(1, weight=1)

        def lbl(parent, text, row, col, **kw):
            ttk.Label(parent, text=text).grid(row=row, column=col, sticky="w",
                                              padx=(0, 6), pady=2, **kw)

        lbl(cfg, "Source folder 1:", 0, 0)
        self.v_src = tk.StringVar(value=r"G:\NewTask_20260419_212151")
        self.v_src.trace_add("write", lambda *_: self._on_src_changed())
        ttk.Entry(cfg, textvariable=self.v_src).grid(row=0, column=1, sticky="ew", padx=4, pady=2)
        ttk.Button(cfg, text="Browse…", width=9,
                   command=lambda: self._browse(self.v_src)).grid(row=0, column=2, padx=4, pady=2)

        lbl(cfg, "Source folder 2:", 1, 0)
        self.v_src2 = tk.StringVar(value="")
        self.v_src2.trace_add("write", lambda *_: self._on_src_changed())
        ttk.Entry(cfg, textvariable=self.v_src2).grid(row=1, column=1, sticky="ew", padx=4, pady=2)
        ttk.Button(cfg, text="Browse…", width=9,
                   command=lambda: self._browse(self.v_src2)).grid(row=1, column=2, padx=4, pady=2)

        self.v_sort_inplace = tk.BooleanVar(value=True)
        self._lbl_dst = ttk.Label(cfg, text="Destination:")
        self._lbl_dst.grid(row=2, column=0, sticky="w", padx=(0, 6), pady=2)
        self.v_dst = tk.StringVar()
        self._ent_dst = ttk.Entry(cfg, textvariable=self.v_dst)
        self._ent_dst.grid(row=2, column=1, sticky="ew", padx=4, pady=2)
        self._btn_dst = ttk.Button(cfg, text="Browse…", width=9,
                   command=lambda: self._browse(self.v_dst, must_exist=False))
        self._btn_dst.grid(row=2, column=2, padx=4, pady=2)

        # Filters row
        fr = ttk.Frame(cfg)
        fr.grid(row=3, column=0, columnspan=3, sticky="w", pady=(4, 2))

        def fp(label, var, width=11):
            ttk.Label(fr, text=label).pack(side="left", padx=(0, 3))
            ttk.Entry(fr, textvariable=var, width=width).pack(side="left", padx=(0, 14))

        self.v_start   = tk.StringVar(value="04/05/2026")
        self.v_end     = tk.StringVar(value="04/10/2026")
        self.v_cameras = tk.StringVar(value="")
        self.v_workers = tk.IntVar(value=8)
        fp("Start date (MM/DD/YYYY):", self.v_start)
        fp("End date:", self.v_end)
        fp("Cameras (blank=all, e.g. 1,2):", self.v_cameras, width=12)
        ttk.Label(fr, text="Workers:").pack(side="left", padx=(0, 3))
        ttk.Spinbox(fr, textvariable=self.v_workers, from_=1, to=32, width=4).pack(side="left")

        # Options row
        op = ttk.Frame(cfg)
        op.grid(row=4, column=0, columnspan=3, sticky="w", pady=(2, 4))
        self.v_date_sub   = tk.BooleanVar(value=True)
        self.v_review     = tk.BooleanVar(value=True)
        self.v_auto_copy  = tk.BooleanVar(value=False)
        ttk.Label(op, text="Options:").pack(side="left")
        ttk.Checkbutton(op, text="Sort in Place — MOVE files, zero disk space",
                        variable=self.v_sort_inplace,
                        command=self._on_sort_inplace_toggle).pack(side="left", padx=(8, 0))
        ttk.Checkbutton(op, text="Date subfolders",
                        variable=self.v_date_sub).pack(side="left", padx=(12, 0))
        ttk.Checkbutton(op, text="Unknown cam → Review/",
                        variable=self.v_review).pack(side="left", padx=(12, 0))
        ttk.Checkbutton(op, text="★ Auto-copy after scan",
                        variable=self.v_auto_copy).pack(side="left", padx=(16, 0))

        # ── Action bar ────────────────────────────────────────────────────────
        ab = ttk.Frame(self)
        ab.pack(fill="x", padx=10, pady=4)

        def btn(parent, text, cmd, bg, fg="white", side="left", pad=(0, 6)):
            b = tk.Button(parent, text=text, command=cmd, bg=bg, fg=fg,
                          font=("Segoe UI", 9, "bold"), relief="flat",
                          padx=12, pady=5, cursor="hand2", activebackground=bg)
            b.pack(side=side, padx=pad)
            return b

        btn(ab, "  SCAN ALL FILES  ",   self._start_scan,       "#16a34a")
        self._btn_action = btn(ab, "  MOVE TO FOLDERS  ", self._start_copy, "#2563eb")
        btn(ab, "  STOP  ",             self._do_stop,         "#dc2626", pad=(0, 18))
        btn(ab, "Camera Summary",       self._show_cam_summary,"#7c3aed", fg="white", pad=(0, 6))
        btn(ab, "Export Report",        self._export_report,   "#0f766e", fg="white", pad=(0, 6))
        btn(ab, "Load Index",           self._load_index,      "#64748b", fg="white", pad=(0, 6))
        btn(ab, "Clear",                self._clear,           "#94a3b8", fg="white", pad=(0, 0))

        self.lbl_status = ttk.Label(ab, text="Ready", foreground="#475569")
        self.lbl_status.pack(side="right", padx=8)

        # ── Progress bar ──────────────────────────────────────────────────────
        pb_frame = ttk.Frame(self)
        pb_frame.pack(fill="x", padx=10, pady=(0, 4))
        self.v_prog = tk.DoubleVar()
        self.prog   = ttk.Progressbar(pb_frame, variable=self.v_prog, maximum=100)
        self.prog.pack(side="left", fill="x", expand=True, ipady=1)
        self.lbl_prog = ttk.Label(pb_frame, text="", width=18, anchor="e")
        self.lbl_prog.pack(side="right")

        # ── Filter bar ────────────────────────────────────────────────────────
        fb = ttk.Frame(self)
        fb.pack(fill="x", padx=10, pady=(0, 2))
        ttk.Label(fb, text="Filter table →  Camera:").pack(side="left")
        self.v_f_cam   = tk.StringVar()
        ttk.Entry(fb, textvariable=self.v_f_cam,   width=10).pack(side="left", padx=(3, 10))
        ttk.Label(fb, text="Date from:").pack(side="left")
        self.v_f_start = tk.StringVar()
        ttk.Entry(fb, textvariable=self.v_f_start, width=11).pack(side="left", padx=(3, 6))
        ttk.Label(fb, text="to:").pack(side="left")
        self.v_f_end   = tk.StringVar()
        ttk.Entry(fb, textvariable=self.v_f_end,   width=11).pack(side="left", padx=(3, 8))
        ttk.Button(fb, text="Apply", command=self._apply_filter).pack(side="left")
        ttk.Button(fb, text="Reset", command=self._reset_filter).pack(side="left", padx=(4, 0))
        self.lbl_count = ttk.Label(fb, text="", foreground="#475569")
        self.lbl_count.pack(side="right", padx=4)

        # ── Main paned area (Results table + Log panel) ───────────────────────
        main_paned = ttk.PanedWindow(self, orient=tk.VERTICAL)
        main_paned.pack(fill="both", expand=True, padx=10, pady=(0, 2))

        # ── Upper pane: results table ──────────────────────────────────────────
        tbl = ttk.LabelFrame(main_paned, text=" Scan Results ", padding=(4, 4))
        main_paned.add(tbl, weight=3)
        tbl.rowconfigure(0, weight=1)
        tbl.columnconfigure(0, weight=1)

        cols = ("filename", "camera", "date", "time", "filepath")
        hdrs = {"filename":"Filename","camera":"Camera","date":"Date",
                "time":"Time","filepath":"File Path"}
        widths = {"filename":115,"camera":90,"date":95,"time":80,"filepath":500}

        self.tree = ttk.Treeview(tbl, columns=cols, show="headings", selectmode="extended")
        for c in cols:
            self.tree.heading(c, text=hdrs[c],
                              command=lambda _c=c: self._sort_col(_c))
            self.tree.column(c, width=widths[c], minwidth=50)

        self.tree.tag_configure("unknown", foreground="#94a3b8")
        self.tree.tag_configure("evenrow", background="#f8fafc")

        vs = ttk.Scrollbar(tbl, orient="vertical",   command=self.tree.yview)
        hs = ttk.Scrollbar(tbl, orient="horizontal", command=self.tree.xview)
        self.tree.configure(yscrollcommand=vs.set, xscrollcommand=hs.set)
        self.tree.grid(row=0, column=0, sticky="nsew")
        vs.grid(row=0, column=1, sticky="ns")
        hs.grid(row=1, column=0, sticky="ew")

        self.tree.bind("<Double-1>", self._play_file)

        self._ctx = tk.Menu(self, tearoff=0)
        play_label = "▶  Play in Media Player Classic"
        if not MPC:
            play_label += "  (not found)"
        self._ctx.add_command(label=play_label,           command=self._play_file)
        self._ctx.add_separator()
        self._ctx.add_command(label="Open file location", command=self._open_location)
        self._ctx.add_command(label="Copy filename",      command=self._copy_filename)
        self._ctx.add_command(label="Copy full path",     command=self._copy_path)
        self.tree.bind("<Button-3>", self._show_ctx)

        # ── Lower pane: activity log ───────────────────────────────────────────
        log_frame = ttk.LabelFrame(main_paned, text=" Activity Log ", padding=(4, 4))
        main_paned.add(log_frame, weight=1)
        log_frame.rowconfigure(0, weight=1)
        log_frame.columnconfigure(0, weight=1)

        self.log_txt = tk.Text(
            log_frame, height=7, wrap="none",
            bg="#1e293b", fg="#e2e8f0",
            font=("Consolas", 8), state="disabled",
            insertbackground="white", selectbackground="#334155",
        )
        log_vs = ttk.Scrollbar(log_frame, orient="vertical",   command=self.log_txt.yview)
        log_hs = ttk.Scrollbar(log_frame, orient="horizontal", command=self.log_txt.xview)
        self.log_txt.configure(yscrollcommand=log_vs.set, xscrollcommand=log_hs.set)
        self.log_txt.grid(row=0, column=0, sticky="nsew")
        log_vs.grid(row=0, column=1, sticky="ns")
        log_hs.grid(row=1, column=0, sticky="ew")

        # colour tags
        self.log_txt.tag_config("TIME",    foreground="#475569")
        self.log_txt.tag_config("INFO",    foreground="#94a3b8")
        self.log_txt.tag_config("FOUND",   foreground="#4ade80")
        self.log_txt.tag_config("COPY",    foreground="#60a5fa")
        self.log_txt.tag_config("HLINK",   foreground="#38bdf8")
        self.log_txt.tag_config("MOVE",    foreground="#fb923c")
        self.log_txt.tag_config("ERROR",   foreground="#f87171")
        self.log_txt.tag_config("WARN",    foreground="#fbbf24")
        self.log_txt.tag_config("SUCCESS", foreground="#4ade80")
        self.log_txt.tag_config("PLAY",    foreground="#c084fc")
        self.log_txt.tag_config("SKIP",    foreground="#4b5563")

        # log button bar
        log_ab = ttk.Frame(log_frame)
        log_ab.grid(row=2, column=0, columnspan=2, sticky="ew", pady=(3, 0))
        tk.Button(log_ab, text="Clear Log", command=self._clear_log,
                  bg="#334155", fg="#e2e8f0", font=("Segoe UI", 8),
                  relief="flat", padx=8, pady=2).pack(side="left", padx=(0, 4))
        tk.Button(log_ab, text="Save Log", command=self._save_log,
                  bg="#334155", fg="#e2e8f0", font=("Segoe UI", 8),
                  relief="flat", padx=8, pady=2).pack(side="left")
        self.lbl_log_stat = ttk.Label(log_ab, text="", foreground="#64748b",
                                       font=("Segoe UI", 8))
        self.lbl_log_stat.pack(side="right", padx=4)

        # ── Footer ────────────────────────────────────────────────────────────
        self.lbl_footer = ttk.Label(self, text="", anchor="w",
                                     foreground="#64748b", font=("Segoe UI", 8))
        self.lbl_footer.pack(fill="x", padx=12, pady=(0, 4))

    # ── Log helpers ───────────────────────────────────────────────────────────

    def _log(self, level, msg):
        """Thread-safe: put log message on queue for _poll to render."""
        ts = datetime.now().strftime("%H:%M:%S")
        self._q.put(("log", level, ts, msg))

    def _log_to_widget(self, level, ts, msg):
        """Called from main thread (_poll) to write a log line."""
        MAX_LINES = 3000
        self.log_txt.config(state="normal")
        if self._log_lines >= MAX_LINES:
            self.log_txt.delete("1.0", "500.end+1c")
            self._log_lines -= 500
        self.log_txt.insert("end", f"[{ts}] ", "TIME")
        label = f"[{level:<7}] "
        self.log_txt.insert("end", label, level)
        self.log_txt.insert("end", msg + "\n", level)
        self.log_txt.config(state="disabled")
        self.log_txt.see("end")
        self._log_lines += 1
        self.lbl_log_stat.config(text=f"{self._log_lines} lines")

    def _clear_log(self):
        self.log_txt.config(state="normal")
        self.log_txt.delete("1.0", "end")
        self.log_txt.config(state="disabled")
        self._log_lines = 0
        self.lbl_log_stat.config(text="")

    def _save_log(self):
        path = filedialog.asksaveasfilename(
            title="Save Activity Log",
            defaultextension=".txt",
            filetypes=[("Text files", "*.txt"), ("All files", "*.*")],
            initialfile=f"dvr_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt",
        )
        if not path: return
        try:
            content = self.log_txt.get("1.0", "end")
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            self._log("SUCCESS", f"Log saved → {path}")
        except Exception as e:
            messagebox.showerror("Save Error", str(e))

    def _export_report(self):
        if not self._results:
            messagebox.showwarning("No Data", "Run SCAN first.")
            return
        path = filedialog.asksaveasfilename(
            title="Export Report",
            defaultextension=".html",
            filetypes=[("HTML report", "*.html"), ("CSV", "*.csv"), ("All files", "*.*")],
            initialfile=f"dvr_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.html",
        )
        if not path: return
        try:
            if path.lower().endswith(".csv"):
                rows = sorted(self._results,
                              key=lambda r: (str(r.get("camera","")), r.get("datetime","")))
                with open(path, "w", newline="", encoding="utf-8-sig") as f:
                    w = csv.DictWriter(f, fieldnames=["filename","camera","date","time","datetime","filepath"])
                    w.writeheader(); w.writerows(rows)
            else:
                self._write_html_report(path)
            self._log("SUCCESS", f"Report exported → {path}")
            messagebox.showinfo("Exported", f"Report saved:\n{path}")
        except Exception as e:
            messagebox.showerror("Export Error", str(e))

    def _write_html_report(self, path):
        by_cam = defaultdict(list)
        for r in self._results:
            c = r.get("camera")
            by_cam[c if c else 0].append(r)

        rows_html = ""
        for r in sorted(self._results, key=lambda x: (str(x.get("camera","")), x.get("datetime",""))):
            c = r.get("camera")
            cam_lbl = f"Camera {c:02d}" if c else "UNKNOWN"
            rows_html += (
                f"<tr><td>{r.get('filename','')}</td><td>{cam_lbl}</td>"
                f"<td>{r.get('date','')}</td><td>{r.get('time','')}</td>"
                f"<td style='font-size:11px'>{r.get('filepath','')}</td></tr>\n"
            )

        summary_html = ""
        for cam in sorted(by_cam.keys()):
            items = by_cam[cam]
            dates = sorted(set(r.get("date","") for r in items))
            lbl = f"Camera {cam:02d}" if cam else "UNKNOWN"
            summary_html += (
                f"<tr><td>{lbl}</td><td>{len(items)}</td>"
                f"<td>{dates[0] if dates else '?'}</td>"
                f"<td>{dates[-1] if dates else '?'}</td>"
                f"<td>~{len(items)*6/60:.1f} h</td></tr>\n"
            )

        html = f"""<!DOCTYPE html><html><head><meta charset="utf-8">
<title>DVR Footage Report</title>
<style>
body{{font-family:Segoe UI,sans-serif;background:#f8fafc;color:#1e293b;margin:24px}}
h1{{color:#0f172a}}h2{{color:#334155;margin-top:28px}}
table{{border-collapse:collapse;width:100%;margin-top:8px}}
th{{background:#334155;color:white;padding:7px 10px;text-align:left}}
td{{padding:5px 10px;border-bottom:1px solid #e2e8f0;font-size:13px}}
tr:hover td{{background:#f1f5f9}}
.badge{{background:#16a34a;color:white;border-radius:4px;padding:2px 8px;font-size:12px}}
</style></head><body>
<h1>DVR Footage Extractor — Report</h1>
<p>Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} &nbsp;|&nbsp;
Total files: <span class="badge">{len(self._results)}</span></p>
<h2>Camera Summary</h2>
<table><tr><th>Camera</th><th>Files</th><th>First Recording</th><th>Last Recording</th><th>Est. Duration</th></tr>
{summary_html}</table>
<h2>All Files</h2>
<table><tr><th>Filename</th><th>Camera</th><th>Date</th><th>Time</th><th>File Path</th></tr>
{rows_html}</table>
</body></html>"""
        with open(path, "w", encoding="utf-8") as f:
            f.write(html)

    def _on_src_changed(self):
        if self.v_sort_inplace.get():
            self._update_sort_dest_preview()

    # ── Sort-in-place toggle ──────────────────────────────────────────────────

    def _on_sort_inplace_toggle(self):
        if self.v_sort_inplace.get():
            self._btn_dst.config(state="disabled")
            self._ent_dst.config(state="disabled")
            self.v_date_sub.set(True)
            self._update_sort_dest_preview()
            self._btn_action.config(text="  MOVE TO FOLDERS  ", bg="#ea580c")
        else:
            self._lbl_dst.config(text="Destination:")
            self._btn_dst.config(state="normal")
            self._ent_dst.config(state="normal")
            self._btn_action.config(text="  COPY ALL CAMERAS  ", bg="#2563eb")

    def _update_sort_dest_preview(self):
        """Show auto-computed sort destinations in the (disabled) dest field."""
        drives = []
        for sv in [self.v_src, self.v_src2]:
            raw = sv.get().strip()
            if raw and os.path.isdir(raw):
                d = Path(raw).drive.upper()
                if d and d not in drives:
                    drives.append(d)
        if drives:
            preview = "  |  ".join(f"{d}\\DVR_Sorted" for d in drives)
        else:
            preview = "[Drive]:\\DVR_Sorted  (auto)"
        self._lbl_dst.config(text="Auto destinations:")
        self._ent_dst.config(state="normal")
        self.v_dst.set(preview)
        self._ent_dst.config(state="disabled")

    # ── Browse helpers ────────────────────────────────────────────────────────

    def _browse(self, var, must_exist=True):
        init = var.get() if var.get() and os.path.isdir(var.get()) else "/"
        d = filedialog.askdirectory(title="Select folder", initialdir=init)
        if d:
            var.set(d)

    # ── Table management ──────────────────────────────────────────────────────

    def _add_row(self, r, check_even=True):
        cam = r.get("camera")
        cam_lbl = f"Camera {cam:02d}  (Ch.{cam})" if cam else "--- UNKNOWN ---"
        tag = "unknown" if not cam else ("evenrow" if check_even and len(self.tree.get_children())%2 else "")
        iid = self.tree.insert("", "end",
                               values=(r["filename"], cam_lbl, r.get("date",""),
                                       r.get("time",""), r.get("filepath","")),
                               tags=(tag,))
        return iid

    def _refresh_table(self, rows):
        self.tree.delete(*self.tree.get_children())
        self._all_rows = []
        for i, r in enumerate(rows):
            iid = self._add_row(r, check_even=(i%2==0))
            self._all_rows.append(iid)
        self._update_footer()

    def _update_footer(self):
        total = len(self._results)
        by_cam = defaultdict(int)
        for r in self._results:
            c = r.get("camera")
            by_cam[f"Cam {c:02d}" if c else "Unknown"] += 1
        parts = [f"{k}: {v}" for k, v in sorted(by_cam.items())]
        self.lbl_footer.config(text=f"Total scanned: {total}   |   " + "   ".join(parts))
        self.lbl_count.config(text=f"{len(self.tree.get_children()):,} rows shown")

    def _sort_col(self, col):
        rev = (self._sort_col == col and not self._sort_rev)
        self._sort_col = col
        self._sort_rev = rev
        items = [(self.tree.set(k, col), k) for k in self.tree.get_children("")]
        items.sort(reverse=rev)
        for i, (_, k) in enumerate(items):
            self.tree.move(k, "", i)

    def _apply_filter(self):
        cam_f   = self.v_f_cam.get().strip()
        start_f = self.v_f_start.get().strip()
        end_f   = self.v_f_end.get().strip()

        cam_set = None
        if cam_f:
            try:
                cam_set = {int(x) for x in re.split(r"[,\s]+", cam_f) if x}
            except ValueError:
                messagebox.showerror("Filter", "Camera filter must be numbers")
                return

        start_d = end_d = None
        try:
            if start_f: start_d = datetime.strptime(start_f, "%m/%d/%Y").date()
            if end_f:   end_d   = datetime.strptime(end_f,   "%m/%d/%Y").date()
        except ValueError:
            messagebox.showerror("Filter", "Date format must be MM/DD/YYYY")
            return

        filtered = []
        for r in self._results:
            c = r.get("camera")
            if cam_set is not None:
                if c not in cam_set:
                    continue
            if start_d or end_d:
                try:
                    rd = datetime.strptime(r["date"], "%Y-%m-%d").date()
                    if start_d and rd < start_d: continue
                    if end_d   and rd > end_d:   continue
                except (ValueError, KeyError):
                    continue
            filtered.append(r)

        self._refresh_table(filtered)
        self.lbl_count.config(text=f"{len(filtered):,} rows (filtered)")

    def _reset_filter(self):
        self.v_f_cam.set("")
        self.v_f_start.set("")
        self.v_f_end.set("")
        self._refresh_table(self._results)

    # ── Context menu ──────────────────────────────────────────────────────────

    def _show_ctx(self, event):
        iid = self.tree.identify_row(event.y)
        if iid:
            self.tree.selection_set(iid)
            self._ctx.post(event.x_root, event.y_root)

    def _play_file(self, event=None):
        sel = self.tree.selection()
        if not sel: return
        fp = self.tree.set(sel[0], "filepath")
        fname = self.tree.set(sel[0], "filename")
        if not fp:
            messagebox.showwarning("No Path", "No file path in this record.")
            return
        if not os.path.exists(fp):
            self._log("WARN", f"File not found: {fp}")
            ans = messagebox.askyesno(
                "File Not Found",
                f"File not found at:\n{fp}\n\n"
                "The drive may be mounted with a different letter.\n"
                "Browse to find the file?",
            )
            if ans:
                new_fp = filedialog.askopenfilename(
                    title="Locate the file",
                    initialfile=Path(fp).name,
                    filetypes=[("Video files", "*.mpg *.mpeg *.mp4 *.avi *"),
                               ("All files", "*.*")],
                )
                if new_fp:
                    fp = new_fp
                else:
                    return
            else:
                return
        try:
            if MPC and os.path.exists(MPC):
                subprocess.Popen([MPC, fp], creationflags=_NO_WIN, startupinfo=_SI)
                self._log("PLAY", f"{fname}  →  MPC-HC")
            else:
                os.startfile(fp)
                self._log("PLAY", f"{fname}  →  default player")
        except Exception as e:
            self._log("ERROR", f"Cannot open {fname}: {e}")
            messagebox.showerror("Cannot Open", f"Failed to open file:\n{e}")

    def _open_location(self):
        sel = self.tree.selection()
        if not sel: return
        fp = self.tree.set(sel[0], "filepath")
        if fp and os.path.exists(fp):
            # Select the file in Explorer
            subprocess.Popen(
                ["explorer", "/select,", fp],
                creationflags=_NO_WIN, startupinfo=_SI,
            )

    def _copy_filename(self):
        sel = self.tree.selection()
        if not sel: return
        self.clipboard_clear()
        self.clipboard_append(self.tree.set(sel[0], "filename"))

    def _copy_path(self):
        sel = self.tree.selection()
        if not sel: return
        self.clipboard_clear()
        self.clipboard_append(self.tree.set(sel[0], "filepath"))

    # ── Load index ────────────────────────────────────────────────────────────

    def _load_index_silent(self):
        if not os.path.exists(INDEX_FILE): return
        try:
            self._load_from_file(INDEX_FILE)
        except Exception: pass

    def _load_index(self):
        path = filedialog.askopenfilename(
            title="Open index CSV",
            defaultextension=".csv",
            filetypes=[("CSV files","*.csv"),("All files","*.*")],
            initialfile=INDEX_FILE,
        )
        if not path: return
        try:
            self._load_from_file(path)
            self.lbl_status.config(text=f"Loaded {len(self._results)} records")
        except Exception as e:
            messagebox.showerror("Load Error", str(e))

    def _load_from_file(self, path):
        # Parse the current date filter so we can apply it to loaded rows
        try:
            filt_start = datetime.strptime(self.v_start.get().strip(), "%m/%d/%Y").date()
            filt_end   = datetime.strptime(self.v_end.get().strip(),   "%m/%d/%Y").date()
        except ValueError:
            filt_start = filt_end = None   # no filter if dates are invalid

        with open(path, encoding="utf-8-sig") as f:
            rows = list(csv.DictReader(f))
        self._results = []
        self._processed = set()
        skipped = 0
        for r in rows:
            # Apply date filter
            if filt_start and filt_end:
                try:
                    rd = datetime.strptime(r["date"], "%Y-%m-%d").date()
                    if not (filt_start <= rd <= filt_end):
                        skipped += 1
                        continue
                except (ValueError, KeyError):
                    skipped += 1
                    continue
            raw = r.get("camera", "")
            try:
                r["camera"] = int(raw) if raw and raw not in ("None", "") else None
            except ValueError:
                r["camera"] = None
            self._results.append(r)
        self._refresh_table(self._results)
        if skipped:
            self.lbl_status.config(
                text=f"Loaded {len(self._results)} records ({skipped} outside date filter skipped)")

    def _clear(self):
        if messagebox.askyesno("Clear", "Clear all results from view?\n(Index files on disk are kept.)"):
            self._results.clear()
            self._processed.clear()
            self.tree.delete(*self.tree.get_children())
            self.lbl_footer.config(text="")
            self.lbl_count.config(text="")

    # ── Scan ──────────────────────────────────────────────────────────────────

    def _start_scan(self):
        src1 = self.v_src.get().strip()
        src2 = self.v_src2.get().strip()

        if not src1 or not os.path.isdir(src1):
            messagebox.showerror("Error", f"Source folder 1 not found:\n{src1}")
            return
        if src2 and not os.path.isdir(src2):
            messagebox.showerror("Error", f"Source folder 2 not found:\n{src2}")
            return
        if not os.path.exists(FFMPEG):
            messagebox.showerror("Missing FFmpeg",
                f"FFmpeg not found at:\n{FFMPEG}\n\n"
                "Install via:  pip install imageio-ffmpeg\n"
                "or place ffmpeg.exe in C:\\ffmpeg\\")
            return
        if not os.path.exists(TESSERACT):
            messagebox.showerror("Missing Tesseract",
                f"Tesseract not found at:\n{TESSERACT}\n\n"
                "Download from:\nhttps://github.com/UB-Mannheim/tesseract/wiki")
            return

        # Parse date range for smart scan
        try:
            scan_start = datetime.strptime(self.v_start.get().strip(), "%m/%d/%Y").date()
            scan_end   = datetime.strptime(self.v_end.get().strip(),   "%m/%d/%Y").date()
        except ValueError:
            messagebox.showerror("Date Error", "Dates must be MM/DD/YYYY")
            return

        srcs = [s for s in [src1, src2] if s]
        self._stop.clear()
        threading.Thread(
            target=self._scan_worker,
            args=(srcs, scan_start, scan_end),
            daemon=True,
        ).start()

    def _scan_worker(self, srcs, scan_start, scan_end):
        workers = self.v_workers.get()

        # Kill any lingering FFmpeg/Tesseract from a previous scan
        self._kill_worker_procs()

        # Always start completely fresh — discard any data from index auto-load
        self._results = []
        self._processed = set()
        self._q.put(("clear_table",))
        self._log("INFO", f"=== SCAN STARTED  {scan_start} → {scan_end}  workers={workers} ===")

        # ── Collect files from all source directories ──
        self._q.put(("status", "Discovering files…"))
        src_files = {}  # src_path -> [sorted file list]
        for src in srcs:
            try:
                files = sorted(f for f in Path(src).rglob("*")
                               if f.is_file() and f.stat().st_size >= 50_000)
                src_files[src] = files
                self._q.put(("status", f"Found {len(files):,} files in {src}"))
            except Exception as e:
                self._q.put(("error", f"Error reading {src}:\n{e}"))
                return

        # ── Binary search each source to narrow to target date range ──
        candidate_files = []
        for src, files in src_files.items():
            if not files:
                continue
            n = len(files)
            src_label = Path(src).name

            def _cb(msg, _lbl=src_label):
                self._q.put(("status", f"[{_lbl}] {msg}"))

            def _pcb(idx, total, phase, _lbl=src_label):
                pct = idx / total * 100 if total else 0
                self._q.put(("prog_bs", pct, idx, total, _lbl, phase))

            self._q.put(("pmax_bs", n))
            self._log("INFO", f"[{src_label}] Binary search in {n:,} files for {scan_start} → {scan_end}")
            lo, hi = _find_date_range(files, scan_start, scan_end,
                                      status_cb=_cb, progress_cb=_pcb,
                                      workers=workers)
            slice_files = files[lo:hi+1]
            candidate_files.extend(slice_files)
            self._log("INFO", f"[{src_label}] Range: files {lo:,}–{hi:,}  ({len(slice_files):,} candidates)")
            self._q.put(("status",
                f"[{src_label}] Range found: files {lo:,}–{hi:,} "
                f"({len(slice_files):,} candidates)"))

        # ── Load previous progress, keeping only results in the target date range ──
        if os.path.exists(PROGRESS_FILE):
            try:
                with open(PROGRESS_FILE, encoding="utf-8") as f:
                    saved = json.load(f)
                raw_results = saved.get("results", [])
                self._processed = set(saved.get("processed", []))
                self._results = []
                for r in raw_results:
                    try:
                        rd = datetime.strptime(r["date"], "%Y-%m-%d").date()
                        if not (scan_start <= rd <= scan_end):
                            continue
                    except (ValueError, KeyError):
                        continue
                    raw = r.get("camera")
                    r["camera"] = int(raw) if raw and raw not in (None, "None", "") else None
                    self._results.append(r)
                if self._results:
                    self._log("INFO", f"Resumed {len(self._results)} results from previous session")
                    self._q.put(("reload", list(self._results)))
            except Exception:
                pass

        remaining = [f for f in candidate_files if f.name not in self._processed]
        total     = len(remaining)
        self._q.put(("pmax", total))
        self._q.put(("status",
            f"Phase 3/3: Scanning {total:,} candidate files with {workers} workers…"))
        self._log("INFO", f"Phase 3/3: OCR scanning {total:,} files  |  {workers} workers")

        done   = [0]
        found  = [0]
        failed = [0]
        t_last_log = [time.time()]

        def worker(fp):
            if self._stop.is_set(): return fp.name, None
            try:   return fp.name, _analyze_file(str(fp))
            except: return fp.name, None

        self._executor = concurrent.futures.ThreadPoolExecutor(max_workers=workers)
        try:
            futs = {self._executor.submit(worker, fp): fp for fp in remaining}
            for fut in concurrent.futures.as_completed(futs):
                if self._stop.is_set(): break
                fname, result = fut.result()
                self._processed.add(fname)
                done[0] += 1
                if result:
                    try:
                        rd = datetime.strptime(result["date"], "%Y-%m-%d").date()
                        if scan_start <= rd <= scan_end:
                            self._results.append(result)
                            self._q.put(("row", result))
                            found[0] += 1
                            cam = result.get("camera")
                            cam_lbl = f"Cam {cam:02d}" if cam else "CAM?"
                            self._log("FOUND",
                                f"{result['filename']}  →  {cam_lbl}  |  {result.get('datetime','?')}")
                        else:
                            failed[0] += 1
                    except (ValueError, KeyError):
                        failed[0] += 1
                else:
                    failed[0] += 1
                self._q.put(("prog", done[0], total))
                # Progress log every 200 files or every 30 seconds
                now = time.time()
                if done[0] % 200 == 0 or (now - t_last_log[0]) >= 30:
                    t_last_log[0] = now
                    elapsed = now - (self._scan_start_t or now)
                    rate    = done[0] / elapsed if elapsed > 0 else 0
                    rem     = (total - done[0]) / rate if rate > 0 else 0
                    eta     = f"{rem/3600:.1f}h" if rem > 3600 else (f"{rem/60:.0f}m" if rem > 60 else f"{rem:.0f}s")
                    self._log("INFO",
                        f"Progress {done[0]:,}/{total:,} ({done[0]/total*100:.1f}%)  "
                        f"Found:{found[0]}  Skip:{failed[0]}  Rate:{rate:.1f}/s  ETA:{eta}")
                if done[0] % 50 == 0:
                    self._save_progress()
        finally:
            self._executor.shutdown(wait=False)
            self._executor = None

        self._save_progress()
        self._write_index()
        by_cam = defaultdict(int)
        for r in self._results:
            c = r.get("camera")
            if c: by_cam[c] += 1
        cam_summary = "  ".join(f"Cam{c:02d}:{n}" for c, n in sorted(by_cam.items()))
        self._log("SUCCESS",
            f"SCAN COMPLETE — {len(self._results)} files matched  |  {cam_summary or 'no cameras'}")
        self._q.put(("status",
            f"Scan complete — {len(self._results):,} files in {scan_start} to {scan_end}"))
        self._q.put(("scan_done",))

    def _save_progress(self):
        try:
            with open(PROGRESS_FILE, "w", encoding="utf-8") as f:
                json.dump({
                    "results"  : self._results,
                    "processed": list(self._processed),
                }, f, default=str)
        except Exception: pass

    def _write_index(self):
        try:
            rows = sorted(self._results,
                          key=lambda r: (str(r.get("camera","")), r.get("datetime","")))
            with open(INDEX_FILE, "w", newline="", encoding="utf-8-sig") as f:
                w = csv.DictWriter(f, fieldnames=["filename","camera","date","time","datetime","filepath"])
                w.writeheader()
                w.writerows(rows)
        except Exception: pass

    # ── Copy ──────────────────────────────────────────────────────────────────

    def _parse_copy_filters(self):
        try:
            start = datetime.strptime(self.v_start.get().strip(), "%m/%d/%Y").date()
            end   = datetime.strptime(self.v_end.get().strip(),   "%m/%d/%Y").date()
        except ValueError:
            messagebox.showerror("Date Error", "Dates must be MM/DD/YYYY")
            return None, None, False

        cam_raw = self.v_cameras.get().strip()
        if cam_raw:
            try:
                cams = {int(x) for x in re.split(r"[,\s]+", cam_raw) if x}
            except ValueError:
                messagebox.showerror("Camera Error", "Camera filter must be numbers (e.g. 1 or 1,2,3)")
                return None, None, False
        else:
            cams = None  # all cameras

        return start, end, cams

    def _start_copy(self, silent=False):
        sort_inplace = self.v_sort_inplace.get()

        if not self._results:
            if not silent:
                messagebox.showwarning("No Data",
                    "No scan results yet.\nRun SCAN first, or load an existing index.")
            return

        start, end, cams = self._parse_copy_filters()
        if start is None: return

        # ── Sort-in-Place mode: MOVE files within their own drive ─────────────
        if sort_inplace:
            folder_name = "DVR_Sorted"  # always fixed; dest field is just a preview

            srcs = []
            for sv in [self.v_src, self.v_src2]:
                raw = sv.get().strip()
                if raw and os.path.isdir(raw):
                    srcs.append(Path(raw).resolve())
            if not srcs:
                messagebox.showerror("Error", "No valid source folder.")
                return

            seen_drives = {}
            for s in srcs:
                seen_drives[s.drive.upper()] = s.drive.upper() + "\\" + folder_name
            dest_lines = "\n".join(f"  {v}" for v in seen_drives.values())

            ans = messagebox.askyesno(
                "Confirm MOVE — Sort in Place",
                f"Files will be MOVED (not copied) to:\n\n{dest_lines}\n\n"
                f"  Structure: Camera_XX \\ YYYY-MM-DD \\ filename.mpg\n\n"
                "Files leave their original folders. Operation is instant\n"
                "and uses ZERO extra disk space (same-partition rename).\n\n"
                "Proceed?"
            )
            if not ans: return
            self._stop.clear()
            threading.Thread(
                target=self._copy_worker,
                args=(None, start, end, cams, True, self.v_review.get()),
                kwargs={"sort_inplace": True, "sort_folder": folder_name},
                daemon=True,
            ).start()
            return

        # ── Normal copy mode ──────────────────────────────────────────────────
        dst = self.v_dst.get().strip()
        if not dst:
            if not silent:
                messagebox.showerror("Error", "Please set a destination folder")
            return

        dest = Path(dst).resolve()
        for sv in [self.v_src, self.v_src2]:
            raw = sv.get().strip()
            if not raw: continue
            try:
                src = Path(raw).resolve()
                if dest == src or dest.is_relative_to(src):
                    messagebox.showerror("Safety",
                        f"Destination must NOT be inside a source folder!\n{src}")
                    return
            except Exception: pass

        # ── Free space check ──────────────────────────────────────────────────
        try:
            dest.mkdir(parents=True, exist_ok=True)
            free_bytes   = shutil.disk_usage(dest).free
            needed_bytes = 0
            for r in self._results:
                try:
                    rd = datetime.strptime(r["date"], "%Y-%m-%d").date()
                    if not (start <= rd <= end): continue
                    cam = r.get("camera")
                    if cams is not None and cam not in cams: continue
                    p = Path(r.get("filepath", ""))
                    if p.exists():
                        needed_bytes += p.stat().st_size
                except Exception:
                    pass
            free_gb   = free_bytes   / 1_073_741_824
            needed_gb = needed_bytes / 1_073_741_824
            if needed_bytes > 0 and needed_bytes > free_bytes * 0.95:
                messagebox.showerror(
                    "Not Enough Space",
                    f"Not enough free space on destination disk!\n\n"
                    f"Needed:  {needed_gb:.1f} GB\n"
                    f"Free:    {free_gb:.1f} GB\n\n"
                    f"Free up space before copying."
                )
                return
            if needed_bytes > 0:
                ans = messagebox.askyesno(
                    "Confirm Copy",
                    f"Ready to copy {needed_gb:.1f} GB to:\n{dst}\n\n"
                    f"Free space available: {free_gb:.1f} GB\n\nProceed?"
                )
                if not ans: return
        except Exception:
            pass

        self._stop.clear()
        threading.Thread(
            target=self._copy_worker,
            args=(dst, start, end, cams, self.v_date_sub.get(), self.v_review.get()),
            daemon=True,
        ).start()

    def _copy_worker(self, dst_dir, start, end, cam_filter, date_subfolders, do_review,
                     sort_inplace=False, sort_folder="DVR_Sorted"):
        if not sort_inplace:
            dest = Path(dst_dir)
            dest.mkdir(parents=True, exist_ok=True)
        else:
            dest = None  # per-file destination derived from source drive

        # ── Resolve active source folders ─────────────────────────────────────
        raw_srcs = [self.v_src.get().strip(), self.v_src2.get().strip()]
        active_srcs = [Path(s).resolve() for s in raw_srcs if s and os.path.isdir(s)]
        multi_src   = len(active_srcs) > 1

        def src_label_for(filepath):
            """Return source folder name for a file, or 'Unknown'."""
            fp = Path(filepath).resolve()
            for src in active_srcs:
                try:
                    fp.relative_to(src)
                    return src.name
                except ValueError:
                    continue
            return "Unknown_Source"

        # ── Group results by (source_label, camera) ───────────────────────────
        # by_src_cam[(src_label, cam)] = [result, ...]
        by_src_cam = defaultdict(list)
        review     = []

        for r in self._results:
            try:
                rd = datetime.strptime(r["date"], "%Y-%m-%d").date()
            except (ValueError, KeyError):
                continue
            if not (start <= rd <= end):
                continue
            cam = r.get("camera")
            slbl = src_label_for(r.get("filepath", ""))
            if cam is None:
                if do_review: review.append((slbl, r))
            else:
                if cam_filter is None or cam in cam_filter:
                    by_src_cam[(slbl, cam)].append(r)

        total_files = sum(len(v) for v in by_src_cam.values()) + (len(review) if do_review else 0)
        if total_files == 0:
            self._log("WARN", "No matching files found for selected filters.")
            self._q.put(("warn", "No matching files found for selected date range."))
            return

        # summary for log
        src_names = sorted({k[0] for k in by_src_cam})
        dest_label_log = f"[each drive]\\{sort_folder}" if sort_inplace else str(dst_dir)
        self._log("INFO", f"{'Move' if sort_inplace else 'Copy'} starting — {total_files} files  |  sources: {src_names}  →  {dest_label_log}")
        for slbl in src_names:
            cams_in_src = sorted({k[1] for k in by_src_cam if k[0] == slbl})
            for c in cams_in_src:
                n = len(by_src_cam[(slbl, c)])
                self._log("INFO", f"  [{slbl}]  Camera {c:02d}: {n} files")
        if review:
            self._log("INFO", f"  Unknown camera: {len(review)} files → Review/")

        all_unique_cams = sorted({k[1] for k in by_src_cam})
        status_parts = [f"Cam {c:02d}: {sum(len(by_src_cam[(s,c)]) for s in src_names if (s,c) in by_src_cam)}"
                        for c in all_unique_cams]
        self._q.put(("status",
            f"{len(src_names)} source(s) | {len(all_unique_cams)} cameras — "
            + ", ".join(status_parts[:8]) + ("…" if len(status_parts) > 8 else "")))
        self._q.put(("pmax", total_files))

        done = ok = failed = 0

        def resolve_folder(r, slbl, cam, date_str):
            """Return the destination folder for a file."""
            if sort_inplace:
                src_path = Path(r.get("filepath", ""))
                drive_root = Path(src_path.drive + "\\")
                base = drive_root / sort_folder
                cam_tag = f"Camera_{cam:02d}" if cam else "Unknown"
                if multi_src:
                    return base / slbl / cam_tag / date_str
                else:
                    return base / cam_tag / date_str
            else:
                if multi_src:
                    src_root = dest / slbl
                else:
                    src_root = dest
                cam_tag = f"Camera_{cam:02d}" if cam else "Unknown"
                cam_dir = src_root / cam_tag
                return (cam_dir / date_str) if date_subfolders else cam_dir

        def copy_one(r, folder=None):
            nonlocal done, ok, failed
            src_path = Path(r.get("filepath", ""))
            if not src_path.exists():
                self._log("ERROR", f"NOT FOUND: {src_path.name}")
                failed += 1; done += 1
                self._q.put(("prog", done, total_files))
                return

            cam      = r.get("camera")
            slbl     = src_label_for(str(src_path))
            date_str = r.get("date", "unknown_date")

            if folder is None:
                folder = resolve_folder(r, slbl, cam, date_str)

            folder.mkdir(parents=True, exist_ok=True)
            dst_path = folder / src_path.name

            if dst_path.exists():
                ok += 1; done += 1
                self._q.put(("prog", done, total_files))
                return
            try:
                if sort_inplace:
                    os.rename(src_path, dst_path)
                    self._log("MOVE", f"{src_path.name}  →  {folder.name}/")
                elif src_path.drive.lower() == dest.drive.lower():
                    os.link(src_path, dst_path)
                    self._log("HLINK", f"{src_path.name}  →  {folder.name}/")
                else:
                    shutil.copy2(src_path, dst_path)
                    if dst_path.stat().st_size != src_path.stat().st_size:
                        dst_path.unlink(missing_ok=True)
                        self._log("ERROR", f"Size mismatch after copy: {src_path.name}")
                        failed += 1; done += 1
                        self._q.put(("prog", done, total_files))
                        return
                    self._log("COPY", f"{src_path.name}  →  {folder.name}/")
                ok += 1
            except Exception as ex:
                self._log("ERROR", f"Failed {src_path.name}: {ex}")
                failed += 1
                if not sort_inplace:
                    try: dst_path.unlink(missing_ok=True)
                    except: pass
            done += 1
            self._q.put(("prog", done, total_files))

        # ── Process: iterate by source then camera ────────────────────────────
        all_cams = set()
        op_word = "Moving" if sort_inplace else "Copying"
        for slbl in src_names:
            if self._stop.is_set(): break

            cams_in_src = sorted({k[1] for k in by_src_cam if k[0] == slbl})
            all_cams.update(cams_in_src)
            for cam in cams_in_src:
                if self._stop.is_set(): break
                files_here = by_src_cam[(slbl, cam)]
                label = f"[{slbl}] Camera {cam:02d}"
                self._log("INFO", f"{op_word} {label} — {len(files_here)} files")
                self._q.put(("status", f"{op_word} {label} — {len(files_here)} files"))

                for r in sorted(files_here, key=lambda x: x.get("datetime", "")):
                    if self._stop.is_set(): break
                    copy_one(r)

        # ── Review folder ────────────────────────────────────────────────────
        if do_review and review and not self._stop.is_set():
            for slbl, r in sorted(review, key=lambda x: x[1].get("datetime", "")):
                if self._stop.is_set(): break
                if sort_inplace:
                    sp = Path(r.get("filepath", ""))
                    rev_root = Path(sp.drive + "\\") / sort_folder / (slbl if multi_src else "") / "Review"
                else:
                    rev_root = (dest / slbl / "Review") if multi_src else (dest / "Review")
                rev_root.mkdir(parents=True, exist_ok=True)
                copy_one(r, rev_root)
            self._log("WARN", f"{len(review)} unknown-camera files → Review/")

        dest_label = f"[each source drive]\\{sort_folder}" if sort_inplace else dst_dir
        level = "SUCCESS" if failed == 0 else "WARN"
        op_label = "MOVE" if sort_inplace else "COPY"
        self._log(level, f"{op_label} COMPLETE — OK:{ok}  Failed:{failed}  →  {dest_label}")
        self._q.put(("status", f"{op_label.title()} complete — {ok} files, {failed} failed"))
        self._q.put(("copy_done", ok, failed, len(review) if do_review else 0, dest_label,
                     sorted(all_cams)))

    def _kill_worker_procs(self):
        """Kill any ffmpeg/tesseract processes left running from a scan."""
        for proc in ("ffmpeg.exe", "tesseract.exe"):
            try:
                subprocess.run(
                    ["taskkill", "/F", "/IM", proc],
                    capture_output=True, timeout=5,
                    creationflags=_NO_WIN, startupinfo=_SI,
                )
            except Exception:
                pass

    def _do_stop(self):
        self._stop.set()
        self._kill_worker_procs()
        if self._executor:
            try: self._executor.shutdown(wait=False, cancel_futures=True)
            except Exception: pass
        self.lbl_status.config(text="Stopped")

    def _on_close(self):
        """Clean shutdown: kill child processes then destroy window."""
        self._stop.set()
        self._kill_worker_procs()
        if self._executor:
            try: self._executor.shutdown(wait=False, cancel_futures=True)
            except Exception: pass
        self.destroy()

    def _show_cam_summary(self):
        """Pop up a detailed camera breakdown from current scan results."""
        if not self._results:
            messagebox.showinfo("Summary", "No scan results yet.\nRun SCAN first.")
            return

        by_cam  = defaultdict(list)
        unknown = []
        for r in self._results:
            cam = r.get("camera")
            if cam:
                by_cam[cam].append(r)
            else:
                unknown.append(r)

        win = tk.Toplevel(self)
        win.title("Camera Summary")
        win.geometry("520x480")
        win.resizable(True, True)

        ttk.Label(win, text="Cameras found in scan results",
                  font=("Segoe UI", 11, "bold")).pack(pady=(12, 4))
        ttk.Label(win, text=f"Total: {len(self._results)} files  |  "
                             f"{len(by_cam)} cameras  |  "
                             f"{len(unknown)} unknown",
                  foreground="#475569").pack(pady=(0, 8))

        # Scrollable table
        frame = ttk.Frame(win)
        frame.pack(fill="both", expand=True, padx=12, pady=(0, 8))
        cols = ("camera", "files", "date_from", "date_to", "hours")
        tv = ttk.Treeview(frame, columns=cols, show="headings", height=16)
        tv.heading("camera",    text="Camera")
        tv.heading("files",     text="Files")
        tv.heading("date_from", text="First recording")
        tv.heading("date_to",   text="Last recording")
        tv.heading("hours",     text="Est. hours")
        tv.column("camera",    width=100, anchor="center")
        tv.column("files",     width=60,  anchor="center")
        tv.column("date_from", width=110, anchor="center")
        tv.column("date_to",   width=110, anchor="center")
        tv.column("hours",     width=80,  anchor="center")
        sb = ttk.Scrollbar(frame, orient="vertical", command=tv.yview)
        tv.configure(yscrollcommand=sb.set)
        tv.pack(side="left", fill="both", expand=True)
        sb.pack(side="right", fill="y")

        for cam in sorted(by_cam.keys()):
            items = by_cam[cam]
            dates = sorted(r.get("datetime", "") for r in items)
            hrs   = len(items) * 6 / 60
            tv.insert("", "end", values=(
                f"Camera {cam:02d}", len(items),
                dates[0][:10] if dates[0] else "?",
                dates[-1][:10] if dates[-1] else "?",
                f"{hrs:.1f} h",
            ))

        if unknown:
            tv.insert("", "end", values=(
                "UNKNOWN", len(unknown), "?", "?",
                f"{len(unknown)*6/60:.1f} h",
            ), tags=("unk",))
            tv.tag_configure("unk", foreground="#94a3b8")

        ttk.Button(win, text="Close", command=win.destroy).pack(pady=8)

    # ── Queue polling ─────────────────────────────────────────────────────────

    def _poll(self):
        try:
            while True:
                msg = self._q.get_nowait()
                kind = msg[0]

                if kind == "log":
                    self._log_to_widget(msg[1], msg[2], msg[3])

                elif kind == "clear_table":
                    self.tree.delete(*self.tree.get_children())
                    self._all_rows = []
                    self.lbl_count.config(text="")
                    self.lbl_footer.config(text="")

                elif kind == "row":
                    self._add_row(msg[1])
                    self._update_footer()

                elif kind == "reload":
                    self._refresh_table(msg[1])

                elif kind == "prog":
                    _, done, total = msg
                    pct = done / total * 100 if total else 0
                    self.v_prog.set(pct)
                    eta_str = ""
                    if self._scan_start_t and done > 10:
                        elapsed = time.time() - self._scan_start_t
                        rate    = done / elapsed
                        rem     = (total - done) / rate if rate > 0 else 0
                        if   rem > 3600: eta_str = f"  ETA {rem/3600:.1f}h"
                        elif rem > 60:   eta_str = f"  ETA {rem/60:.0f}m"
                        else:            eta_str = f"  ETA {rem:.0f}s"
                    self.lbl_prog.config(
                        text=f"{done:,} / {total:,}  ({pct:.1f}%){eta_str}")

                elif kind == "pmax":
                    self.v_prog.set(0)
                    self._scan_start_t = time.time()
                    self.lbl_prog.config(text=f"0 / {msg[1]:,}  (0.0%)")

                elif kind == "pmax_bs":
                    # Binary-search phase starting — show total file count
                    self.v_prog.set(0)
                    self.lbl_prog.config(text=f"Locating range in {msg[1]:,} files…")

                elif kind == "prog_bs":
                    # Binary-search probe — show which file index is being checked
                    _, pct, idx, total, lbl, phase = msg
                    self.v_prog.set(pct)
                    self.lbl_prog.config(
                        text=f"{phase}: file {idx:,}/{total:,}  ({pct:.1f}%)")

                elif kind == "status":
                    self.lbl_status.config(text=msg[1], foreground="#475569")

                elif kind == "warn":
                    self.lbl_status.config(text=msg[1], foreground="#b45309")
                    messagebox.showwarning("No Matches", msg[1])

                elif kind == "error":
                    messagebox.showerror("Error", msg[1])

                elif kind == "scan_done":
                    self.v_prog.set(100)
                    self._update_footer()
                    by_cam = defaultdict(int)
                    for r in self._results:
                        c = r.get("camera")
                        if c: by_cam[c] += 1
                    cam_lines = "\n".join(
                        f"  Camera {c:02d}: {n} files"
                        for c, n in sorted(by_cam.items())
                    ) or "  (none found)"
                    if self.v_auto_copy.get():
                        # Auto-copy: skip info popup, start copy immediately
                        self.lbl_status.config(
                            text=f"Scan done — auto-copy starting…", foreground="#16a34a")
                        self.after(500, self._start_copy)
                    else:
                        messagebox.showinfo("Scan Complete",
                            f"Scan finished!\n\n"
                            f"{len(self._results):,} files identified in date range.\n\n"
                            f"Cameras found:\n{cam_lines}\n\n"
                            f"Index saved to: {INDEX_FILE}\n\n"
                            f"Use 'Camera Summary' button for full details.")

                elif kind == "copy_done":
                    _, ok, failed, rev, dst, cam_list = msg
                    cam_lines = "\n".join(f"  Camera_{c:02d}/" for c in sorted(cam_list))
                    details = (
                        f"Copied:   {ok} files\n"
                        f"Failed:   {failed} files\n"
                    )
                    if rev:
                        details += f"Review:   {rev} files (unknown camera)\n"
                    details += f"\nFolders created:\n{cam_lines}"
                    if rev:
                        details += "\n  Review/"
                    details += f"\n\nDestination:\n{dst}"
                    messagebox.showinfo("Copy Complete", details)

        except queue.Empty:
            pass
        self.after(80, self._poll)


# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    app = App()
    app.mainloop()
