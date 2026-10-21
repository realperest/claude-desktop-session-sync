# macOS kılavuzu: bu projenin bütün hikâyesi ve macOS'a taşıma planı

Bu belge, **Mac'te açılan bir Claude (Claude Code) oturumu** için yazıldı. O oturum bu dosyayı okuyunca şunları anlayabilmeli: projenin neden var olduğu, hangi sorunlarla karşılaşıldığı, her birinin nasıl çözüldüğü, Windows sürümünün bugün nasıl çalıştığı ve aynı çözümün macOS için nasıl yapılacağı.

## 0. Mac'teki Claude için ilk talimat

1. Önce bu dosyayı baştan sona oku. Sonra şu üç dosyayı oku:
   - `README.md`: aracın kullanıcıya anlatılışı;
   - `docs/FINDINGS.md`: uygulamanın oturumları nasıl sakladığına dair teknik bulgular;
   - `hesap-oturum-esitle.ps1`: Windows betiği, yani taşınacak mantığın kendisi.
2. Kullanıcıyla **Türkçe** konuş. Kısa, net ve çözüme odaklı ol.
3. Kod yazmadan önce bu belgenin 6. bölümündeki "Mac'te ilk doğrulanacaklar" listesini çalıştır, sonucu kullanıcıya göster ve planı onaylat.
4. Herkese açık her işlem için (GitHub'a gönderme, sürüm yayınlama, issue'lara yorum yazma) önce kullanıcıdan açık onay al.
5. Bu depoda commit'ler GitHub'ın gizli adresiyle yapılır, kişisel e-posta asla commit'e girmez (ayrıntılar 7. bölümde).

## 1. Kullanıcı ve hedef

- Kullanıcının iki Claude hesabı var; farklı e-posta adresleriyle. Claude masaüstü uygulamasında bu iki hesap arasında **yalnız kullanım limitini değiştirmek için** geçiş yapıyor.
- **Hedef:** Hesap değişince limit dışında hiçbir şey değişmemeli. Code sekmesindeki oturum listesi, sohbet geçmişi, worktree'ler ve ayarlar aynen kalmalı.
- Kullanıcı Windows'ta çalışıyor. Bu çözüm Windows için yapıldı, test edildi ve herkese açık olarak yayınlandı. Şimdi aynı çözüm macOS için isteniyor.

## 2. Temel bilgi: uygulama oturumları nasıl saklıyor

- Sohbet dökümleri (konuşmanın kendisi) `~/.claude/projects/<proje>/<cli oturum kimliği>.jsonl` dosyalarında durur. Bu dökümler **hesaptan bağımsızdır**.
- Kenar çubuğundaki liste ise hesaba ve kuruluşa göre ayrılmış klasörlerdeki küçük kayıt dosyalarından oluşur:

  ```
  <uygulama verisi>/claude-code-sessions/<hesap kimliği>/<kuruluş kimliği>/local_<oturum kimliği>.json
  ```

- Hesap değişince uygulama öbür hesabın klasörünü okur. Oturumlar silinmez, yalnız **görünmez** olur. Sorunun kökü budur.
- Anthropic'in farklı e-postalı hesaplar için resmi bir çözümü yok. Bkz. [anthropics/claude-code#74662](https://github.com/anthropics/claude-code/issues/74662).

## 3. Karşılaşılan sorunlar ve çözümleri (kronolojik)

Her madde aynı sırayı izliyor: **belirti → gerçek neden → yapılan çözüm**.

### 3.1. Hesap değişince oturumlar kayboluyor

- **Belirti:** Öbür hesaba geçince Code sekmesi boş ya da eksik görünüyor.
- **Neden:** Liste hesap ve kuruluşa göre ayrı klasörlerde tutuluyor (2. bölüm).
- **Çözüm:** Hesap klasörlerini eşitleyen bir betik yazıldı.

### 3.2. İlk çözüm (junction) sessizce veri kaybettirdi

