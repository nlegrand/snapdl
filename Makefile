all:
	nroff -man snapdl.1 > snapdl.cat1

install: all
	install -c -o root -g bin -m 555 ${.CURDIR}/snapdl.pl \
	/usr/local/bin/snapdl
	install -c -o root -g bin -m 444 ${.CURDIR}/snapdl.cat1 \
	/usr/local/man/cat1/snapdl.0

uninstall:
	rm /usr/local/bin/snapdl
	rm /usr/local/man/cat1/snapdl.0

clean:
	rm snapdl.cat1