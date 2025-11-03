#!/usr/bin/bash
for x in `cat bb_targets.txt`; do 
	BB_BIN=$x/BB/Acc/BB.bin; 
	BB_LOG=$x/BB/Acc/BB.log; 
	if [[ -f "$BB_BIN" && -f "$BB_LOG" && $(grep -c "Simulation completed" "$BB_LOG") -gt 0 ]]; 
	then    
		continue; 
	else    
		echo $x;
	fi; 
done

