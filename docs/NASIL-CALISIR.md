# MacGuard nasıl çalışır

Bu belge uygulamanın içini anlatır: hangi tetik nasıl algılanıyor, alarm neyi
değiştiriyor, neden öyle yapıldı. Kullanım için [README](../README.md) yeterli.

## Durum makinesi

Her şey `Core/GuardEngine.swift` içindeki tek bir durum makinesinden geçer:

```
kapalı → devreye giriyor (geri sayım) → koruma → [uyarı] → alarm
   ↑                                                           │
   └──────────── PIN ya da parmak izi → uygulama kapanır ◄─────┘
```

- **Devreye giriyor:** geri sayım (en az 3 sn). Bu sırada kamera ısınır.
- **Koruma:** sensörler nöbette, kilit ekranı açık.
- **Uyarı** (isteğe bağlı, Ayarlar → Zamanlama → Uyarı süresi): tam sirenden önce
  kesik bip ve geri sayım. Süre içinde susturulursa alarm hiç çalmaz.
- **Alarm:** siren, perde, fotoğraf, bildirim.

Sahibi korumayı kapatınca her şey bulunduğu hâline döner ve uygulama kapanır.
Alarm anındaki fotoğraf ve bildirim hâlâ gönderiliyorsa en fazla 15 sn beklenir.
Koruma durumu diske yazılmaz; uygulama her zaman "kapalı" başlar.

## Tetikler

| Tetik | Nasıl algılanıyor | Kaynak |
|---|---|---|
| Hareket | Kamera karelerinin farkı, kareye yayılma oranıyla | `Sensors/CameraSensor.swift` |
| Yakınlık | Vision ile yüz kutusunun kadrajdaki yüksekliği | `Sensors/CameraSensor.swift` |
| Şarj kablosu | IOKit güç kaynağı bildirimi | `Sensors/PowerSensor.swift` |
| Ekran kapağı | `IOPMrootDomain` → `AppleClamshellState` yoklaması | `Sensors/ClamshellSensor.swift` |
| USB aygıt | IOKit eşleşme bildirimleri | `Sensors/USBSensor.swift` |
| Klavye / trackpad | Sistemin "son girdiden beri geçen süre" sayacı | `Sensors/InputSensor.swift` |
| Güç düğmesi | Güç yönetimindeki düğme kaydı (aşağıda) | `Sensors/InputSensor.swift` |
| Harici ekran | Ekran sayısının değişmesi | `Sensors/DisplaySensor.swift` |
| Tanınmayan parmak izi | Touch ID'nin "eşleşmedi" sonucu | `Core/GuardEngine.swift` |

### Hareket neden kamerayla algılanıyor

Apple Silicon MacBook'larda ivmeölçer yok; eski Intel'lerdeki Sudden Motion
Sensor SSD'ye geçişle kaldırıldı. MacGuard hareketi görüntüden çıkarıyor:
bilgisayar kaldırılınca bütün sahne birden kayar.

Kare 48×36'lık bir parlaklık ızgarasına indirgenip ardışık kareler karşılaştırılır.
Odanın ışığı topluca değişince tetiklenmesin diye ortalama fark çıkarılır, tek
karelik gürültü alarm çaldırmasın diye eşiğin iki ardışık karede aşılması gerekir.

"Bilgisayar oynadı" ile "önünde biri kıpırdadı"yı ayıran **kare kaplama oranı**:
bilgisayar oynayınca karenin tamamı değişir, önünde biri kıpırdayınca yalnızca
bir bölgesi. Tetik için hem değişimin şiddeti hem kaplama oranı eşiği geçmeli
(varsayılan kaplama eşiği %50).

### Sakinleşme

Korumayı başlattığın anda sen hâlâ bilgisayarın başındasın. Bu yüzden sensörler
hemen tetik üretmez:

| Sensör | Nöbete geçme şartı |
|---|---|
| Hareket | ~1,2 sn boyunca sahne sakin |
| Yakınlık | ~2 sn boyunca kadrajda eşiğe yakın yüz yok |
| Klavye / trackpad | 2 sn hiç dokunulmamış |

