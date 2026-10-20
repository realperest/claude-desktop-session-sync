<#
.SYNOPSIS
    Claude masaüstü uygulamasında (Code sekmesi) tüm hesapların oturum listesini tek klasörde ortaklaştırır.

.DESCRIPTION
    Uygulama oturum listesini hesap ve kuruluş kimliğine göre ayrı klasörlerde tutar:
        <veri>\claude-code-sessions\<hesapUUID>\<orgUUID>\local_*.json
    Hesap değişince yalnızca o hesabın klasörü listelenir; eski oturumlar silinmez ama görünmez.

    Bu betik:
      1. Uygulamanın veri klasörlerini bulur (MSIX paketi içi ve paket dışı Claude-Data).
      2. Veri klasörünün yeri önceki çalıştırmadakinden farklıysa uyarı verir (uygulama klasörü kendi taşıyabilir).
      3. En son kullanılan gerçek klasörü "ana klasör" seçer.
      4. Öteki gerçek klasörlerdeki oturum kayıtlarını ana klasöre kopyalar (eksik ya da daha yeni olanları).
      5. Öteki klasörü yedekler, adını <ad>_eski_<zaman> yapar ve yerine ana klasöre NTFS bağlantısı (junction) kurar.
      6. Kırık ya da başka yeri gösteren bağlantıları ana klasöre yeniden yönlendirir.
      7. Sohbet dökümü (~/.claude/projects/*.jsonl) duran ama liste kaydı hiç yazılmamış masaüstü oturumlarını
         bulur, ana klasörü yedekler ve eksik liste kaydını dökümden üretir. Son 15 dakikada açılan oturumlara
         dokunmaz (uygulama kaydını henüz yazmamış olabilir; çift kayıt oluşmasın).
      8. Hesaba göre ayrı tutulan iki düz ayar dosyasını eşitler: kayıtlı ortam ayarları (ccd-session-presets.json,
         kimliğe göre birleşim) ve MCP araç seçimleri (mcp-user-tool-toggles.json, birleşim). Önce yedek alır.
    Kenar çubuğu özel grupları uygulamanın Local Storage (leveldb) deposundadır; betik bunlara dokunmaz.
    Hiçbir dosya silinmez. Her çalıştırma idempotenttir; yapacak iş yoksa hiçbir şey değiştirmez.
    Çıktı yalnızca bir değişiklik ya da uyarı olduğunda üretilir (Claude Code SessionStart kancası bu çıktıyı bağlama ekler).

.PARAMETER KuruCalisma
    Hiçbir değişiklik yapmadan yapılacakları günlüğe ve ekrana yazar.

.PARAMETER Bildir
    Değişiklik ya da uyarı olursa kullanıcıya küçük bir pencereyle bildirir (Windows oturum açılışı görevi için).

.PARAMETER GorevKur
    Betiği Windows oturumu açılınca çalıştıran zamanlanmış görevi kurar (ya da günceller) ve çıkar.

.NOTES
    Günlük: %USERPROFILE%\Claude-hesap-esitleme\esitleme.log
    Durum:  %USERPROFILE%\Claude-hesap-esitleme\durum.json (son görülen veri klasörleri)
    Yedekler: %USERPROFILE%\Claude-hesap-esitleme\yedek\
    Birleştirilen ya da onarılan liste, uygulama tepsiden tamamen kapatılıp açılınca görünür.
#>
param(
    [switch]$KuruCalisma,
    [switch]$Bildir,
    [switch]$GorevKur
)

$ErrorActionPreference = 'Stop'

$KokKlasor    = Join-Path $env:USERPROFILE 'Claude-hesap-esitleme'
$GunlukDosya  = Join-Path $KokKlasor 'esitleme.log'
$DurumDosya   = Join-Path $KokKlasor 'durum.json'
$YedekKlasor  = Join-Path $KokKlasor 'yedek'
$ProjeKlasoru = Join-Path $env:USERPROFILE '.claude\projects'
$GuidDeseni   = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
$GorevAdi     = 'Claude hesap oturum esitleme'
# Bu kadar günden eski dökümler onarılmaz (çok eski, bilerek kaldırılmış oturumlar geri gelmesin)
$OnarimGunu   = 30
# Bu kadar dakikadan yeni açılmış dökümler onarılmaz (uygulama liste kaydını henüz yazıyor olabilir)
$YeniDokumDakika = 15

$script:Bildirimler = New-Object System.Collections.Generic.List[string]
$script:YenidenAcGerekli = $false

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
        SessionStart kancası uygulama oturum listesini okuduktan sonra çalışır; bu görev onarımı uygulama
        açılmadan önce yapma şansı verir. Görev yalnızca geçerli kullanıcı adına, yönetici yetkisi olmadan çalışır.
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
        MSIX paketi %APPDATA%\Claude yolunu paket içine yönlendirir. Bağlantı hedefleri çekirdek tarafından
        çözüldüğü için hedef her zaman gerçek yol olmalıdır; bu yüzden %APPDATA% yolu yalnızca başka kök
        bulunamazsa kullanılır.
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
    #>
    param([string[]]$Kokler)
    $simdiki = @($Kokler | Sort-Object)
    if (Test-Path $DurumDosya) {
        $onceki = @()
        try {
            $durum = Get-Content $DurumDosya -Raw -Encoding UTF8 | ConvertFrom-Json
            $onceki = @($durum.kokler | Sort-Object)
        }
        catch {
            Yaz-Gunluk ("Durum dosyasi okunamadi, yeniden yazilacak: " + $_.Exception.Message) 'UYARI'
        }
        $fark = Compare-Object -ReferenceObject $onceki -DifferenceObject $simdiki
        if ($onceki.Count -gt 0 -and $fark) {
            Yaz-Gunluk ("Veri klasorunun yeri degisti. Onceki: " + ($onceki -join '; ') + " | Simdiki: " + ($simdiki -join '; ')) 'UYARI'
            $script:Bildirimler.Add("Claude veri klasorunun yeri degisti (" + ($simdiki -join '; ') + "). Baglantilar ve eksik kayitlar bu calistirmada onarildi; liste eksikse uygulamayi tepsiden tamamen kapatip acin.")
            $script:YenidenAcGerekli = $true
        }
    }
    if (-not $KuruCalisma) {
        $metin = [ordered]@{ kokler = $simdiki; guncelleme = (Get-Date -Format 'dd.MM.yyyy HH:mm:ss') } | ConvertTo-Json
        [System.IO.File]::WriteAllText($DurumDosya, $metin, (New-Object System.Text.UTF8Encoding($false)))
    }
}

function Get-SonEtkinlik {
    <#
    .SYNOPSIS
        Bir oturum klasöründeki en yeni oturum kaydının zamanını döndürür; kayıt yoksa klasör zamanını.
    #>
    param([string]$Klasor)
    $son = Get-ChildItem $Klasor -File -Filter 'local_*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($son) { return $son.LastWriteTime }
    return (Get-Item $Klasor).LastWriteTime
}

function Esitle-Kok {
    <#
    .SYNOPSIS
        Tek bir claude-code-sessions kökünde tüm hesap/kuruluş klasörlerini ana klasörde birleştirir.
    .OUTPUTS
        Ana klasörün tam yolu; uygun klasör yoksa $null.
    #>
    param([string]$Kok)

    # Hesap\kuruluş klasörlerini topla (yalnız GUID adlılar; _eski yedekleri hariç)
    $orgKlasorleri = @()
    Get-ChildItem $Kok -Directory -Force | Where-Object { $_.Name -match $GuidDeseni } | ForEach-Object {
        Get-ChildItem $_.FullName -Directory -Force | Where-Object { $_.Name -match $GuidDeseni } | ForEach-Object {
            $orgKlasorleri += $_
        }
    }
    $gercekler = @($orgKlasorleri | Where-Object { -not $_.LinkType })
    $baglantilar = @($orgKlasorleri | Where-Object { $_.LinkType -eq 'Junction' })
    if ($gercekler.Count -eq 0) {
        if ($orgKlasorleri.Count -gt 0) {
            Yaz-Gunluk "Kok: $Kok -> gercek klasor yok, butun klasorler baglanti. Elle kontrol gerekir." 'UYARI'
        }
        return $null
    }

    # Ana klasör: en son etkinlik gösteren gerçek klasör (etkin hesap)
    $ana = $gercekler | Sort-Object { Get-SonEtkinlik $_.FullName } -Descending | Select-Object -First 1
    if ($orgKlasorleri.Count -lt 2) {
        Yaz-Gunluk "Kok: $Kok -> tek klasor var, birlestirilecek klasor yok."
        return $ana.FullName
    }
    Yaz-Gunluk "Kok: $Kok -> ana klasor: $($ana.Parent.Name)\$($ana.Name)"

    $zaman = Get-Date -Format 'yyMMdd_HHmmss'
    $birlesen = 0

    foreach ($klasor in $gercekler) {
        if ($klasor.FullName -eq $ana.FullName) { continue }
        $etiket = "$($klasor.Parent.Name)\$($klasor.Name)"

        # 1. Oturum kayıtlarını ana klasöre kopyala (eksik ya da daha yeni olanlar)
        $kopyalanan = 0
        Get-ChildItem $klasor.FullName -File | Where-Object { $_.Name -like 'local_*.json' -or $_.Name -like 'deleted_*' } | ForEach-Object {
            $hedefDosya = Join-Path $ana.FullName $_.Name
            $gerekli = (-not (Test-Path $hedefDosya)) -or ((Get-Item $hedefDosya).LastWriteTime -lt $_.LastWriteTime)
            if ($gerekli) {
                if (-not $KuruCalisma) { Copy-Item $_.FullName $hedefDosya -Force }
                $kopyalanan++
            }
        }
        $planliGorev = Join-Path $klasor.FullName 'scheduled-tasks.json'
        if (Test-Path $planliGorev) {
            $icerik = Get-Content $planliGorev -Raw | ConvertFrom-Json
            if ($icerik.scheduledTasks -and @($icerik.scheduledTasks).Count -gt 0) {
                Yaz-Gunluk "$etiket icinde zamanlanmis gorev var; birlestirilmedi, yedekte duruyor." 'UYARI'
            }
        }

        # 2. Yedekle, adını değiştir, yerine bağlantı kur
        $yedekHedef = Join-Path $YedekKlasor "$zaman\$($klasor.Parent.Name)\$($klasor.Name)"
        $yeniAd = "$($klasor.Name)_eski_$zaman"
        if ($KuruCalisma) {
            Yaz-Gunluk "[KURU] $etiket -> $kopyalanan dosya kopyalanacak, yedek: $yedekHedef, ad: $yeniAd, baglanti -> ana klasor"
            continue
        }
        New-Item -ItemType Directory -Force $yedekHedef | Out-Null
        Copy-Item (Join-Path $klasor.FullName '*') $yedekHedef -Recurse -Force
        $yol = $klasor.FullName
        Rename-Item $yol $yeniAd
        New-Item -ItemType Junction -Path $yol -Target $ana.FullName | Out-Null
        Yaz-Gunluk "$etiket -> $kopyalanan dosya kopyalandi, yedek alindi, ad '$yeniAd' yapildi, ana klasore baglandi."
        $birlesen++
    }

    # 3. Kırık ya da başka yeri gösteren bağlantıları ana klasöre yönlendir
    foreach ($baglanti in $baglantilar) {
        $hedef = @($baglanti.Target)[0]
        $etiket = "$($baglanti.Parent.Name)\$($baglanti.Name)"
        if ($hedef -eq $ana.FullName -and (Test-Path $hedef)) { continue }
        if ($KuruCalisma) {
            Yaz-Gunluk "[KURU] $etiket baglantisi '$hedef' yerine ana klasore yonlendirilecek."
            continue
        }
        # Yalnızca bağlantının kendisi silinir; hedefteki dosyalara dokunulmaz
        [System.IO.Directory]::Delete($baglanti.FullName, $false)
        New-Item -ItemType Junction -Path $baglanti.FullName -Target $ana.FullName | Out-Null
        Yaz-Gunluk "$etiket baglantisi '$hedef' yerine ana klasore yonlendirildi."
        $birlesen++
    }

    if ($birlesen -gt 0) {
        $script:Bildirimler.Add("$birlesen hesap klasoru ortak oturum listesine baglandi.")
        $script:YenidenAcGerekli = $true
    }
    return $ana.FullName
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

function Onar-EksikKayitlar {
    <#
    .SYNOPSIS
        Dökümü olup liste kaydı olmayan masaüstü oturumları için ana klasörde liste kaydı üretir.
    .DESCRIPTION
        Bir oturumun liste kaydı (local_*.json) ana klasörde yoksa ve şu koşulların hepsi tutuyorsa kayıt üretilir:
          - Döküm masaüstü uygulamasından (entrypoint = claude-desktop), alt ajan dökümü değil.
          - Son $OnarimGunu gün içinde değişmiş.
          - Kullanıcı silmemiş: deleted_<id> işareti ya da <id>.desktop-released.json yok.
          - Çalışma klasörü (cwd) hâlâ var.
        Yazmadan önce ana klasörün tamamı yedeklenir. Var olan hiçbir dosya değiştirilmez.
    #>
    param([string]$Ana)
    if (-not (Test-Path $ProjeKlasoru)) { return }

    $kayitli = New-Object 'System.Collections.Generic.HashSet[string]'
    $capalar = @{}
    $sablonIzin = 'default'
    Get-ChildItem $Ana -File -Filter 'local_*.json' | ForEach-Object {
        $dosya = $_
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
    $adaylar = Get-ChildItem $ProjeKlasoru -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notmatch '\\subagents\\' -and $_.LastWriteTime -gt $sinir -and $_.CreationTime -lt $yeniSinir -and
        $_.BaseName -match $GuidDeseni -and
        -not $kayitli.Contains($_.BaseName) -and -not $silinen.Contains($_.BaseName) -and
        -not (Test-Path (Join-Path $_.DirectoryName ($_.BaseName + '.desktop-released.json')))
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $yedeklendi = $false
    $onarilan = 0
    foreach ($dokum in $adaylar) {
        $cli = $dokum.BaseName
        try {
            $ozet = Oku-DokumOzeti -Yol $dokum.FullName
        }
        catch {
            Yaz-Gunluk ("Dokum okunamadi: " + $dokum.FullName + " | " + $_.Exception.Message) 'UYARI'
            continue
        }
        if (-not $ozet) { continue }
        if (-not $ozet.cwd -or -not (Test-Path $ozet.cwd)) {
            Yaz-Gunluk "Kaydi olmayan oturum $cli onarilmadi: calisma klasoru yok ($($ozet.cwd))."
            continue
        }

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
    if ($onarilan -gt 0) {
        $script:Bildirimler.Add("$onarilan oturumun eksik liste kaydi dokumden yeniden olusturuldu.")
        $script:YenidenAcGerekli = $true
    }
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

function Esitle-HesapAyarlari {
    <#
    .SYNOPSIS
        Hesaba göre ayrı tutulan ortam ayarlarını ve MCP araç seçimlerini iki hesapta aynı yapar.
    .DESCRIPTION
        - ccd-session-presets.json: byAccount.<hesap>.presets listeleri kimliğe (id) göre birleştirilir;
          her hesapta eksik olan ayar eklenir, var olan hiçbir ayar değiştirilmez ya da silinmez.
        - mcp-user-tool-toggles.json: owners.<hesap> listeleri birleştirilir.
        Değişiklik gerekiyorsa önce iki dosya yedeklenir. Ayar değerleri günlüğe yazılmaz.
    #>
    param([string]$VeriKlasoru)
    $zaman = Get-Date -Format 'yyMMdd_HHmmss'
    $yedeklendi = $false

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
                    $yedeklendi = $true
                    Yaz-JsonAtomik -Yol $presetDosya -Nesne $p
                    Yaz-Gunluk "Ortam ayarlari esitlendi: $eklenen ayar eksik hesaba eklendi. Yedek: $yedekHedef"
                    $script:Bildirimler.Add("$eklenen kayitli ortam ayari iki hesapta ortak yapildi.")
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
                    $yedeklendi = $true
                    Yaz-JsonAtomik -Yol $secimDosya -Nesne $s
                    Yaz-Gunluk "MCP arac secimleri esitlendi: $eklenen secim eksik hesaba eklendi. Yedek: $yedekHedef"
                    $script:Bildirimler.Add("$eklenen MCP arac secimi iki hesapta ortak yapildi.")
                }
            }
        }
    }
    if ($yedeklendi) { $script:YenidenAcGerekli = $true }
}

function Gonder-Bildirimler {
    <#
    .SYNOPSIS
        Bildirimleri kancaya çıktı olarak ya da -Bildir ile kullanıcıya pencereyle iletir.
    #>
    if ($script:Bildirimler.Count -eq 0) { return }
    $metin = ($script:Bildirimler -join "`n")
    if ($script:YenidenAcGerekli) { $metin += "`nClaude aciksa listeyi gormek icin uygulamayi tepsiden tamamen kapatip yeniden acin." }
    $metin += "`nGunluk: $GunlukDosya"
    if ($Bildir) {
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

if ($GorevKur) {
    Kur-Gorev
    exit 0
}

# Aynı anda başlayan oturumların çakışmaması için sistem genelinde kilit
$kilit = New-Object System.Threading.Mutex($false, 'Global\ClaudeHesapOturumEsitle')
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
        exit 0
    }
    $kokler = @(Get-VeriKokleri)
    if ($kokler.Count -eq 0) {
        Yaz-Gunluk 'Claude veri klasoru bulunamadi.' 'UYARI'
    }
    else {
        Denetle-KokTasinmasi -Kokler $kokler
    }
    foreach ($kok in $kokler) {
        $anaKlasor = Esitle-Kok -Kok $kok
        if ($anaKlasor) {
            try {
                Onar-EksikKayitlar -Ana $anaKlasor
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
    Gonder-Bildirimler
}
catch {
    # Kanca oturumu engellemesin: hata günlüğe yazılır, çıkış kodu 0 kalır
    Yaz-Gunluk ("Hata: " + $_.Exception.Message + " | " + $_.ScriptStackTrace) 'HATA'
}
finally {
    if ($kilitAlindi) { $kilit.ReleaseMutex() }
    $kilit.Dispose()
}
exit 0
