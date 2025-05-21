#!/bin/bash

# Usage
# --------
# curl -LO georg9741.github.io/archlinux/install.sh
# chmod +x install.sh
# ./install.sh

# Notes
# --------
# system first, then the rest, like create user
# create user (don't allow empty var)
# disk selection
# re-enter password (no empty var)
# root password
# create partitions
# format partitions
# setup lvm
# format lvm partitions
# mount filesystems
# generate mirrorlist
# install base packages
# generate fstab
# chroot, ...
# some result panel
# unmount/reboot
# start script (only if all options correctly filled)

# Exit on error
set -uo pipefail

# Variables
backtitle="archinstall"
menuoption1="Create User"
menuoption2="Option 2"
menuoption3="Option 3"
menuoption4="Option 4"
menuoption5="Start Script"
dialog="dialog --clear --backtitle ${backtitle} --cancel-button Exit"

# Functions
pressanykey(){
  echo; read -n1 -p "Press any key to continue."
}
main_menu(){
  if [ "${1:-}" = "" ]; then
    nextitem="."
  else
    nextitem=${1}
  fi
  options=()
  options+=("${menuoption1}" "${username:-}")
  options+=("${menuoption2}" "")
  options+=("${menuoption3}" "")
  options+=("${menuoption4}" "")
  options+=("" "")
  options+=("${menuoption5}" "")
  sel=$(${dialog} --title "Main Menu" --default-item "${nextitem}" --menu "" 7 0 0 "${options[@]}" --output-fd 1)
  if [ $? = 0 ]; then
    case ${sel} in
      "${menuoption1}")
        create_user
        main_menu "${menuoption2}"
        ;;
      "${menuoption2}")
        main_menu "${menuoption3}"
        ;;
      "${menuoption3}")
        main_menu "${menuoption4}"
        ;;
      "${menuoption4}")
        main_menu "${menuoption5}"
        ;;
      "${menuoption5}")
        continue
        ;;
      "")
        main_menu "${menuoption5}"
        ;;
    esac
  fi
}
create_user(){
  username=$(${dialog} --title "${menuoption1}" --inputbox "Enter your username" 0 0 --output-fd 1)
  if [ $? = 0 ]; then
    echo "Username is ${username}"
    pressanykey
  fi
  password=$(${dialog} --title "${menuoption1}" --passwordbox "Enter your password" 0 0 --output-fd 1)
  if [ $? = 0 ]; then
    echo "Password is ${password}"
    pressanykey
  fi
}
continue(){
  pressanykey
}

# Dialog Config
create_dialogrc(){
  cat << EOF > $1
use_shadow = OFF
screen_color = (CYAN,BLACK,OFF)
shadow_color = (BLACK,BLACK,ON)
dialog_color = (WHITE,BLACK,OFF)
title_color = (CYAN,BLACK,ON)
border_color = (WHITE,BLACK,OFF)
border2_color = border_color
button_active_color = (WHITE,MAGENTA,ON)
button_inactive_color = dialog_color
button_key_active_color = (WHITE,MAGENTA,OFF)
button_key_inactive_color = (BLUE,BLACK,ON)
button_label_active_color = button_active_color
button_label_inactive_color = dialog_color
inputbox_color = dialog_color
inputbox_border_color = dialog_color
inputbox_border2_color = inputbox_border_color
searchbox_color = dialog_color
searchbox_title_color = title_color
searchbox_border_color = border_color
searchbox_border2_color = searchbox_border_color
position_indicator_color = title_color
menubox_color = dialog_color
menubox_border_color = border_color
menubox_border2_color = menubox_border_color
item_color = dialog_color
item_selected_color = dialog_color
tag_color = title_color
tag_selected_color = button_label_active_color
tag_key_color = button_key_inactive_color
tag_key_selected_color = button_active_color
check_color = dialog_color
check_selected_color = button_active_color
uarrow_color = (GREEN,WHITE,ON)
darrow_color = uarrow_color
itemhelp_color = (WHITE,BLACK,OFF)
form_active_text_color = button_active_color
form_text_color = (WHITE,CYAN,ON)
form_item_readonly_color = (CYAN,WHITE,ON)
gauge_color = title_color
EOF
  export DIALOGRC="dialog.archinstall"
}

# Start Script
create_dialogrc dialog.archinstall
main_menu
rm dialog.archinstall