Panelde her sensör kartında "Nöbette" ya da "Sakinleşme bekleniyor" yazar.
Klavye sensörü fare her oynadığında beklemeyi baştan başlattığı için devreye
girme gecikmesi en az 3 sn.

### Klavye, F tuşları ve güç düğmesi

Klavye sensörü olay dinlemiyor; `CGEventSource.secondsSinceLastEventType` ile
"her tür girdi" (`kCGAnyInputEventType`) için son girdiden beri geçen süreyi
okuyor. Bu yöntem izin istemez ve F tuşlarını da kapsar. Parlaklık, ses, Odak
gibi tuşlar normal tuş değil "sistem tanımlı" olay olarak geliyor.

Güç/Touch ID düğmesi hiçbir girdi sayacına düşmüyor. Ama her basışta WindowServer,
güç yönetimine `service:AppleM68Buttons` adını taşıyan bir "kullanıcı aktif" kaydı
bırakıyor. MacGuard bu kaydı `IOPMCopyAssertionsByProcess` ile okuyup kimliği ya da
zaman damgası değişince basış sayıyor. Parmağı yalnızca okutmak bu kaydı
oluşturmuyor. Kayıt adı macOS'un iç biçimi; ileride değişirse bu tetik sessizce
çalışmaz hâle gelir. Intel Mac'lerde düğme servisinin adı farklı olabilir.

## Kilit ekranı ve alarm perdesi

İkisi de her ekranda bir tane olmak üzere kenarlıksız, ekran koruyucu seviyesinde
pencereler (`UI/LockScreenOverlay.swift`, `UI/AlarmOverlay.swift`). Alarm perdesi
kilit ekranının bir seviye üstünde.

`UI/OverlayGuardian.swift` perdeyi kurup unutmaz:

- **Ekran düzeni değişirse** (kapak açılıp kapandı, ekran takıldı) perdeyi o anki
  ekranlara göre yeniden kurar.
- **Kullanıcı az önce dokunduysa** perdeyi öne alır ve klavyeyi farenin bulunduğu
  ekrandaki tuş takımına verir.

Alarm süresince `Alarm/EscapeLockdown.swift` Dock'u, menü çubuğunu, ⌘-Tab'ı,
Zorla Çık'ı ve oturumu kapatmayı devre dışı bırakır. ⌘Q koruma açıkken sessizce
reddedilir; uyarı kutusu açılmaz, çünkü perdenin arkasında kalıp uygulamayı
kilitliyordu.

## Susturma

### PIN

`Security/PinStore.swift`: PIN tuzlanmış, 50.000 turlu SHA-256 özeti olarak
`~/Library/Application Support/MacGuard/pin.json` içinde (0600). Anahtar Zinciri
bilerek kullanılmıyor: imza değiştikçe macOS onay penceresi açıp uygulamayı
kilitliyordu. Üç hatalı denemeden sonra katlanarak artan bekleme (en fazla 60 sn).

### Touch ID

`Security/BiometricAuth.swift` ve `UI/DisarmPanel.swift`:

- **Yalnızca biyometrik.** Mac parolasına düşen bir yedek yok; olsaydı parolayı
  bilen herkes alarmı kapatabilirdi.
- **Perdenin içine gömülü.** Sistemin Touch ID penceresi ekran koruyucu
  seviyesindeki perdenin arkasında kalırdı. `LAAuthenticationView` doğrulamayı
  perdedeki panelin içinde gösteriyor.
- **Her zaman odaktaki pencerede.** Gömülü görünüm yalnızca anahtar (key)
  pencerede çalışıyor; odak kaçınca sistem beklemeyi duraklatıyor. Bekleme bu
  yüzden odağı izliyor: alarm perdesi kilit ekranının üstüne açılıp odağı alınca
  bekleme oraya taşınıp baştan başlıyor.
- **Kendini toparlıyor.** Uyku, ekran kilidi ya da Touch ID düğmesine basmak
  beklemeyi iptal eder; bekleme kendiliğinden yeniden başlar.
- **Tanınmayan parmak izi alarm çalar** (koruma açıkken). İlk hatalı okumada değil,
  Touch ID'nin kendi tekrar denemeleri de tutmazsa.
