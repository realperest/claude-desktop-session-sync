<#
.SYNOPSIS
    Claude masaüstü uygulamasında (Code sekmesi) tüm hesapların oturum listesini ortak tutar.

.DESCRIPTION
    Uygulama oturum listesini hesap ve kuruluş kimliğine göre ayrı klasörlerde tutar:
        <veri>\claude-code-sessions\<hesapUUID>\<orgUUID>\local_*.json
    Hesap değişince yalnızca o hesabın klasörü listelenir; eski oturumlar silinmez ama görünmez.

    Uygulamanın yeni sürümleri bağlantı (junction/symlink) olan klasörlere yazmayı reddeder
    ("Refusing non-directory at private dir path"). Bu yüzden klasörler bağlanmaz, kopyalanarak eşitlenir.

    Bu betik:
      1. Uygulamanın veri klasörlerini bulur (MSIX paketi içi ve paket dışı Claude-Data).
      2. Veri klasörünün yeri önceki çalıştırmadakinden farklıysa uyarı verir (uygulama klasörü kendi taşıyabilir).
      3. Eski sürümün kurduğu bağlantıları gerçek klasöre çevirir.
      4. Bütün hesap/kuruluş klasörlerini çift yönlü eşitler: her kayıt dosyasının en yeni sürümü öteki
         klasörlere kopyalanır (değiştirilme zamanı korunur, gidip gelme olmaz).
      5. Kullanıcının sildiği oturumları (deleted_<cliSessionId> işareti) bütün klasörlere yayar; silinen
         oturumun kalan kopyalarını silmez, yedek klasörüne taşır.
      6. Sohbet dökümü (~/.claude/projects/*.jsonl) duran ama liste kaydı hiç yazılmamış masaüstü oturumlarını
         bulur, etkin klasörü yedekler ve eksik liste kaydını dökümden üretir. Son 15 dakikada açılan oturumlara
         ve uygulama günlüğüne göre başka bir oturuma ait eski CLI kimliklerine dokunmaz.
      7. Hesaba göre ayrı tutulan iki düz ayar dosyasını eşitler (yalnız uygulama kapalıyken; açıkken uygulama
         dosyayı kendi belleğindeki hâliyle yeniden yazar ve ekleme kaybolur).
      8. Arka planda izleyiciyi başlatır: izleyici 15 saniyede bir klasörleri eşitler, 10 dakikada bir onarım
         ve ayar eşitlemesi yapar. Böylece hesap değiştirildiği anda öteki hesabın klasörü zaten güncel olur.
    Kenar çubuğu özel grupları uygulamanın Local Storage (leveldb) deposundadır; betik bunlara dokunmaz.
    Hiçbir dosya silinmez. Her çalıştırma idempotenttir; yapacak iş yoksa hiçbir şey değiştirmez.
    Çıktı yalnızca bir değişiklik ya da uyarı olduğunda üretilir (Claude Code SessionStart kancası bu çıktıyı bağlama ekler).

.PARAMETER KuruCalisma
    Hiçbir değişiklik yapmadan yapılacakları günlüğe ve ekrana yazar. İzleyiciyi başlatmaz.

.PARAMETER Bildir
    Değişiklik ya da uyarı olursa kullanıcıya küçük bir pencereyle bildirir (Windows oturum açılışı görevi için).

.PARAMETER GorevKur
    Betiği Windows oturumu açılınca çalıştıran zamanlanmış görevi kurar (ya da günceller) ve çıkar.

.PARAMETER Izle
    Arka plan izleyicisi olarak sürekli çalışır (tek kopya). Normalde betik bunu kendisi başlatır.

.NOTES
    Günlük: %USERPROFILE%\Claude-hesap-esitleme\esitleme.log
    Durum:  %USERPROFILE%\Claude-hesap-esitleme\durum.json (son görülen veri klasörleri)
    Yedekler: %USERPROFILE%\Claude-hesap-esitleme\yedek\
#>
param(
    [switch]$KuruCalisma,
    [switch]$Bildir,
    [switch]$GorevKur,
    [switch]$Izle
)

$ErrorActionPreference = 'Stop'

$KokKlasor    = Join-Path $env:USERPROFILE 'Claude-hesap-esitleme'
$GunlukDosya  = Join-Path $KokKlasor 'esitleme.log'
$DurumDosya   = Join-Path $KokKlasor 'durum.json'
$YedekKlasor  = Join-Path $KokKlasor 'yedek'
$ProjeKlasoru = Join-Path $env:USERPROFILE '.claude\projects'
$UygulamaGunlugu = Join-Path $env:LOCALAPPDATA 'Claude\logs\main.log'
$GuidDeseni   = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
$GorevAdi     = 'Claude hesap oturum esitleme'
$KilitAdi     = 'Global\ClaudeHesapOturumEsitle'
$IzleyiciKilitAdi = 'Global\ClaudeHesapOturumIzle'
# Bu kadar günden eski dökümler onarılmaz (çok eski, bilerek kaldırılmış oturumlar geri gelmesin)
$OnarimGunu   = 30
# Bu kadar dakikadan yeni açılmış dökümler onarılmaz (uygulama liste kaydını henüz yazıyor olabilir)
$YeniDokumDakika = 15
# İzleyici aralıkları
$IzlemeSaniye = 15
$TamEsitlemeDakika = 10

$script:Bildirimler = New-Object System.Collections.Generic.List[string]
$script:YenidenAcGerekli = $false
$script:CliOnbellek = @{}

function Yaz-Gunluk {
    <#
    .SYNOPSIS
        Günlük dosyasına zaman damgalı satır ekler; kuru çalışmada ekrana da yazar.
    #>
    param([string]$Mesaj, [string]$Seviye = 'BILGI')
    $satir = '{0} [{1}] {2}' -f (Get-Date -Format 'dd.MM.yyyy HH:mm:ss'), $Seviye, $Mesaj
    if (-not (Test-Path $KokKlasor)) { New-Item -ItemType Directory -Force $KokKlasor | Out-Null }
    Add-Content -Path $GunlukDosya -Value $satir -Encoding UTF8
    # Fonksiyon dönüş değerlerini kirletmemek için çıktı hattı yerine doğrudan konsola yazılır
    if ($KuruCalisma) { [Console]::WriteLine($satir) }
}

function Kur-Gorev {
    <#
    .SYNOPSIS
        Betiği Windows oturumu açılınca -Bildir ile çalıştıran zamanlanmış görevi kurar ya da günceller.
    .DESCRIPTION
        Görev oturum açılışında eşitlemeyi uygulama açılmadan önce yapar ve arka plan izleyicisini başlatır.
        Görev yalnızca geçerli kullanıcı adına, yönetici yetkisi olmadan çalışır.
    #>
    $betik = $PSCommandPath
    $eylem = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Bildir' -f $betik)
    $tetik = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $ayar = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -StartWhenAvailable
    $kimlik = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $GorevAdi -Action $eylem -Trigger $tetik -Settings $ayar -Principal $kimlik `
        -Description 'Claude masaustu uygulamasinda hesaplar arasi ortak oturum listesini esitler ve eksik kayitlari onarir.' `
        -Force | Out-Null
    Yaz-Gunluk "Zamanlanmis gorev kuruldu: '$GorevAdi' (oturum acilisinda)."
    Write-Output "Zamanlanmis gorev kuruldu: $GorevAdi"
}

function Get-VeriKokleri {
    <#
    .SYNOPSIS
        Uygulamanın claude-code-sessions klasörlerini gerçek (sanallaştırılmamış) yollarıyla döndürür.
    .DESCRIPTION
        MSIX paketi %APPDATA%\Claude yolunu paket içine yönlendirir; bu yüzden %APPDATA% yolu yalnızca
        başka kök bulunamazsa kullanılır.
    #>
    $kokler = New-Object System.Collections.Generic.List[string]
    Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | ForEach-Object {
        $aday = Join-Path $_.FullName 'LocalCache\Roaming\Claude\claude-code-sessions'
        if (Test-Path $aday) { $kokler.Add($aday) }
    }
    Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Claude-Data') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $aday = Join-Path $_.FullName 'claude-code-sessions'
        if (Test-Path $aday) { $kokler.Add($aday) }
    }
    if ($kokler.Count -eq 0) {
        $aday = Join-Path $env:APPDATA 'Claude\claude-code-sessions'
        if (Test-Path $aday) { $kokler.Add($aday) }
    }
    return $kokler
}

function Denetle-KokTasinmasi {
    <#
    .SYNOPSIS
        Veri klasörlerinin yeri önceki çalıştırmadan farklıysa uyarı verir ve yeni durumu kaydeder.
    .DESCRIPTION
        Uygulama veri klasörünü kendiliğinden taşıyabilir (ör. Packages\...\Roaming\Claude -> Local\Claude-Data).
        Taşıma sırasında açılan oturumların liste kaydı yazılmayabilir; bu yüzden kullanıcı bilgilendirilir.
        Durum dosyası yalnızca kökler değişince yazılır (izleyici her turda diske yazmasın).
    #>
    param([string[]]$Kokler)
    $simdiki = @($Kokler | Sort-Object)
    $onceki = @()
    if (Test-Path $DurumDosya) {
        try {
            $durum = Get-Content $DurumDosya -Raw -Encoding UTF8 | ConvertFrom-Json
            $onceki = @($durum.kokler | Sort-Object)
        }
        catch {
            Yaz-Gunluk ("Durum dosyasi okunamadi, yeniden yazilacak: " + $_.Exception.Message) 'UYARI'
        }
    }
    $fark = Compare-Object -ReferenceObject $onceki -DifferenceObject $simdiki
    if ($onceki.Count -gt 0 -and $fark) {
        Yaz-Gunluk ("Veri klasorunun yeri degisti. Onceki: " + ($onceki -join '; ') + " | Simdiki: " + ($simdiki -join '; ')) 'UYARI'
        $script:Bildirimler.Add("Claude veri klasorunun yeri degisti (" + ($simdiki -join '; ') + "). Klasorler ve eksik kayitlar bu calistirmada esitlendi.")
        $script:YenidenAcGerekli = $true
    }
    if (-not $KuruCalisma -and ($fark -or $onceki.Count -eq 0)) {
        $metin = [ordered]@{ kokler = $simdiki; guncelleme = (Get-Date -Format 'dd.MM.yyyy HH:mm:ss') } | ConvertTo-Json
        [System.IO.File]::WriteAllText($DurumDosya, $metin, (New-Object System.Text.UTF8Encoding($false)))
    }
}

function Oku-GunlukSonu {
    <#
    .SYNOPSIS
        Uygulama günlüğünün son bölümünü (varsayılan 512 KB) paylaşımlı açarak satır dizisi olarak döndürür.
    #>
    param([long]$Bayt = 524288)
    if (-not (Test-Path $UygulamaGunlugu)) { return @() }
    $akis = New-Object System.IO.FileStream($UygulamaGunlugu, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        if ($akis.Length -gt $Bayt) { [void]$akis.Seek(-$Bayt, [System.IO.SeekOrigin]::End) }
        $okuyucu = New-Object System.IO.StreamReader($akis, [System.Text.Encoding]::UTF8)
        $metin = $okuyucu.ReadToEnd()
    }
    finally {
        $akis.Dispose()
    }
    return ($metin -split "`r?`n")
}

function Get-EtkinKlasor {
    <#
    .SYNOPSIS
        Uygulamanın şu an oturum listesini okuduğu hesap/kuruluş klasörünü bulur.
    .DESCRIPTION
        Önce uygulama günlüğündeki son "Loaded N persisted sessions from <yol>" satırına bakılır; günlük yoksa
        ya da yol bu kökte değilse en son değişen kayıt dosyasını taşıyan klasör seçilir.
    #>
    param([string]$Kok, [System.IO.DirectoryInfo[]]$Klasorler)
    try {
        $satirlar = Oku-GunlukSonu
        for ($i = $satirlar.Count - 1; $i -ge 0; $i--) {
            if ($satirlar[$i] -match 'Loaded \d+ persisted sessions from (.+\\claude-code-sessions\\[0-9a-f-]{36}\\[0-9a-f-]{36})\s*$') {
                $yol = $Matches[1]
                $eslesen = $Klasorler | Where-Object { $_.FullName -eq $yol } | Select-Object -First 1
                if ($eslesen) { return $eslesen }
                break
            }
        }
    }
    catch {
        Yaz-Gunluk ("Uygulama gunlugu okunamadi: " + $_.Exception.Message) 'UYARI'
    }
    $enYeni = $null
    $enYeniZaman = [datetime]::MinValue
    foreach ($k in $Klasorler) {
        $son = Get-ChildItem -LiteralPath $k.FullName -File -Filter 'local_*.json' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        $zaman = $(if ($son) { $son.LastWriteTimeUtc } else { $k.LastWriteTimeUtc })
        if ($zaman -gt $enYeniZaman) { $enYeniZaman = $zaman; $enYeni = $k }
    }
    return $enYeni
}

function Get-CliKimligi {
    <#
    .SYNOPSIS
        Bir liste kaydının cliSessionId alanını döndürür; dosya yolu ve değişme zamanına göre önbelleğe alır.
    #>
    param([System.IO.FileInfo]$Dosya)
    $anahtar = $Dosya.FullName + '|' + $Dosya.LastWriteTimeUtc.Ticks
    if ($script:CliOnbellek.ContainsKey($anahtar)) { return $script:CliOnbellek[$anahtar] }
    if ($script:CliOnbellek.Count -gt 2000) { $script:CliOnbellek.Clear() }
    $cli = $null
    try {
        $j = Get-Content -LiteralPath $Dosya.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($j.cliSessionId) { $cli = [string]$j.cliSessionId }
    }
    catch {
        Yaz-Gunluk ("Liste kaydi okunamadi: " + $Dosya.FullName + " | " + $_.Exception.Message) 'UYARI'
        return $null
    }
    $script:CliOnbellek[$anahtar] = $cli
    return $cli
}

function Kopyala-Atomik {
    <#
    .SYNOPSIS
        Dosyayı önce geçici ada kopyalar, sonra hedefin yerine tek adımda koyar; değişme zamanını korur.
    .DESCRIPTION
        Uygulama aynı anda okursa yarım dosya görmesin diye geçici dosya + File.Replace/File.Move kullanılır.
        Değişme zamanı kaynaktakiyle aynı tutulur; böylece klasörler arasında gidip gelen kopyalama olmaz.
    #>
    param([System.IO.FileInfo]$Kaynak, [string]$Hedef)
    $gecici = Join-Path (Split-Path $Hedef -Parent) ('.esitle_' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::Copy($Kaynak.FullName, $gecici, $true)
        [System.IO.File]::SetLastWriteTimeUtc($gecici, $Kaynak.LastWriteTimeUtc)
        if (Test-Path -LiteralPath $Hedef) {
            # PowerShell $null'u boş metne çevirir; yedek dosya istenmediğini .NET'e gerçek null ile bildirmek gerekir
            [System.IO.File]::Replace($gecici, $Hedef, [NullString]::Value)
        }
        else {
            [System.IO.File]::Move($gecici, $Hedef)
        }
        [System.IO.File]::SetLastWriteTimeUtc($Hedef, $Kaynak.LastWriteTimeUtc)
    }
    finally {
        if (Test-Path -LiteralPath $gecici) { Remove-Item -LiteralPath $gecici -Force }
    }
}

function Esitle-Kok {
    <#
    .SYNOPSIS
        Tek bir claude-code-sessions kökünde bütün hesap/kuruluş klasörlerini çift yönlü eşitler.
    .DESCRIPTION
        - Bağlantı (junction) olan klasörler gerçek klasöre çevrilir (yalnız bağlantının kendisi kaldırılır).
        - local_*.json ve deleted_* dosyalarının en yeni sürümü her klasöre kopyalanır.
        - deleted_<cliSessionId> işareti olan oturumun liste kayıtları yedek klasörüne taşınır.
        - Etkin klasöre (uygulamanın okuduğu) yeni kayıt geldiyse yeniden açma bildirimi verilir.
    .OUTPUTS
        Etkin klasörün tam yolu; uygun klasör yoksa $null.
    #>
    param([string]$Kok)

    $zaman = Get-Date -Format 'yyMMdd_HHmmss'

    # Hesap\kuruluş klasörlerini topla (yalnız GUID adlılar; _eski yedekleri hariç)
    $orgKlasorleri = @()
    Get-ChildItem $Kok -Directory -Force | Where-Object { $_.Name -match $GuidDeseni } | ForEach-Object {
        Get-ChildItem $_.FullName -Directory -Force | Where-Object { $_.Name -match $GuidDeseni } | ForEach-Object {
            $orgKlasorleri += $_
        }
    }
    if ($orgKlasorleri.Count -eq 0) { return $null }

    # 1. Bağlantıları gerçek klasöre çevir (uygulama bağlantılı klasöre yazmayı reddeder)
    foreach ($baglanti in @($orgKlasorleri | Where-Object { $_.LinkType })) {
        $etiket = "$($baglanti.Parent.Name)\$($baglanti.Name)"
        if ($KuruCalisma) {
            Yaz-Gunluk "[KURU] $etiket baglantisi gercek klasore cevrilecek."
            continue
        }
        # Yalnızca bağlantının kendisi silinir; hedefteki dosyalara dokunulmaz
        [System.IO.Directory]::Delete($baglanti.FullName, $false)
        New-Item -ItemType Directory -Path $baglanti.FullName | Out-Null
        Yaz-Gunluk "$etiket baglantisi gercek klasore cevrildi; icerigi esitlemeyle doldurulacak."
    }
    $klasorler = @(foreach ($k in $orgKlasorleri) {
        $guncel = Get-Item -LiteralPath $k.FullName -Force
        if (-not $guncel.LinkType) { $guncel }
    })
    if ($klasorler.Count -eq 0) { return $null }
    $etkin = Get-EtkinKlasor -Kok $Kok -Klasorler $klasorler
    if ($klasorler.Count -lt 2) { return $etkin.FullName }

    # 2. Dosya envanteri: ad -> bütün klasörlerdeki sürümler
    $surumler = @{}
    $silinen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($k in $klasorler) {
        Get-ChildItem -LiteralPath $k.FullName -File -Force | Where-Object { $_.Name -like 'local_*.json' -or $_.Name -like 'deleted_*' } | ForEach-Object {
            if (-not $surumler.ContainsKey($_.Name)) { $surumler[$_.Name] = New-Object System.Collections.Generic.List[System.IO.FileInfo] }
            $surumler[$_.Name].Add($_)
            if ($_.Name -like 'deleted_*') { [void]$silinen.Add($_.Name.Substring(8)) }
        }
    }

    $kopyalanan = 0
    $etkineGelen = 0
    $tasinan = 0
    foreach ($ad in @($surumler.Keys)) {
        $liste = $surumler[$ad]
        $enYeni = $liste | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1

        # Kullanıcının sildiği oturumun kalan kopyaları yedeğe taşınır (silinmez, geri de gelmez)
        if ($ad -like 'local_*.json') {
            $cli = Get-CliKimligi -Dosya $enYeni
            if ($cli -and $silinen.Contains($cli)) {
                foreach ($f in $liste) {
                    $hedefKlasor = Join-Path $YedekKlasor "${zaman}_silinen\$($f.Directory.Parent.Name)\$($f.Directory.Name)"
                    if ($KuruCalisma) {
                        Yaz-Gunluk "[KURU] Silinmis oturum kaydi yedege tasinacak: $($f.Directory.Parent.Name)\$($f.Directory.Name)\$ad"
                    }
                    else {
                        New-Item -ItemType Directory -Force $hedefKlasor | Out-Null
                        Move-Item -LiteralPath $f.FullName -Destination (Join-Path $hedefKlasor $ad) -Force
                        Yaz-Gunluk "Silinmis oturum kaydi yedege tasindi: $($f.Directory.Parent.Name)\$($f.Directory.Name)\$ad -> $hedefKlasor"
                    }
                    $tasinan++
                }
                continue
            }
        }

        foreach ($k in $klasorler) {
            $hedef = Join-Path $k.FullName $ad
            $mevcut = $liste | Where-Object { $_.DirectoryName -eq $k.FullName } | Select-Object -First 1
            if ($mevcut -and $mevcut.LastWriteTimeUtc -ge $enYeni.LastWriteTimeUtc) { continue }
            $etiket = "$($k.Parent.Name)\$($k.Name)\$ad"
            if ($KuruCalisma) {
                Yaz-Gunluk "[KURU] Kopyalanacak: $etiket"
            }
            else {
                try {
                    Kopyala-Atomik -Kaynak $enYeni -Hedef $hedef
                }
                catch {
                    # Uygulama dosyayı o an tutuyorsa sonraki turda yeniden denenir
                    Yaz-Gunluk ("Kopyalanamadi, sonra yeniden denenecek: " + $etiket + " | " + $_.Exception.Message) 'UYARI'
                    continue
                }
            }
            $kopyalanan++
            if ($etkin -and $k.FullName -eq $etkin.FullName -and $ad -like 'local_*.json' -and -not $mevcut) { $etkineGelen++ }
        }
    }

    if ($kopyalanan -gt 0 -or $tasinan -gt 0) {
        $onek = $(if ($KuruCalisma) { '[KURU] ' } else { '' })
        Yaz-Gunluk ("{0}Kok: {1} -> {2} dosya esitlendi, {3} silinmis kayit yedege tasindi, etkin klasor: {4}\{5}" -f $onek, $Kok, $kopyalanan, $tasinan, $etkin.Parent.Name, $etkin.Name)
    }
    if ($etkineGelen -gt 0 -and -not $KuruCalisma) {
        $script:Bildirimler.Add("$etkineGelen oturum etkin hesabin listesine eklendi.")
        $script:YenidenAcGerekli = $true
    }
    return $etkin.FullName
}

function Coz-JsonMetni {
    <#
    .SYNOPSIS
        JSON içinde kaçışlı duran bir metin değerini (tırnaksız) çözer.
    #>
    param([string]$Ham)
    return ('"' + $Ham + '"' | ConvertFrom-Json)
}

function Oku-DokumOzeti {
    <#
    .SYNOPSIS
        Bir sohbet dökümünden (.jsonl) liste kaydı için gereken alanları satır satır okuyarak çıkarır.
    .DESCRIPTION
        Uygulama dosyaya yazarken de okunabilsin diye dosya paylaşımlı açılır. Masaüstü uygulamasına ait
        olmayan (entrypoint farklı) dökümlerde okuma erken biter ve $null döner.
    .OUTPUTS
        cwd, ilk, son, dal, baslik, model, izin, ilkMesaj alanlarını taşıyan nesne ya da $null.
    #>
    param([string]$Yol)
    $ozet = @{ giris = $null; cwd = $null; ilk = $null; son = $null; dal = $null; baslik = $null; model = $null; izin = $null; ilkMesaj = $null }
    $akis = New-Object System.IO.FileStream($Yol, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $okuyucu = New-Object System.IO.StreamReader($akis, [System.Text.Encoding]::UTF8)
    try {
        $sira = 0
        while ($null -ne ($satir = $okuyucu.ReadLine())) {
            $sira++
            if (-not $ozet.giris -and $satir -match '"entrypoint":"([^"]+)"') {
                $ozet.giris = $Matches[1]
                if ($ozet.giris -ne 'claude-desktop') { return $null }
            }
            if (-not $ozet.giris -and $sira -gt 200) { return $null }
            if ($satir -match '"timestamp":"([^"]+)"') {
                if (-not $ozet.ilk) { $ozet.ilk = $Matches[1] }
                $ozet.son = $Matches[1]
            }
            if (-not $ozet.cwd -and $satir -match '"cwd":"((?:[^"\\]|\\.)*)"') { $ozet.cwd = Coz-JsonMetni $Matches[1] }
            if ($satir -match '"gitBranch":"((?:[^"\\]|\\.)*)"') { $ozet.dal = Coz-JsonMetni $Matches[1] }
            if ($satir -match '"type":"custom-title"' -and $satir -match '"customTitle":"((?:[^"\\]|\\.)*)"') { $ozet.baslik = Coz-JsonMetni $Matches[1] }
            if ($satir -match '"model":"(claude-[^"]+)"') { $ozet.model = $Matches[1] }
            if ($satir -match '"permissionMode":"([^"]+)"') { $ozet.izin = $Matches[1] }
            if (-not $ozet.ilkMesaj -and $satir -match '"type":"user"' -and $satir -match '"content":"((?:[^"\\]|\\.)*)"') {
                $metin = Coz-JsonMetni $Matches[1]
                if ($metin -and -not $metin.StartsWith('<')) { $ozet.ilkMesaj = $metin }
            }
        }
    }
    finally {
        $okuyucu.Dispose()
        $akis.Dispose()
    }
    if ($ozet.giris -ne 'claude-desktop') { return $null }
    return [pscustomobject]$ozet
}

function Get-EskiCliKimlikleri {
    <#
    .SYNOPSIS
        Uygulama günlüğüne göre hâlâ kaydı olan bir oturuma eşlenmiş CLI kimliklerini döndürür.
    .DESCRIPTION
        Uygulama bir oturumu zamanla yeni bir CLI kimliğine eşleyebilir (ör. konuşma temizlenince).
        Eski kimliğin dökümü kayıtsız görünür ama oturum yaşıyordur; bunu kopya olarak geri getirmemek için
        "Mapping internal session local_X to CLI session Y" satırlarındaki Y, local_X kaydı varsa atlanır.
    #>
    param([System.Collections.Generic.HashSet[string]]$YerelKimlikler)
    $eski = New-Object 'System.Collections.Generic.HashSet[string]'
    if (-not (Test-Path $UygulamaGunlugu)) { return ,$eski }
    try {
        Select-String -LiteralPath $UygulamaGunlugu -Pattern 'Mapping internal session (local_[0-9a-f-]{36}) to CLI session ([0-9a-f-]{36})' | ForEach-Object {
            $m = $_.Matches[0]
            if ($YerelKimlikler.Contains($m.Groups[1].Value)) { [void]$eski.Add($m.Groups[2].Value) }
        }
    }
    catch {
        Yaz-Gunluk ("Uygulama gunlugu taranamadi: " + $_.Exception.Message) 'UYARI'
    }
    return ,$eski
}

function Onar-EksikKayitlar {
    <#
    .SYNOPSIS
        Dökümü olup liste kaydı olmayan masaüstü oturumları için etkin klasörde liste kaydı üretir.
    .DESCRIPTION
        Bir oturumun liste kaydı (local_*.json) etkin klasörde yoksa ve şu koşulların hepsi tutuyorsa kayıt üretilir:
          - Döküm masaüstü uygulamasından (entrypoint = claude-desktop), alt ajan dökümü değil.
          - Son $OnarimGunu gün içinde değişmiş, $YeniDokumDakika dakikadan önce oluşturulmuş.
          - Kullanıcı silmemiş: deleted_<id> işareti ya da <id>.desktop-released.json yok.
          - Uygulama günlüğüne göre kaydı olan başka bir oturumun eski CLI kimliği değil.
          - Çalışma klasörü (cwd) hâlâ var.
        Yazmadan önce etkin klasörün tamamı yedeklenir. Var olan hiçbir dosya değiştirilmez.
    .OUTPUTS
        Onarılan kayıt sayısı.
    #>
    param([string]$Ana)
    if (-not (Test-Path $ProjeKlasoru)) { return 0 }

    $kayitli = New-Object 'System.Collections.Generic.HashSet[string]'
    $yerelKimlikler = New-Object 'System.Collections.Generic.HashSet[string]'
    $capalar = @{}
    $sablonIzin = 'default'
    Get-ChildItem $Ana -File -Filter 'local_*.json' | ForEach-Object {
        $dosya = $_
        [void]$yerelKimlikler.Add($dosya.BaseName)
        try {
            $j = Get-Content $dosya.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.cliSessionId) { [void]$kayitli.Add([string]$j.cliSessionId) }
            if ($j.originCwd -and $j.gitAnchors -and -not $capalar.ContainsKey($j.originCwd)) { $capalar[$j.originCwd] = $j.gitAnchors }
        }
        catch {
            Yaz-Gunluk ("Liste kaydi okunamadi: " + $dosya.Name + " | " + $_.Exception.Message) 'UYARI'
        }
    }
    $silinen = New-Object 'System.Collections.Generic.HashSet[string]'
    Get-ChildItem $Ana -File -Filter 'deleted_*' | ForEach-Object { [void]$silinen.Add($_.Name.Substring(8)) }

    $sinir = (Get-Date).AddDays(-$OnarimGunu)
    $yeniSinir = (Get-Date).AddMinutes(-$YeniDokumDakika)
    $adaylar = @(Get-ChildItem $ProjeKlasoru -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notmatch '\\subagents\\' -and $_.LastWriteTime -gt $sinir -and $_.CreationTime -lt $yeniSinir -and
        $_.BaseName -match $GuidDeseni -and
        -not $kayitli.Contains($_.BaseName) -and -not $silinen.Contains($_.BaseName) -and
        -not (Test-Path (Join-Path $_.DirectoryName ($_.BaseName + '.desktop-released.json')))
    })
    if ($adaylar.Count -eq 0) { return 0 }
    $eskiCli = Get-EskiCliKimlikleri -YerelKimlikler $yerelKimlikler

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $yedeklendi = $false
    $onarilan = 0
    foreach ($dokum in $adaylar) {
        $cli = $dokum.BaseName
        if ($eskiCli.Contains($cli)) { continue }
        try {
            $ozet = Oku-DokumOzeti -Yol $dokum.FullName
        }
        catch {
            Yaz-Gunluk ("Dokum okunamadi: " + $dokum.FullName + " | " + $_.Exception.Message) 'UYARI'
            continue
        }
        if (-not $ozet) { continue }
        if (-not $ozet.cwd -or -not (Test-Path $ozet.cwd)) { continue }

        # Worktree oturumu ise ana depo yolu ve dal bilgisi klasör adından çıkarılır
        $kokYol = $ozet.cwd
        $agacAdi = $null
        if ($ozet.cwd -match '^(.*?)\\\.claude\\worktrees\\([^\\]+)$') {
            $kokYol = $Matches[1]
            $agacAdi = $Matches[2]
        }
        $baslik = $ozet.baslik
        if (-not $baslik -and $ozet.ilkMesaj) { $baslik = ($ozet.ilkMesaj -replace '\s+', ' ').Trim() }
        if (-not $baslik) { $baslik = 'Kurtarilan oturum' }
        if ($baslik.Length -gt 80) { $baslik = $baslik.Substring(0, 80) }
        $ilkMs = [long]([DateTimeOffset]::Parse($ozet.ilk)).ToUnixTimeMilliseconds()
        $sonMs = [long]([DateTimeOffset]::Parse($ozet.son)).ToUnixTimeMilliseconds()

        $kayit = [ordered]@{
            sessionId      = 'local_' + [guid]::NewGuid().ToString()
            cliSessionId   = $cli
            cwd            = $ozet.cwd
            originCwd      = $kokYol
        }
        if ($agacAdi) {
            $kayit.worktreePath = $ozet.cwd
            $kayit.worktreeName = $agacAdi
            $kayit.sourceBranch = 'main'
        }
        if ($capalar.ContainsKey($kokYol)) {
            $kayit.gitAnchors = $capalar[$kokYol]
            $kayit.gitAnchorsLookupOnly = $true
        }
        if ($ozet.dal) { $kayit.branch = $ozet.dal }
        $kayit.createdAt      = $ilkMs
        $kayit.lastActivityAt = $sonMs
        $kayit.lastFocusedAt  = $sonMs
        $kayit.indexedAt      = $ilkMs
        if ($ozet.model) { $kayit.model = $ozet.model }
        $kayit.isArchived     = $false
        $kayit.title          = $baslik
        $kayit.titleSource    = 'tool'
        $kayit.permissionMode = $(if ($ozet.izin) { $ozet.izin } else { $sablonIzin })

        $hedef = Join-Path $Ana ($kayit.sessionId + '.json')
        if ($KuruCalisma) {
            Yaz-Gunluk "[KURU] Kaydi olmayan oturum onarilacak: $cli '$baslik' ($($ozet.cwd))"
            $onarilan++
            continue
        }
        if (-not $yedeklendi) {
            $yedekHedef = Join-Path $YedekKlasor ((Get-Date -Format 'yyMMdd_HHmmss') + '_onarim_oncesi')
            New-Item -ItemType Directory -Force $yedekHedef | Out-Null
            Copy-Item (Join-Path $Ana '*') $yedekHedef -Recurse -Force
            Yaz-Gunluk "Onarim oncesi yedek: $yedekHedef"
            $yedeklendi = $true
        }
        [System.IO.File]::WriteAllText($hedef, ($kayit | ConvertTo-Json -Depth 8), $utf8)
        Yaz-Gunluk "Kaydi olmayan oturum onarildi: $cli '$baslik' -> $($kayit.sessionId).json"
        $onarilan++
    }
    if ($onarilan -gt 0 -and -not $KuruCalisma) {
        $script:Bildirimler.Add("$onarilan oturumun eksik liste kaydi dokumden yeniden olusturuldu.")
        $script:YenidenAcGerekli = $true
    }
    return $onarilan
}

function Yaz-JsonAtomik {
    <#
    .SYNOPSIS
        Nesneyi JSON olarak önce geçici dosyaya yazar, sonra hedefin yerine tek adımda koyar.
    .DESCRIPTION
        Uygulama aynı dosyayı okurken yarım yazılmış içerik görmesin diye File.Replace kullanılır.
    #>
    param([string]$Yol, $Nesne)
    $gecici = $Yol + '.esitle.tmp'
    try {
        [System.IO.File]::WriteAllText($gecici, ($Nesne | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
        # PowerShell $null'u boş metne çevirir; yedek dosya istenmediğini .NET'e gerçek null ile bildirmek gerekir
        [System.IO.File]::Replace($gecici, $Yol, [NullString]::Value)
    }
    finally {
        if (Test-Path $gecici) { Remove-Item $gecici -Force }
    }
}

function Test-UygulamaAcik {
    <#
    .SYNOPSIS
        Claude masaüstü uygulamasının (MSIX paketindeki Claude.exe) çalışıp çalışmadığını döndürür.
    #>
    $surec = Get-Process -Name 'claude' -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -match '\\WindowsApps\\Claude_' } catch { $false }
    } | Select-Object -First 1
    return [bool]$surec
}

function Esitle-HesapAyarlari {
    <#
    .SYNOPSIS
        Hesaba göre ayrı tutulan ortam ayarlarını ve MCP araç seçimlerini iki hesapta aynı yapar.
    .DESCRIPTION
        - ccd-session-presets.json: byAccount.<hesap>.presets listeleri kimliğe (id) göre birleştirilir;
          her hesapta eksik olan ayar eklenir, var olan hiçbir ayar değiştirilmez ya da silinmez.
        - mcp-user-tool-toggles.json: owners.<hesap> listeleri birleştirilir.
        Uygulama açıkken çalışmaz: uygulama bu dosyaları kendi belleğindeki hâliyle yeniden yazdığı için
        ekleme kaybolur ve her çalıştırmada aynı ekleme tekrarlanırdı. Değişiklik gerekiyorsa önce dosya
        yedeklenir. Ayar değerleri günlüğe yazılmaz; kullanıcıya bildirim gönderilmez.
    #>
    param([string]$VeriKlasoru)
    if (Test-UygulamaAcik) { return }
    $zaman = Get-Date -Format 'yyMMdd_HHmmss'

    # 1. Kayıtlı ortam ayarları
    $presetDosya = Join-Path $VeriKlasoru 'ccd-session-presets.json'
    if (Test-Path $presetDosya) {
        $p = Get-Content $presetDosya -Raw -Encoding UTF8 | ConvertFrom-Json
        $hesaplar = @($p.byAccount.PSObject.Properties)
        if ($hesaplar.Count -ge 2) {
            $tumu = [ordered]@{}
            foreach ($h in $hesaplar) {
                foreach ($x in @($h.Value.presets)) { if ($x -and $x.id -and -not $tumu.Contains([string]$x.id)) { $tumu[[string]$x.id] = $x } }
            }
            $eklenen = 0
            foreach ($h in $hesaplar) {
                $liste = New-Object System.Collections.Generic.List[object]
                foreach ($x in @($h.Value.presets)) { if ($x) { $liste.Add($x) } }
                $varOlan = @($liste | ForEach-Object { [string]$_.id })
                foreach ($id in $tumu.Keys) {
                    if ($varOlan -notcontains $id) { $liste.Add($tumu[$id]); $eklenen++ }
                }
                $h.Value.presets = [object[]]$liste.ToArray()
            }
            if ($eklenen -gt 0) {
                if ($KuruCalisma) {
                    Yaz-Gunluk "[KURU] Ortam ayarlari esitlenecek: $eklenen ayar eksik hesaba eklenecek."
                }
                else {
                    $yedekHedef = Join-Path $YedekKlasor "${zaman}_ayar_oncesi"
                    New-Item -ItemType Directory -Force $yedekHedef | Out-Null
                    Copy-Item $presetDosya $yedekHedef -Force
                    Yaz-JsonAtomik -Yol $presetDosya -Nesne $p
                    Yaz-Gunluk "Ortam ayarlari esitlendi: $eklenen ayar eksik hesaba eklendi. Yedek: $yedekHedef"
                }
            }
        }
    }

    # 2. MCP araç seçimleri
    $secimDosya = Join-Path $VeriKlasoru 'mcp-user-tool-toggles.json'
    if (Test-Path $secimDosya) {
        $s = Get-Content $secimDosya -Raw -Encoding UTF8 | ConvertFrom-Json
        $sahipler = @($s.owners.PSObject.Properties)
        if ($sahipler.Count -ge 2) {
            $tumu = [ordered]@{}
            foreach ($o in $sahipler) {
                foreach ($x in @($o.Value)) { if ($null -ne $x) { $anahtar = ($x | ConvertTo-Json -Compress -Depth 10); if (-not $tumu.Contains($anahtar)) { $tumu[$anahtar] = $x } } }
            }
            $eklenen = 0
            foreach ($o in $sahipler) {
                $liste = New-Object System.Collections.Generic.List[object]
                foreach ($x in @($o.Value)) { if ($null -ne $x) { $liste.Add($x) } }
                $varOlan = @($liste | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 10 })
                foreach ($anahtar in $tumu.Keys) {
                    if ($varOlan -notcontains $anahtar) { $liste.Add($tumu[$anahtar]); $eklenen++ }
                }
                $s.owners.($o.Name) = [object[]]$liste.ToArray()
            }
            if ($eklenen -gt 0) {
                if ($KuruCalisma) {
                    Yaz-Gunluk "[KURU] MCP arac secimleri esitlenecek: $eklenen secim eksik hesaba eklenecek."
                }
                else {
                    $yedekHedef = Join-Path $YedekKlasor "${zaman}_ayar_oncesi"
                    New-Item -ItemType Directory -Force $yedekHedef | Out-Null
                    Copy-Item $secimDosya $yedekHedef -Force
                    Yaz-JsonAtomik -Yol $secimDosya -Nesne $s
                    Yaz-Gunluk "MCP arac secimleri esitlendi: $eklenen secim eksik hesaba eklendi. Yedek: $yedekHedef"
                }
            }
        }
    }
}

function Gonder-Bildirimler {
    <#
    .SYNOPSIS
        Bildirimleri kancaya çıktı olarak ya da -Bildir/-Izle ile kullanıcıya pencereyle iletir; sonra listeyi boşaltır.
    #>
    if ($script:Bildirimler.Count -eq 0) { return }
    $metin = ($script:Bildirimler -join "`n")
    if ($script:YenidenAcGerekli) { $metin += "`nClaude aciksa listeyi gormek icin uygulamayi tepsiden tamamen kapatip yeniden acin." }
    $metin += "`nGunluk: $GunlukDosya"
    $script:Bildirimler.Clear()
    $script:YenidenAcGerekli = $false
    if ($Bildir -or $Izle) {
        try {
            $kabuk = New-Object -ComObject WScript.Shell
            [void]$kabuk.Popup($metin, 120, 'Claude hesap esitleme', 64)
        }
        catch {
            Yaz-Gunluk ("Bildirim penceresi acilamadi: " + $_.Exception.Message) 'UYARI'
        }
    }
    else {
        Write-Output ("Claude hesap esitleme: " + $metin + "`nKullaniciya bu durumu bildir.")
    }
}

function Calistir-Esitleme {
    <#
    .SYNOPSIS
        Bir eşitleme turu çalıştırır: klasör eşitleme, isteğe bağlı onarım ve ayar eşitleme.
    .PARAMETER Tam
        Onarım ve ayar eşitlemesini de yapar (izleyici bunu seyrek, kanca ve oturum açılışı her zaman yapar).
    #>
    param([switch]$Tam)
    $kokler = @(Get-VeriKokleri)
    if ($kokler.Count -eq 0) {
        if ($Tam) { Yaz-Gunluk 'Claude veri klasoru bulunamadi.' 'UYARI' }
        return
    }
    Denetle-KokTasinmasi -Kokler $kokler
    foreach ($kok in $kokler) {
        $etkinKlasor = Esitle-Kok -Kok $kok
        if (-not $Tam) { continue }
        if ($etkinKlasor) {
            try {
                $onarilan = Onar-EksikKayitlar -Ana $etkinKlasor
                # Onarılan kayıtlar hemen öteki hesap klasörlerine de yayılsın
                if ($onarilan -gt 0 -and -not $KuruCalisma) { [void](Esitle-Kok -Kok $kok) }
            }
            catch {
                Yaz-Gunluk ("Eksik kayit onarimi hatasi: " + $_.Exception.Message + " | " + $_.ScriptStackTrace) 'HATA'
            }
        }
        try {
            Esitle-HesapAyarlari -VeriKlasoru (Split-Path $kok -Parent)
        }
        catch {
            Yaz-Gunluk ("Hesap ayarlari esitleme hatasi: " + $_.Exception.Message + " | " + $_.ScriptStackTrace) 'HATA'
        }
    }
}

function Test-IzleyiciCalisiyor {
    <#
    .SYNOPSIS
        Arka plan izleyicisinin kilidi sistemde varsa (izleyici çalışıyorsa) $true döndürür.
    #>
    $m = $null
    if ([System.Threading.Mutex]::TryOpenExisting($IzleyiciKilitAdi, [ref]$m)) {
        $m.Dispose()
        return $true
    }
    return $false
}

function Baslat-Izleyici {
    <#
    .SYNOPSIS
        Arka plan izleyicisi çalışmıyorsa gizli pencerede başlatır.
    .DESCRIPTION
        Süreç WMI (Win32_Process.Create) ile başlatılır; böylece Claude Code kancasının iş nesnesinden
        (job object) bağımsız olur ve kanca bitince kapanmaz.
    #>
    if (Test-IzleyiciCalisiyor) { return }
    $komut = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Izle' -f $PSCommandPath
    try {
        $baslangic = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
        $sonuc = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $komut; ProcessStartupInformation = $baslangic }
        if ($sonuc.ReturnValue -ne 0) {
            Yaz-Gunluk ("Izleyici baslatilamadi, WMI donus kodu: " + $sonuc.ReturnValue) 'HATA'
        }
    }
    catch {
        Yaz-Gunluk ("Izleyici baslatilamadi: " + $_.Exception.Message) 'HATA'
    }
}

function Calistir-Izleyici {
    <#
    .SYNOPSIS
        Arka planda sürekli çalışır: 15 saniyede bir klasörleri, 10 dakikada bir onarım ve ayarları eşitler.
    .DESCRIPTION
        Tek kopya çalışır (sistem genelinde kilit). Betik dosyası değişirse kendini yeni sürümle yeniden başlatır.
        Hatalar günlüğe yazılır, izleyici durmaz.
    #>
    $izKilit = New-Object System.Threading.Mutex($false, $IzleyiciKilitAdi)
    $alindi = $false
    try {
        $alindi = $izKilit.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        $alindi = $true
    }
    if (-not $alindi) { $izKilit.Dispose(); return }

    $surum = (Get-Item -LiteralPath $PSCommandPath).LastWriteTimeUtc
    Yaz-Gunluk "Izleyici basladi (PID $PID)."
    $sonTam = [datetime]::MinValue
    $yenidenBaslat = $false
    try {
        while ($true) {
            $tam = ((Get-Date) - $sonTam).TotalMinutes -ge $TamEsitlemeDakika
            $kilit = New-Object System.Threading.Mutex($false, $KilitAdi)
            $kilitAlindi = $false
            try {
                try { $kilitAlindi = $kilit.WaitOne(5000) }
                catch [System.Threading.AbandonedMutexException] { $kilitAlindi = $true }
                if ($kilitAlindi) {
                    Calistir-Esitleme -Tam:$tam
                    if ($tam) { $sonTam = Get-Date }
                }
            }
            catch {
                Yaz-Gunluk ("Izleyici turu hatasi: " + $_.Exception.Message + " | " + $_.ScriptStackTrace) 'HATA'
            }
            finally {
                if ($kilitAlindi) { $kilit.ReleaseMutex() }
                $kilit.Dispose()
            }
            Gonder-Bildirimler
            Start-Sleep -Seconds $IzlemeSaniye
            if ((Get-Item -LiteralPath $PSCommandPath).LastWriteTimeUtc -ne $surum) {
                Yaz-Gunluk "Betik degisti; izleyici yeni surumle yeniden baslatiliyor."
                $yenidenBaslat = $true
                break
            }
        }
    }
    finally {
        $izKilit.ReleaseMutex()
        $izKilit.Dispose()
    }
    if ($yenidenBaslat) { Baslat-Izleyici }
}

if ($GorevKur) {
    Kur-Gorev
    exit 0
}

if ($Izle) {
    try {
        Calistir-Izleyici
    }
    catch {
        Yaz-Gunluk ("Izleyici durdu: " + $_.Exception.Message + " | " + $_.ScriptStackTrace) 'HATA'
    }
    exit 0
}

# Aynı anda başlayan oturumların çakışmaması için sistem genelinde kilit
$kilit = New-Object System.Threading.Mutex($false, $KilitAdi)
$kilitAlindi = $false
try {
    try {
        $kilitAlindi = $kilit.WaitOne(15000)
    }
    catch [System.Threading.AbandonedMutexException] {
        # Önceki çalıştırma yarıda kaldıysa kilit yine de bize geçer
        $kilitAlindi = $true
        Yaz-Gunluk 'Onceki calistirmadan kalan kilit devralindi.' 'UYARI'
    }
    if (-not $kilitAlindi) {
        Yaz-Gunluk 'Kilit 15 saniyede alinamadi; baska bir esitleme calisiyor, atlandi.' 'UYARI'
    }
    else {
        Calistir-Esitleme -Tam
        Gonder-Bildirimler
    }
}
catch {
    # Kanca oturumu engellemesin: hata günlüğe yazılır, çıkış kodu 0 kalır
    Yaz-Gunluk ("Hata: " + $_.Exception.Message + " | " + $_.ScriptStackTrace) 'HATA'
}
finally {
    if ($kilitAlindi) { $kilit.ReleaseMutex() }
    $kilit.Dispose()
}
if (-not $KuruCalisma) { Baslat-Izleyici }
exit 0
