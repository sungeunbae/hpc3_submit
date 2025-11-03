#!/usr/bin/bash
find . -name *.rlog -exec grep -H FINISHED {} \;
