# Güvenlik

## Açık bildirimi

MacGuard bir güvenlik aracı. Bir açık bulursan **herkese açık issue açma**;
GitHub üzerinden özel olarak bildir:

- [Report a vulnerability](https://github.com/furkan-berkay/mac-guard/security/advisories/new)

Düzeltme yayımlanana kadar ayrıntıyı paylaşmamanı rica ederim.

## Tehdit modeli

**Koruduğu senaryo:** kafede, kütüphanede, ofiste kısa süre başından ayrıldığın
bilgisayar. Fırsatçı birinin bilgisayarı alıp götürmesini ya da kurcalamasını
gürültüyle caydırır, kanıt toplar ve sana haber verir.

**Korumadığı senaryo:** kararlı ve hazırlıklı bir hırsız. Güç düğmesine 10 saniye
basılı tutmak Mac'i kapatır ve alarmı susturur; hiçbir yazılım bunu engelleyemez.
MacGuard bir caydırıcıdır, kilit değil.

**Güvendiği şeyler:** macOS oturumunun kendisi. Oturumuna erişimi olan biri
MacGuard'ın dosyalarını okuyabilir ve ayarlarını değiştirebilir; bu, MacGuard'ın
koruma alanının dışında.

## Veriler nerede

| Ne | Nerede | İzin |
|---|---|---|
| PIN özeti | `~/Library/Application Support/MacGuard/pin.json` | `0600` |
| Alarm fotoğrafları | `~/Library/Application Support/MacGuard/Snapshots/` | `0700` / `0600` |
| Olay kaydı | `~/Library/Application Support/MacGuard/events.json` | `0600` |
| Yerel imza kimliği | `~/Library/Application Support/MacGuard/signing/` | `0700` |
| Ayarlar | `UserDefaults` (`com.furkanberkay.macguard`) | — |

Hiçbiri bilgisayardan çıkmaz. **Tek istisna:** telefon bildirimini sen açarsan
tetik mesajı, saat ve alarm anındaki tek kare ntfy sunucusuna gönderilir.
Kullanıcı adı, makine adı ya da konum gönderilmez.

## İzinler

| İzin | Neden | Zorunlu mu |
|---|---|---|
| Kamera | Hareket, yakınlık, alarm fotoğrafı | Hayır; yoksa bu üçü çalışmaz |
| Erişilebilirlik | Koruma açıkken sistem tuşlarını kilitlemek | Hayır; yoksa yalnızca tuş kilidi çalışmaz |
| Yönetici şifresi | "Kapak kapansa bile uyuma" için `pmset` | Hayır; seçenek kapalıysa hiç istenmez |

Erişilebilirlik izniyle kurulan olay dinleyicisi yalnızca koruma açıkken
çalışır, tuşları kaydetmez ve hiçbir yere göndermez; PIN tuşları dışındakileri
yalnızca durdurur.

İsteğe bağlı sudoers kuralı (`/etc/sudoers.d/macguard`) yalnızca
`pmset -a disablesleep 1` ve `pmset -a disablesleep 0` komutlarını kapsar.
Kurmazsan MacGuard hiçbir root yetkisi kullanmaz.

## Bilinen sınırlar

- **Kısa PIN kaba kuvvetle kırılabilir.** PIN tuzlanmış, 50.000 turlu SHA-256
  özeti olarak saklanıyor; ama 4 haneli bir PIN'in arama uzayı küçük. Dosyayı
  okuyabilen biri zaten oturumuna erişmiş demektir. Uzun bir PIN seç.
- **Kayıtlı her parmak izi alarmı kapatır.** Mac'e başka birinin parmak izi de
  kayıtlıysa o kişi de susturabilir.
- **ntfy konu adı bir paroladır.** Konuyu bilen herkes o konuya düşen fotoğrafları
  görebilir. Uygulamanın ürettiği rastgele adı kullan (~103 bit).
- **Kum havuzu ve notarizasyon yok.** Uygulama kendi bilgisayarında kaynaktan
  derlenip bu Mac'e özel, kendinden imzalı bir sertifikayla imzalanır.
  Başkasının derlediği bir MacGuard ikilisini çalıştırmadan önce kaynağa bak.
- **Güç düğmesi tetiği macOS'un iç bir kayıt adına dayanıyor.** Apple bu adı
  değiştirirse düğme basışı sessizce algılanmaz hâle gelir.
