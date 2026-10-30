# Item icons: 14 x 14 interior grids, wrapped in a 1-px frame (index 1) to make 16 x 16.
# Index: . = 0 black, 1 = frame, 2 and 3 = the icon's own colours.
param([string]$OutDir = $PSScriptRoot)
Add-Type -AssemblyName System.Drawing

$BALL  = @(255,204,0)
$WHITE = @(255,255,255)
$GREEN = @(0,200,0)
$RED   = @(220,0,0)

$icons = @(
  @{ name='LOW GRAVITY'; kind='buff'; c2=$BALL; c3=@(0,220,255); g=@(
    '.....2222.....',
    '....222222....',
    '....222222....',
    '....222222....',
    '....222222....',
    '.....2222.....',
    '..............',
    '......33......',
    '......33......',
    '......33......',
    '....333333....',
    '.....3333.....',
    '......33......',
    '..............')},
  @{ name='INVINCIBLE'; kind='buff'; c2=@(40,110,255); c3=$WHITE; g=@(
    '..............',
    '..2222222222..',
    '..2222332222..',
    '..2222332222..',
    '..2333333332..',
    '..2333333332..',
    '..2222332222..',
    '..2222332222..',
    '...22233222...',
    '...22222222...',
    '....222222....',
    '.....2222.....',
    '......22......',
    '..............')},
  @{ name='TIME BONUS'; kind='buff'; c2=$WHITE; c3=@(255,230,0); g=@(
    '...........3..',
    '..........333.',
    '...........3..',
    '...222222.....',
    '..2......2....',
    '.2...3....2...',
    '.2...3....2...',
    '.2...3....2...',
    '.2...3333.2...',
    '.2........2...',
    '.2........2...',
    '..2......2....',
    '...222222.....',
    '..............')},
  @{ name='REVERSE GRAV'; kind='debuff'; c2=$BALL; c3=@(255,0,255); g=@(
    '......33......',
    '.....3333.....',
    '....333333....',
    '...33333333...',
    '......33......',
    '......33......',
    '..............',
    '..............',
    '.....2222.....',
    '....222222....',
    '....222222....',
    '....222222....',
    '....222222....',
    '.....2222.....')},
  @{ name='HIGH GRAVITY'; kind='debuff'; c2=$BALL; c3=@(255,120,0); g=@(
    '.....2222.....',
    '....222222....',
    '....222222....',
    '....222222....',
    '....222222....',
    '.....2222.....',
    '..............',
    '..3333333333..',
    '...33333333...',
    '....333333....',
    '..3333333333..',
    '...33333333...',
    '....333333....',
    '.....3333.....')},
  @{ name='ZERO GRAVITY'; kind='debuff'; c2=$BALL; c3=@(120,160,255); g=@(
    '..............',
    '..............',
    '....333333....',
    '..33......33..',
    '.3...2222...3.',
    '3...222222...3',
    '3...222222...3',
    '3...222222...3',
    '3...222222...3',
    '.3...2222...3.',
    '..33......33..',
    '....333333....',
    '..............',
    '..............')},
  @{ name='INVERT CTRL'; kind='debuff'; c2=$WHITE; c3=@(255,230,0); g=@(
    '..............',
    '..............',
    '.........2....',
    '.........22...',
    '..22222222222.',
    '.........22...',
    '.........2....',
    '..............',
    '....3.........',
    '...33.........',
    '.33333333333..',
    '...33.........',
    '....3.........',
    '..............')},
  @{ name='FOG OF WAR'; kind='debuff'; c2=@(200,200,200); c3=@(110,110,110); g=@(
    '..............',
    '..............',
    '......2222....',
    '...222222222..',
    '..22222222222.',
    '.2222222222222',
    '22222222222222',
    '22222222222222',
    '.222222222222.',
    '..............',
    '.33333.333333.',
    '..............',
    '...3333333.33.',
    '..............')}
)

# RGB888 -> RGB565 -> RGB888, so the preview shows what the OLED can show
function Q565($c) {
  $r = [int]($c[0] -shr 3); $g = [int]($c[1] -shr 2); $b = [int]($c[2] -shr 3)
  return @((($r -shl 3) -bor ($r -shr 2)), (($g -shl 2) -bor ($g -shr 4)), (($b -shl 3) -bor ($b -shr 2)), (($r -shl 11) -bor ($g -shl 5) -bor $b))
}

