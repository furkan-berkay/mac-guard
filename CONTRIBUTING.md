# Katkı

MacGuard'ın küçük, okunur ve güvenilir kalmasını istiyorum. Katkıya açığım.

## Temel kurallar

1. **Hiçbir şey ücretli olmayacak.** Ücretli servis, sunucu, lisans ya da Apple
   geliştirici üyeliği gerektiren bir çözüm eklenmez. CI, GitHub Actions'ın
   herkese açık depolar için ücretsiz macOS makinelerinde çalışıyor.
2. **Dış bağımlılık yok.** Yalnızca Apple'ın sistem çerçeveleri.
3. **Perdeden her zaman bir çıkış olmalı.** Kilit ekranı ya da alarm perdesi
   gösteren her değişiklik PIN'i ulaşılabilir bırakmalı. Sahibi kendi alarmını
   susturamaz hâle gelirse Mac'i güç düğmesiyle kapatmak zorunda kalır.
4. **Sıfır uyarı.** CI `swift build -c release -Xswiftc -warnings-as-errors`
   çalıştırır; tek bir uyarı bile CI'ı kırar.

## Geliştirme ortamı

macOS 14+ ve Xcode ya da Xcode Command Line Tools yeterli.

```bash
git clone https://github.com/furkan-berkay/mac-guard.git
cd mac-guard
./install.sh
```

| Komut | Ne yapar |
|---|---|
| `swift build` | Hızlı derleme, sadece hata kontrolü |
| `swift build -c release -Xswiftc -warnings-as-errors` | CI'ın yaptığı kontrol |
| `./Scripts/build_app.sh` | `.app` paketini `build.noindex/` altına üretir |
| `./install.sh` | Derler, `/Applications` altına kurar, açar |

Uygulamanın gerçek davranışı ancak `/Applications` altına kurulmuş `.app`'te
görülür; kamera, Touch ID ve Erişilebilirlik izinleri paket kimliğine bağlı.

## Akış

1. Değişikliği yap, `./install.sh` ile kur.
2. Aşağıdaki test listesinden değişikliğe dokunan maddeleri elle dene.
3. Commit'le, push'la ya da PR aç. CI yeşil olmadan birleştirme.

## Elle test listesi

Birim testi yok; davranış donanıma ve sistem izinlerine bağlı. Riskli bir
değişiklikten sonra:

- [ ] Ayarlar → Koruma ekranı → **Önizle (10 sn)**: perde açılıyor, PIN ve parmak
      iziyle kapanıyor
- [ ] Korumayı başlat, şarj kablosunu çıkar: alarm çalıyor
- [ ] Alarmı PIN'le sustur: uygulama kapanıyor
- [ ] Alarmı parmak iziyle sustur: uygulama kapanıyor
- [ ] Parmak izi seçiliyken **PIN ile gir** çalışıyor
- [ ] Koruma açıkken bir F tuşuna ve güç düğmesinin kenarına basmak alarm çalıyor
- [ ] Alarm sırasında ses kısılınca geri geliyor; oynat tuşu Müzik'i açmıyor
- [ ] Ayarlar → Alarm → **Alarmı 5 saniye dinle** ayarlanan seviyede çalıyor
- [ ] Metin eklediysen: Ayarlar → Sistem → Dil → English ile ekranda İngilizce görünüyor

Alarm testlerini evde yapıyorsan önce Ayarlar → Alarm'dan ses seviyesini düşür.

## Metinler ve çeviri

Arayüz Türkçe yazılır; anahtar Türkçe metnin kendisidir. İngilizce karşılıkları
`Resources/en.lproj/Localizable.strings` içinde.

- SwiftUI'ya doğrudan yazılan metinler (`Text("…")`, `Button("…")`) kendiliğinden
  çevrilir. Düz `String` olarak dolaşan metinleri (olay kaydı, bildirim, sensör
  mesajı) `String(localized: "…")` ile yaz.
- Yeni bir metin eklediysen İngilizcesini `en.lproj/Localizable.strings`'e ekle ve
  kontrol et:

```bash
python3 Scripts/check_localization.py
```

Betik anahtarları derleyiciye çıkartır; çevirisi olmayan ya da `%@`, `%lld`
belirteçleri tutmayan bir metin varsa hata verir. CI'da da çalışır.

## Kod tarzı

- **Yorumlar Türkçe** ve *ne* değil *neden* anlatır. Kod zaten ne yaptığını söyler.
- **Ana iş parçacığını bloklama.** `Process`, Anahtar Zinciri ve dosya sistemi
  çağrıları bu projede uygulamayı kilitledi; arka plan kuyruğunda çalışsınlar.
- **Sensör durumu hangi kuyrukta okunuyorsa orada yazılsın.** Veri yarışı
  istemiyoruz.
- **Başarısızlığı yutma.** Bildirim gitmediyse, izin yoksa, bir sensör
  çalışmıyorsa kullanıcı bunu görmeli.
- Commit mesajları Türkçe; neyin neden değiştiğini anlatır.

## Proje yapısı

```
Sources/MacGuard/
├── App/        Giriş noktası, menü çubuğu, künye, oturum açılış öğesi
├── Core/       GuardEngine (durum makinesi), ayarlar, olay kaydı, tetik türleri
├── Sensors/    Kamera, güç, kapak, USB, klavye/güç düğmesi, ekran, kamera izni
├── Alarm/      Siren, ses çıkışları, sesli uyarı, uyku engeli, tuş kilidi,
│               medya tuşları, kaçış kilitleri
├── Security/   PIN, Touch ID, alarm fotoğrafları
├── Notify/     ntfy istemcisi, alarm anı bildirimi
└── UI/         Ana pencere (Dashboard/), ayarlar, perdeler, susturma paneli
Scripts/
├── build_app.sh       .app paketini kurar ve imzalar
├── setup_signing.sh   Yerel imza kimliği
├── check_localization.py  Her metnin İngilizce çevirisi var mı
├── make_icon.swift    Uygulama ikonunu çizer
└── export_siren.swift Sireni WAV dosyasına aktarır
```

Ayrıntılı iç yapı: [docs/NASIL-CALISIR.md](docs/NASIL-CALISIR.md).

## Sireni dosyaya aktarmak

```bash
swiftc -O -o /tmp/export_siren Scripts/export_siren.swift Sources/MacGuard/Alarm/AlarmSiren.swift
```

```bash
/tmp/export_siren ~/Downloads
```

Dalga formu uygulamanın çaldığıyla birebir aynı; ikisi de `SirenVoice`'u
kullanıyor.

## Güvenlik bulguları

PR ya da issue yerine [SECURITY.md](SECURITY.md)'deki özel bildirim yolunu kullan.
