#!/bin/bash
# Проверка и настройка службы Bluetooth
if ! systemctl is-enabled --quiet bluetooth; then
    echo "Bluetooth служба не настроена на автозапуск. Активируем..."
    sudo systemctl enable bluetooth
    if ! systemctl is-enabled --quiet bluetooth; then
        echo "Не удалось настроить автозапуск Bluetooth службы. Выход."
        exit 1
    fi
fi

if ! systemctl is-active --quiet bluetooth; then
    echo "Bluetooth служба не запущена. Запускаем..."
    sudo systemctl start bluetooth
    if ! systemctl is-active --quiet bluetooth; then
        echo "Не удалось запустить Bluetooth службу. Выход."
        exit 1
    fi
fi

# Проверка и включение Bluetooth
if ! bluetoothctl show | grep -q "Powered: yes"; then
    echo "Bluetooth выключен. Включаем..."
    bluetoothctl power on
    sleep 2
    if ! bluetoothctl show | grep -q "Powered: yes"; then
        echo "Не удалось включить Bluetooth. Выход."
        exit 1
    fi
fi

# Очистка кэша Bluetooth
sudo find /var/lib/bluetooth/ -mindepth 1 -delete

# Включаем Bluetooth (ещё раз, на всякий случай)
bluetoothctl power on

# Перед запуском GUI создаем временный файл с сообщением-заглушкой
echo "wait|Ждите... ищу устройства" > /tmp/bt_devices.txt

# Запускаем сканирование в фоне (результаты перезапишут файл /tmp/bt_devices.txt)
(
    bluetoothctl scan on &
    sleep 10
    # Выключаем сканирование, игнорируя возможные ошибки
    bluetoothctl scan off || true
    # Получаем список устройств и форматируем имена
    devices=$(bluetoothctl devices | grep "Device" | while read -r line; do
        mac=$(echo "$line" | awk '{print $2}')
        # Извлекаем имя, убираем MAC и "Device", оставляем чистое имя
        name=$(echo "$line" | cut -d ' ' -f 3- | sed 's/[^[:alnum:] -]//g' | tr -s ' ')
        if [[ -n "$name" ]]; then
            echo "$mac|BT адаптер: $name"
        fi
    done)
    # Если устройства найдены, перезаписываем файл с результатами
    if [[ -n "$devices" ]]; then
        echo "$devices" > /tmp/bt_devices.txt
    else
        # При отсутствии найденных устройств можно оставить сообщение об ошибке
        echo "error|Не удалось обнаружить устройства" > /tmp/bt_devices.txt
    fi
) &

# Создаем Tcl/Tk скрипт для GUI
cat << 'EOF' > /tmp/bt_gui.tcl
#!/usr/bin/wish

package require Tk

# Глобальная переменная для контроля обновления списка устройств
set listUpdated 0

# Функция применения темы
proc apply_theme {is_dark} {
    if {$is_dark} {
        ttk::style configure TFrame -background "#2b2b2b"
        ttk::style configure TButton -background "#3c3f41" -foreground "#ffffff"
        ttk::style configure TLabel -background "#2b2b2b" -foreground "#ffffff"
        ttk::style configure TCheckbutton -background "#2b2b2b" -foreground "#ffffff"
        ttk::style configure Treeview -background "#2b2b2b" -foreground "#ffffff" -fieldbackground "#2b2b2b"
        ttk::style configure Treeview.Heading -background "#252525" -foreground "#ffffff"
        ttk::style configure TProgressbar -background "#3c3f41" -troughcolor "#2b2b2b"
        ttk::style map TButton -background [list active "#1c2526" pressed "#1c2526"]
        ttk::style map Treeview -background [list selected "#3c3f41"]
        . configure -background "#2b2b2b"
    } else {
        ttk::style configure TFrame -background "#f0f0f0"
        ttk::style configure TButton -background "#d3d3d3" -foreground "#000000"
        ttk::style configure TLabel -background "#f0f0f0" -foreground "#000000"
        ttk::style configure TCheckbutton -background "#f0f0f0" -foreground "#000000"
        ttk::style configure Treeview -background "#ffffff" -foreground "#000000" -fieldbackground "#ffffff"
        ttk::style configure Treeview.Heading -background "#e0e0e0" -foreground "#000000"
        ttk::style configure TProgressbar -background "#add8e6" -troughcolor "#d3d3d3"
        ttk::style map TButton -background [list active "#b0b0b0" pressed "#b0b0b0"]
        ttk::style map Treeview -background [list selected "#add8e6"]
        . configure -background "#f0f0f0"
    }
}

# Настройки окна
wm title . "Bluetooth устройства"
wm geometry . 400x320
ttk::style configure TButton -font {Arial 12}
ttk::style configure TLabel -font {Arial 12}
ttk::style configure TCheckbutton -font {Arial 12}

# Создаем фреймы
ttk::frame .main_frame -padding 10
grid .main_frame -sticky nsew

# Фрейм для настроек
ttk::frame .main_frame.settings_frame
grid .main_frame.settings_frame -sticky w -pady 5

# Галка тёмной темы
set theme_file "$env(HOME)/.bt_gui_theme"
set dark_theme 0
if {[file exists $theme_file]} {
    set f [open $theme_file r]
    set dark_theme [read -nonewline $f]
    close $f
}
ttk::checkbutton .main_frame.settings_frame.dark_theme -text "Тёмная тема" \
    -variable dark_theme -command {
        apply_theme $dark_theme
        set f [open $theme_file w]
        puts $f $dark_theme
        close $f
    }
grid .main_frame.settings_frame.dark_theme -sticky w

