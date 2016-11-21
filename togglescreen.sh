#!/bin/sh

STATUS=`vcgencmd display_power`
if [ "$STATUS" = "display_power=1" ] ; then
    vcgencmd display_power 0 > /dev/null
else
    vcgencmd display_power 1 > /dev/null
fi
