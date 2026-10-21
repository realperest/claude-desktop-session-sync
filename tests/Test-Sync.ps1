<#
.SYNOPSIS
    hesap-oturum-esitle.ps1 için uçtan uca test. Gerçek Claude verisine dokunmaz.

.DESCRIPTION
    Geçici bir klasörde sahte bir Claude veri yapısı kurar, LOCALAPPDATA ve USERPROFILE ortam
    değişkenlerini oraya yönlendirerek eşitleme betiğini bir kez çalıştırır ve sonucu doğrular:
      1. Yalnız bir klasörde olan geçerli kayıt bütün klasörlere kopyalanır.
      2. Eski kimliğine (priorCliSessionIds) bağlı silme işareti olan kayıt yedeğe taşınır,
         işaret bütün klasörlere yayılır.
      3. En yeni sürümü bozuk olan kayıt kopyalanmaz; bozuk kopya yerinde kalır, sağlam sürüm
         kaydın olmadığı klasörlere gider.
      4. Yarım yazılmış (geçersiz JSON) en yeni sürüm kopyalanmaz.
      5. Junction olan bir hesap klasörü gerçek klasöre çevrilir ve doldurulur.
      6. Kaydı olmayan bir masaüstü dökümü için liste kaydı onarılır.
    Başarısız bir kontrol olursa çıkış kodu 1 olur.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Sync.ps1
#>
$ErrorActionPreference = 'Stop'

$betik = Join-Path (Split-Path $PSScriptRoot -Parent) 'hesap-oturum-esitle.ps1'
$kok = Join-Path ([System.IO.Path]::GetTempPath()) ('claude-sync-test-' + [guid]::NewGuid().ToString('N'))
$lad = Join-Path $kok 'LocalAppData'
$usr = Join-Path $kok 'User'
$ses = Join-Path $lad 'Claude-Data\claude_test\claude-code-sessions'
$A = '11111111-1111-1111-1111-111111111111'; $B = '22222222-2222-2222-2222-222222222222'
$O1 = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; $O2 = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
$AO1 = Join-Path $ses "$A\$O1"; $AO2 = Join-Path $ses "$A\$O2"; $BO1 = Join-Path $ses "$B\$O1"; $BO2 = Join-Path $ses "$B\$O2"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:hata = 0

function Yaz-Dosya($klasor, $ad, $icerik, $zaman) {
    <#
    .SYNOPSIS
        Verilen içerikle dosya yazar ve değişme zamanını ayarlar.
    #>
    $yol = Join-Path $klasor $ad
    [System.IO.File]::WriteAllText($yol, $icerik, $utf8)
    (Get-Item $yol).LastWriteTime = $zaman
}

function Dogrula([string]$Ad, [bool]$Kosul) {
    <#
    .SYNOPSIS
        Bir kontrolün sonucunu yazar; başarısızsa hata sayacını artırır.
    #>
    if ($Kosul) { Write-Host "  GECTI  $Ad" }
    else { Write-Host "  KALDI  $Ad" -ForegroundColor Red; $script:hata++ }
}

function Oku([string]$Yol) {
    <#
    .SYNOPSIS
        Dosya varsa içeriğini, yoksa $null döndürür.
    #>
    if (Test-Path -LiteralPath $Yol) { return [System.IO.File]::ReadAllText($Yol) }
    return $null
}