$full = @()
foreach ($ic in $icons) {
  if ($ic.g.Count -ne 14) { throw "$($ic.name): $($ic.g.Count) rows" }
  foreach ($row in $ic.g) { if ($row.Length -ne 14) { throw "$($ic.name): row '$row' is $($row.Length) wide" } }
  $px = New-Object 'int[,]' 16,16
  for ($y = 0; $y -lt 16; $y++) { for ($x = 0; $x -lt 16; $x++) {
    if ($x -eq 0 -or $y -eq 0 -or $x -eq 15 -or $y -eq 15) { $px[$y,$x] = 1 }
    else { $ch = $ic.g[$y-1][$x-1]; $px[$y,$x] = if ($ch -eq '.') { 0 } else { [int]::Parse([string]$ch) } }
  }}
  $frame = if ($ic.kind -eq 'buff') { $GREEN } else { $RED }
  $pal = @((Q565 @(0,0,0)), (Q565 $frame), (Q565 $ic.c2), (Q565 $ic.c3))
  $full += @{ name=$ic.name; kind=$ic.kind; px=$px; pal=$pal }
}

# .mem: 8 icons x 256 pixels, one 2-bit index per line; palette: 8 x 4 RGB565 words
$mem = foreach ($f in $full) { for ($y=0;$y -lt 16;$y++){ for($x=0;$x -lt 16;$x++){ '{0:x1}' -f $f.px[$y,$x] } } }
Set-Content -Path (Join-Path $OutDir 'item_icons.mem') -Value $mem -Encoding ascii
$palm = foreach ($f in $full) { foreach ($p in $f.pal) { '{0:x4}' -f $p[3] } }
Set-Content -Path (Join-Path $OutDir 'item_icons_palette.mem') -Value $palm -Encoding ascii

function Draw-Icon($gfx, $f, $ox, $oy, $s) {
  for ($y=0;$y -lt 16;$y++){ for($x=0;$x -lt 16;$x++){
    $c = $f.pal[$f.px[$y,$x]]
    $br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($c[0],$c[1],$c[2]))
    $gfx.FillRectangle($br, $ox + $x*$s, $oy + $y*$s, $s, $s); $br.Dispose()
  }}
}

# Sheet: buffs on row 1, debuffs on row 2, at 8x; an OLED mock (96 x 64 at 4x) on the right
$S = 8; $cell = 16*$S; $gap = 28; $lab = 26
$sheetW = 5*($cell+$gap) + $gap + 96*4 + $gap
$sheetH = 2*($cell+$lab+$gap) + $gap + 40
$bmp = New-Object System.Drawing.Bitmap $sheetW, $sheetH
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.Clear([System.Drawing.Color]::FromArgb(32,32,40))
$font = New-Object System.Drawing.Font 'Consolas', 11, ([System.Drawing.FontStyle]::Bold)
$hfont = New-Object System.Drawing.Font 'Consolas', 13, ([System.Drawing.FontStyle]::Bold)
$wb = [System.Drawing.Brushes]::White
$gfx.DrawString('BUFF', $hfont, $wb, $gap, 8)
$i = 0; $j = 0
foreach ($f in $full) {
  $row = if ($f.kind -eq 'buff') { 0 } else { 1 }
  if ($row -eq 0) { $col = $i; $i++ } else { $col = $j; $j++ }
  $ox = $gap + $col*($cell+$gap); $oy = 40 + $row*($cell+$lab+$gap)
  Draw-Icon $gfx $f $ox $oy $S
  $gfx.DrawString($f.name, $font, $wb, $ox, $oy + $cell + 4)
}
$gfx.DrawString('DEBUFF', $hfont, $wb, $gap, 40 + $cell + $lab + 4)

# OLED mock: black 96 x 64, icon at 3x (48 x 48) centred, drawn at 4x
$mx = 5*($cell+$gap) + $gap; $my = 40
$gfx.DrawString('OLED 96x64 (shown 4x)', $hfont, $wb, $mx, 8)
$gfx.FillRectangle([System.Drawing.Brushes]::Black, $mx, $my, 96*4, 64*4)
Draw-Icon $gfx $full[0] ($mx + 24*4) ($my + 8*4) (3*4)
$gfx.DrawRectangle([System.Drawing.Pens]::Gray, $mx-1, $my-1, 96*4+1, 64*4+1)
$bmp.Save((Join-Path $OutDir 'item_icons_preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$gfx.Dispose(); $bmp.Dispose()
"wrote $($full.Count) icons"