# Фрейм для списка устройств
ttk::frame .main_frame.device_frame
grid .main_frame.device_frame -sticky nsew -pady 10
ttk::label .main_frame.device_frame.label -text "Доступные устройства:" -font {Arial 14}
grid .main_frame.device_frame.label -sticky w
ttk::treeview .main_frame.device_frame.list -columns {mac name} -show headings -height 8
.main_frame.device_frame.list heading mac -text "MAC"
.main_frame.device_frame.list heading name -text "Имя устройства"
.main_frame.device_frame.list column mac -width 0 -stretch 0
.main_frame.device_frame.list column name -width 300
grid .main_frame.device_frame.list -sticky nsew -pady 5

# Добавляем начальное сообщение "Ждите... ищу устройства"
.main_frame.device_frame.list insert {} end -values [list "wait" "Ждите... ищу устройства"]

# Фрейм для кнопок действий
ttk::frame .main_frame.action_frame
grid .main_frame.action_frame -sticky nsew -pady 10
ttk::button .main_frame.action_frame.connect -text "Подключить" \
    -command {perform_action "connect"}
ttk::button .main_frame.action_frame.disconnect -text "Отключить" \
    -command {perform_action "disconnect"}
ttk::button .main_frame.action_frame.cancel -text "Отмена" \
    -command {set ::action "cancel"; destroy .}
grid .main_frame.action_frame.connect -row 0 -column 0 -padx 5
grid .main_frame.action_frame.disconnect -row 0 -column 1 -padx 5
grid .main_frame.action_frame.cancel -row 0 -column 2 -padx 5

# Прогресс-бар под кнопками
ttk::progressbar .progress -mode determinate -maximum 100 -value 0
grid .progress -sticky ew -pady 5
grid remove .progress

# Функция получения выбранного элемента
proc get_selection {} {
    set selection [.main_frame.device_frame.list selection]
    if {$selection != ""} {
        return [.main_frame.device_frame.list item $selection -values]
    }
    return ""
}

# Функция анимации прогресс-бара
proc update_progress {value} {
    .progress configure -value $value
    if {$value < 100} {
        after 50 [list update_progress [expr {$value + 5}]]
    } else {
        grid remove .progress
    }
}

# Функция проверки статуса устройства
proc check_device_status {mac} {
    set info [exec bluetoothctl info $mac]
    if {[string match "*Connected: yes*" $info]} {
        return "connected"
    } elseif {[string match "*Connecting: yes*" $info]} {
        return "connecting"
    } else {
        return "disconnected"
    }
}

# Функция выполнения действия
proc perform_action {action} {
    set selected [get_selection]
    if {$selected == ""} {
        tk_messageBox -message "Пожалуйста, выберите устройство!" -type ok -icon warning
        return
    }
    set mac [lindex $selected 0]
    if {$action == "connect"} {
        set status [check_device_status $mac]
        if {$status == "connected"} {
            tk_messageBox -message "Устройство уже подключено!" -type ok -icon info
            return
        } elseif {$status == "connecting"} {
            tk_messageBox -message "Устройство в процессе подключения, подождите!" -type ok -icon warning
            return
        }
        grid .progress -sticky ew
        update_progress 0
        if {[catch {exec bluetoothctl connect $mac} err]} {
            tk_messageBox -message "Ошибка подключения: $err" -type ok -icon error
            grid remove .progress
            return
        }
        after 1000
        catch {exec notify-send -t 10000 "Наушники подключены"}
    } elseif {$action == "disconnect"} {
        set status [check_device_status $mac]
        if {$status == "disconnected"} {
            tk_messageBox -message "Устройство уже отключено!" -type ok -icon info
            return
        }
        exec bluetoothctl disconnect $mac
        exec notify-send -t 10000 "Наушники отключены"
    }
}

# Функция опроса файла с устройствами и обновления списка
proc poll_devices {} {
    global listUpdated
    if {[file exists "/tmp/bt_devices.txt"]} {
        set content [exec cat /tmp/bt_devices.txt]
        set lines [split $content "\n"]
        if {[lindex $lines 0] eq "error|Не удалось обнаружить устройства"} {
            tk_messageBox -message "Ошибка: не обнаружено ни одного устройства" -type ok -icon error
            set listUpdated 1
        } elseif {[lindex $lines 0] ne "wait|Ждите... ищу устройства"} {
            if {!$listUpdated} {
                # Обновляем список только один раз, чтобы не сбрасывать выделение
                set items [.main_frame.device_frame.list children {}]
                foreach item $items {
                    .main_frame.device_frame.list delete $item
                }
                foreach line $lines {
                    if {$line != ""} {
                        set parts [split $line "|"]
                        set mac [lindex $parts 0]
                        set name [lindex $parts 1]
                        .main_frame.device_frame.list insert {} end -values [list $mac $name]
                    }
                }
                set listUpdated 1
            }
        }
    }
    after 2000 poll_devices
}

# Запуск опроса файла с устройствами
poll_devices

# Центрирование окна
set screen_width [winfo screenwidth .]
set screen_height [winfo screenheight .]
set window_width 450
set window_height 400
set x [expr {($screen_width - $window_width) / 2}]
set y [expr {($screen_height - $window_height) / 2}]
wm geometry . "${window_width}x${window_height}+${x}+${y}"

# Применяем тему при старте
apply_theme $dark_theme

# Переменные для результата
set ::action ""

# Обработчик двойного клика
bind .main_frame.device_frame.list <Double-1> {
    perform_action "connect"
}

# Обработчик закрытия окна
wm protocol . WM_DELETE_WINDOW {set ::action "cancel"; destroy .}

vwait ::action
EOF

# Делаем tcl скрипт исполняемым
chmod +x /tmp/bt_gui.tcl

# Запускаем GUI
wish /tmp/bt_gui.tcl

# Очистка временных файлов
rm /tmp/bt_gui.tcl /tmp/bt_devices.txt