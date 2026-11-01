# win11-arm64-image-builder

Полностью автоматическая сборка **ISO Win11 ARM64 + самоподписанные драйверы gunyah/virtio** в **qcow2, который сразу загружается в DroidVM (Gunyah/crosvm)**.

Что получается по умолчанию: локальная учётная запись `USER` (автовход, пароль без срока действия), включены testsigning + nointegritychecks, драйверы установлены, SSH/RDP включены, система очищена от лишнего (debloat, в том числе отключён Windows Update — вернуть его можно через `enable_windows_update.bat` на рабочем столе), сон и отключение экрана выключены, Reserved Storage отключено, IPv6 SLAAC использует EUI-64 (адрес можно вычислить по MAC).

## Сборка в GitHub Actions (этот форк)

Workflow `.github/workflows/build-win11-gunyah.yml` собирает образ по маршруту A на `windows-latest`:

1. Освобождает место на диске (нужно 45+ ГБ).
2. Ставит QEMU (winget) и aria2 (choco).
3. Скачивает драйверы и сертификат в `windows/files/` (`ZIP/drivers`, `ZIP/DroidVM_Test.cer`).
4. Получает ссылку на ISO Win11 24H2 ARM64 через Fido и качает его `aria2c -x16 -s16`. Можно передать свою ссылку в параметре `iso_url`.
5. Запускает `windows_build.ps1` с `QEMU_IMG_INSTALL=1`, `COMPRESS=1`, `OUT_VMPKG=1`.
6. Выкладывает `.vmpkg` и `.qcow2` как артефакты, а также GitHub Release с частями `win11-droidvm.vmpkg.7z.001…` по 1900 МБ. Прямые ссылки появляются в сводке запуска.

Запуск: **Actions → Build Win11 ARM64 (Gunyah / DroidVM) → Run workflow**.
Сначала включите Actions: **Settings → Actions → General → Allow all actions**, а в **Workflow permissions** выберите **Read and write**.

На телефоне скачайте все части `.7z.*` и распакуйте `.001` (ZArchiver / 7-Zip) — получится `win11-droidvm.vmpkg`, который импортируется в DroidVM.

> В этом форке `vms.json` по умолчанию использует **3072 МБ RAM** (при 4096 МБ на ядрах Gunyah со страницами 4K бывает чёрный экран) и **256 МБ swiotlb**.

## Два маршрута (выбирается один, результат одинаковый)

| Маршрут | Среда | Точка входа | Как работает | Время |
|---|---|---|---|---|
| **A. Windows** | x64 Windows (администратор) | `windows_build.ps1` | DISM офлайн применяет образ + офлайн внедряет драйверы + bcdboot/bcdedit; Setup и VM не запускаются | ~5–10 мин |
| **B. macOS** | Mac на Apple Silicon | `macos_build.sh` | qemu HVF запускает Setup, ставит систему и драйверы, затем `sysprep /generalize` возвращает её в состояние для развёртывания | ~30 мин |

Оба маршрута делают образ в состоянии **OOBE-pending** (первоначальная настройка не пройдена). Настоящая «первая загрузка» происходит на **целевой машине Gunyah**: она заново определяет оборудование и ставит драйверы. Главное — `rdmapool` привязывается к `ACPI\RDMA0000`, который есть только на целевой машине (restricted-DMA pool защищённой VM). Поэтому DMA у `viostor` идёт через bounce-буфер и не попадает в lent-память. Именно это позволяет драйверам правильно загрузиться при старте.

> **Функционально результат одинаковый, размер разный:** маршрут B (macOS) — около **7 ГБ**, маршрут A (Windows) — около **14 ГБ**. Причина в том, как освобождается место: macOS делает TRIM прямо во время работы qemu (`discard=unmap`) и debloat онлайн. С `COMPRESS=1` (кластеры qcow2 сжимаются **zstd**) маршрут A даёт **4,7 ГБ**. Новый crosvm читает zstd-кластеры напрямую, распаковывать после импорта не нужно (zlib `-c` crosvm не читает, поэтому сборщик его больше не делает).

## Использование

В обоих случаях: поменяйте переменные в начале скрипта входа и запустите.

```powershell
# Маршрут A (Windows, права администратора запрашиваются автоматически)
powershell -ExecutionPolicy Bypass -File windows_build.ps1
```
```bash
# Маршрут B (macOS)
bash macos_build.sh
```

