<#
.SYNOPSIS
    Claude masaüstü uygulamasında hesaplar arası ortak oturum listesi düzenini bir bilgisayara kurar ya da kaldırır.

.DESCRIPTION
    Kurulum adımları:
      1. Kullanıcı klasörünü ve Claude veri klasörünü bulur.
      2. settings.json, CLAUDE.md ve varsa eski eşitleme betiğini yedekler (Claude-hesap-esitleme\yedek\kurulum_<zaman>).
      3. hesap-oturum-esitle.ps1 dosyasını Claude-hesap-esitleme klasörüne kopyalar.
      4. ~/.claude/settings.json içine SessionStart kancasını ekler; öteki ayarlara ve kancalara dokunmaz, kanca varsa çoğaltmaz.
      5. ~/.claude/CLAUDE.md içine "Claude Account Switching" maddesini bu bilgisayarın yollarıyla yazar; madde varsa yeniler.
      6. Windows oturum açılışında çalışan zamanlanmış görevi kurar.
      7. Eşitlemeyi önce kuru, sonra gerçek olarak çalıştırır.
    Bir adım hata verirse o ana kadar değişen dosyalar yedekten geri yüklenir; kurulum yarım kalmaz.
    Her adım ekrana ve Claude-hesap-esitleme\kurulum.log dosyasına yazılır.

.PARAMETER Deneme
    Hiçbir şeyi değiştirmeden yapılacakları gösterir.

.PARAMETER Kaldir
    Kancayı, CLAUDE.md maddesini ve zamanlanmış görevi kaldırır. Oturum klasörlerindeki bağlantılara ve
    kayıtlara dokunmaz (kaldırmak oturumları yeniden gizler); betik ve yedekler yerinde kalır.

.PARAMETER GorevKurma
    Zamanlanmış görevi kurmaz.

.PARAMETER EsitlemeAtla
    Kurulumdan sonra eşitlemeyi çalıştırmaz.

