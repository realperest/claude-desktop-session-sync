# CLAUDE_BIRLESTIR

Claude masaüstü uygulamasında (Code sekmesi) birden fazla hesap arasında geçiş yaparken oturum listesinin, sohbet geçmişinin ve ayarların aynı kalmasını sağlar. Hesap değişince yalnızca kullanım limiti değişir.

## Ne yapar

Uygulama, Code sekmesindeki oturum listesini her hesap için ayrı bir klasörde tutar:

```
<veri>\claude-code-sessions\<hesapUUID>\<kurulusUUID>\local_*.json
```

Hesap değişince öbür hesabın oturumları silinmez ama listede görünmez. `hesap-oturum-esitle.ps1` betiği şunları yapar:

- **Çift yönlü eşitleme:** Bütün hesap klasörlerini (bir hesap birden fazla kuruluş klasörü kullanabilir) gerçek klasör olarak tutar. Her kayıt dosyasının en yeni sürümünü öbür klasörlere kopyalar. Değiştirilme zamanını koruduğu için kopyalar klasörler arasında gidip gelmez.
- **Arka plan izleyicisi:** Gizli bir izleyici klasörleri 15 saniyede bir eşitler, 10 dakikada bir de kayıp kayıt onarımı ve ayar eşitlemesi yapar. Böylece hesap değiştirdiğin anda öbür hesabın listesi zaten günceldir. İzleyici tek kopya çalışır, betik güncellenince kendini yeni sürümle yeniden başlatır.
- **Silinen oturumlar geri gelmez:** Bir hesapta silinen oturumun (`deleted_<kimlik>` işareti) öbür klasörlerdeki kopyaları silinmez, `yedek\` klasörüne taşınır.
- **Kayıp kayıt onarımı:** Sohbet dökümü duran ama listede kaydı olmayan oturumların kaydını dökümden yeniden oluşturur. Silinmiş oturumlar, son 15 dakikada açılan oturumlar ve uygulama günlüğüne göre yaşayan bir oturumun eski kimliği olan dökümler onarılmaz.
- **Ortak ayarlar:** Kayıtlı ortam ayarlarını (`ccd-session-presets.json`) ve MCP araç seçimlerini (`mcp-user-tool-toggles.json`) iki hesapta aynı yapar. Yalnızca eksik olanı ekler. Uygulama açıkken bu dosyaları kendi belleğinden yeniden yazdığı için bu adım yalnız uygulama kapalıyken çalışır.
- **Taşınma uyarısı:** Uygulama veri klasörünü taşırsa günlüğe uyarı yazar ve haber verir.
- **Bağlantı temizliği:** Eski sürümlerin kurduğu NTFS bağlantılarını (junction) gerçek klasöre çevirir.

> **Neden bağlantı (junction) yok:** Uygulamanın yeni sürümleri bağlantı olan klasöre yazmayı reddeder (`Refusing non-directory at private dir path (symlink/file plant)`). Bağlantıdan okuyabildiği için liste normal görünür, ama yeni oturumlar ve değişiklikler diske yazılmaz ve hesap değişince kaybolur. Mesaj gönderirken görülen "Gönderilemedi" hatası da büyük ihtimalle bu yüzdendir. Bu yüzden eşitleme kopyalayarak yapılır.

Hiçbir dosyayı silmez. Her değişiklikten önce `yedek\` klasörüne yedek alır.

## Kurulum

Her bilgisayarda bir kez yapılır. Windows PowerShell 5.1 yeterli; yönetici yetkisi gerekmez.

1. Depoyu indir:

   ```bash
   git clone https://github.com/realperest/CLAUDE_BIRLESTIR.git
   ```

2. Önce deneme modunda çalıştır. Hiçbir şey değişmez, yalnızca yapılacaklar gösterilir:

   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File .\CLAUDE_BIRLESTIR\kur.ps1 -Deneme
   ```

