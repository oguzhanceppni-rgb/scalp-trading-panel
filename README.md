# Scalp Panel

TradingView için teknik analiz paneli + otomatik tarama botu (simülasyon, gerçek para yok).

- `scalp-panel.pine` — Pine v6 göstergesi: VWMA/RSI uyumsuzluğu, ICT bölgeleri, premium/discount, BOS, risk/R:R tablosu.
- `div_check.py` — göstergedeki `divF()` mantığının Python kopyası + testler (`python div_check.py`).
- `oto-scalp.ps1` — [tradingview-mcp](https://github.com/tradesdontlie/tradingview-mcp) ve `claude -p` ile periyodik tarama turu çalıştıran PowerShell döngüsü.
- `tarama.txt` — her turda Claude'a verilen talimat (kurallar, makro filtre, işlem açma/kapama).
- `gosterge-ayarlari.md` — grafikteki yardımcı gösterge ayarları.

İşlem günlükleri ve loglar repoya dahil değildir.
