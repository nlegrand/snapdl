VERSION=1.2.2

all:
	mandoc snapdl.1 > snapdl.cat1

archive: all
	mkdir snapdl-${VERSION}
	cp Makefile snapdl.pl snapdl.1 snapdl-${VERSION}
	tar cfvz snapdl-${VERSION}.tar.gz snapdl-${VERSION}

clean:
	rm -rf snapdl.cat1 snapdl-*
