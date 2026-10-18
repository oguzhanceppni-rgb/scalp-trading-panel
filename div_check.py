"""Scalp Panel divF() mantığının Python kopyası + testler.
Kullanım: python div_check.py            -> sentetik testler
          python div_check.py bars.json  -> gerçek barlarda son durum (TradingView data_get_ohlcv çıktısı)
"""
import json
import sys


def rsi(closes, n=14):
    # TradingView ta.rsi: Wilder RMA, ilk değer SMA ile tohumlanır
    out = [None] * len(closes)
    gains, losses = [], []
    ag = al = None
    for i in range(1, len(closes)):
        ch = closes[i] - closes[i - 1]
        g, l = max(ch, 0.0), max(-ch, 0.0)
        if ag is None:
            gains.append(g)
            losses.append(l)
            if len(gains) == n:
                ag, al = sum(gains) / n, sum(losses) / n
        else:
            ag = (ag * (n - 1) + g) / n
            al = (al * (n - 1) + l) / n
        if ag is not None:
            out[i] = 100.0 if al == 0 else 100 - 100 / (1 + ag / al)
    return out


def pivot(vals, i, pv, high):
    # ta.pivothigh/low(src, pv, pv): bar i-pv, solunda ve sağında pv bar boyunca en uç değer
    c = i - pv
    if c - pv < 0:
        return None
    win = vals[c - pv:i + 1]
    v = vals[c]
    if high:
        return v if all(v > x for j, x in enumerate(win) if j != pv) else None
    return v if all(v < x for j, x in enumerate(win) if j != pv) else None


def div_state(highs, lows, closes, pv=3, n=14):
    r = rsi(closes, n)
    pH = rH = pL = rL = None
    d, at = 0, None
    for i in range(len(closes)):
        ph = pivot(highs, i, pv, True)
        pl = pivot(lows, i, pv, False)
        if ph is not None and r[i - pv] is not None:
            if pH is not None and ph > pH and r[i - pv] < rH:
                d, at = -1, i
            elif d == -1:
                d = 0
            pH, rH = ph, r[i - pv]
        if pl is not None and r[i - pv] is not None:
            if pL is not None and pl < pL and r[i - pv] > rL:
                d, at = 1, i
            elif d == 1:
                d = 0
            pL, rL = pl, r[i - pv]
        if d == -1 and closes[i] > pH:
            d = 0
        if d == 1 and closes[i] < pL:
            d = 0
    return d, (len(closes) - 1 - at) if at is not None else None


def tests():
    # Yükseliş: önce güçlü tepe, sonra RSI'ı zayıf daha yüksek tepe → ayı uyumsuzluğu
    up = [100 + i * 2 for i in range(20)]                       # güçlü yükseliş
    seg1 = up + [140, 137, 135, 134, 133, 134]                   # tepe 1 (140, tekil) ve geri çekilme
    seg2 = [134.5, 135, 135.5, 136, 141, 140, 139, 138]          # yavaş tırmanış, tepe 2 (141 > 140) zayıf RSI
    closes = seg1 + seg2
    highs = [c + 1 for c in closes]
    lows = [c - 1 for c in closes]
    d, _ = div_state(highs, lows, closes)
    assert d == -1, f"ayı uyumsuzluğu bekleniyordu, d={d}"

    # Aynı seri + fiyat tepe 2'nin üstünde kapanırsa → geçersiz
    c2 = closes + [143]
    d, _ = div_state([c + 1 for c in c2], [c - 1 for c in c2], c2)
    assert d == 0, f"kapanışla iptal bekleniyordu, d={d}"

    # Aynı seri + güçlü yeni tepe (RSI de yükselir) pivot olarak onaylanırsa → geçersiz
    c3 = closes + [137, 145, 152, 158, 150, 146, 144]
    d, _ = div_state([c + 1 for c in c3], [c - 1 for c in c3], c3)
    assert d == 0, f"uyumsuzluksuz yeni tepeyle iptal bekleniyordu, d={d}"

    # Ayna: boğa uyumsuzluğu
    m = [200 - c for c in closes]
    d, _ = div_state([c + 1 for c in m], [c - 1 for c in m], m)
    assert d == 1, f"boğa uyumsuzluğu bekleniyordu, d={d}"
    # Kapanmış mum kuralı: tepe 2'nin pivotu ancak son (oluşmakta olan) mumla onaylanıyorsa sayılmaz
    d, _ = div_state(highs[:-1], lows[:-1], closes[:-1])
    assert d == 0, f"oluşmakta olan mumla onaylanan uyumsuzluk sayılmamalıydı, d={d}"
    print("testler geçti (5/5)")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        bars = json.load(open(sys.argv[1], encoding="utf-8"))["bars"]
        closed = "--closed" in sys.argv
        if closed:
            bars = bars[:-1]  # son (oluşmakta olan) mumu at, panelin divClosed() ile aynı
        d, ago = div_state([b["high"] for b in bars], [b["low"] for b in bars], [b["close"] for b in bars])
        if closed and ago is not None:
            ago += 1
        print({0: "-", 1: "Boğa", -1: "Ayı"}[d], "" if ago is None or d == 0 else f"{ago} bar önce")
    else:
        tests()