- **İlk deneme:** Bütün hesap klasörleri tek bir ortak klasöre NTFS junction ile bağlandı. Liste görünüşte düzeldi.
- **Belirti:** Yeni açılan oturumlar hesap değişince ya da uygulama yeniden başlayınca tamamen kayboldu. Mesaj gönderirken "Gönderilemedi" ve "Bir şeyler ters gitti" hataları çıktı.
- **Gerçek neden** (uygulama günlüğünde bulundu):

  ```
  Failed to save session local_...: Refusing non-directory at private dir path (symlink/file plant)
  ```

  Uygulamanın yeni sürümleri bağlantı olan klasöre **yazmayı reddediyor**, ama **okumaya devam ediyor**. Bu yüzden liste tam görünüyordu, ama yeni oturumlar yalnız bellekte duruyor ve kayboluyordu.
- **Çözüm:** Bağlantılar kaldırıldı. Bütün klasörler **gerçek klasör** olarak tutuluyor ve **kopyalanarak** eşitleniyor. Betik, bulduğu bağlantıyı gerçek klasöre çeviriyor.
- **macOS için anlamı:** Sembolik bağlantı (symlink) kullanma. Uygulama büyük ihtimalle orada da reddediyor ("symlink/file plant" mesajı bunu düşündürüyor).

### 3.3. Bir hesap birden fazla kuruluş klasörü kullanıyor

- **Bulgu:** Aynı hesap, farklı açılışlarda listeyi iki farklı kuruluş klasöründen yükledi. İki hesap × iki kuruluş = **dört klasör**.
- **Çözüm:** Eşitleme hesap başına bir klasörü değil, **bütün** `<hesap>/<kuruluş>` klasörlerini kapsıyor. Etkin klasör, uygulama günlüğündeki son `Loaded N persisted sessions from <yol>` satırından okunuyor.

### 3.4. Eşitleme anlık olmalı

- **Sorun:** Betik yalnız oturum başlangıcında çalışırsa, hesap değiştiğinde öbür klasör henüz güncel olmayabiliyor.
- **Çözüm:** Arka planda tek kopya çalışan bir **izleyici**: 15 saniyede bir, uygulama kapalıyken 2 saniyede bir eşitliyor; 10 dakikada bir onarım ve ayar eşitlemesi yapıyor; betik değişince kendini yeniden başlatıyor. Windows'ta WMI ile başlatılıyor, böylece kanca bitince kapanmıyor.
- **Kural:** Değiştirilme zamanı korunarak kopyalanıyor; en yeni sürüm kazanıyor, kopyalar klasörler arasında gidip gelmiyor.

### 3.5. Kaybolan oturumların kaydını geri getirmek

- **Sorun:** Junction döneminde açılan bazı oturumların dökümü diskte vardı, ama kenar çubuğu kaydı hiç yazılmamıştı.
- **Çözüm:** Kayıp kayıt onarımı. Dökümden (`cwd`, başlık, dal, model, zamanlar) yeni bir `local_*.json` kaydı üretiliyor. Şu durumlarda onarım yapılmıyor:
  - döküm masaüstü uygulamasından gelmiyorsa (`"entrypoint":"claude-desktop"` yoksa);
  - kullanıcı oturumu silmişse (`deleted_<kimlik>` işareti ya da `<kimlik>.desktop-released.json` dosyası varsa);
  - döküm son 15 dakikada oluşturulmuşsa;
  - uygulama günlüğüne göre o kimlik, yaşayan bir oturumun eski kimliğiyse.

### 3.6. Onarılan worktree oturumlarında "Bir şeyler ters gitti"

- **Belirti:** Onarılan bir worktree oturumunda her mesaj hatayla bitiyor:

  ```
  the session's branch is checked out in a folder that exists; not recreating its worktree
  ```