try {
    foreach ($d in $AO1, $AO2, $BO1) { New-Item -ItemType Directory -Force $d | Out-Null }
    $t0 = (Get-Date).AddHours(-3)

    # 1. Yalnız A\O1'de olan geçerli kayıt
    Yaz-Dosya $AO1 'local_s1.json' '{"sessionId":"local_s1","cliSessionId":"c1","title":"one"}' $t0
    # 2. Eski kimliği silinmiş kayıt
    $s2 = '{"sessionId":"local_s2","cliSessionId":"c2new","priorCliSessionIds":["c2old"],"title":"two"}'
    Yaz-Dosya $AO1 'local_s2.json' $s2 $t0
    Yaz-Dosya $BO1 'local_s2.json' $s2 $t0
    Yaz-Dosya $BO1 'deleted_c2old' '1792000000000' $t0
    # 3. En yeni sürümü bozuk (sessionId uyuşmuyor)
    Yaz-Dosya $BO1 'local_s3.json' '{"sessionId":"local_s3","cliSessionId":"c3","title":"three sound"}' $t0
    Yaz-Dosya $AO2 'local_s3.json' '{"sessionId":"BROKEN","cliSessionId":"c3","title":"three broken"}' $t0.AddHours(1)
    # 4. En yeni sürümü yarım yazılmış
    Yaz-Dosya $AO1 'local_s4.json' '{"sessionId":"local_s4","cli' $t0.AddHours(2)
    Yaz-Dosya $BO1 'local_s4.json' '{"sessionId":"local_s4","cliSessionId":"c4","title":"four sound"}' $t0
    # 5. Junction olan klasör (eski sürümlerin kurduğu yapı)
    New-Item -ItemType Junction -Path $BO2 -Target $AO1 | Out-Null
    # 6. Kaydı olmayan masaüstü dökümü
    $calisma = Join-Path $kok 'proje'
    New-Item -ItemType Directory -Force $calisma | Out-Null
    $projeKlasoru = Join-Path $usr '.claude\projects\test-proje'
    New-Item -ItemType Directory -Force $projeKlasoru | Out-Null
    $cwdJson = ($calisma | ConvertTo-Json)
    $damga = (Get-Date).AddHours(-2).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $dokum = @(
        '{"type":"user","entrypoint":"claude-desktop","cwd":' + $cwdJson + ',"timestamp":"' + $damga + '","message":{"role":"user","content":"rebuild me"}}'
        '{"type":"custom-title","customTitle":"Recovered test session"}'
    ) -join "`n"
    $dokumYolu = Join-Path $projeKlasoru '55555555-5555-5555-5555-555555555555.jsonl'
    [System.IO.File]::WriteAllText($dokumYolu, $dokum, $utf8)
    # Onarım son 15 dakikada oluşturulan dökümlere dokunmaz; oluşturma zamanı geriye alınır
    (Get-Item $dokumYolu).CreationTime = (Get-Date).AddHours(-2)

    $env:LOCALAPPDATA = $lad
    $env:USERPROFILE = $usr
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $betik -IzleyiciBaslatma | Out-Null

    Write-Host "Sonuclar:"
    $hepsi = @($AO1, $AO2, $BO1, $BO2)
    Dogrula '1. gecerli kayit butun klasorlere kopyalandi' (@($hepsi | Where-Object { Test-Path (Join-Path $_ 'local_s1.json') }).Count -eq 4)
    Dogrula '2. silinen kayit hicbir klasorde kalmadi' (@($hepsi | Where-Object { Test-Path (Join-Path $_ 'local_s2.json') }).Count -eq 0)
    $yedek = Join-Path $usr 'Claude-hesap-esitleme\yedek'
    Dogrula '2. silinen kayit yedege tasindi' (@(Get-ChildItem $yedek -Recurse -Filter 'local_s2.json' -ErrorAction SilentlyContinue).Count -ge 2)
    Dogrula '2. silme isareti butun klasorlere yayildi' (@($hepsi | Where-Object { Test-Path (Join-Path $_ 'deleted_c2old') }).Count -eq 4)
    Dogrula '3. bozuk kopya yerinde kaldi' ((Oku (Join-Path $AO2 'local_s3.json')) -match 'BROKEN')
    Dogrula '3. saglam surum eksik klasore gitti' ((Oku (Join-Path $AO1 'local_s3.json')) -match 'three sound')
    Dogrula '4. yarim kopya yerinde kaldi' ((Oku (Join-Path $AO1 'local_s4.json')) -eq '{"sessionId":"local_s4","cli')
    Dogrula '4. saglam surum eksik klasore gitti' ((Oku (Join-Path $AO2 'local_s4.json')) -match 'four sound')
    $bo2 = Get-Item -LiteralPath $BO2 -Force
    Dogrula '5. junction gercek klasore cevrildi' (-not $bo2.LinkType)
    Dogrula '5. cevrilen klasor dolduruldu' (Test-Path (Join-Path $BO2 'local_s1.json'))
    $onarilan = @(Get-ChildItem $AO1 -Filter 'local_*.json' | Where-Object { (Oku $_.FullName) -match '55555555-5555-5555-5555-555555555555' })
    Dogrula '6. kaydi olmayan dokum icin kayit onarildi' ($onarilan.Count -eq 1)
    if ($onarilan.Count -eq 1) {
        Dogrula '6. onarilan kaydin basligi dokumden alindi' ((Oku $onarilan[0].FullName) -match 'Recovered test session')
    }
}
finally {
    if (Test-Path $kok) {
        $bag = Get-Item -LiteralPath $BO2 -Force -ErrorAction SilentlyContinue
        # Junction kaldıysa yalnız bağlantı silinir, hedefe dokunulmaz
        if ($bag -and $bag.LinkType) { [System.IO.Directory]::Delete($BO2, $false) }
        Remove-Item $kok -Recurse -Force
    }
}

if ($script:hata -gt 0) {
    Write-Host "$($script:hata) kontrol basarisiz." -ForegroundColor Red
    exit 1
}
Write-Host "Butun kontroller gecti."
exit 0
