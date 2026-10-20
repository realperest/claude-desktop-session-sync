# CLAUDE_BIRLESTIR

Claude masaüstü uygulamasında (Code sekmesi) birden fazla hesap arasında geçiş yaparken oturum listesinin, sohbet geçmişinin ve ayarların aynı kalmasını sağlar. Hesap değişince yalnızca kullanım limiti değişir.

## Ne yapar

Uygulama, Code sekmesindeki oturum listesini her hesap için ayrı bir klasörde tutar:

```
<veri>\claude-code-sessions\<hesapUUID>\<kurulusUUID>\local_*.json
```

Hesap değişince öbür hesabın oturumları silinmez ama listede görünmez. `hesap-oturum-esitle.ps1` betiği şunları yapar:

- **Ortak klasör:** Bütün hesap klasörlerini tek bir ortak klasörde birleştirir. Öbür klasörleri yedekler ve yerlerine NTFS bağlantısı (junction) kurar.
- **Bağlantı onarımı:** Kırık ya da yanlış yeri gösteren bağlantıları düzeltir.
- **Kayıp kayıt onarımı:** Sohbet dökümü duran ama listede kaydı olmayan oturumların kaydını dökümden yeniden oluşturur. Uygulama veri klasörünü taşırken böyle kayıplar olabiliyor. Silinmiş oturumlar ve son 15 dakikada açılan oturumlar onarılmaz.
- **Ortak ayarlar:** Kayıtlı ortam ayarlarını (`ccd-session-presets.json`) ve MCP araç seçimlerini (`mcp-user-tool-toggles.json`) iki hesapta aynı yapar. Yalnızca eksik olanı ekler.
- **Taşınma uyarısı:** Uygulama veri klasörünü taşırsa günlüğe uyarı yazar ve haber verir.

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
5. Hesapların hepsine bu bilgisayarda en az bir kez giriş yap. Bir hesaba ilk kez giriş yaptıysan bir kez daha çıkış yapıp gir. O hesabın klasörü ilk girişte oluşur ve bir sonraki çalıştırmada ortak klasöre bağlanır.

### `kur.ps1` neler yapar

1. Kullanıcı klasörünü ve Claude veri klasörünü bulur.
2. `settings.json` dosyasını, `CLAUDE.md` dosyasını ve varsa eski betiği `Claude-hesap-esitleme\yedek\kurulum_<zaman>\` klasörüne yedekler.
3. Eşitleme betiğini `%USERPROFILE%\Claude-hesap-esitleme\` klasörüne kopyalar.
4. `~/.claude/settings.json` dosyasına SessionStart kancasını ekler. Öteki ayarlara dokunmaz, kanca varsa ikinci kez eklemez.
5. `~/.claude/CLAUDE.md` dosyasına bu bilgisayarın yollarıyla "Claude Account Switching" maddesini yazar. Madde varsa yeniler.
6. Windows oturum açılışında çalışan zamanlanmış görevi kurar.
7. Eşitlemeyi önce kuru, sonra gerçek olarak çalıştırır.

Bir adım hata verirse o ana kadar yapılan değişiklikleri yedekten geri alır ve durur. Her adım ekrana ve `Claude-hesap-esitleme\kurulum.log` dosyasına yazılır.

### Seçenekler

| Seçenek | Açıklama |
|---|---|
| `-Deneme` | Hiçbir şeyi değiştirmeden yapılacakları gösterir. |
| `-Kaldir` | Kancayı, `CLAUDE.md` maddesini ve zamanlanmış görevi kaldırır. Betik, günlük ve yedekler yerinde kalır. |
| `-GorevKurma` | Zamanlanmış görevi kurmaz ya da kaldırmaz. |
| `-EsitlemeAtla` | Kurulumdan sonra eşitlemeyi çalıştırmaz. |
| `-KullaniciKlasoru <yol>` | Başka bir kullanıcı klasörüne kurar (deneme için). |

`-Kaldir`, oturum klasörlerindeki bağlantılara dokunmaz. Bağlantıları kaldırmak öbür hesabın oturumlarını yeniden gizler. Eski klasörler `<ad>_eski_<zaman>` adıyla, yedekleri de `yedek\` altında durur.

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

Kenar çubuğunda aynı proje iki grup olarak görünüyorsa, sebep büyük ihtimalle elle oluşturulmuş ve projeyle aynı adı taşıyan özel bir gruptur. Bu gruplar uygulamanın kendi deposunda durduğu için betik onlara dokunmaz. Grubu uygulamadan sil ya da Claude'dan silmesini iste. Oturumlar silinmez, projeye göre gruplanır.

## Sınırlar

- **Bilgisayar başına çalışır.** Bilgisayarlar arasında oturum eşitlemez. Sohbet dökümleri ve worktree'ler her bilgisayarın kendi diskinde durur.
- **Ortak olmayanlar:** Kenar çubuğu özel grupları ve sabitlemeler, claude.ai bağlayıcıları, claude.ai skill'leri ve eklentileri, bulut oturumları ve arka plan ajan oturumları her hesapta ayrı kalır.
- **Resmi değil.** Uygulamanın belgelenmemiş klasör yapısına dayanır. Bir uygulama güncellemesi yapıyı değiştirirse betik güncellenmelidir.
- **Hesap bilgisi yok.** Betik hiçbir hesap bilgisine, şifreye ya da jetona dokunmaz.

## Dosyalar

| Dosya | Görev |
|---|---|
| `hesap-oturum-esitle.ps1` | Eşitleme betiği. SessionStart kancası ve zamanlanmış görev bunu çalıştırır. |
| `kur.ps1` | Kurulum ve kaldırma betiği. |
| `sablon/claude-md-bolum.md` | `CLAUDE.md` dosyasına yazılan maddenin şablonu. |
