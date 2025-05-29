#!/bin/bash
cd /home/live/.local/bin/tkbluman
notify-send -t 10000 "Доставка Блютуз устройства в пути..."
notify-send -t 11500 "Оно близко, где-то на радаре :)"
nohup ./tkbt_man-06.sh &
