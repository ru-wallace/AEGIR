CC=gcc

INCLUDE_PATHS=./include
INCLUDE_FLAGS=$(addprefix -I, $(INCLUDE_PATHS))
CFLAGS=-Wall -Wextra $(INCLUDE_FLAGS)

LIBS=pigpiod_if2 m
LDFLAGS=$(addprefix -l, $(LIBS))
SRC=$(wildcard src/*.c) $(wildcard src/*/*.c)



all: 
	mkdir -p ./build
	
	$(CC) $(SRC) $(CFLAGS) $(LDFLAGS) -o ./build/depthLogger

clean:
	rm -f ./build/*
	