- **PIN hep ulaşılabilir.** Touch ID panelinin altında "PIN ile gir" var; Touch ID
  kullanılamazsa (kapak kapalı, kilitlenmiş) panel kendiliğinden PIN'e döner.

### Güvenlik PIN'i

Ayarlar'ın en altında ikinci bir PIN alanı var: perde bir sebeple ulaşılamaz
olursa alarm buradan durdurulur. Hatalı deneme sayacı perdeyle aynı.

## Alarm çıktıları

`Alarm/AlarmOutputs.swift` alarmın duyulan tarafını yönetir ve bitince sistemi
bulduğu gibi bırakır:

- **Siren** kodda üretilir (`Alarm/AlarmSiren.swift`, üçgen frekans süpürmesi ve
  `tanh` kırpma); ses dosyası taşınmaz. Uyarı aşamasında kesik bip çalar.
- **Ses seviyesi** CoreAudio ile ayarlanır ve saniyede bir kontrol edilir; biri
  kısarsa ya da sessize alırsa geri getirilir. İstenirse çıkış dahili hoparlöre
  alınır.
- **Sesli uyarı** `AVSpeechSynthesizer` ile Türkçe okunur.
- **Medya tuşları** (`Alarm/MediaKeyShield.swift`): MacGuard kendini "şu an çalan
  uygulama" olarak bildirir; oynat tuşu Müzik'i açmaz. İzin gerekmez.
- **Tuş kilidi** (`Alarm/SystemKeyLock.swift`): Erişilebilirlik izni varsa koruma
  açıkken bir olay dinleyicisi klavyeden yalnızca PIN tuşlarını (rakamlar, sil,
  Enter) geçirir; Odak, Spotlight, Dikte, Mission Control ve medya tuşları durur.
  Fare, Touch ID ve güç düğmesi etkilenmez.

Ayarlardaki **Alarmı 5 saniye dinle** aynı yolu kullanır; önizlemede duyduğun,
alarmda duyacağınla aynı.

## Fotoğraf ve bildirim

`Notify/RemoteAlert.swift`: alarm anında kameradan tek kare alınır ve önce diske
yazılır (`Snapshots/`, klasör 0700, dosyalar 0600, en son 100 kare). Bildirim
açıksa sonra ntfy'ye gönderilir. Kurulum: [Telefona bildirim](TELEFON-BILDIRIMI.md).

## Uyku

`Alarm/SleepBlocker.swift`:

- Koruma açıkken sistem uykusu, kilit ekranı açıksa ekran uykusu da `IOPMAssertion`
  ile engellenir. Alarm anında ekran her durumda uyandırılır.
- **Kapak kapansa bile uyuma** seçeneği koruma süresince `pmset disablesleep 1`
  yapar, bitince geri alır. Root ister; isteğe bağlı `/etc/sudoers.d/macguard`
  kuralı yalnızca bu iki `pmset` komutunu kapsar ve yazılmadan önce `visudo -cf`
  ile doğrulanır.
- Uyku engeli açıkken uygulama çökerse bir sonraki açılışta ayar geri alınır.
- Mac uyuyup uyanırsa alarm kaldığı yerden devam eder.

## İmza ve derleme

- `Scripts/build_app.sh` `.app` paketini elle kurar ve imzalar.
- **Yerel imza kimliği** (`Scripts/setup_signing.sh`): ad-hoc imzada macOS
  uygulamayı kod özetiyle tanır; her derlemede özet değişir ve kamera ile
  Erişilebilirlik izinleri düşer. Betik ayrı bir anahtar zinciri dosyasında
  (`~/Library/Application Support/MacGuard/signing/`) kendinden imzalı bir
  sertifika üretir. Giriş anahtar zincirine ve sistem güven ayarlarına dokunmaz.
- **Command Line Tools yedeği:** bazı Command Line Tools sürümleri macOS 27
  SDK'sıyla birlikte SwiftUI'nin makro eklentisini getirmiyor ve derleme `@State`
  hatalarıyla düşüyor. Betik bunu fark edip varsa Xcode'u, yoksa CLT içindeki eski
  SDK'yı kullanıyor.