- **İlk düşünülen neden:** Kayıtta worktree çapası (`gitAnchors` içinde worktree'nin kendi girdisi) eksikti. Eklendi, ama **yetmedi**.
- **Gerçek neden:** Uygulamanın `git-worktrees.json` adlı bir worktree defteri var. Her worktree orada bir oturuma kiralanmış (`leasedBy`). Onarılan kayıt yeni bir kimlik almıştı, defter ise eski kimliği gösteriyordu. Uygulama worktree'yi kendisinin saymayıp yeniden kurmaya çalışıyor, Git dal zaten açık olduğu için reddediyordu.
- **Çözüm:** Kiracısının kaydı hiçbir klasörde olmayan worktree'ler, onu kullanan gerçek oturuma yeniden kiralanıyor. Onarımda da yeni kimlik üretmek yerine defterdeki eski kiracı kimliği kullanılıyor.

### 3.7. Düzeltmeler uygulamaya yansımıyordu

- **Sorun:** Uygulama kayıtları ve defteri **bellekte** tutuyor ve açıkken kendi kopyasıyla üstlerine yazıyor. Kullanıcı "kapatıp açtım" dediğinde uygulama aslında hiç kapanmamıştı; yalnız pencere kapanmıştı.
- **Çözüm:**
  - Bu tür düzeltmeler yalnız **uygulama kapalıyken** yapılıyor; izleyici uygulama kapalıyken 2 saniyede bir bakıyor.
  - Kullanıcıya uygulamayı **tepsi/menü çubuğundan Çıkış** ile tamamen kapatması söyleniyor.
  - Yeniden başlatmanın gerçekten olduğu, süreç başlama zamanından ve günlükte yeni bir `Loaded ...` satırından doğrulanıyor.
- **macOS için anlamı:** Mac'te kapatma Cmd+Q ile ya da menü çubuğundan **Quit** ile yapılır. Pencereyi kapatmak uygulamayı kapatmaz.

### 3.8. Ayar eşitlemesi her seferinde tekrarlanıyordu

- **Belirti:** Günlükte her çalıştırmada "1 ayar eklendi" satırı çıkıyordu.
- **Neden:** Uygulama açıkken ayar dosyalarını bellekteki hâliyle yeniden yazıp eklemeyi siliyordu.
- **Çözüm:** Ayar eşitlemesi (`ccd-session-presets.json`, `mcp-user-tool-toggles.json`) yalnız uygulama kapalıyken çalışıyor ve bildirim göndermiyor.

### 3.9. Silinen oturumlar geri gelebiliyordu

- **Sorun:** Silme işareti (`deleted_<kimlik>`) yalnız `cliSessionId` ile karşılaştırılıyordu.
- **Çözüm:** Uygulamanın kendisi gibi, kaydın **bütün kimlikleriyle** karşılaştırılıyor: `cliSessionId`, `unarchivedCliSessionId`, `priorCliSessionIds` ve dosya adındaki kimlik. Silinen oturumun kalan kopyaları silinmiyor, yedek klasörüne taşınıyor.

### 3.10. Bozuk kayıt her yere yayılabilirdi

- **Risk:** Yarım yazılmış en yeni kopya, dört klasördeki sağlam kopyaların üstüne yazılabilirdi.
- **Çözüm:** Kopyanın kaynağı en yeni **geçerli** sürüm: JSON olarak okunabilmeli ve `sessionId` alanı dosya adıyla aynı olmalı. Bozuk sürüm kopyalanmıyor; daha yeni olduğu için üstüne de yazılmıyor.

### 3.11. Günlük şişiyordu

- **Sorun:** İzleyici, uygulamanın her kayıt yazışında günlüğe bir satır ekliyordu.
- **Çözüm:** Yalnız yeni dosya ya da taşıma olan turlar yazılıyor. Günlük 5 MB'ı aşınca tarihli bir dosyaya taşınıyor (silinmiyor).

### 3.12. Turuncu noktalar her hesap değişiminde geri geliyor

- **Belirti:** Kenar çubuğunda turuncu "girdi bekliyor / engellenmiş" noktaları. Oturumu açmak noktayı kaldırmıyor; "Tamamlandı olarak işaretle" kaldırıyor, ama hesap değişince nokta geri geliyor.
- **Neden 1:** Nokta, oturumun son turu kullanıcıya açık bir şey bıraktığında çıkıyor: son "sonraki adım" kutusu bir soru sormuşsa ya da tur kutusuz bitmişse.
- **Neden 2:** "Tamamlandı" onayı uygulamanın tarayıcı deposunda (`Local Storage`) `epitaxy-awaiting-ack-v1` anahtarında duruyor. Uygulama **her çıkışta** bu anahtarı ve `epitaxy-unread-v1` anahtarını siliyor.
- **Çözüm:**
  - Local Storage'a dokunulmuyor (kilitli, ikili; bozulursa bütün arayüz durumu gider).
  - Bunun yerine kullanıcının genel `CLAUDE.md` dosyasına bir kural eklendi: araç kullanılan, önceki kutunun sorusuna metinle yanıt verilen ya da önceki kutunun kullanıcıyı beklediği her tur, kısa olsa bile **sonraki adım kutusuyla** kapatılır. Kutu kaydı (`turnWrapUp`) oturum dosyasında tutuluyor ve eşitlemeyle öbür hesaba da geçiyor.
- **Mac'teki Claude için:** Turlarını her zaman sonraki adım kutusuyla kapat. Kullanıcı kutuda soru sorulmasını seviyor.

### 3.13. Daha iyi bir hazır çözüm var mı diye araştırıldı

- **Resmi belgeler:** Aynı e-postalı kişisel ve kurumsal hesaplar menüden değiştirilebiliyor; farklı e-postalı hesaplar için yerleşik bir yol yok.
- **GitHub:** Masaüstü tarafındaki araçlar birkaç haftalık ve küçük. Hiçbiri dört klasörün hepsini, silme işaretlerinin bütün kimliklerle karşılaştırılmasını ve worktree kiralamasını birlikte kapsamıyor. Mac'te var olanlar: `claude-transplant`, `ccdejavu`, `restore-desktop-sessions`.
- **Uygulamanın kodunda yerel çoklu hesap özelliği bulundu.** Sunucu tarafındaki bir anahtara bağlı; ayrıca `disableMultiAccount` ("Single account only") adlı bir kurumsal ilke var. Henüz açılmamış. **Zorla açılmaz.** Açılınca bu araca gerek kalıp kalmadığı yeniden değerlendirilmeli.
- **Hesap değiştirmeden alternatif:** Masaüstü uygulaması bir hesapta, VS Code/Cursor eklentisi ya da terminaldeki Claude Code öbür hesapta. Onların girişi masaüstünden bağımsız ve geçmişleri yerel.

### 3.14. Herkese açık yayın

- Depo `claude-desktop-session-sync` adıyla herkese açıldı. Lisans MIT. İçinde İngilizce ve Türkçe README, teknik bulgular, katkı rehberi, değişiklik notları, hata/öneri formları ve GitHub Actions testi var. İlk sürüm: v1.0.0.
- Yayından önce commit geçmişindeki kişisel e-posta, GitHub'ın gizli adresiyle değiştirildi.
- Kullanıcının onayıyla [#74662](https://github.com/anthropics/claude-code/issues/74662) kaydına aracı ve bulguları anlatan bir yorum yazıldı.

## 4. Son durum: Windows sürümü nasıl çalışıyor

| Parça | Görev |
|---|---|
| `hesap-oturum-esitle.ps1` | Eşitleme, onarım ve ayar betiği. Parametresiz: bir tam tur, sonra izleyiciyi başlatır. `-KuruCalisma`: hiçbir şey değiştirmez. `-Izle`: izleyici modu. `-ZorlaDuzelt`: worktree düzeltmelerini uygulama açıkken de yapar. `-GorevKur`: oturum açılışı görevini kurar. `-IzleyiciBaslatma`: testlerde izleyiciyi başlatmaz. |
| `kur.ps1` | Kurulum ve kaldırma. Betiği `%USERPROFILE%\Claude-hesap-esitleme\` klasörüne kopyalar, `~/.claude/settings.json` dosyasına `SessionStart` kancası ekler, `~/.claude/CLAUDE.md` dosyasına açıklama bölümü yazar, oturum açılışı görevini kurar. Hata olursa yedekten geri alır. |
| `sablon/claude-md-bolum.md` | CLAUDE.md'ye yazılan bölümün şablonu. `CLAUDE_BIRLESTIR:BASLA/BITIS` işaretleri mevcut kurulumlarla uyumluluk için değiştirilmez. |
| `tests/Test-Sync.ps1` | Sahte veri klasöründe uçtan uca test (6 durum, 12 kontrol). Gerçek veriye dokunmaz. |
| `.github/workflows/test.yml` | Her gönderimde testi `windows-latest` üzerinde çalıştırır. |

**Bir eşitleme turunun akışı:**
1. Veri klasörünü bul.
2. Yeri değiştiyse uyar.
3. Bağlantıları gerçek klasöre çevir.
4. Dört klasördeki `local_*.json` ve `deleted_*` dosyalarının envanterini çıkar.
5. Silinmiş oturumların kopyalarını yedeğe taşı.
6. Her kaydın en yeni geçerli sürümünü eksik ya da eski olan klasörlere atomik olarak kopyala.
7. Uygulama kapalıysa worktree çapalarını ve kiralamalarını düzelt.
8. Tam turdaysa kayıp kayıtları onar ve ayarları birleştir (yalnız uygulama kapalıyken).

**Güvenlik kuralları (değişmez):**
- Hiçbir dosya silinmez; yedek klasörüne taşınır.
- Her değişiklikten önce yedek alınır.
- Dosyalar geçici dosyaya yazılıp tek adımda yerine konur.
- Hesap bilgilerine, jetonlara ve çerezlere dokunulmaz.
- Local Storage'a yazılmaz.
- Klasörler bağlanmaz (junction ya da symlink kullanılmaz).

## 5. macOS'a taşıma planı

### 5.1. Karar: aynı depo

macOS desteği bu depoya eklenir; ayrı depo açılmaz. Sorun, bulgular ve test senaryoları ortak.

### 5.2. Dil seçimi (kullanıcıya sorulacak; önerilen ilk sırada)

1. **PowerShell 7 ile tek kod (önerilen):** Aynı betik iki sistemde çalışır. Mac'te bir kez `brew install powershell` gerekir. Windows'ta PowerShell 5.1 uyumluluğu korunmalı: yalnız 7'de olan sözdizimi kullanılmamalı, `.ps1` dosyaları BOM'lu UTF-8 kalmalı.
2. **Python 3:** Mac'te git yüklüyse genelde hazır gelir. Ama iki ayrı kod tabanı oluşur.
3. **zsh/bash:** Bu kadar karmaşık mantık için kırılgan; önerilmez.

### 5.3. Windows'a özgü kısımların macOS karşılıkları

| Windows | macOS (doğrulanmalı) |
|---|---|
| `%LOCALAPPDATA%\Claude-Data\claude_<id>\` ya da `%APPDATA%\Claude\` | `~/Library/Application Support/Claude/` |
| `%LOCALAPPDATA%\Claude\logs\main.log` | Büyük ihtimalle `~/Library/Logs/Claude/main.log` |
| Junction | Symlink; aynı yasak geçerli |
| `Global\...` mutex | Kilit dosyası (örneğin `~/Claude-hesap-esitleme/izleyici.lock`, içinde PID) |
| WMI ile başlatılan izleyici | `launchd` LaunchAgent: `~/Library/LaunchAgents/<ad>.plist`, `KeepAlive` ile |
| Oturum açılışı zamanlanmış görevi | Aynı LaunchAgent, `RunAtLoad` ile |
| `Claude.exe` (`WindowsApps` yolundan) | `/Applications/Claude.app/Contents/MacOS/Claude` süreci |
| `File.Replace` ile atomik yazma | Geçici dosya + `rename` (aynı disk bölümünde atomik) |
| WScript açılır pencere bildirimi | `osascript -e 'display notification ...'` |
| `%USERPROFILE%\Claude-hesap-esitleme\` | `~/Claude-hesap-esitleme/` |

### 5.4. Taşıma adımları

1. Mac'te 6. bölümdeki doğrulamaları yap ve sonuçları `docs/FINDINGS.md` dosyasına "macOS" başlığıyla ekle.
2. Yol bulma, süreç kontrolü, kilit ve izleyici başlatma işlerini işletim sistemine göre ayıran küçük fonksiyonlar yaz (PowerShell 7'de `$IsMacOS` / `$IsWindows`). Eşitleme mantığına dokunma.
3. Symlink'i gerçek klasöre çeviren kodu ekle (junction çevirme kodunun karşılığı).
4. `kur.ps1` için macOS kurulumunu yaz: betiği kopyala, `SessionStart` kancası ekle, CLAUDE.md bölümünü yaz, LaunchAgent'ı kur ve yükle (`launchctl bootstrap gui/$(id -u) <plist>`). `-Kaldir` LaunchAgent'ı kaldırmalı.
5. `tests/Test-Sync.ps1` macOS'ta da çalışacak hale getirilmeli: ortam değişkenleri yerine test için veri klasörü yolunu parametre olarak alabilmeli; junction yerine symlink kullanmalı.
6. `.github/workflows/test.yml` dosyasına `macos-latest` ekle.
7. README.md ve README.tr.md'ye macOS kurulumunu ekle; CHANGELOG'a 1.1.0 (macOS beta) yaz.
8. Kullanıcının kendi Mac'inde iki hesapla gerçek deneme yap: hesap değiştir, yeni oturum aç, sil, yeniden adlandır, worktree oturumunda mesaj gönder. Ancak bundan sonra yayınla.

### 5.5. Güvenlik ve kalite kuralları (macOS'ta da aynen)

- Gerçek veriye dokunan her şey önce `-KuruCalisma` ile denenir.
- Uygulama açıkken uygulamanın bellekte tuttuğu dosyalara (worktree defteri, ayarlar) yazılmaz.
- Yeni bir davranış eklenince önce sahte veri testine bir senaryo eklenir.
- Hatalar sessizce yutulmaz; günlüğe yazılır.

## 6. Mac'te ilk doğrulanacaklar

Bu komutlar yalnız okur, hiçbir şeyi değiştirmez. Çıktıları kullanıcıya göster.

```bash
ls -la ~/Library/Application\ Support/Claude/
```

```bash
find ~/Library/Application\ Support/Claude/claude-code-sessions -maxdepth 2 -type d -exec ls -ld {} \;
```

```bash
ls ~/Library/Logs/Claude/ 2>/dev/null; ls ~/Library/Application\ Support/Claude/logs/ 2>/dev/null
```

```bash
grep -h "Loaded .* persisted sessions from" ~/Library/Logs/Claude/main.log | tail -5
```

```bash
grep -h "Failed to save session\|not recreating its worktree" ~/Library/Logs/Claude/main.log | tail -5
```

```bash
ls -la ~/Library/Application\ Support/Claude/git-worktrees.json ~/Library/Application\ Support/Claude/ccd-session-presets.json ~/Library/Application\ Support/Claude/mcp-user-tool-toggles.json
```

```bash
pgrep -lf "Claude.app/Contents/MacOS/Claude"
```

```bash
command -v pwsh python3 git jq
```

Yanıtları bulunması gereken sorular:
- Kaç hesap ve kuruluş klasörü var? Aralarında symlink var mı?
- Uygulama günlüğü nerede ve `Loaded ... persisted sessions from` satırı Mac'te de var mı?
- `git-worktrees.json`, `ccd-session-presets.json` ve `mcp-user-tool-toggles.json` Mac'te aynı adla ve aynı yerde mi?
- Uygulamanın süreç adı ne?
- Hangi araçlar yüklü (pwsh, python3, git, jq)?

## 7. Çalışma kuralları (kullanıcının tercihleri)

- **Dil:** Kullanıcıyla bütün iletişim Türkçe.
- **Onay:** Büyük mimari değişikliklerden önce kısa bir özet sun ve onay bekle. Commit, push, sürüm yayınlama ve herkese açık yorumlar için ayrıca onay al.
- **Soru kipi:** Kullanıcının mesajında `?`, "açıkla", "anlat", "nasıl", "neden" gibi bir ifade varsa kod yazma, dosya değiştirme; yalnız yanıt ver ve onay bekle.
- **Sonraki adım kutusu:** Her turu kutuyla kapat (3.12). Kutuda soru sorabilirsin.
- **Git:** Bu depoda commit'ler gizli adresle yapılır: `82565425+realperest@users.noreply.github.com` (depoya özel `user.email` olarak ayarla). Kişisel e-posta asla commit'e girmez. Commit mesajları Türkçe yazılır.
- **Belgeler:** Betik değişince README.md, README.tr.md, `docs/FINDINGS.md`, CHANGELOG.md ve `sablon/claude-md-bolum.md` birlikte güncellenir.
- **Yedek:** Bir dosyanın %25'inden fazlası değişecekse önce `_ydk` uzantılı yedeğini al.
- **Bağış:** Sponsor düğmesi şimdilik yok; `.github/FUNDING.yml` dosyası yalnız kullanıcı bir hesap açınca eklenir.
- **Konuşma günlüğü:** Kullanıcı her projede konuşmaların ayrıntılı kaydını, ana proje klasöründeki `KONUSMALAR/konusma##.md` dosyalarında tutuyor. Bu klasör git'e girmez. Mac'te bu proje için aynı düzeni kur: `KONUSMALAR/` klasörü oluştur, `.gitignore`'a ekle, `konusma01.md` ile başla.
