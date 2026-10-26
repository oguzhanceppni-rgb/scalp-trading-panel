# Hafta içi her gün (ScalpSim Pzt–Cum 16:15) scalp simülasyonu: 16:20–19:00 yeni işlem taraması; 19:00'da açık işlem varsa TP/SL'e kadar izlenir (güvenlik 23:45). Claude limiti dolarsa erken durur.
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
$basla = Get-Date "$bugun 16:20"
$bitis = Get-Date "$bugun 19:00"  # yeni işlem sonu
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
while ((Get-Date) -lt $basla) { Start-Sleep -Seconds 5 }
$talimat = (Get-Content -Raw -Encoding UTF8 (Join-Path $dir 'tarama.txt')) -replace '\d\d\.\d\d\.20\d\d', (Get-Date -Format 'dd.MM.yyyy') -replace 'islem-gunlugu-\d{4}-\d\d-\d\d', "islem-gunlugu-$bugun"

function Tur {  # $true döner: Claude limiti doldu
    $p = "Şu an: $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n$talimat"
    $p = $p.Replace('"','\"')  # PS 5.1 iç tırnakları kaçırmaz; yoksa prompt ilk " işaretinde bölünür
    $out = & $claude -p $p --allowedTools mcp__tradingview Read Edit Write 'Bash(python *)' 2>&1
    Add-Content -LiteralPath $log -Encoding UTF8 "=== $(Get-Date -Format HH:mm:ss)`n$($out -join "`n")"
    return [bool](($out -join "`n") -match "hit your .*limit")
}

function AcikSatir { Select-String -LiteralPath $gunluk -Pattern '\|\s*AÇIK\s*\|' -Encoding UTF8 | Select-Object -First 1 }

function Dokundu($satir) {  # grafikteki son 5dk barı açık işlemin SL veya TP'sine değdi mi
    $c = $satir.Line.Split('|') | ForEach-Object { $_.Trim() }  # 1 #, 2 açılış, 3 parite, 4 yön, 5 giriş, 6 SL, 7 TP
    $sayi = { param($s) [double]::Parse([regex]::Match($s, '\d+(\.\d+)?').Value, [Globalization.CultureInfo]::InvariantCulture) }
    $sl = & $sayi $c[6]; $tp = & $sayi $c[7]
    try { $q = (node $tv quote) -join "`n" | ConvertFrom-Json } catch { return $false }
    if (-not $q.success -or $q.symbol -notmatch [regex]::Escape($c[3])) { return $false }  # grafik başka sembolde: 30 dk dolsun
    if ($c[4] -match 'LONG') { return ($q.low -le $sl -or $q.high -ge $tp) }
    return ($q.high -ge $sl -or $q.low -le $tp)
}

$limit = $false
while (((Get-Date) -lt $bitis) -or ((AcikSatir) -and (Get-Date) -lt $sinir)) {  # 19:00 sonrası yalnızca açık işlem varken
    $t0 = Get-Date
    if (Tur) { $limit = $true; break }
    $satir = AcikSatir
    if ($satir) {
        while ((Get-Date) -lt $t0.AddMinutes(30) -and (Get-Date) -lt $sinir) {
            Start-Sleep -Seconds 60
            if (Dokundu $satir) { break }  # SL/TP'ye değdi: hemen tur, sonra 10 dk düzeni
        }
    } else {
        $kalan = [Math]::Min(($t0.AddMinutes(10) - (Get-Date)).TotalSeconds, ($bitis - (Get-Date)).TotalSeconds)
        if ($kalan -gt 0) { Start-Sleep -Seconds $kalan }
    }
}

if ($limit) {
    $acik = if (AcikSatir) { 'Açık işlem KAPATILAMADI, tabloda AÇIK duruyor (son tur dışında P/L hesaplanmadı).' } else { 'Açık işlem yok.' }
    Add-Content -LiteralPath $gunluk -Encoding UTF8 "`n## Gün sonu (otomatik)`n- $(Get-Date -Format HH:mm): Claude oturum limiti doldu, tarama durduruldu (talimat gereği sonraki oturuma geçilmedi). $acik"
} else {
    Tur | Out-Null  # gün sonu turu (19:00 sonrası, açık işlem kalmadığında ya da 23:45 sınırında)
}
hermes cron run $rapor | Out-Null
Start-Sleep -Seconds 900  # rapor gönderilene kadar PC uyanık kalsın
