# 19.10 scalp simülasyonu: 16:30'dan Claude oturum limiti dolana kadar (en geç 23:00) tarama.
# İşlem yokken 10 dk'da bir; açık işlemde 30 dk'da bir, ama fiyat SL/TP'ye değerse hemen tur + 10 dk'ya dönüş.
# Limit dolunca durur, limit sıfırlansa da devam etmez. Bitince Hermes raporunu tetikler.
$dir = (Get-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Artifical*\Scalp Panel')).FullName
Set-Location -LiteralPath $dir
Add-Type -Namespace W -Name P -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
[W.P]::SetThreadExecutionState([uint32]2147483649) | Out-Null  # script bitene kadar uyku yok
$claude = "$env:USERPROFILE\.local\bin\claude.exe"
$tv = "$env:USERPROFILE\tradingview-mcp\src\cli\index.js"
$log = Join-Path $dir 'oto.log'
$gunluk = Join-Path $dir 'islem-gunlugu-2026-10-19.md'
$basla = Get-Date '2026-10-19 16:30'
$bitis = Get-Date '2026-10-19 23:00'  # güvenlik sınırı; normalde limit daha önce dolar
$rapor = '9279d2b37bb8'

if (-not ((node $tv status) -match '"cdp_connected": true')) {
    Start-Process node -ArgumentList "`"$tv`" launch" -WindowStyle Hidden  # görünür pencere açılmasın
    Start-Sleep 60
}
while ((Get-Date) -lt $basla) { Start-Sleep -Seconds 5 }
$talimat = Get-Content -Raw -Encoding UTF8 (Join-Path $dir 'tarama.txt')

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
while ((Get-Date) -lt $bitis) {
    $t0 = Get-Date
    if (Tur) { $limit = $true; break }
    $satir = AcikSatir
    if ($satir) {
        while ((Get-Date) -lt $t0.AddMinutes(30) -and (Get-Date) -lt $bitis) {
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
    Tur | Out-Null  # 23:00 gün sonu turu
}
hermes cron run $rapor | Out-Null
Start-Sleep -Seconds 900  # rapor gönderilene kadar PC uyanık kalsın