В этом форке переменные в `windows_build.ps1` — только значения по умолчанию: если переменная окружения уже задана, используется она.

## Настройки (переменные в скрипте входа)

Файловые переменные (`SRC_ISO` / `DRIVERS_DIR` / `OPENSSH_SRC`) принимают **URL** (файл скачивается в `files/`) или **локальный путь**; zip распаковывается автоматически.

| Переменная | Описание |
|---|---|
| `SRC_ISO` | **Обязательно.** ISO Win11 ARM64 (URL или путь) |
| `DRIVERS_DIR` | Источник драйверов: zip из GitHub release / локальный zip / папка. По умолчанию — release `dev` из `gunyah-guest-drivers-windows` |
| `DRIVER_INSTALL` | Ставить только эти подпапки драйверов (по умолчанию `NetKVM rdmapool pvmpower vioinput viostor vioscsi`; `viostor` для загрузочного диска обязателен) |
| `DRIVER_CERT` | Сертификат подписи (пусто — извлекается из `.cat` драйвера) |
| `IMAGE_INDEX` | Индекс редакции в install.wim (пусто — показать список и спросить) |
| `USERNAME` / `PASSWORD` | Локальный администратор. На macOS — `USERNAME` / `PASSWORD`, на Windows — `$env:DVM_USERNAME` / `$env:DVM_PASSWORD` |
| `SSH_PUBKEY` | Публичный ключ SSH (пусто — вход только по паролю) |
| `OUT_QCOW` | Путь к выходному qcow2 |
| `OUT_VMPKG` | Путь к выходному `.vmpkg` (`1` — имя по умолчанию) |
| `COMPRESS` | `1` — сжимать кластеры qcow2 zstd |
| `EMS_SAC_SOURCE` | Откуда брать FoD для интерактивного `SAC>`: **`skip`** (по умолчанию, только boot-EMS) / **`online`** (маршрут A ставит при **первой загрузке на целевой машине** из сети; маршрут B ставит **во время сборки** внутри qemu и вшивает в образ) / **`E:\`** (точка монтирования или папка ISO с ARM64 FoD, **только маршрут A**: офлайн `dism /Add-Capability`, без сети) |

## EMS / SAC (последовательная консоль, `SAC>`)

Позволяет сразу после загрузки получить **Emergency Management Services**: интерактивную консоль Windows `SAC>` на порту SBSA в приложении. **BCD EMS всегда вшивается** (`emssettings BIOS` + `ems on` + `bootems on`), поэтому текст загрузки в порт выводится всегда. Различается только **интерактивный `SAC>`** (FoD `Windows.Desktop.EMS-SAC.Tools`, которого нет в LTSC/Pro ARM64):

| | Маршрут A (Windows) | Маршрут B (macOS) |
|---|---|---|
| **Офлайн FoD** (без сети, рекомендуется) | `EMS_SAC_SOURCE=E:\` → офлайн DISM | Нет (хост не Windows; путь вызовет ошибку) |
| **Онлайн FoD** | `EMS_SAC_SOURCE=online` → ставится при первой загрузке на целевой машине + одна перезагрузка | `EMS_SAC_SOURCE=online` → скачивается во время сборки, на целевой машине сеть не нужна |
| `skip` (по умолчанию) | Только boot-EMS | То же |

Без сети ничего **не зависает**: скрипт пропускает установку, boot-EMS работает, просто не будет интерактивного `SAC>`.

### В VM нужен порт SBSA, назначенный консолью гостя

SAC работает через ACPI SPCR, который edk2 строит по узлу FDT SBSA UART от crosvm; узел должен быть назначен консолью гостя.

- **Из коробки — vmpkg**: сборщик выдаёт `.vmpkg` с конфигом (`vms.json`), где `serial_ports` уже содержит `{"hardware":"sbsa","num":1,"backend":"app_console","console":true}` (COM2–4 — sink).
- **Голый qcow2** — два шага в приложении: **Периферия → Последовательные порты → Добавить SBSA**, затем отметить **«Консоль гостя (SPCR)»**.

Флаг crosvm, который выдаёт daemon:
```
--serial type=file,hardware=sbsa,num=1,earlycon,console,path=/proc/self/fd/N,input=/proc/self/fd/M
```

Нужен **новый crosvm** с SBSA UART `@0x6000` и PmReset `@0x5000` (последний даёт выключение и перезагрузку Windows-on-ARM без PSCI).

## Прямой вывод vmpkg

Если задан `OUT_VMPKG`, вместе с qcow2 создаётся **`.vmpkg` для прямого импорта** с вшитыми настройками VM (RAM / swiotlb / консоль SBSA / boot).

- **Источник настроек — `vms.json`** в корне репозитория. В нём меняются RAM / CPU / swiotlb / порты и т. д.; упаковщик сам добавит qcow2 как диск.
- **Упаковщики** (формат байт-в-байт совпадает с экспортом приложения):
  - Windows: **`pack-vmpkg.ps1`** — чистый PowerShell + встроенный `tar.exe`, Python не нужен. `-Compression auto`: zstd в несколько потоков, если `tar.exe` поддерживает libzstd (Win11), иначе gzip.
    ```powershell
    .\pack-vmpkg.ps1 -Qcow2 out.qcow2 -Config vms.json -Out win11.vmpkg   # [-Compression auto|zstd|gzip|none] [-Threads N]
    ```
  - macOS: **`pack-vmpkg.py`** (Python 3, только стандартная библиотека), многопоточный gzip.
    ```bash
    python3 pack-vmpkg.py --qcow2 out.qcow2 --config vms.json --out win11.vmpkg   # [--threads N]
    ```
  - Переменные: `VMPKG_COMPRESSION` (Windows — `auto`, macOS — `gzip`; при `COMPRESS=1` по умолчанию `none`), `VMPKG_THREADS` (0 — все ядра).
- **Сеть**: каждая NIC в `networks[]` имеет `pkg_network_ref` и может содержать `pkg_network` (NetworkConfig, schema 2). При импорте режим «existing» ищет сеть по имени (шаблон указывает на `br-wifi`), а «auto» создаёт новую.
- **Файл ≥ 8 ГиБ**: GNU tar пишет размер в base-256, `TarReader` приложения читает его как 0, и диск после импорта получается 0 Б. Упаковщик пишет 12-значное восьмеричное число; в PowerShell-версии это возможно только при `-Compression none`.
- **Как сочетать сжатие qcow2 и vmpkg** (замеры на маршруте A):

  | | qcow2 | vmpkg | qcow2 на устройстве |
  |---|---|---|---|
  | `COMPRESS` выкл. + vmpkg zstd | 9,78 ГиБ | **4,18 ГиБ** | 9,78 ГиБ, без накладных расходов |
  | `COMPRESS=1` + vmpkg none | 4,70 ГиБ | 4,70 ГиБ | 4,70 ГиБ; чтение с распаковкой, запись делает несжатые кластеры, файл растёт |
  | `COMPRESS=1` + vmpkg zstd | 4,70 ГиБ | 4,62 ГиБ | То же |

  Чтобы **скачивать меньше** — не сжимайте qcow2 (vmpkg zstd). Чтобы **экономить место на устройстве** — `COMPRESS=1`.

> Совместимость: `serial_ports` — новое поле. Старые версии приложения его игнорируют и добавляют четыре COM-порта (просто без SBSA).

## Требования

- **macOS:** `brew install qemu wimlib xorriso colima docker`; около **50 ГБ** свободного места (`macos/files`). Патч BCD для testsigning делается hivex внутри контейнера Colima.
- **Windows:** x64 Windows (администратор), встроенные `dism` / `bcdboot` / `diskpart`, `qemu-img` (QEMU for Windows; если его нет, сборщик предложит `winget install SoftwareFreedomConservancy.QEMU`, с `QEMU_IMG_INSTALL=1` — без вопроса. Пакет `cloudbase.qemu-img` версии 2.3.0 zstd не умеет — не используйте).

## Структура

```
.github/workflows/  сборка в GitHub Actions (маршрут A)
macos_build.sh      вход маршрута B
windows_build.ps1   вход маршрута A
macos/              реализация маршрута B
windows/            реализация маршрута A: build.ps1 + unattend (см. windows/README.md)
pack-vmpkg.py       упаковщик qcow2 + vms.json → .vmpkg (macOS)
pack-vmpkg.ps1      то же для Windows
vms.json            шаблон настроек VM (RAM/swiotlb/порты/boot)
files/              кэш промежуточных файлов (в .gitignore)
```
