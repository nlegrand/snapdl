VERSION=1.1

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

archive: all
	mkdir snapdl-${VERSION}
	cp Makefile snapdl.pl snapdl.1 snapdl-${VERSION}
	tar cfvz snapdl-${VERSION}.tar.gz snapdl-${VERSION}

clean:
	rm -rf snapdl.cat1 snapdl-*
