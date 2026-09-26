# MacGuard

[![CI](https://github.com/furkan-berkay/mac-guard/actions/workflows/ci.yml/badge.svg)](https://github.com/furkan-berkay/mac-guard/actions/workflows/ci.yml)
[![Lisans: MIT](https://img.shields.io/badge/lisans-MIT-green.svg)](LICENSE.md)
![Platform](https://img.shields.io/badge/macOS-14%2B-lightgrey.svg)

Kafede, kütüphanede ya da ofiste kısa süre başından ayrıldığın MacBook için
hırsızlık alarmı. Korumayı başlatırsın; biri bilgisayarına dokunursa siren çalar,
fotoğrafı çekilir, telefonuna haber gelir. Alarmı yalnızca senin PIN'in ya da
parmak izin susturur.

Swift ve SwiftUI ile yazılmış yerel bir macOS uygulaması. Hiçbir dış bağımlılığı,
hesabı ya da ücretli servisi yok.

<!-- Ekran görüntüleri: docs/images/README.md
![Ana pencere](docs/images/dashboard.png)
![Koruma ekranı](docs/images/lockscreen.png)
-->

## Ne yapar

**Alarmı tetikleyenler:**

- Bilgisayarın yerinden oynatılması (kamerayla algılanır)
- Birinin kameraya fazla yaklaşması
- Şarj kablosunun çıkarılması
- Ekran kapağının kapatılması
- USB aygıt takılması ya da çıkarılması
- Klavyeye, trackpad'e, F tuşlarına ya da güç düğmesine dokunulması
- Harici ekran bağlantısının koparılması
- Tanınmayan bir parmak izinin okutulması

İlk yedisi ayrı ayrı açılıp kapatılır; tanınmayan parmak izi her zaman alarm çalar.

**Alarm çaldığında:**

- Siren, ayarladığın ses seviyesinde çalar; biri sesi kısarsa ya da sessize alırsa
  saniyesinde geri açılır, kulaklık takılıysa dahili hoparlöre geçer
- Sesli uyarı okunur ("Dikkat! Bu bilgisayar korumalıdır…")
- Tüm ekranları bir alarm perdesi kaplar; Dock, ⌘-Tab, ⌘-Q ve Zorla Çık çalışmaz
- Kameradan tek kare çekilip diske kaydedilir
- İstersen telefonuna bildirim ve fotoğraf gider ([ntfy](docs/TELEFON-BILDIRIMI.md), ücretsiz)

**Alarm çalmadan önce:** koruma açıkken ekranda sakin bir "kilit altında" tabelası
durur. Masaya yaklaşan kişi bilgisayara dokunmadan uyarıyı okusun diye.

**Susturmak:** kurulumda seçtiğin yöntemle, PIN ya da Touch ID. Parmak izini seçsen
de PIN her zaman yedek olarak çalışır. Korumayı kapattığında MacGuard da kapanır.

## Kurulum

Gereken: **macOS 14 (Sonoma) veya üstü** ve **Xcode** ya da Xcode Command Line
Tools. İkisi de ücretsiz. Command Line Tools yoksa kur:

```bash
xcode-select --install
```

Sonra projeyi indirip kur:

```bash
git clone https://github.com/furkan-berkay/mac-guard.git
cd mac-guard
./install.sh
```

Betik uygulamayı kaynaktan derler, `/Applications` altına kurar ve açar. İlk
kurulumda bu Mac'e özel, ücretsiz bir imza sertifikası da üretir; bu sayede
verdiğin izinler sonraki güncellemelerde kaybolmaz.

**Güncellemek için:** proje klasöründe `git pull` ve ardından `./install.sh`.

> Şimdilik hazır paket yok; uygulama kaynaktan kuruluyor. Bir güvenlik aracını
> kendi bilgisayarında kaynaktan derlemek zaten en güvenli yol.

## İlk kullanım

1. **Susturma yöntemini seç ve PIN belirle.** Uygulama ilk açılışta sorar: PIN
   mi, parmak izi mi. Parmak izini seçsen de bir PIN belirlersin.
2. **Kamera iznini ver.** Hareket ve yakınlık algılama kamerayı kullanır.
   Görüntü bilgisayarından çıkmaz.
3. **Erişilebilirlik iznini ver (önerilir).** Ayarlar → Alarm → **İzin ver**. Koruma
   açıkken Odak (F6), Spotlight ve medya tuşları çalışmaz, klavyeden yalnızca PIN
   girilir. İzin vermezsen alarm yine çalışır, yalnızca bu tuşlar kilitlenmez.
4. **Kamerayı ayarla.** Ana penceredeki **Kamerayı Ayarla** ile canlı ölçümü aç.
   Bilgisayarı oynattığında iki çubuk da sarı çizgiyi geçmeli; elini kameranın
   önünde salladığında "kareye yayılma" çubuğu çizginin altında kalmalı.
5. **Alarmı dinle.** Ayarlar → Alarm → **Alarmı 5 saniye dinle**. Evde denerken
   ses seviyesini düşür, dışarıda %100'e al.

## Kullanım

- **Korumayı başlat** düğmesine bas ve uzaklaş. Varsayılan 8 saniye sonra devreye
  girer.
- Döndüğünde PIN'ini gir ya da parmağını Touch ID'ye koy (basma; basmak Mac'i
  uyutur). MacGuard korumayı kapatıp kendini de kapatır.
- **Tek tuşla yeniden açmak için** Denetim Merkezi'ne düğme ekle: Kestirmeler
  uygulamasında "Uygulamayı Aç → MacGuard" adımlı bir kestirme oluştur, sonra
  Denetim Merkezi → Denetimleri Düzenle → **Kestirme** denetimini ekleyip bu
  kestirmeyi seç.

Ayarlarda ayrıca uyarı süresi (tam sirenden önce PIN için süre tanıyan kesik bip),
kilit ekranı metni, kapak kapansa bile uyumama ve telefona bildirim var.

## Sınırlar

MacGuard bir **caydırıcı**, kilit değil. Gürültü çıkarır, kanıt toplar ve sana
haber verir; bilgisayarın götürülmesini fiziksel olarak engellemez.

- **Güç düğmesine 10 saniye basılı tutmak** Mac'i kapatır ve alarmı susturur.
  Hiçbir yazılım bunu engelleyemez. Fotoğraf ve bildirim tetik anında gittiği
  için kapatmak onları geri almaz.
- **Kapak kapanınca Mac uyur** ve alarm susar; uyanır uyanmaz kaldığı yerden devam
  eder. Uyumaması için Ayarlar → Alarm → "Kapak kapansa bile uyuma" (yönetici
  şifresi ister).
- **Kapak kapalıyken kamera kör olur;** hareket ve yakınlık algılama çalışmaz,
  diğer tetikler çalışır.
- Kamera kullanılırken yeşil ışık yanar; bu macOS'un donanım göstergesi.
- Apple Silicon ve macOS 26 üzerinde geliştirilip test edildi. Intel Mac'lerde
  derlenir, ama güç düğmesi tetiği çalışmayabilir.

## Acil durum

Alarm çalıyor ve PIN ekranına ulaşamıyorsan (ikinci ekranda kaldıysa, kapak
kapanıp açıldıysa):

- **Ekrana ya da trackpad'e dokun.** Perde öne gelir ve tuş takımı farenin
  bulunduğu ekrana geçer.
- **Parmak izi takıldıysa** Touch ID panelinin altındaki **PIN ile gir**'e bas.
- **Son çare:** güç düğmesini 10 saniye basılı tut. MacGuard yeniden açıldığında
  koruma kapalı başlar.

**PIN'i unuttuysan:** Mac'i yeniden başlat ve PIN dosyasını sil; uygulama
açılışta yeni PIN ister.

```bash
rm ~/Library/Application\ Support/MacGuard/pin.json
```

## Kaldırma

1. Ayarlar → Sistem'de "Oturum açılınca MacGuard'ı başlat" açıksa kapat. "Kapak
   kapansa bile uyuma" için şifresiz kural kurduysan Ayarlar → Alarm'daki
   **Kuralı kaldır** ile kaldır.
2. Uygulamayı ve verilerini sil:

```bash
osascript -e 'quit app "MacGuard"'
```

```bash
rm -rf /Applications/MacGuard.app ~/Library/Application\ Support/MacGuard
```

```bash
defaults delete com.furkanberkay.macguard
```

Son olarak Sistem Ayarları → Gizlilik ve Güvenlik'te Kamera ve Erişilebilirlik
listelerinden MacGuard'ı kaldırabilirsin.

## Daha fazlası

- [Nasıl çalışır](docs/NASIL-CALISIR.md): sensörler, Touch ID, tuş kilidi, imza
- [Telefona bildirim](docs/TELEFON-BILDIRIMI.md): ntfy kurulumu
- [Güvenlik](SECURITY.md): tehdit modeli, veriler nerede, açık bildirimi
- [Katkı](CONTRIBUTING.md): geliştirme ortamı ve kurallar

## Lisans

[MIT](LICENSE.md) © Furkan Berkay Çam. Sorun bulursan
[issue aç](https://github.com/furkan-berkay/mac-guard/issues).
