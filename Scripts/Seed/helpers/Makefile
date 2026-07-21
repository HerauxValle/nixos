CC = gcc
CFLAGS = -Wall -Wextra -Werror -O2 -static
LDFLAGS = -static

sd-init: sd-init.c sd-init-seccomp.h sd-init-caps.h
	$(CC) $(CFLAGS) -o $@ sd-init.c $(LDFLAGS)

clean:
	rm -f sd-init

.PHONY: clean
