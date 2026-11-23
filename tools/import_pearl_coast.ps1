# Normalizes the Pearl Coast assets package into res://art/lishi_worlds/pearl_coast/
# so ContentService can treat it like the Three New Worlds packs.
#   powershell -File tools/import_pearl_coast.ps1 -Zip C:\path\Pearl_Coast_Assets_Package.zip
#
# Copies only what the game uses: world + gameplay backgrounds (resized JPG), UI nodes,
# and individually cropped props from the props sheet. Sheets, previews, the framed world
# card and the wide banner stay out of the project. Run `godot --headless --path . --import`
# afterwards.
param(
    [Parameter(Mandatory = $true)][string]$Zip
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root "art/lishi_worlds/pearl_coast"
$tmp = Join-Path $env:TEMP ("pearl_coast_import_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    Expand-Archive -Path $Zip -DestinationPath $tmp -Force
    $pack = Join-Path $tmp "Pearl_Coast_Assets_Package"
    if (-not (Test-Path $pack)) {
        $pack = Get-ChildItem $tmp -Directory | Select-Object -First 1 -ExpandProperty FullName
    }

    foreach ($sub in @("backgrounds", "ui", "props")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $dest $sub) | Out-Null
    }

    $code = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

public static class PearlImg {
  public static void SaveJpeg(Bitmap src, string path, int w, int h, long quality) {
    using (var dst = new Bitmap(w, h, PixelFormat.Format24bppRgb))
    using (var g = Graphics.FromImage(dst)) {
      g.InterpolationMode = InterpolationMode.HighQualityBicubic;
      g.SmoothingMode = SmoothingMode.HighQuality;
      g.PixelOffsetMode = PixelOffsetMode.HighQuality;
      g.CompositingQuality = CompositingQuality.HighQuality;
      g.DrawImage(src, 0, 0, w, h);
      var enc = GetJpegEncoder();
      var ep = new EncoderParameters(1);
      ep.Param[0] = new EncoderParameter(Encoder.Quality, quality);
      dst.Save(path, enc, ep);
    }
  }

  public static void SavePngFit(Bitmap src, string path, int size, bool clearDarkBg) {
    Bitmap work = src;
    Bitmap cleared = null;
    if (clearDarkBg) {
      cleared = ClearDarkBackground(src);
      work = cleared;
    }
    try {
      // Trim near-empty margins then fit into a square canvas.
      Rectangle bounds = ContentBounds(work);
      if (bounds.Width < 1 || bounds.Height < 1) bounds = new Rectangle(0, 0, work.Width, work.Height);
      int pad = Math.Max(2, Math.Min(bounds.Width, bounds.Height) / 40);
      int x = Math.Max(0, bounds.X - pad);
      int y = Math.Max(0, bounds.Y - pad);
      int rw = Math.Min(work.Width - x, bounds.Width + 2 * pad);
      int rh = Math.Min(work.Height - y, bounds.Height + 2 * pad);
      using (var crop = work.Clone(new Rectangle(x, y, rw, rh), PixelFormat.Format32bppArgb))
      using (var dst = new Bitmap(size, size, PixelFormat.Format32bppArgb))
      using (var g = Graphics.FromImage(dst)) {
        g.Clear(Color.Transparent);
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.SmoothingMode = SmoothingMode.HighQuality;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        float scale = Math.Min((float)size / crop.Width, (float)size / crop.Height);
        int dw = Math.Max(1, (int)(crop.Width * scale));
        int dh = Math.Max(1, (int)(crop.Height * scale));
        int ox = (size - dw) / 2;
        int oy = (size - dh) / 2;
        g.DrawImage(crop, new Rectangle(ox, oy, dw, dh));
        dst.Save(path, ImageFormat.Png);
      }
    } finally {
      if (cleared != null) cleared.Dispose();
    }
  }

  public static Bitmap CropRect(Bitmap src, int x, int y, int w, int h, int pad) {
    int cx = Math.Max(0, x - pad);
    int cy = Math.Max(0, y - pad);
    int cw = Math.Min(src.Width - cx, w + 2 * pad);
    int ch = Math.Min(src.Height - cy, h + 2 * pad);
    return src.Clone(new Rectangle(cx, cy, cw, ch), PixelFormat.Format32bppArgb);
  }

  static Bitmap ClearDarkBackground(Bitmap src) {
    var dst = new Bitmap(src.Width, src.Height, PixelFormat.Format32bppArgb);
    for (int y = 0; y < src.Height; y++) {
      for (int x = 0; x < src.Width; x++) {
        Color c = src.GetPixel(x, y);
        // Sheet / node crops sit on near-black; drop dark low-alpha pixels.
        if (c.A < 160 || (c.R + c.G + c.B) < 55) {
          dst.SetPixel(x, y, Color.Transparent);
        } else {
          dst.SetPixel(x, y, c);
        }
      }
    }
    return dst;
  }

  static Rectangle ContentBounds(Bitmap src) {
    int minx = src.Width, miny = src.Height, maxx = -1, maxy = -1;
    for (int y = 0; y < src.Height; y++) {
      for (int x = 0; x < src.Width; x++) {
        if (src.GetPixel(x, y).A < 16) continue;
        if (x < minx) minx = x;
        if (y < miny) miny = y;
        if (x > maxx) maxx = x;
        if (y > maxy) maxy = y;
      }
    }
    if (maxx < minx) return Rectangle.Empty;
    return new Rectangle(minx, miny, maxx - minx + 1, maxy - miny + 1);
  }

  static ImageCodecInfo GetJpegEncoder() {
    foreach (var c in ImageCodecInfo.GetImageEncoders())
      if (c.FormatID == ImageFormat.Jpeg.Guid) return c;
    throw new InvalidOperationException("JPEG encoder missing");
  }
}
'@
    Add-Type -TypeDefinition $code -ReferencedAssemblies System.Drawing

    $n = 0

    # --- Backgrounds ---
    $worldBg = Join-Path $pack "02_Backgrounds/Pearl_Coast_Level_Map_Background.png"
    $gameBg = Join-Path $pack "02_Backgrounds/Pearl_Coast_Gameplay_Background.png"
    foreach ($pair in @(
        @{ Src = $worldBg; Stem = "world_background" },
        @{ Src = $gameBg; Stem = "gameplay_background" }
    )) {
        $bmp = [System.Drawing.Bitmap]::FromFile($pair.Src)
        try {
            [PearlImg]::SaveJpeg($bmp, (Join-Path $dest ("backgrounds/{0}_1440x2560.jpg" -f $pair.Stem)), 1440, 2560, 88)
            [PearlImg]::SaveJpeg($bmp, (Join-Path $dest ("backgrounds/{0}_720x1280.jpg" -f $pair.Stem)), 720, 1280, 85)
            $n += 2
        } finally { $bmp.Dispose() }
    }

    # --- UI nodes ---
    $uiMap = @(
        @{ From = "05_UI_Nodes/Pearl_Coast_Chapter_Medallion.png"; To = "ui/world_badge_512.png"; Size = 512 },
        @{ From = "05_UI_Nodes/Pearl_Coast_Node_Available.png"; To = "ui/level_node_active_256.png"; Size = 256 },
        @{ From = "05_UI_Nodes/Pearl_Coast_Node_Current.png"; To = "ui/level_node_current_256.png"; Size = 256 },
        @{ From = "05_UI_Nodes/Pearl_Coast_Node_Completed.png"; To = "ui/level_node_completed_256.png"; Size = 256 },
        @{ From = "05_UI_Nodes/Pearl_Coast_Node_Locked.png"; To = "ui/level_node_locked_256.png"; Size = 256 }
    )
    foreach ($u in $uiMap) {
        $bmp = [System.Drawing.Bitmap]::FromFile((Join-Path $pack $u.From))
        try {
            [PearlImg]::SavePngFit($bmp, (Join-Path $dest $u.To), $u.Size, $true)
            $n++
        } finally { $bmp.Dispose() }
    }

    # --- Props (hardcoded crops from props sheet at alpha>=160; skip standalone scallop) ---
    # Names match bloom.json world_art and the redesign plan.
    $propCrops = @(
        @{ Name = "blossom_branch"; X = 33; Y = 7; W = 787; H = 314 },
        @{ Name = "pearl_shell"; X = 970; Y = 13; W = 420; H = 364 },
        @{ Name = "starfish"; X = 825; Y = 313; W = 226; H = 182 },
        @{ Name = "conch"; X = 328; Y = 337; W = 275; H = 148 },
        @{ Name = "lantern"; X = 53; Y = 319; W = 238; H = 335 },
        @{ Name = "coastal_tree"; X = 1052; Y = 431; W = 352; H = 323 },
        @{ Name = "rope_fence"; X = 336; Y = 513; W = 361; H = 189 },
        @{ Name = "coral"; X = 734; Y = 500; W = 304; H = 248 },
        @{ Name = "villa"; X = 21; Y = 647; W = 400; H = 405 },
        @{ Name = "flower_vase"; X = 431; Y = 756; W = 241; H = 283 },
        @{ Name = "rocks"; X = 681; Y = 809; W = 365; H = 220 },
        @{ Name = "sand"; X = 1068; Y = 862; W = 356; H = 152 }
    )
    $sheet = [System.Drawing.Bitmap]::FromFile((Join-Path $pack "04_Props/Pearl_Coast_Props_Sheet.png"))
    try {
        foreach ($p in $propCrops) {
            $crop = [PearlImg]::CropRect($sheet, $p.X, $p.Y, $p.W, $p.H, 4)
            try {
                [PearlImg]::SavePngFit($crop, (Join-Path $dest ("props/{0}_512.png" -f $p.Name)), 512, $true)
                [PearlImg]::SavePngFit($crop, (Join-Path $dest ("props/{0}_256.png" -f $p.Name)), 256, $true)
                $n += 2
            } finally { $crop.Dispose() }
        }
    } finally { $sheet.Dispose() }

    Write-Output "wrote $n files into $dest"
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
