#!/usr/bin/env bash
# Adds contacts to the emulator's address book, or removes them by name.
#   scripts/seed-contacts.sh <device> add "<name>" "<number>" ["<name>" "<number>" ...]
#   scripts/seed-contacts.sh <device> remove "<name>" ...
set -euo pipefail
DEVICE=$1 ACTION=$2
shift 2
C=content://com.android.contacts
a() { adb -s "$DEVICE" shell "$@"; }
# `adb shell` joins arguments into one shell line, so values are quoted again.
q() { printf "'%s'" "${1//\'/}"; }
case $ACTION in
  add)
    while [ $# -ge 2 ]; do
      a content insert --uri $C/raw_contacts --bind account_type:n: --bind account_name:n:
      id=$(a content query --uri $C/raw_contacts --projection _id --sort "'_id DESC'" | head -1 | sed -E 's/.*_id=([0-9]+).*/\1/')
      a content insert --uri $C/data --bind raw_contact_id:i:"$id" \
        --bind mimetype:s:vnd.android.cursor.item/name --bind data1:s:"$(q "$1")"
      a content insert --uri $C/data --bind raw_contact_id:i:"$id" \
        --bind mimetype:s:vnd.android.cursor.item/phone_v2 --bind data1:s:"$(q "$2")" --bind data2:i:2
      shift 2
    done
    ;;
  remove)
    for name in "$@"; do
      a content delete --uri "'$C/raw_contacts?caller_is_syncadapter=true'" --where "\"display_name=$(q "$name")\""
    done
    ;;
  *) echo "usage: seed-contacts.sh <device> add|remove ..."; exit 2 ;;
esac
