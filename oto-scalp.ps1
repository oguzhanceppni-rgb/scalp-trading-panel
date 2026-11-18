# Hafta içi her gün (ScalpSim Pzt–Cum 10:45; runner NY 03:00'ı bekler) scalp simülasyonu: iki pencere NY 03:00–05:00 Londra + 09:20–12:00 NY (kış TSİ 11:00–13:00 + 17:20–20:00, arada tarama yok; açık işlem script tarafından izlenir) yeni işlem taraması; sonrasında açık işlem varsa TP/SL'e kadar izlenir (güvenlik 23:45). Claude limiti dolarsa erken durur.
# İşlem yokken 10 dk'da bir; açık işlemde 30 dk'da bir, ama fiyat SL/TP'ye değerse hemen tur + 10 dk'ya dönüş.
# Limit dolunca durur, limit sıfırlansa da devam etmez. Bitince Hermes raporunu tetikler.
$dir = (Get-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Artifical*\Scalp Panel')).FullName
Set-Location -LiteralPath $dir
Add-Type -Namespace W -Name P -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
[W.P]::SetThreadExecutionState([uint32]2147483649) | Out-Null  # script bitene kadar uyku yok
$claude = "$env:USERPROFILE\.local\bin\claude.exe"
$tv = "$env:USERPROFILE\tradingview-mcp\src\cli\index.js"
$log = Join-Path $dir 'oto.log'
$bugun = Get-Date -Format 'yyyy-MM-dd'
$gunluk = Join-Path $dir "islem-gunlugu-$bugun.md"
# 10.11: seans NY açılışına bağlı (ET 09:20–12:00 → TSİ; yaz saati/kış saati otomatik). Kış: 17:20–20:00, yaz: 16:20–19:00
$ny = [TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time')
function NY([string]$hm) { [TimeZoneInfo]::ConvertTime([DateTimeOffset]::new([datetime]"$bugun $hm", $ny.GetUtcOffset([datetime]"$bugun $hm")), [TimeZoneInfo]::Local).DateTime }
$lbasla = NY '03:00'  # 11.11 kullanıcı: Londra penceresi (Londra açılışı → seans sonu), kış TSİ 11:00–13:00
$lbitis = NY '05:00'
$basla = NY '09:20'
$bitis = NY '12:00'  # yeni işlem sonu
$sinir = Get-Date "$bugun 23:45"  # açık işlem için güvenlik sınırı (sonra güncel fiyattan kapanır)

# Bugünün günlüğü yoksa bir önceki günlüğün başlığından kur (işlem satırları hariç), bakiye önceki günün bitişinden devam
if (-not (Test-Path -LiteralPath $gunluk)) {
    $onceki = Get-ChildItem -LiteralPath $dir -Filter 'islem-gunlugu-*.md' | Where-Object { $_.Name -lt "islem-gunlugu-$bugun.md" } | Sort-Object Name | Select-Object -Last 1
    $satirlar = Get-Content -LiteralPath $onceki.FullName -Encoding UTF8
    $metin = $satirlar -join "`n"
    $eskiTarih = [datetime]::ParseExact($onceki.BaseName.Substring(14), 'yyyy-MM-dd', $null)
    $bakiye = ([regex]'bitiş \*\*\$([\d.]+)').Matches($metin) | Select-Object -Last 1 | ForEach-Object { $_.Groups[1].Value }
    if (-not $bakiye) {  # gün sonu yazılmamışsa: son işlem satırının bakiyesi, o da yoksa önceki başlangıç
        $bakiye = $satirlar | Where-Object { $_ -match '^\|\s*\d+\s*\|' } | Select-Object -Last 1 | ForEach-Object { ($_.Trim('|', ' ') -split '\|')[-1].Trim() -replace '[^\d.]', '' }
        if (-not $bakiye) { $bakiye = ([regex]'Başlangıç: \*\*\$([\d.]+)').Match($metin).Groups[1].Value }
    }
    $baslik = @(); foreach ($s in $satirlar) { if ($s -match '^## Tarama kaydı') { break }; if ($s -notmatch '^\|\s*\d') { $baslik += $s } }
    $baslik = ($baslik -join "`n").Replace($eskiTarih.ToString('dd.MM.yyyy'), (Get-Date -Format 'dd.MM.yyyy'))
    $baslik = $baslik -replace 'Başlangıç: \*\*\$[\d.]+\*\* \([\d.]+ bitişinden devam\)', ('Başlangıç: **$$' + $bakiye + '** (' + $eskiTarih.ToString('dd.MM') + ' bitişinden devam)')
    [IO.File]::WriteAllText($gunluk, "$baslik`n## Tarama kaydı`n", (New-Object System.Text.UTF8Encoding $true))
}

# Hermes yedek raporu: bugün 23:55 tek seferlik (script bitince ayrıca hemen tetiklenir)
$r = hermes cron create --name scalp-rapor --deliver telegram --repeat 1 --script scalp_rapor.py "55 23 $((Get-Date).Day) $((Get-Date).Month) *" "Script çıktısındaki talimata göre raporu yaz." | Out-String
$rapor = ([regex]'Created job: ([0-9a-f]{12})').Match($r).Groups[1].Value

if (-not ((node $tv status) -match '"cdp_connected": true')) {
    Start-Process node -ArgumentList "`"$tv`" launch" -WindowStyle Hidden  # görünür pencere açılmasın
    Start-Sleep 60
}
while ((Get-Date) -lt $lbasla) { Start-Sleep -Seconds 5 }
$talimat = (Get-Content -Raw -Encoding UTF8 (Join-Path $dir 'tarama.txt')) -replace '\d\d\.\d\d\.20\d\d', (Get-Date -Format 'dd.MM.yyyy') -replace 'islem-gunlugu-\d{4}-\d\d-\d\d', "islem-gunlugu-$bugun" -replace 'LBASLA_SAAT', $lbasla.ToString('HH:mm') -replace 'LBITIS_SAAT', $lbitis.ToString('HH:mm') -replace 'BASLA_SAAT', $basla.ToString('HH:mm') -replace 'BITIS_SAAT', $bitis.ToString('HH:mm')

function Tur {  # $true döner: Claude limiti doldu
    $p = "Şu an: $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n$talimat"
    $p = $p.Replace('"','\"')  # PS 5.1 iç tırnakları kaçırmaz; yoksa prompt ilk " işaretinde bölünür
    $out = & $claude -p $p --allowedTools mcp__tradingview Read Edit Write 'Bash(python *)' 2>&1
    Add-Content -LiteralPath $log -Encoding UTF8 "=== $(Get-Date -Format HH:mm:ss)`n$($out -join "`n")"
    return [bool](($out -join "`n") -match "hit your .*limit")
}

function AcikSatir { Select-String -LiteralPath $gunluk -Pattern '\|\s*AÇIK\s*\|' -Encoding UTF8 | Select-Object -First 1 }

function Bakiye {  # son kapanmış işlemin bakiyesi, yoksa günün başlangıcı
    $b = Select-String -LiteralPath $gunluk -Pattern '^\|\s*\d+\s*\|' -Encoding UTF8 | Where-Object { $_.Line -notmatch '\|\s*AÇIK\s*\|' } |
        ForEach-Object { ($_.Line.Trim('|', ' ') -split '\|')[-1].Trim() } | Where-Object { $_ -match '\d' } | Select-Object -Last 1
    if (-not $b) { $b = ([regex]'Başlangıç: \*\*\$([\d.]+)').Match((Get-Content -Raw -Encoding UTF8 -LiteralPath $gunluk)).Groups[1].Value }
    [double]::Parse(($b -replace '[^\d.]', ''), $inv)
}

function Kapat([switch]$Zorla) {  # açık işlemi 1dk mumlarla script kapatır (Claude turu gerekmez): SL/TP'den ilk değen; ikisi aynı mumda → STOP. -Zorla: son fiyattan kapat
    $satir = AcikSatir; if (-not $satir) { return }
    $c = $satir.Line.Split('|') | ForEach-Object { $_.Trim() }  # 1 #, 2 açılış, 3 parite, 4 yön, 5 giriş, 6 SL, 7 TP, 8 miktar, 12 durum, 13 P/L, 14 bakiye
    $sayi = { param($s) [double]::Parse([regex]::Match($s, '\d+(\.\d+)?').Value, $inv) }
    $giris = & $sayi $c[5]; $sl = & $sayi $c[6]; $tp = & $sayi $c[7]; $mik = & $sayi $c[8]; $long = $c[4] -match 'LONG'
    # 10.11: günlükte sembol zaten 'CAPITALCOM:XAGUSD' → eskiden 'CAPITALCOM:CAPITALCOM:…' isteniyordu, grafik yanlış feed'de kalıp 09.11 #1'i sahte STOP yazdı
    $sym = 'CAPITALCOM:' + ($c[3] -replace '^.*:', '')
    node $tv symbol $sym | Out-Null; node $tv timeframe 1 | Out-Null; Start-Sleep 5
    try { $grafik = ((node $tv status) -join "`n" | ConvertFrom-Json).chart_symbol } catch { $grafik = '' }
    if ($grafik -ne $sym) { Add-Content -LiteralPath $log -Encoding UTF8 "=== $(Get-Date -Format HH:mm:ss) Kapat: grafik '$grafik' ≠ $sym, kontrol atlandı"; return }
    try { $bars = ((node $tv ohlcv --count 500) -join "`n" | ConvertFrom-Json).bars } catch { return }
    if (-not $bars) { return }
    $acilis = [DateTimeOffset](Get-Date "$bugun $($c[2])")
    $durum = $null
    foreach ($m in $bars | Where-Object { $_.time -ge $acilis.ToUnixTimeSeconds() + 60 }) {  # giriş dakikasından sonraki mumlar
        $saat = [DateTimeOffset]::FromUnixTimeSeconds($m.time).ToLocalTime().ToString('HH:mm')
        $stop = if ($long) { $m.low -le $sl } else { $m.high -ge $sl }
        $hedef = if ($long) { $m.high -ge $tp } else { $m.low -le $tp }
        if ($stop) { $durum = "STOP $saat"; $cikis = $sl; break }
        if ($hedef) { $durum = "HEDEF $saat"; $cikis = $tp; break }
    }
    if (-not $durum -and $Zorla) { $cikis = $bars[-1].close; $durum = "KAPANIŞ $(Get-Date -Format HH:mm) @$cikis (23:45 sınırı)" }
    if (-not $durum) { return }
    $pl = [Math]::Round((($cikis - $giris) * $mik) * $(if ($long) { 1 } else { -1 }), 2)
    $c[12] = $durum; $c[13] = $(if ($pl -ge 0) { '+' } else { '−' }) + [Math]::Abs($pl).ToString('0.00', $inv); $c[14] = ((Bakiye) + $pl).ToString('0.00', $inv)
    $metin = [IO.File]::ReadAllText($gunluk).Replace($satir.Line, '| ' + ($c[1..14] -join ' | ') + ' |')
    [IO.File]::WriteAllText($gunluk, $metin, (New-Object System.Text.UTF8Encoding $true))
    Add-Content -LiteralPath $log -Encoding UTF8 "=== $(Get-Date -Format HH:mm:ss) script kapattı: #$($c[1]) $($c[3]) $durum P/L $($c[13])"
}

$inv = [Globalization.CultureInfo]::InvariantCulture
$baslangic = Bakiye
$limit = $false
while (((Get-Date) -lt $bitis) -or ((AcikSatir) -and (Get-Date) -lt $sinir)) {  # işlem saati sonrası yalnızca açık işlem varken
    if (AcikSatir) { Kapat; if (AcikSatir) { Start-Sleep -Seconds 60 }; continue }  # açık işlemde Claude turu yok (tek işlem kuralı), script izler
    if ($limit) { break }  # limit dolduysa yeni tur yok, yalnız açık işlem izlendi
    if ((Get-Date) -ge $lbitis -and (Get-Date) -lt $basla) { Start-Sleep -Seconds 60; continue }  # Londra sonu → NY açılışı arası tarama yok (backtest: ara saatler −0.12R)
    $t0 = Get-Date
    if (Tur) { $limit = $true; continue }
    if (-not (AcikSatir)) {
        $kalan = [Math]::Min(($t0.AddMinutes(10) - (Get-Date)).TotalSeconds, ($(if ((Get-Date) -lt $lbitis) { $lbitis } else { $bitis }) - (Get-Date)).TotalSeconds)
        if ($kalan -gt 0) { Start-Sleep -Seconds $kalan }
    }
}
if (AcikSatir) { Kapat -Zorla }  # 23:45 sınırı

if ($limit -or (Tur)) {  # gün sonu turu da limite takılırsa (05.11) script yazar
    $son = Bakiye; $n = @(Select-String -LiteralPath $gunluk -Pattern '^\|\s*\d+\s*\|' -Encoding UTF8).Count
    $yuzde = (($son / $baslangic - 1) * 100).ToString('0.00', $inv)
    Add-Content -LiteralPath $gunluk -Encoding UTF8 "`n## Gün sonu (otomatik)`n- $(Get-Date -Format HH:mm): Claude oturum limiti doldu, gün sonu script tarafından yazıldı (sonraki oturuma geçilmedi); açık işlem varsa script 1dk mumlarla kapattı.`n- Başlangıç **`$$($baslangic.ToString('0.00', $inv))** → bitiş **`$$($son.ToString('0.00', $inv))** (%$yuzde) · İşlem: $n"
}
hermes cron run $rapor | Out-Null
Start-Sleep -Seconds 900  # rapor gönderilene kadar PC uyanık kalsın