3. Kur:

   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File .\CLAUDE_BIRLESTIR\kur.ps1
   ```

4. Claude uygulamasını tepsideki simgeden tamamen kapatıp yeniden aç. Pencereyi kapatmak yetmez.
5. Hesapların hepsine bu bilgisayarda en az bir kez giriş yap. Bir hesaba ilk kez giriş yaptıysan bir kez daha çıkış yapıp gir. O hesabın klasörü ilk girişte oluşur ve izleyici onu birkaç saniye içinde öbür klasörlerle eşitler.

### `kur.ps1` neler yapar

1. Kullanıcı klasörünü ve Claude veri klasörünü bulur.
2. `settings.json` dosyasını, `CLAUDE.md` dosyasını ve varsa eski betiği `Claude-hesap-esitleme\yedek\kurulum_<zaman>\` klasörüne yedekler.
3. Eşitleme betiğini `%USERPROFILE%\Claude-hesap-esitleme\` klasörüne kopyalar.
4. `~/.claude/settings.json` dosyasına SessionStart kancasını ekler. Öteki ayarlara dokunmaz, kanca varsa ikinci kez eklemez.
5. `~/.claude/CLAUDE.md` dosyasına bu bilgisayarın yollarıyla "Claude Account Switching" maddesini yazar. Madde varsa yeniler.
6. Windows oturum açılışında çalışan zamanlanmış görevi kurar.
7. Eşitlemeyi önce kuru, sonra gerçek olarak çalıştırır. Gerçek çalıştırma arka plan izleyicisini de başlatır.

Bir adım hata verirse o ana kadar yapılan değişiklikleri yedekten geri alır ve durur. Her adım ekrana ve `Claude-hesap-esitleme\kurulum.log` dosyasına yazılır.

### Seçenekler

| Seçenek | Açıklama |
|---|---|
| `-Deneme` | Hiçbir şeyi değiştirmeden yapılacakları gösterir. |
| `-Kaldir` | Kancayı, `CLAUDE.md` maddesini ve zamanlanmış görevi kaldırır, arka plan izleyicisini durdurur. Betik, günlük ve yedekler yerinde kalır. |
| `-GorevKurma` | Zamanlanmış görevi kurmaz ya da kaldırmaz. |
| `-EsitlemeAtla` | Kurulumdan sonra eşitlemeyi çalıştırmaz. |
| `-KullaniciKlasoru <yol>` | Başka bir kullanıcı klasörüne kurar (deneme için). |

`-Kaldir`, oturum klasörlerindeki kayıtlara dokunmaz. Her hesap klasörü o ana kadar eşitlenmiş kayıtları tutar, ama sonraki değişiklikler artık öbür hesaba geçmez. Eski sürümlerden kalan klasörler `<ad>_eski_<zaman>` adıyla, yedekler de `yedek\` altında durur.

## Güncelleme

Depoyu güncelleyip `kur.ps1` dosyasını yeniden çalıştır. Kurulum tekrar çalıştırılabilir: değişmeyen dosyalara dokunmaz, kancayı çoğaltmaz, `CLAUDE.md` maddesini yeniler.

```bash
git -C .\CLAUDE_BIRLESTIR pull
```

## Sorun giderme

Hesap değiştirince oturumlar eksikse, önce değişiklik yapmadan neler olacağına bak:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\Claude-hesap-esitleme\hesap-oturum-esitle.ps1" -KuruCalisma
```

Sonra `%USERPROFILE%\Claude-hesap-esitleme\esitleme.log` dosyasını oku.

Uygulamanın kendi günlüğünde (`%LOCALAPPDATA%\Claude\logs\main.log`) `Failed to save session` satırı varsa, uygulama kayıtları diske yazamıyor demektir. Önce bu satırı ara.

İzleyicinin çalıştığını görmek için:

```bash
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object CommandLine -match '-Izle' | Select-Object ProcessId,CreationDate"
```

Kenar çubuğunda aynı proje iki grup olarak görünüyorsa, sebep büyük ihtimalle elle oluşturulmuş ve projeyle aynı adı taşıyan özel bir gruptur. Bu gruplar uygulamanın kendi deposunda durduğu için betik onlara dokunmaz. Grubu uygulamadan sil ya da Claude'dan silmesini iste. Oturumlar silinmez, projeye göre gruplanır.

## Sınırlar

- **Bilgisayar başına çalışır.** Bilgisayarlar arasında oturum eşitlemez. Sohbet dökümleri ve worktree'ler her bilgisayarın kendi diskinde durur.
- **Ortak olmayanlar:** Kenar çubuğu özel grupları ve sabitlemeler, claude.ai bağlayıcıları, claude.ai skill'leri ve eklentileri, bulut oturumları ve arka plan ajan oturumları her hesapta ayrı kalır.
- **Resmi değil.** Uygulamanın belgelenmemiş klasör yapısına dayanır. Bir uygulama güncellemesi yapıyı değiştirirse betik güncellenmelidir.
- **Hesap bilgisi yok.** Betik hiçbir hesap bilgisine, şifreye ya da jetona dokunmaz.

## Dosyalar

| Dosya | Görev |
|---|---|
| `hesap-oturum-esitle.ps1` | Eşitleme betiği. SessionStart kancası ve zamanlanmış görev bunu çalıştırır. Arka plan izleyicisi aynı betiğin `-Izle` modudur. |
| `kur.ps1` | Kurulum ve kaldırma betiği. |
| `sablon/claude-md-bolum.md` | `CLAUDE.md` dosyasına yazılan maddenin şablonu. |
