#!/bin/bash -exu

IDX=${AWS_BATCH_JOB_ARRAY_INDEX:-0}
SEED_START=$(expr $IDX \* $RANGE + 1000)
SEED_END=$(expr $IDX \* $RANGE + $RANGE + 1000)

aws s3 cp s3://marathon-tester/AHC014/in.zip in.zip
unzip in.zip

g++ -Wall -Wextra -Wshadow -Wno-sign-compare -std=gnu++17 -O2 -DLOCAL -o main main.cpp
for (( i = $SEED_START; i < $SEED_END; i++ )); do
	seed=$(printf "%04d" $i)
	echo "seed:$seed"
	./main < in/"$seed".txt 2> "$seed".txt
	tail -n 1 "$seed".txt >> log.txt
done

aws s3 cp log.txt s3://marathon-tester/$RESULT_PATH/$(printf "%04d" $SEED_START).txt