.PARAMETER KullaniciKlasoru
    Kurulumun yapılacağı kullanıcı klasörü. Varsayılan: %USERPROFILE%. Deneme amaçlı geçici klasör verilebilir.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\kur.ps1 -Deneme
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\kur.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\kur.ps1 -Kaldir
#>
param(
    [switch]$Deneme,
    [switch]$Kaldir,
    [switch]$GorevKurma,
    [switch]$EsitlemeAtla,
    [string]$KullaniciKlasoru = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'

$Kaynak        = $PSScriptRoot
$BetikAdi      = 'hesap-oturum-esitle.ps1'
$KaynakBetik   = Join-Path $Kaynak $BetikAdi
$Sablon        = Join-Path $Kaynak 'sablon\claude-md-bolum.md'
$Hedef         = Join-Path $KullaniciKlasoru 'Claude-hesap-esitleme'
$HedefBetik    = Join-Path $Hedef $BetikAdi
$ClaudeKlasoru = Join-Path $KullaniciKlasoru '.claude'
$AyarDosyasi   = Join-Path $ClaudeKlasoru 'settings.json'
$ClaudeMd      = Join-Path $ClaudeKlasoru 'CLAUDE.md'
$GunlukDosya   = Join-Path $Hedef 'kurulum.log'
$Zaman         = Get-Date -Format 'yyMMdd_HHmmss'
$KurulumYedek  = Join-Path $Hedef "yedek\kurulum_$Zaman"
$GorevAdi      = 'Claude hesap oturum esitleme'
$Basla         = '<!-- CLAUDE_BIRLESTIR:BASLA -->'
$Bitis         = '<!-- CLAUDE_BIRLESTIR:BITIS -->'

# Hata olursa geri alınacak değişiklikler: @{ Yol; Yedek; YeniMi }
$script:Degisenler = New-Object System.Collections.Generic.List[object]
$script:GorevKuruldu = $false

function Yaz {
    <#
    .SYNOPSIS
        Mesajı ekrana ve (deneme değilse) kurulum günlüğüne yazar.
    #>
    param([string]$Mesaj, [string]$Seviye = 'BILGI')
    $onek = $(if ($Deneme) { '[DENEME] ' } else { '' })
    $satir = '{0} [{1}] {2}{3}' -f (Get-Date -Format 'dd.MM.yyyy HH:mm:ss'), $Seviye, $onek, $Mesaj
    Write-Host $satir
    if (-not $Deneme -and (Test-Path $Hedef)) { Add-Content -Path $GunlukDosya -Value $satir -Encoding UTF8 }
}

function Oku-Metin {
    <#
    .SYNOPSIS
        Metin dosyasını okur; UTF-8 BOM olup olmadığını ve satır sonu türünü de döndürür.
    #>
    param([string]$Yol)
    if (-not (Test-Path $Yol)) { return @{ Metin = ''; Bom = $false; SatirSonu = "`r`n"; Var = $false } }
    $bayt = [System.IO.File]::ReadAllBytes($Yol)
    $bom = ($bayt.Length -ge 3 -and $bayt[0] -eq 0xEF -and $bayt[1] -eq 0xBB -and $bayt[2] -eq 0xBF)
    $metin = [System.Text.Encoding]::UTF8.GetString($bayt, $(if ($bom) { 3 } else { 0 }), $bayt.Length - $(if ($bom) { 3 } else { 0 }))
    $satirSonu = $(if ($metin.Contains("`r`n") -or -not $metin.Contains("`n")) { "`r`n" } else { "`n" })
    return @{ Metin = $metin; Bom = $bom; SatirSonu = $satirSonu; Var = $true }
}

function Yedekle-VeKaydet {
    <#
    .SYNOPSIS
        Değişecek dosyayı kurulum yedeğine kopyalar ve geri alma listesine ekler.
    #>
    param([string]$Yol)
    foreach ($d in $script:Degisenler) { if ($d.Yol -eq $Yol) { return } }
    if (Test-Path $Yol) {
        $ad = ($Yol.Substring($KullaniciKlasoru.Length).TrimStart('\') -replace '[\\/:]', '_')
        $yedek = Join-Path $KurulumYedek $ad
        Copy-Item $Yol $yedek -Force
        $script:Degisenler.Add(@{ Yol = $Yol; Yedek = $yedek; YeniMi = $false })
    }
    else {
        $script:Degisenler.Add(@{ Yol = $Yol; Yedek = $null; YeniMi = $true })
    }
}

function Yaz-Metin {
    <#
    .SYNOPSIS
        Metni önce geçici dosyaya, sonra hedefin yerine tek adımda yazar (BOM tercihi korunur).
    #>
    param([string]$Yol, [string]$Metin, [bool]$Bom)
    $klasor = Split-Path $Yol -Parent
    if (-not (Test-Path $klasor)) { New-Item -ItemType Directory -Force $klasor | Out-Null }
    $gecici = $Yol + '.kur.tmp'
    try {
        [System.IO.File]::WriteAllText($gecici, $Metin, (New-Object System.Text.UTF8Encoding($Bom)))
        if (Test-Path $Yol) { [System.IO.File]::Replace($gecici, $Yol, [NullString]::Value) }
        else { [System.IO.File]::Move($gecici, $Yol) }
    }
    finally {
        if (Test-Path $gecici) { Remove-Item $gecici -Force }
    }
}

function Get-VeriKlasoru {
    <#
    .SYNOPSIS
        Claude masaüstü uygulamasının gerçek veri klasörünü bulur (MSIX paketi içi ya da Claude-Data).
    #>
    $adaylar = @()
    Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Claude-Data') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $adaylar += $_.FullName }
    Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | ForEach-Object {
        $adaylar += (Join-Path $_.FullName 'LocalCache\Roaming\Claude')
    }
    foreach ($a in $adaylar) { if (Test-Path (Join-Path $a 'claude-code-sessions')) { return $a } }
    foreach ($a in $adaylar) { if (Test-Path $a) { return $a } }
    return $null
}

function Get-KancaKomutu {
    <#
    .SYNOPSIS
        settings.json içine yazılacak SessionStart kanca komutunu üretir.
    #>
    return ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f ($HedefBetik -replace '\\', '/'))
}

function Guncelle-Ayar {
    <#
    .SYNOPSIS
        settings.json içindeki SessionStart kancasını ekler, günceller ya da kaldırır.
    .DESCRIPTION
        Yalnızca komutunda hesap-oturum-esitle.ps1 geçen kanca girdilerine dokunulur. Dosya geçerli JSON değilse
        hiçbir şey yazılmaz ve kurulum durur.
    #>
    param([bool]$KaldirMi)
    $dosya = Oku-Metin $AyarDosyasi
    if ($dosya.Var -and $dosya.Metin.Trim()) {
        try { $ayar = $dosya.Metin | ConvertFrom-Json }
        catch { throw "settings.json gecerli JSON degil, elle duzeltilmesi gerekiyor: $($_.Exception.Message)" }
    }
    else {
        $ayar = New-Object psobject
    }
    $istenen = Get-KancaKomutu
    if (-not $ayar.PSObject.Properties['hooks']) {
        if ($KaldirMi) { Yaz 'settings.json: kanca zaten yok.'; return }
        $ayar | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object psobject)
    }
    $girdiler = New-Object System.Collections.Generic.List[object]
    if ($ayar.hooks.PSObject.Properties['SessionStart']) { foreach ($g in @($ayar.hooks.SessionStart)) { if ($null -ne $g) { $girdiler.Add($g) } } }

    $bulundu = $false
    $degisti = $false
    $yeniGirdiler = New-Object System.Collections.Generic.List[object]
    foreach ($g in $girdiler) {
        $kancalar = New-Object System.Collections.Generic.List[object]
        foreach ($k in @($g.hooks)) {
            if ($null -eq $k) { continue }
            if ($k.command -and $k.command -like "*$BetikAdi*") {
                $bulundu = $true
                if ($KaldirMi) { $degisti = $true; continue }
                if ($k.command -ne $istenen) { $k.command = $istenen; $degisti = $true }
            }
            $kancalar.Add($k)
        }
        if ($kancalar.Count -gt 0) {
            $g.hooks = [object[]]$kancalar.ToArray()
            $yeniGirdiler.Add($g)
        }
    }
    if (-not $bulundu -and -not $KaldirMi) {
        $yeni = [pscustomobject]@{ hooks = [object[]]@([pscustomobject][ordered]@{ type = 'command'; command = $istenen; timeout = 60 }) }
        $yeniGirdiler.Add($yeni)
        $degisti = $true
    }
    if (-not $degisti) {
        Yaz $(if ($KaldirMi) { 'settings.json: kanca zaten yok.' } else { 'settings.json: kanca zaten dogru, degisiklik yok.' })
        return
    }
    if ($yeniGirdiler.Count -gt 0) {
        if ($ayar.hooks.PSObject.Properties['SessionStart']) { $ayar.hooks.SessionStart = [object[]]$yeniGirdiler.ToArray() }
        else { $ayar.hooks | Add-Member -NotePropertyName SessionStart -NotePropertyValue ([object[]]$yeniGirdiler.ToArray()) }
    }
    else {
        $ayar.hooks.PSObject.Properties.Remove('SessionStart')
        if (@($ayar.hooks.PSObject.Properties).Count -eq 0) { $ayar.PSObject.Properties.Remove('hooks') }
    }
    $islem = $(if ($KaldirMi) { 'kaldirilacak' } elseif ($bulundu) { 'guncellenecek' } else { 'eklenecek' })
    if ($Deneme) { Yaz "settings.json: SessionStart kancasi $islem."; return }
    Yedekle-VeKaydet $AyarDosyasi
    Yaz-Metin -Yol $AyarDosyasi -Metin ($ayar | ConvertTo-Json -Depth 50) -Bom $dosya.Bom
    # Yazılan dosyanın yeniden okunabildiğini doğrula
    $null = (Get-Content $AyarDosyasi -Raw -Encoding UTF8 | ConvertFrom-Json)
    Yaz "settings.json: SessionStart kancasi $($islem -replace 'acak$','di' -replace 'ecek$','di')."
}

function Guncelle-ClaudeMd {
    <#
    .SYNOPSIS
        CLAUDE.md içine hesap değiştirme maddesini yazar, yeniler ya da kaldırır.
    .DESCRIPTION
        Madde işaretlerle (CLAUDE_BIRLESTIR:BASLA / BITIS) sarılır. İşaretsiz eski bir "Claude Account Switching"
        maddesi varsa aynı numarayla yenisiyle değiştirilir. Yoksa son madde numarasının bir fazlasıyla sona eklenir.
    #>
    param([bool]$KaldirMi)
    $dosya = Oku-Metin $ClaudeMd
    $metin = $dosya.Metin
    $ss = $dosya.SatirSonu
    $blokDeseni = '(?s)(\r?\n)*' + [regex]::Escape($Basla) + '.*?' + [regex]::Escape($Bitis) + '[ \t]*(\r?\n)?'
    $eskiDeseni = '(?ms)^(\d+)\.\s+Claude Account Switching \(Shared Session List\)\s*$.*?(?=^\d+\.\s|\z)'

    if ($KaldirMi) {
        if ($metin -notmatch $blokDeseni) { Yaz 'CLAUDE.md: kurulumun ekledigi madde yok.'; return }
        $yeniMetin = [regex]::Replace($metin, $blokDeseni, $ss)
        if ($Deneme) { Yaz 'CLAUDE.md: madde kaldirilacak.'; return }
        Yedekle-VeKaydet $ClaudeMd
        Yaz-Metin -Yol $ClaudeMd -Metin $yeniMetin -Bom $dosya.Bom
        Yaz 'CLAUDE.md: madde kaldirildi.'
        return
    }

    $no = $null
    $mBlok = [regex]::Match($metin, $blokDeseni)
    $mEski = [regex]::Match($metin, $eskiDeseni)
    if ($mBlok.Success) {
        $mNo = [regex]::Match($mBlok.Value, '(?m)^(\d+)\.\s+Claude Account Switching')
        if ($mNo.Success) { $no = $mNo.Groups[1].Value }
    }
    elseif ($mEski.Success) {
        $no = $mEski.Groups[1].Value
    }
    if (-not $no) {
        $en = 0
        foreach ($m in [regex]::Matches($metin, '(?m)^(\d+)\.\s')) { $n = [int]$m.Groups[1].Value; if ($n -gt $en) { $en = $n } }
        $no = [string]($en + 1)
    }

    $veri = Get-VeriKlasoru
    $sablonMetni = [System.IO.File]::ReadAllText($Sablon, [System.Text.Encoding]::UTF8)
    $bolum = $sablonMetni.Replace('{{NO}}', $no).Replace('{{BETIK_KLASORU}}', $Hedef).Replace('{{CLAUDE_KLASORU}}', $ClaudeKlasoru).
        Replace('{{VERI_KLASORU}}', $(if ($veri) { $veri } else { 'bulunamadi (uygulama hic acilmamis olabilir)' })).
        Replace('{{TARIH}}', (Get-Date -Format 'dd.MM.yyyy'))
    $bolum = ($bolum -replace "\r?\n", $ss).TrimEnd() + $ss

    if ($mBlok.Success) {
        $yeniMetin = $metin.Substring(0, $mBlok.Index).TrimEnd() + $ss + $ss + $bolum + $metin.Substring($mBlok.Index + $mBlok.Length).TrimStart("`r", "`n")
        $islem = 'yenilendi'
    }
    elseif ($mEski.Success) {
        $sonrasi = $metin.Substring($mEski.Index + $mEski.Length)
        $yeniMetin = $metin.Substring(0, $mEski.Index) + $bolum + $(if ($sonrasi) { $ss + $sonrasi } else { '' })
        $islem = 'eski isaretsiz madde yenisiyle degistirildi'
    }
    else {
        $yeniMetin = $(if ($metin.Trim()) { $metin.TrimEnd() + $ss + $ss } else { '' }) + $bolum
        $islem = "$no. madde olarak eklendi"
    }
    if ($yeniMetin -eq $metin) { Yaz 'CLAUDE.md: madde zaten guncel.'; return }
    if ($Deneme) { Yaz "CLAUDE.md: madde ($no) $(if ($mBlok.Success) { 'yenilenecek' } elseif ($mEski.Success) { 'eski isaretsiz maddenin yerine yazilacak' } else { 'eklenecek' })."; return }
    Yedekle-VeKaydet $ClaudeMd
    Yaz-Metin -Yol $ClaudeMd -Metin $yeniMetin -Bom $dosya.Bom
    Yaz "CLAUDE.md: madde $islem."
}

function Kopyala-Betik {
    <#
    .SYNOPSIS
        Eşitleme betiğini hedef klasöre kopyalar; içerik aynıysa dokunmaz.
    #>
    if ((Test-Path $HedefBetik) -and ((Get-FileHash $HedefBetik).Hash -eq (Get-FileHash $KaynakBetik).Hash)) {
        Yaz 'Esitleme betigi zaten guncel.'
        return
    }
    if ($Deneme) { Yaz "Esitleme betigi kopyalanacak: $HedefBetik"; return }
    Yedekle-VeKaydet $HedefBetik
    Copy-Item $KaynakBetik $HedefBetik -Force
    Yaz "Esitleme betigi kopyalandi: $HedefBetik"
}

function Ayarla-Gorev {
    <#
    .SYNOPSIS
        Oturum açılışı görevini kurar ya da kaldırır.
    #>
    param([bool]$KaldirMi)
    $var = $null -ne (Get-ScheduledTask -TaskName $GorevAdi -ErrorAction SilentlyContinue)
    if ($KaldirMi) {
        if (-not $var) { Yaz 'Zamanlanmis gorev zaten yok.'; return }
        if ($Deneme) { Yaz 'Zamanlanmis gorev kaldirilacak.'; return }
        Unregister-ScheduledTask -TaskName $GorevAdi -Confirm:$false
        Yaz 'Zamanlanmis gorev kaldirildi.'
        return
    }
    if ($Deneme) { Yaz $(if ($var) { 'Zamanlanmis gorev yeni betik yoluyla yenilenecek.' } else { 'Zamanlanmis gorev kurulacak.' }); return }
    $cikti = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HedefBetik -GorevKur 2>&1
    if (-not (Get-ScheduledTask -TaskName $GorevAdi -ErrorAction SilentlyContinue)) { throw "Zamanlanmis gorev kurulamadi: $cikti" }
    if (-not $var) { $script:GorevKuruldu = $true }
    Yaz 'Zamanlanmis gorev kuruldu (Windows oturum acilisinda calisir).'
}

function Calistir-Esitleme {
    <#
    .SYNOPSIS
        Eşitlemeyi önce kuru, sonra (deneme değilse) gerçek olarak çalıştırır ve çıktıyı gösterir.
    #>
    $betik = $(if (Test-Path $HedefBetik) { $HedefBetik } else { $KaynakBetik })
    Yaz 'Esitleme kuru calisma:'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $betik -KuruCalisma | ForEach-Object { Write-Host "    $_" }
    if ($Deneme) { return }
    Yaz 'Esitleme gercek calisma:'
    $cikti = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $betik
    if ($cikti) { $cikti | ForEach-Object { Write-Host "    $_" } } else { Write-Host '    Yapilacak is yoktu.' }
}

function Geri-Al {
    <#
    .SYNOPSIS
        Hata durumunda bu çalıştırmada değişen dosyaları yedekten geri yükler, yeni oluşanları siler.
    #>
    for ($i = $script:Degisenler.Count - 1; $i -ge 0; $i--) {
        $d = $script:Degisenler[$i]
        try {
            if ($d.YeniMi) { if (Test-Path $d.Yol) { Remove-Item $d.Yol -Force } }
            else { Copy-Item $d.Yedek $d.Yol -Force }
            Yaz "Geri alindi: $($d.Yol)" 'UYARI'
        }
        catch {
            Yaz "Geri alinamadi: $($d.Yol) | $($_.Exception.Message) | yedek: $($d.Yedek)" 'HATA'
        }
    }
    if ($script:GorevKuruldu) {
        try { Unregister-ScheduledTask -TaskName $GorevAdi -Confirm:$false; Yaz 'Geri alindi: zamanlanmis gorev' 'UYARI' }
        catch { Yaz "Zamanlanmis gorev geri alinamadi: $($_.Exception.Message)" 'HATA' }
    }
}

# --- Ana akış ---
try {
    if (-not (Test-Path $KaynakBetik)) { throw "Kaynak betik bulunamadi: $KaynakBetik" }
    if (-not (Test-Path $Sablon)) { throw "CLAUDE.md sablonu bulunamadi: $Sablon" }
    if (-not (Test-Path $KullaniciKlasoru)) { throw "Kullanici klasoru bulunamadi: $KullaniciKlasoru" }
    if (-not $Deneme) {
        New-Item -ItemType Directory -Force $Hedef | Out-Null
        New-Item -ItemType Directory -Force $KurulumYedek | Out-Null
    }
    $veri = Get-VeriKlasoru
    Yaz ("Basladi. Mod: {0} | Kullanici klasoru: {1} | Claude veri klasoru: {2}" -f $(if ($Kaldir) { 'kaldirma' } else { 'kurulum' }), $KullaniciKlasoru, $(if ($veri) { $veri } else { 'bulunamadi' }))
    if (-not $veri -and -not $Kaldir) { Yaz 'Claude veri klasoru bulunamadi. Uygulamayi bir kez acip giris yaptiktan sonra kurulumu yeniden calistirin; kanca yine de kurulur.' 'UYARI' }

    if ($Kaldir) {
        Guncelle-Ayar -KaldirMi $true
        Guncelle-ClaudeMd -KaldirMi $true
        if (-not $GorevKurma) { Ayarla-Gorev -KaldirMi $true }
        Yaz "Kaldirma bitti. Betik, gunluk ve yedekler yerinde birakildi: $Hedef. Oturum klasorlerindeki baglantilara dokunulmadi."
    }
    else {
        Kopyala-Betik
        Guncelle-Ayar -KaldirMi $false
        Guncelle-ClaudeMd -KaldirMi $false
        if ($GorevKurma) { Yaz 'Zamanlanmis gorev atlandi (-GorevKurma).' } else { Ayarla-Gorev -KaldirMi $false }
        if ($EsitlemeAtla) { Yaz 'Esitleme atlandi (-EsitlemeAtla).' } else { Calistir-Esitleme }
        Yaz 'Kurulum bitti.'
        Write-Host ''
        Write-Host 'Sonraki adimlar:'
        Write-Host '  1. Claude uygulamasini tepsideki simgeden tamamen kapatip yeniden acin.'
        Write-Host '  2. Iki hesaba da bu bilgisayarda en az bir kez giris yapin. Bir hesaba ilk kez giris yaptiysaniz bir kez daha cikis yapip girin.'
        Write-Host '  3. Hesap degistirince kenar cubugundaki listeyi kontrol edin. Eksik varsa: hesap-oturum-esitle.ps1 -KuruCalisma ve esitleme.log'
        if (-not $Deneme) { Write-Host "  Kurulum gunlugu: $GunlukDosya | Yedekler: $KurulumYedek" }
    }
}
catch {
    Yaz ("Hata: " + $_.Exception.Message) 'HATA'
    if (-not $Deneme) {
        Geri-Al
        Yaz "Kurulum durduruldu ve yapilan degisiklikler geri alindi. Yedekler: $KurulumYedek" 'HATA'
    }
    exit 1
}
exit 0
