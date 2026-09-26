# Telefona bildirim

Alarm çaldığında telefonuna anlık bildirim ve alarm anında çekilen fotoğraf
gelir. Bunun için [ntfy](https://ntfy.sh) kullanılıyor: ücretsiz ve açık kaynak.
Hesap, API anahtarı ya da kayıt gerekmiyor.

## Kurulum

1. **Telefonuna ntfy'yi kur.**
   [iOS](https://apps.apple.com/app/ntfy/id1625396347) ·
   [Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy)
2. **MacGuard'da konu adı üret.** Ayarlar → Telefona bildirim →
   **Alarm anında telefonuma bildirim gönder**'i aç → **Rastgele konu üret**.
3. **Adresi kontrol et.** Konu alanının altında yeşil renkte, bildirimin gideceği
   adres yazar (`https://ntfy.sh/macguard-…`). Telefonda tam olarak bu adrese
   abone olacaksın.
4. **Telefonda abone ol.** ntfy'de sağ üstteki **+** → konu adını yaz (adresin son
   parçası, `https://ntfy.sh/` olmadan) → **Subscribe**.
5. **Dene.** MacGuard'da **Test bildirimi gönder**. Yeşil tik görürsen bildirim
   telefonuna ulaşmıştır; kırmızı uyarı çıkarsa nedeni orada yazar.

## Konu adı bir paroladır

ntfy'de konular herkese açıktır. **Konu adını bilen herkes o konuya düşen her
şeyi görebilir**, alarm anında çekilen fotoğraf dahil: yüzün, evin, oturduğun
kafe.

`macguard`, `alarm`, `test` gibi adlar saniyeler içinde tahmin edilir.
Uygulamanın ürettiği ad 20 rastgele karakterden oluşur (~103 bit); onu kullan.
Bu yüzden uygulama boş gelir ve depoda hazır bir konu adı yoktur.

Konu adında yalnızca İngiliz alfabesi harfleri, rakam, `_` ve `-` kullanılabilir.

## Sık yapılan hata

"Sunucu" alanına tam adresi (`https://ntfy.sh/benim-konum`) yapıştırmak. Doğrusu:

| Alan | Ne yazılır |
|---|---|
| Sunucu | `https://ntfy.sh` |
| Konu adı | yalnızca konu, örn. `macguard-xxxxxxxxxxxxxxxxxxxx` |

MacGuard sunucu alanına yapıştırılan konuyu kendisi ayıklıyor. Yine de emin olmak
için yeşil satıra bak; orada ne yazıyorsa bildirim oraya gider.

## Kendi sunucun

ntfy'yi kendi sunucunda da çalıştırabilirsin. Sunucu alanına kendi adresini yaz
(`https://ntfy.evim.net`, port gerekiyorsa `https://ntfy.evim.net:8080`); gerisi
aynı.

## Ne gönderiliyor

Yalnızca tetik mesajı (örn. "Şarj kablosu çıkarıldı"), saat ve açıksa tek bir
fotoğraf. Kullanıcı adı, makine adı ya da konum gönderilmez. Bildirim gitmezse
olay kaydına "Telefona bildirim GÖNDERİLEMEDİ" ve nedeni düşer; telefonun haber
vereceğini sanıp güvenmeyesin diye.
