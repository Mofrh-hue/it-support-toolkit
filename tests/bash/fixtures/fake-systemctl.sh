#!/usr/bin/env bash
# Fake systemctl for tests. Services listed in $FAKE_ACTIVE are active;
# services listed in $FAKE_FIXABLE become active after a restart
# (tracked in $FAKE_STATE_DIR).
cmd=$1 svc=${2:-}
case "$cmd" in
  is-active)
    if [[ " $FAKE_ACTIVE " == *" $svc "* || -f "$FAKE_STATE_DIR/$svc" ]]; then
      echo active
    else
      echo inactive
      exit 3
    fi
    ;;
  restart)
    if [[ " $FAKE_FIXABLE " == *" $svc "* ]]; then
      touch "$FAKE_STATE_DIR/$svc"
    else
      echo "Job for $svc.service failed." >&2
      exit 1
    fi
    ;;
esac
