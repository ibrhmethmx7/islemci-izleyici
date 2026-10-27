# İşlemci İzleyici

Mac'i o anda neyin yorduğunu gösteren küçük bir menü çubuğu uygulaması (SwiftUI `MenuBarExtra`).

- Menü çubuğunda toplam CPU; ana diskte 50 GB'tan az yer kalınca boş alan da yazılır.
- Pencerede: toplam CPU, bellek baskısı ve swap, disklerin boş alanı, en çok CPU ya da bellek kullanan 10 süreç (kısa Türkçe açıklamayla).
- Kendi süreçleriniz için: önceliği düşür (nice +10) ve onaylı sonlandır (SIGTERM). Sistem süreçlerinde, WindowServer ve loginwindow'da düğmeler kapalıdır.
- Her 2 saniyede yenilenir. Pencere kapalıyken süreç listesi hiç ölçülmez.

## Derleme

Xcode projesi gerekmez, yalnızca Xcode'un komut satırı araçları (Swift 5.9+) yeter. macOS 14 ve üstü.

```bash
./build-app.sh
open build/IslemciIzleyici.app
```

Çıkmak için pencerenin altındaki **Çık** düğmesi.

### Açılışta başlatma

Uygulamayı kalıcı bir yere kurup pencerenin altındaki **Açılışta başlat** kutusunu işaretleyin:

```bash
./build-app.sh --install          # ~/Applications/IslemciIzleyici.app
open ~/Applications/IslemciIzleyici.app
```

Komut satırından da açılıp kapatılabilir:

```bash
~/Applications/IslemciIzleyici.app/Contents/MacOS/IslemciIzleyici --login-item on   # off | status
```

Sistem Ayarları > Genel > Giriş Öğeleri'nde de görünür, oradan da kapatılabilir.

Ölçümleri terminalde görmek için (top / vm_stat / df ile karşılaştırmaya yarar):

```bash
build/IslemciIzleyici.app/Contents/MacOS/IslemciIzleyici --dump 3
```

## Ölçümler nereden geliyor

| Değer | Kaynak |
|---|---|
| Toplam CPU | Mach `host_statistics(HOST_CPU_LOAD_INFO)`, iki ölçüm arasındaki fark |
| Süreç CPU | `/bin/ps` (setuid, sistem süreçlerini de görür); birikmiş CPU süresinin 2 sn'lik farkı. %100 = 1 çekirdek |
| kernel_task | `ps` göstermez, yetkisiz okunamaz. Toplam meşguliyetten görünen süreçler çıkarılarak **tahmin** edilir; `top` ile ±15 puan içinde tuttu |
| Süreç belleği | Kendi süreçlerinizde `proc_pid_rusage` → phys_footprint (Etkinlik Monitörü'ndeki "Bellek"). Sistem süreçlerinde yalnızca RSS okunabilir, önlerinde `≈` vardır |
| Bellek baskısı | `kern.memorystatus_vm_pressure_level` (macOS'un kendi değeri) |
| Swap | `vm.swapusage`; diske yazma/okuma hızı `vm_statistics64` farkından |
| Disk | `volumeAvailableCapacityForImportantUsage` (Finder'ın "kullanılabilir"i) ve `volumeAvailableCapacity` (df'teki boş alan) |

## Lisans

MIT. Ayrıntılar için [LICENSE](LICENSE) dosyasına bakın.
