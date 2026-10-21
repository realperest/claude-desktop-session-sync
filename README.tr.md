# Claude Desktop Session Sync

**Windows'taki Claude masaüstü uygulamasında, bütün Claude hesaplarında tek bir Code sekmesi oturum listesi.**

[English](README.md) · [Teknik bulgular (İngilizce)](docs/FINDINGS.md) · [Değişiklikler](CHANGELOG.md) · [Katkı](CONTRIBUTING.md)

> Resmi değildir. Anthropic ile bağlantısı yoktur ve Anthropic tarafından onaylanmamıştır. Uygulamanın dosyalarını bugün nasıl sakladığına dayanır; bu, yayımlanmış bir arayüz değildir. Bir uygulama güncellemesi aracı bozabilir. Kullanmadan önce [uyarıyı](#uyarı) oku.

## Sorun

Masaüstü uygulamasında birden fazla Claude hesabı kullanıyorsan, örneğin kişisel ve iş hesabı ya da kullanım limitini paylaştırmak için iki hesap, hesap değiştirdiğinde **Code** sekmesindeki oturumların kenar çubuğundan kaybolur. Oturumlar silinmez; konuşmalar diskte `~/.claude/projects` altında durur. Ama uygulama her hesap ve kuruluş için ayrı bir liste tutar:

```
<uygulama verisi>\claude-code-sessions\<hesap kimliği>\<kuruluş kimliği>\local_<oturum kimliği>.json
```

Öbür hesaba girdiğinde uygulama öbür klasörü okur ve oturumların görünmez olur. Farklı e-posta adresli hesaplar için Anthropic'in yerleşik bir çözümü henüz yok. Bkz. [anthropics/claude-code#74662](https://github.com/anthropics/claude-code/issues/74662) ve [#48511](https://github.com/anthropics/claude-code/issues/48511).

## Ne yapar

Bir PowerShell betiği bütün hesap ve kuruluş klasörlerini eşit tutar. Böylece hangi hesaba girersen gir, kenar çubuğunda aynı oturumlar görünür.

- **Kopyalayarak çift yönlü eşitleme.** Her oturum kaydının en yeni geçerli sürümü öbür bütün klasörlere kopyalanır. Değiştirilme zamanı korunduğu için kopyalar klasörler arasında gidip gelmez. Bir hesap birden fazla kuruluş klasörü kullanabilir; hepsi eşitlenir.
- **Arka plan izleyicisi.** Gizli bir izleyici 15 saniyede bir (uygulama kapalıyken 2 saniyede bir) eşitler. Hesap değiştirdiğinde öbür hesabın listesi zaten günceldir; uygulamayı yeniden başlatmana gerek kalmaz.
- **Silinen oturumlar geri gelmez.** Bir oturumu sildiğinde uygulama bir `deleted_<kimlik>` işareti yazar. Betik bu işareti kaydın bütün kimlikleriyle karşılaştırır (`cliSessionId`, `unarchivedCliSessionId`, `priorCliSessionIds` ve dosya adındaki kimlik). Kalan kopyaları silmez, yedek klasörüne taşır.
- **Bozuk kayıt yayılmaz.** Yarım yazılmış ya da bozuk bir kayıt hiçbir yere kopyalanmaz ve sağlam bir kopyanın üstüne yazmaz.
- **Kayıp kayıt onarımı.** Konuşması diskte duran ama kenar çubuğunda kaydı olmayan oturumların kaydını dökümden yeniden oluşturur. Bu durum, uygulama veri klasörünü taşıdığında ya da kayıt yazamadığında ortaya çıkar.
- **Worktree onarımı.** Kaydı yeniden oluşturulmuş ve *"Bir şeyler ters gitti"* / `branch is checked out somewhere else` hatası veren worktree oturumlarını düzeltir ([bulgular](docs/FINDINGS.md#worktree-lease)).
- **Ortak ayarlar.** Kayıtlı ortam ayarlarını ve MCP araç seçimlerini hesaplar arasında birleştirir; bunu yalnız uygulama kapalıyken yapar.
- **Güvenli tasarım.** Hiçbir dosyayı silmez. Her değişiklikten önce yedek alır, dosyaları yarım bırakmadan tek adımda yazar ve hesap bilgilerine, parolalara ya da jetonlara hiç dokunmaz.

### Neden klasörler bağlanmıyor?

Önceki sürümler hesap klasörlerini NTFS bağlantısıyla (junction) birbirine bağlıyordu. **Bunu yapma.** Uygulamanın güncel sürümleri bağlantı olan klasöre yazmayı reddediyor (uygulama günlüğünde `Refusing non-directory at private dir path (symlink/file plant)`). Uygulama bağlantıdan okuyabildiği için her şey normal görünür, ama yeni oturumlar ve değişiklikler diske yazılmaz ve bir sonraki hesap değişiminde ya da yeniden başlatmada kaybolur. Bu araç bulduğu bağlantıları gerçek klasöre çevirir. Ayrıntılar [bulgularda](docs/FINDINGS.md#junctions).

## Gereksinimler

- Windows 10 veya 11
- Claude masaüstü uygulaması: Microsoft Store sürümü ya da doğrudan indirilen sürüm. Store (MSIX) sürümüyle test edildi.
- Windows PowerShell 5.1 (Windows'la birlikte gelir). Yönetici yetkisi gerekmez.
- Git; ya da depoyu ZIP olarak indir.

## Kurulum

1. **Dosyaları indir:**

   ```bash
   git clone https://github.com/realperest/claude-desktop-session-sync.git
   ```

   Ya da GitHub'da **Code > Download ZIP** ile indirip klasöre çıkar.

2. **Deneme modunda çalıştır.** Hiçbir şey değişmez, yalnızca yapılacaklar listelenir:

   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File .\claude-desktop-session-sync\kur.ps1 -Deneme
   ```

3. **Kur:**

   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File .\claude-desktop-session-sync\kur.ps1
   ```

4. **Claude uygulamasını tamamen kapatıp yeniden aç.** Saatin yanındaki tepsi simgesine sağ tıkla ve **Çıkış**'ı seç. Pencereyi kapatmak yetmez; uygulama arka planda çalışmaya devam eder. Görev Yöneticisi'nde Claude kalmadığını kontrol et.

5. **Bu bilgisayarda her hesabına en az bir kez giriş yap.** Bir hesabın klasörü ilk girişte oluşur ve izleyici onu birkaç saniye içinde eşitler.

### Kurulum betiği neler yapar

1. Kullanıcı klasörünü ve Claude veri klasörünü bulur.
2. `~/.claude/settings.json`, `~/.claude/CLAUDE.md` ve varsa betiğin eski kopyasını `%USERPROFILE%\Claude-hesap-esitleme\yedek\kurulum_<zaman>\` klasörüne yedekler.
3. Eşitleme betiğini `%USERPROFILE%\Claude-hesap-esitleme\` klasörüne kopyalar.
4. `~/.claude/settings.json` dosyasına bir `SessionStart` kancası ekler; böylece betik her Claude Code oturumu başlarken çalışır. Öteki ayarlara ve kancalara dokunmaz, kancayı iki kez eklemez.
5. `~/.claude/CLAUDE.md` dosyasına, düzeni Claude'a anlatan kısa bir bölümü bu bilgisayarın yollarıyla yazar. Bölüm varsa yeniler.
6. Betiği Windows oturumu açılırken, uygulama başlamadan önce çalıştıran bir zamanlanmış görev kurar.
7. Eşitlemeyi önce deneme olarak, sonra gerçek olarak bir kez çalıştırır. Gerçek çalıştırma arka plan izleyicisini de başlatır.

Bir adım hata verirse o ana kadar değişen her şey yedekten geri yüklenir. Her adım ekrana ve `%USERPROFILE%\Claude-hesap-esitleme\kurulum.log` dosyasına yazılır.

### Kurulum seçenekleri

| Seçenek | Açıklama |
|---|---|
| `-Deneme` | Hiçbir şeyi değiştirmeden yapılacakları gösterir. |
| `-Kaldir` | Kancayı, `CLAUDE.md` bölümünü ve zamanlanmış görevi kaldırır, izleyiciyi durdurur. Betik, günlükler ve yedekler yerinde kalır. |
| `-GorevKurma` | Zamanlanmış görevi kurmaz ya da kaldırmaz. |
| `-EsitlemeAtla` | Kurulumdan sonra eşitlemeyi çalıştırmaz. |
| `-KullaniciKlasoru <yol>` | Başka bir kullanıcı klasörüne kurar (deneme için). |

Kaldırma, oturum kayıtlarına dokunmaz. Her hesap klasörü o ana kadar eşitlenmiş kayıtları tutar; yalnız sonraki değişiklikler artık paylaşılmaz.

## Güncelleme

```bash
git -C .\claude-desktop-session-sync pull
```

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File .\claude-desktop-session-sync\kur.ps1
```

Kurulum betiği istediğin zaman yeniden çalıştırılabilir: değişmeyen dosyalara dokunmaz, kancayı çoğaltmaz, `CLAUDE.md` bölümünü yeniler. Çalışan izleyici betiğin değiştiğini fark edip kendini yeniden başlatır.

## Günlük kullanım

- **Hesap değiştirirken:** Süren bir yanıt varsa bitmesini bekle, çıkış yap, öbür hesapla giriş yap ve kenar çubuğuna bak. Yeniden başlatmaya gerek yok.
- **Geçişten sonra bir şey eksikse:** Uygulamayı tepsiden **Çıkış** ile kapatıp yeniden aç.
- **Betik komutları** (`%USERPROFILE%\Claude-hesap-esitleme\` klasöründen çalıştırılır):

| Komut | Açıklama |
|---|---|
| `hesap-oturum-esitle.ps1 -KuruCalisma` | Deneme: değişecekleri günlüğe yazar, hiçbir şeyi değiştirmez. |
| `hesap-oturum-esitle.ps1` | Bir tam eşitleme ve onarım turu çalıştırır, izleyici çalışmıyorsa başlatır. |
| `hesap-oturum-esitle.ps1 -ZorlaDuzelt` | Worktree düzeltmelerini uygulama açıkken de yapar; düzeltmeler uygulama tamamen yeniden başlayınca geçerli olur. |
| `hesap-oturum-esitle.ps1 -GorevKur` | Oturum açılışı görevini kurar ya da yeniler. |

## Sorun giderme

Önce deneme modunda çalıştırıp günlüğü oku:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\Claude-hesap-esitleme\hesap-oturum-esitle.ps1" -KuruCalisma
```

Günlük: `%USERPROFILE%\Claude-hesap-esitleme\esitleme.log`. 5 MB'ı aşınca `esitleme_<zaman>.log` adını alır ve yeni bir günlük başlar. Yedekler `%USERPROFILE%\Claude-hesap-esitleme\yedek\` klasöründe.

| Belirti | Bakılacak yer |
|---|---|
| Yeni oturumlar hesap değişince ya da yeniden başlatınca kayboluyor | Uygulama günlüğünde (`%LOCALAPPDATA%\Claude\logs\main.log`) `Failed to save session` ara. `symlink/file plant` görüyorsan bir klasör hâlâ bağlantıdır; betiği bir kez çalıştır. |
| Bir oturumda her mesaj "Bir şeyler ters gitti" ile bitiyor | Uygulama günlüğünde `not recreating its worktree` ara. Uygulamayı tepsiden kapat, 30 saniye bekle ve aç; izleyici kaydı uygulama kapalıyken onarır. |
| Bir proje kenar çubuğunda iki kez görünüyor | Büyük ihtimalle projeyle aynı adı taşıyan, elle oluşturulmuş bir kenar çubuğu grubu var. O grubu uygulamadan sil; oturumları silinmez. |
| Turuncu "girdi bekliyor" noktaları her hesap değişiminde geri geliyor | Bu uygulamanın kendi davranışı, bu araçtan kaynaklanmıyor. Bkz. [bulgular](docs/FINDINGS.md#orange-dots). |
| Bir düzeltme geçerli olmuyor gibi | Uygulamanın gerçekten yeniden başladığından emin ol: uygulama günlüğünde yeni bir `Loaded N persisted sessions` satırı çıkmalı. |

İzleyicinin çalıştığını görmek için:

```bash
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object CommandLine -match '-Izle' | Select-Object ProcessId,CreationDate"
```

Hata bildirirken `esitleme.log` dosyasının son 30 satırını, Claude uygulamasının sürümünü ve Store mu yoksa doğrudan indirilen sürüm mü kullandığını ekle. Jetonları ya da `config.json` içeriğini yapıştırma.

## Hesap değiştirmeden iki hesabı kullanmak

Masaüstü uygulamasının girişi, terminaldeki ve VS Code/Cursor eklentisindeki Claude Code'un girişinden ayrıdır. [Resmi belgeye](https://code.claude.com/docs/en/vs-code) göre eklenti ve terminal aynı konuşma geçmişini paylaşır; bu geçmiş bilgisayarda tutulur ve bir hesaba bağlı değildir. Bu yüzden masaüstü uygulamasını bir hesapta, eklentiyi ya da terminali öbür hesapta tutup hiç hesap değiştirmeden çalışabilirsin. Bunun bedeli, iki tarafın ayrı oturum listeleri tutmasıdır.

## Gelecek: uygulama içi çoklu hesap

Masaüstü uygulamasının içinde, sunucu tarafındaki bir anahtara bağlı bir çoklu hesap özelliği zaten var. Uygulamada bir de `disableMultiAccount` ("Single account only") kurumsal ilkesi bulunuyor. Anthropic bu özelliği kademeli olarak açıyor gibi görünüyor. Zorla açmaya çalışma. Hesap menüsünde başka hesap ekleme seçeneğini gördüğünde bu araca hâlâ ihtiyacın olup olmadığına bak.

## Paylaşılmayanlar

- Kenar çubuğu özel grupları ve sabitlemeler
- Kenar çubuğu noktalarındaki "Tamamlandı olarak işaretle" durumu
- claude.ai bağlayıcıları, skill'leri ve eklentileri
- Bulut oturumları ve arka plan ajan oturumları
- Başka bir bilgisayardaki her şey. Araç bilgisayar başına çalışır, çünkü dökümler ve worktree'ler her bilgisayarın kendi diskinde durur.

## Dosyalar

| Dosya | Görev |
|---|---|
| `hesap-oturum-esitle.ps1` | Eşitleme betiği. Kanca, oturum açılışı görevi ve izleyici (`-Izle`) bu dosyayı çalıştırır. |
| `kur.ps1` | Kurulum ve kaldırma betiği. |
| `sablon/claude-md-bolum.md` | `~/.claude/CLAUDE.md` dosyasına yazılan bölümün şablonu. |
| `tests/Test-Sync.ps1` | Sahte bir veri klasöründe uçtan uca test. Gerçek Claude verine hiç dokunmaz. |
| `docs/FINDINGS.md` | Masaüstü uygulamasının oturumları nasıl sakladığı ve aracı yaparken öğrendiklerimiz. |

## Uyarı

Bu resmi olmayan bir araçtır. Anthropic ile bağlantısı yoktur; Anthropic tarafından onaylanmamış ve desteklenmemektedir. Claude masaüstü uygulamasının veri klasöründe, biçimi belgelenmemiş ve haber verilmeden değişebilecek dosyaları okur ve yazar. Araç her değişiklikten önce yedek alır ve hiçbir dosyayı silmez, ama kullanım sorumluluğu sana aittir. `%LOCALAPPDATA%\Claude-Data` (ya da `%APPDATA%\Claude`) ve `%USERPROFILE%\.claude\projects` klasörlerinin kendi yedeklerini al.

## Lisans

[MIT](LICENSE)
