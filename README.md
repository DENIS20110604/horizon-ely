# Патчи Horizon: оффлайн и Ely.by

Патчи к [horizon-rust/horizon](https://github.com/horizon-rust/horizon): снимают проверку
владения Minecraft и добавляют вход через [Ely.by](https://ely.by) (или любой
authlib/Yggdrasil-сервер), чтобы играть без лицензии и на ely-серверах.

Сам лаунчер не форкается целиком: здесь только патчи, скрипты и CI. Патчи применяются к
исходникам апстрима, зафиксированным в [`upstream.txt`](upstream.txt), и собираются в обычный
`horizon-launcher`. Это важно, потому что апстрим выпускает по несколько обновлений в день:
обновление — это поднять пин, перебазировать патчи по конфликтам, выпустить новый тег.

## Что даёт

- **Игра без лицензии.** Оффлайн-имена (сингл, LAN, сервера с `online-mode=false`) и
  `Download and prepare` — скачивание файлов Minecraft 26.3 с Mojang по публичным URL, без
  аккаунта. Гейт «нужен аккаунт, который владеет игрой» снят в лаунчере полностью.
- **Ely.by и другие authlib-серверы.** Вход по нику/почте и паролю (и коду 2FA) прямо в
  настройках лаунчера. Пароль используется один раз и не сохраняется: в системной связке
  ключей лежат только токены. Аккаунт играет на ely-серверах со своим ником; сессию для игры
  лаунчер отдаёт через `--session-file`, а join/профиль/скины идут через локальный прокси
  (`HORIZON_API_DISCOVERY`), потому что authlib-injector в нативном клиенте не работает.
- **Microsoft-вход остаётся.** Для лицензионных аккаунтов ничего не меняется.
- **Самопродление лаунчера выключено**: иначе официальный апдейт заменил бы патченный бинарь.
  Обновления самой игры (`Versions`) работают как раньше.

Чего нет: скины Ely.by в игре пока не рисуются — клиент принимает текстуры только с
`textures.minecraft.net` (это отдельный патч игрового клиента, фаза 2).

## Установка

Готовый бинарь — в [Releases](../../releases), либо собери сам:

```sh
./scripts/build.sh          # клон апстрима по пину + патчи + cargo build --release
./scripts/install.sh        # поставить в ~/.local/bin (или --replace PATH)
```

`install.sh` умеет заменять уже установленный лаунчер, сохраняя бэкап:

```sh
./scripts/install.sh --replace ~/Downloads/horizon-launcher-linux-x86_64/horizon-launcher
./scripts/install.sh --uninstall     # вернуть бэкап
```

Локальная сборка требует dev-пакеты, которые линкует GPUI (Arch: `libxkbcommon`,
`wayland`, `libx11`, `fontconfig`, `vulkan-icd-loader`, `alsa-lib`; Debian/Ubuntu:
`libxkbcommon-x11-dev libwayland-dev libx11-xcb-dev libfontconfig-dev libvulkan-dev
libasound2-dev`). Сборка идёт в `.work/target` — не в `/tmp`, там часто tmpfs.

## Как играть

**Оффлайн.** Settings → Account → новое имя (3–16 букв, цифр, `_`), «Добавить», затем в
верхней панели выбрать его. Или из терминала:

```sh
horizon-launcher account offline Den4ik
horizon-launcher prepare --download      # если файлов 26.3 ещё нет
horizon-launcher play
```

Можно указать свою установку Minecraft (Settings → Minecraft folder). Подойдёт папка
официального лаунчера или корень Prism/MultiMC/PolyMC (не папка инстанса).

**Ely.by.** Settings → Account → карточка Ely.by: сервер (по умолчанию
`https://authserver.ely.by`), ник или e-mail, пароль, код 2FA при включённом. После входа
аккаунт появляется в списке и выбирается как обычный. Из терминала:

```sh
horizon-launcher account ely login --user you@example.com
# пароль читается из stdin, в историю команд не попадает
horizon-launcher account ely sign-out <ник>
```

## Как обновляться

1. Смотрим новый тег апстрима: `git ls-remote --tags https://github.com/horizon-rust/horizon.git 'launcher@*'`.
2. В `upstream.txt` — новый тег и его коммит, в `version.txt` — `<версия>-elyN`.
3. В `.work/dev` (клон апстрима на ветке `ely`) — `git rebase`/`git merge`, чиним конфликты.
4. `git format-patch <тег> -o patches/` и коммит.
5. `git push && git tag ely-v... && git push --tags` — CI соберёт и выложит релиз.

## Что внутри

Один патч-файл `patches/0001-offline-and-elyby.patch` (так серия ребейзится и чинится как одно
целое; апстрим двигается каждый день):

| Часть | Что делает |
|---|---|
| оффлайн | снимает проверку владения: `account::launch`, оффлайн-имена, скачивание с Mojang, экран-гейт, подсказки CLI, самопродление лаунчера |
| ely-аккаунты | `launcher/src/ely.rs`: `/auth/authenticate`, `/auth/refresh`, `/auth/validate`, поле `authlib` у аккаунта, карточка входа в настройках, `account ely login/sign-out` |
| ely-сессия | `launcher/src/ely_proxy.rs`: discovery-документ на 127.0.0.1 и проброс join/verify/profile к authlib-серверу; `HORIZON_API_DISCOVERY` при спавне игры |

## Права и оговорки

Патчи — MIT, как и сам Horizon. В репозитории нет и не будет файлов Mojang: ни jar, ни
assets, ни подготовленных ресурсов. Всё скачивается с CDN Mojang на машину игрока теми же
публичными ссылками и проверяется по sha1. Это мод для личного использования; Minecraft
EULA требует лицензию для игры, и решение играть иначе — на игроке.
