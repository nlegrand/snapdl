VERSION=1.2.3
INSTALL_PROGRAM_DIR=/usr/local/bin
INSTALL=install -c -o root -g bin -m 555

all:
	mandoc snapdl.1 > snapdl.cat1

archive: all
	mkdir snapdl-${VERSION}
	cp Makefile snapdl.pl snapdl.1 snapdl-${VERSION}
	tar cfvz snapdl-${VERSION}.tar.gz snapdl-${VERSION}

clean:
	rm -rf snapdl.cat1 snapdl-*

install: all
	install -c -o root -g bin -m 555 snapdl.pl   /usr/local/bin/snapdl
	install -c -o root -g bin -m 444 snapdl.cat1 /usr/local/man/cat1/snapdl.0

deinstall:
	rm /usr/local/bin/snapdl /usr/local/man/cat1/snapdl.0