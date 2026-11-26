# 노선 데이터(osm-routes.json) + 한국어 이름(ko.tsv) + template.html → ../index.html 생성
# 실행: powershell -File tools\build-data.ps1
param([double]$C = 6, [double]$Scale = 100)
$ErrorActionPreference = 'Stop'
$d = $PSScriptRoot
$j = Get-Content "$d\osm-routes.json" -Raw -Encoding utf8 | ConvertFrom-Json
$nodes = @{}; $j.elements | Where-Object type -eq 'node' | ForEach-Object { $nodes[[string]$_.id] = $_ }
$rels = @{}; $j.elements | Where-Object type -eq 'relation' | ForEach-Object { $rels[[string]$_.id] = $_ }

$ko = @{}
Get-Content "$d\ko.tsv" -Encoding utf8 | Where-Object { $_ -match "`t" } | ForEach-Object { $a = $_ -split "`t"; $ko[$a[0]] = $a[1] }

# id, name, short label, colour, relation ids (one per branch)
$lines = @(
  @('1','1호선','1','#E3002B',@('199200')),
  @('2','2호선','2','#8CC220',@('5611326')),
  @('3','3호선','3','#FCD600',@('196738')),
  @('4','4호선','4','#461D84',@('196854')),
  @('5','5호선','5','#944D9A',@('214779','9170631')),
  @('6','6호선','6','#D40068',@('214736')),
  @('7','7호선','7','#ED6F00',@('6819599')),
  @('8','8호선','8','#0094D8',@('196737')),
  @('9','9호선','9','#87CAED',@('214629')),
  @('10','10호선','10','#C7AFD3',@('7452117','199189')),
  @('11','11호선','11','#871C2B',@('5611110','5611108')),
  @('12','12호선','12','#007A60',@('5498699')),
  @('13','13호선','13','#E999C0',@('214631')),
  @('14','14호선','14','#626020',@('10557250')),
  @('15','15호선','15','#BCA886',@('12231216')),
  @('16','16호선','16','#32D4CB',@('5178631')),
  @('17','17호선','17','#BC796F',@('6325787')),
  @('18','18호선','18','#C4984F',@('10095916')),
  @('pj','푸장선','푸장','#B5B5B6',@('8167020')),
  @('mg','자기부상열차','자기','#009090',@('443258')),
  @('ap','공항연결선','공항','#2B4C9B',@('16404066'))
)

$pos = @{}  # name -> list of [lat,lon]
$order = New-Object System.Collections.Generic.List[string]
$lineOut = @()
foreach ($l in $lines) {
  $segs = @()
  foreach ($rid in $l[4]) {
    $r = $rels[$rid]; if (-not $r) { throw "missing relation $rid" }
    $seq = @()
    foreach ($m in ($r.members | Where-Object { $_.type -eq 'node' -and $_.role -match '^stop' })) {
      $n = $nodes[[string]$m.ref]; $nm = ($n.tags.name -replace '・', '·')
      if (-not $pos.ContainsKey($nm)) { $pos[$nm] = @(); $order.Add($nm) }
      $pos[$nm] += , @([double]$n.lat, [double]$n.lon)
      if ($seq.Count -eq 0 -or $seq[-1] -ne $nm) { $seq += $nm }
    }
    $segs += , $seq
  }
  $lineOut += , @($l, $segs)
}

$lat0 = 31.2323; $lon0 = 121.4737
$kx = [math]::Cos($lat0 * [math]::PI / 180) * 111.32; $ky = 110.57
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('const LINES = [')
foreach ($lo in $lineOut) {
  $l = $lo[0]
  $segTxt = ($lo[1] | ForEach-Object { '[' + (($_ | ForEach-Object { "'$_'" }) -join ',') + ']' }) -join ",`n      "
  [void]$sb.AppendLine("  { id: '$($l[0])', name: '$($l[1])', short: '$($l[2])', color: '$($l[3])',`n    segs: [$segTxt] },")
}
[void]$sb.AppendLine('];')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('// 역: 중국어 이름 = ID / ko: 한국어 / x,y: 노선도 좌표 (실제 위치를 바탕으로 도심을 넓게 펼침)')
[void]$sb.AppendLine('const STATIONS = {')
$missing = @()
foreach ($nm in $order) {
  $p = $pos[$nm]; $la = ($p | ForEach-Object { $_[0] } | Measure-Object -Average).Average; $lo2 = ($p | ForEach-Object { $_[1] } | Measure-Object -Average).Average
  $x = ($lo2 - $lon0) * $kx; $y = -($la - $lat0) * $ky
  $r = [math]::Sqrt($x * $x + $y * $y)
  $f = if ($r -gt 0) { $C * [math]::Log(1 + $r / $C) / $r } else { 1 }
  $X = [math]::Round($x * $f * $Scale); $Y = [math]::Round($y * $f * $Scale)
  $k = $ko[$nm]; if (-not $k) { $missing += $nm; $k = $nm }
  [void]$sb.AppendLine("  '$nm': { ko: '$k', x: $X, y: $Y },")
}
[void]$sb.AppendLine('};')
$u = New-Object System.Text.UTF8Encoding $false
$tpl = [IO.File]::ReadAllText("$d\template.html", $u)
[IO.File]::WriteAllText((Join-Path (Split-Path $d) 'index.html'), $tpl.Replace('/*__DATA__*/', $sb.ToString().TrimEnd()), $u)
"stations: $($order.Count); missing ko: $($missing -join ',')"
